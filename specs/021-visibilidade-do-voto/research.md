# Phase 0 — Research: visibilidade do voto

**Feature**: 021-visibilidade-do-voto | **Data**: 2026-08-09

Três das cinco decisões abaixo foram resolvidas rodando SQL contra o Postgres local
(`supabase_db_iasd`, `Up 2 hours (healthy)`), num schema descartável `exp` que replica a
tabela e as políticas. O schema foi removido ao fim (`DROP SCHEMA`). Nada em `public` foi
tocado.

O motivo de medir em vez de raciocinar: as duas perguntas centrais desta feature —
"apertar a leitura quebra a troca de voto?" e "apertar a leitura quebra a apuração?" — têm
respostas plausíveis e erradas. Uma delas eu tinha escrito errado na própria spec.

---

## Decisão 1 — A regra é `auth.uid() = usuario_id`: só o próprio voto

**Decision**: substituir `votos_select_public ... using (true)` por uma política que
devolve exclusivamente a linha da própria pessoa. Nem "participantes do Grupo", nem
"Dono do Grupo", nem Administrador do distrito.

**Rationale**: nenhuma tela do app consome voto alheio. O único ponto de leitura em Dart
já filtra pelo próprio `uid` (`voting_round_repository.dart:78-86`), e a tela usa isso só
para marcar a candidata escolhida (`voting_round_detail_page.dart:97`). Não existe
contagem de votos por candidata em lugar nenhum da interface. Abrir para o Grupo entregaria
acesso que nada consumiria — exposição sem finalidade, que é o oposto do Princípio II.

**Alternatives considered**:

- **Participantes do Grupo dono da Rodada** — é o que a Política promete hoje. Rejeitada
  como padrão porque a frase não é decisão registrada: nenhuma spec, nenhum achado e nenhum
  documento de decisão contém escolha sobre visibilidade de voto. A frase foi escrita depois
  do `using (true)`, descrevendo-o de forma amenizada. Adotá-la seria promover a descrição
  de um acidente a requisito. **Custo de mudar de ideia: uma expressão SQL e uma frase** —
  a política vira um `exists` contra `participacoes_grupo`, exatamente como
  `rodadas_votacao_checar_participante` já faz.
- **Só depois da Rodada fechar** (voto secreto durante, público depois) — rejeitada por
  Princípio V: ninguém pediu, nenhuma tela mostra, e adiciona uma regra temporal a uma
  tabela que não tem nenhuma.

---

## Decisão 2 — A apuração não é afetada: roda como `postgres`, fora da RLS

**Decision**: não tocar em `fechar_rodada_se_devido`.

**Rationale**: **verificado no banco**, não deduzido:

```
votos                    | relrowsecurity=t | relforcerowsecurity=f | owner=postgres
fechar_rodada_se_devido  | owner=postgres   | prosecdef=t
```

A função é `security definer` com dono `postgres`, e `votos` não tem `force row level
security`. RLS não se aplica ao dono da tabela sem `force`, e a função executa como o dono.
A apuração (`rodada_votacao.sql:168-175`) faz `left join public.votos` e conta com
`count(v.usuario_id)` — continua vendo todas as linhas depois da mudança.

**Alternatives considered**:

- **Dar uma política própria à apuração** — desnecessário: ela não passa por política
  nenhuma.
- **Contar votos numa coluna materializada na Rodada** — rejeitada: inventa estado
  derivado, sincronização e uma classe de bug nova, para resolver um problema que a medição
  mostrou não existir.

---

## Decisão 3 — A dependência do `security definer` vira teste (o achado desta pesquisa)

**Decision**: escrever um teste de integração que falha se a apuração parar de enxergar
todos os votos, e comentar a dependência **dentro da migration**, no ponto onde alguém a
quebraria.

**Rationale**: apertar a RLS **arma uma bomba que hoje está desarmada**. Enquanto
`using (true)` vale, tanto faz a apuração ser `definer` ou `invoker` — todo mundo enxerga
todos os votos, e a contagem sai igual. Depois desta feature, `invoker` passa a contar só
os votos de quem chamou.

Medido no `exp`: BIA e CLARA votaram na candidata `4444`, ANA votou sozinha na `5555`.
Vencedora correta: `4444`, com 2 votos.

```
 APURACAO security definer                   | 4444 | 2      <- correto
 APURACAO security definer                   | 5555 | 1
 APURACAO security invoker (chamada por ANA) | 5555 | 1      <- ANA elege a propria candidata
```

Como invoker chamada por ANA, a candidata `4444` **desaparece da apuração** — não aparece
com 0 votos, some da consulta — e a minoria vence. Silenciosamente: ninguém recebe erro,
a Rodada fecha, uma vencedora é gravada, candidatas perdedoras são apagadas
(`rodada_votacao.sql:177-179`). O estrago é irreversível e não deixa rastro.

Nenhum comentário no código de hoje avisa que a apuração depende disso.

**Alternatives considered**:

- **Confiar na revisão de código** — rejeitada. `using (true)` sobreviveu meses de revisão;
  é literalmente a razão desta feature existir.
- **`force row level security` mais política de serviço** — rejeitada: mais peças móveis,
  e `postgres` é superusuário, que ignora `force` de qualquer jeito. Não resolveria.

---

## Decisão 4 — Trocar de voto continua funcionando: o risco da spec não se confirmou

**Decision**: não mexer em `voting_round_repository.dart`. Manter o `upsert` como está.

**Rationale**: a spec listou como armadilha principal que fechar a **leitura** poderia
quebrar a **escrita**, porque o app grava por `upsert`, que resolve conflito com a linha
existente. **Medido: não quebra.**

Com a política nova aplicada (`select ... using (auth.uid() = usuario_id)`):

```
INSERT 0 1                                            <- ANA vota
INSERT 0 1                                            <- ANA TROCA de voto
 A) ANA trocou de voto, ve candidata          | 5555   <- a segunda escolha, correta
 B) votos que BIA ve (esperado 0)             | 0
 C) votos que ANON ve (esperado 0)            | 0
 D) BIA tenta sobrescrever o voto de ANA      | ERROR:  new row violates row-level
                                                 security policy for table "votos"
```

A razão de não quebrar: a linha em conflito é **sempre a da própria pessoa** — a chave
primária é `(rodada_id, usuario_id)` e a política de `insert` já exige
`auth.uid() = usuario_id`. Logo a linha que o `on conflict` precisa alcançar é justamente
a que a política nova continua deixando visível. A armadilha existiria numa regra mais
apertada que esta; nesta, não existe.

Confirmação do lado do cliente: `postgrest-dart` monta o `upsert` com
`Prefer: resolution=merge-duplicates` e nada mais — `return=representation` só entra se
alguém encadear `.select()`, o que `vote()` não faz. Portanto a escrita não pede leitura de
volta nem no nível do PostgREST.

**Consequência para o plano**: o teste de troca de voto (FR-008) continua obrigatório, mas
como **regressão**, não como investigação. E o registro fica: a spec estava errada sobre o
risco, e descobrir isso custou um experimento em vez de um refactor.

**Alternatives considered**:

- **Trocar `upsert` por `delete` mais `insert`** — rejeitada: resolveria um problema
  inexistente, quebraria a atomicidade e criaria uma janela em que a pessoa não tem voto.
- **Adicionar uma política de `select` extra só para o `on conflict`** — rejeitada: a
  medição mostra que não é necessária.

---

## Decisão 5 — Nomear a política `votos_select_own`

**Decision**: `drop policy votos_select_public` e criar `votos_select_own`.

**Rationale**: o nome antigo passaria a mentir. Um `votos_select_public` que não é público
é pior que nenhum nome — é a mesma classe de divergência entre descrição e comportamento
que a feature está consertando. Trocar o nome também faz qualquer código ou documento que
referencie o nome antigo falhar visivelmente, em vez de continuar apontando para algo com
semântica trocada.

`MAPA-DE-DADOS.md:66` referencia `votos_select_public` por nome e linha — FR-013 já obriga
a atualizá-lo.

**Alternatives considered**:

- **`alter policy votos_select_public using (...)`** — rejeitada: preserva um nome falso.
- **`votos_select_self`** — rejeitada por consistência: o repositório já usa o sufixo
  `_self` para escrita (`votos_insert_self`, `votos_update_self`) e a distinção
  leitura/escrita fica mais legível com `_own` na leitura. Decisão de estilo, sem efeito
  funcional; se preferir `_self`, é troca de uma palavra.

---

## O que ficou sem verificação

- **Comportamento em produção**: tudo acima foi medido no Postgres local. A produção roda a
  mesma migration, então o comportamento deve ser idêntico — mas ninguém rodou lá, e a
  feature 019 ainda está resolvendo o que se sabe sobre o ambiente de produção. O
  `quickstart.md` inclui a verificação pós-deploy por consulta direta à API.
- **Se já existe alguém que leu os votos**: não há log de acesso (`REVISAO-JURIDICA.md`
  registra o Marco Civil art. 15 como pendente de parecer). Não é possível saber se a
  exposição foi explorada, e a spec já decidiu não notificar por não haver canal.
