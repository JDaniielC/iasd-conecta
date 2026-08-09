# Research: Consentimento de responsável para menor de idade

**Feature**: 015-consentimento-responsavel | **Date**: 2026-08-09

As decisões D-001 a D-004 e D-006 não foram deduzidas — foram **rodadas** contra o Postgres
local do projeto (`supabase_db_iasd`), dentro de transação revertida. A saída real de cada
experimento está transcrita, porque "a constraint deve funcionar" e "a constraint funcionou"
são afirmações diferentes.

---

## D-001 — A regra é uma `check constraint`, não gatilho nem política

**Decisão**: FR-009 é cumprido por **duas check constraints** em `public.perfis`, no mesmo
molde de `apelido_obrigatorio_menor` (`20260723191202_perfis_igrejas.sql:38`).

**Rationale**: a pergunta que o plano precisava responder era "constraint, gatilho ou
política?". A resposta sai da natureza da regra:

| Mecanismo | Serve? | Por quê |
|---|---|---|
| **`check constraint`** | ✅ | A regra é uma invariante de **uma linha só**: olha `idade` e quatro colunas da mesma linha, sem consultar mais nada. É exatamente o caso de uso de `CHECK`, e cobre `insert` **e** `update` de graça |
| Gatilho `before insert` | ❌ para esta regra | Faria o mesmo trabalho com mais código, mais um objeto para manter, e mensagem de erro que o cliente teria que reconhecer por texto em vez de por nome de constraint. `_errorMessage` em `profile_signup_page.dart:102-113` já casa erro por **nome de constraint** — o padrão da casa |
| Política RLS (`with check`) | ❌ | Política vale por **papel**. Um `insert` feito por `service_role`, pelo painel do Supabase ou por uma migration não passa por RLS nenhuma, e FR-009 diz "por nenhum caminho". Constraint vale para todo mundo, inclusive o `postgres` |

**O precedente serve, e isso foi confirmado no banco**: `apelido_obrigatorio_menor` é
`check (idade >= 18 or apelido is not null)` e cumpre a mesma classe de exigência desde a
feature 001, com teste de integração próprio (`test/integration/apelido_obrigatorio_test.dart`).
Esta feature copia a forma.

**Uma diferença importante**: `apelido_obrigatorio_menor` nasceu **junto com a tabela**. Esta
constraint chega numa tabela que já tem linhas — e é daí que vem o D-003.

---

## D-002 — O limiar mora numa função de banco, e trocá-lo é uma linha

**Decisão**: `create function public.limiar_crianca() returns integer language sql immutable`,
devolvendo um inteiro. A constraint chama a função; **nunca** um literal.

E uma convenção que absorve a segunda incógnita: **a comparação é sempre
`idade < public.limiar_crianca()`**. O lado do limiar vira o número — "até 12 anos inclusive"
se escreve como **13**; "menor que 12" se escreve como **12**.

**Rationale**: a spec deixou o número em aberto de propósito e o Princípio III proíbe decidir
regra de negócio ad-hoc no código. Então o plano precisa suportar a troca sem obra. Com literal
dentro da constraint, mudar o número exige `drop constraint` + `add constraint`, numa tabela
com linhas antigas — ou seja, exige repensar o D-003 inteiro toda vez.

**Medido**, dentro de uma transação revertida:

```
create function public.limiar_crianca() returns integer language sql immutable as $$ select 12 $$;
alter table public.perfis add constraint autorizacao_responsavel_crianca
  check (idade is null or idade >= public.limiar_crianca() or responsavel_nome is not null) not valid;

-- limiar 12, inserir idade 8 sem responsável:
ERROR:  new row for relation "perfis" violates check constraint "autorizacao_responsavel_crianca"

-- a troca de uma linha:
create or replace function public.limiar_crianca() ... select 6 ;   -->  CREATE FUNCTION

-- limiar 6, inserir a MESMA idade 8 sem responsável:
INSERT 0 1        <-- passou, sem recriar constraint nenhuma
-- limiar 6, inserir idade 5 sem responsável:
ERROR:  new row for relation "perfis" violates check constraint "autorizacao_responsavel_crianca"
```

Ou seja: `create or replace` da função muda o comportamento da constraint **na hora**. O
planejador não congelou o valor.

**Função em `CHECK` é padrão da casa, não invenção**: `perfis.nome` já é
`check (nome_valido(nome))` (`20260723191202_perfis_igrejas.sql:29`), e `nome_valido` nem
`immutable` é — é `stable` e lê outra tabela. `limiar_crianca()` é bem mais conservadora:
`immutable`, sem leitura, sem parâmetro.

**Espelho no Dart**: `const childAgeThreshold` em `lib/features/profile/domain/profile.dart`,
ao lado do `_ageOfMajority` que já existe pela mesma razão. São duas fontes, e isso é
deliberado — o banco **executa**, o Dart dá o feedback imediato na tela. Para elas nunca
divergirem, um teste de integração lê `select public.limiar_crianca()` e compara com a
constante (T008). É uma asserção de uma linha que substitui uma regra de disciplina.

**Alternativa descartada** — *tabela de configuração `parametros`*: um `select` numa tabela
dentro de uma `CHECK` seria `stable`, exigiria `grant`, e criaria a possibilidade de o valor
mudar em produção sem passar por migration — isto é, sem revisão. A regra é de produto e deve
mudar por commit.

---

## D-003 — `not valid` é obrigatório, e o preço dele está medido

**Decisão**: as duas constraints entram com `not valid`. **Nunca** rodar
`VALIDATE CONSTRAINT` sem uma decisão de produto explícita.

**Rationale**: a spec é clara — "a feature **não** os corrige retroativamente nem os bloqueia"
(Assumptions, cadastros de menor que já existem). O experimento mostra que, sem `not valid`, a
feature faz o oposto das duas coisas: nem corrige nem preserva — **quebra a migration**.

**Medido**, com um cadastro antigo de menor semeado (idade 8, sem responsável):

| Experimento | Saída real |
|---|---|
| `alter table ... add constraint ... check (...)` (sem `not valid`) | `ERROR: check constraint "autorizacao_responsavel_crianca" of relation "perfis" is violated by some row` |
| `alter table ... add constraint ... check (...) not valid` | `ALTER TABLE`; `select conname, convalidated` → `convalidated = f` |
| `insert` **novo** de menor sem responsável, com a constraint `not valid` no lugar | `ERROR: new row ... violates check constraint` — **FR-009 cumprido** |
| `update public.perfis set telefone = '81999999999'` na linha **antiga** que viola | `ERROR: new row ... violates check constraint` |
| Anonimização da feature 009 na linha antiga (`idade = null`, entre outros) | `UPDATE 1` — **passou** |

**As duas linhas que mais importam são as duas últimas**, e nenhuma delas é óbvia:

1. **O cadastro antigo de menor vira somente-leitura.** `not valid` significa "não confira as
   linhas que já estão aqui" — **não** significa "deixe essas linhas em paz para sempre".
   Qualquer `update` nelas revalida a linha inteira, mesmo mexendo num campo sem relação
   (telefone, no experimento). Hoje isso é inofensivo: não existe tela de editar perfil
   (`MAPA-DE-DADOS.md:117-122`). Na **feature 016** vira erro de banco na cara do usuário.
   Está registrado como risco 1 do plano e como comentário na própria migration.

2. **A exclusão de conta continua funcionando para esses cadastros.** Era o modo de falha mais
   feio possível — a feature que existe para proteger criança bloqueando o direito de exclusão
   de uma criança (LGPD art. 18, VI). Não acontece, e o motivo é a semântica de três valores do
   `CHECK`: `excluir_minha_conta` zera `idade`, `null >= limiar` é `NULL`, o `OR` inteiro dá
   `NULL`, e `CHECK` que resulta em `NULL` **passa**. É o mesmo motivo pelo qual
   `apelido_obrigatorio_menor` já tolera a anonimização, comentado em
   `20260806140000_exclusao_de_conta.sql:41-43`.

**Quantos cadastros antigos existem hoje**: no banco local, `select count(*) from public.perfis`
→ **1 linha**, `count(*) filter (where idade < 12)` → **0**. Ou seja, hoje a constraint valida
mesmo sem `not valid`. O `not valid` está lá para o banco que **não** é este — e porque a
migration não pode ter comportamento diferente conforme o conteúdo do banco onde roda.

**Alternativa descartada** — *sanear as linhas antigas na migration* (preencher responsável
fictício, ou apagar): inventar um consentimento que ninguém deu é pior do que não ter
consentimento — vira prova falsa. E apagar cadastro de terceiro numa migration não foi pedido
por ninguém.

---

## D-004 — FR-008 exige uma **segunda** constraint, e é ela que amarra a regra dos adolescentes

**Decisão**: `autorizacao_responsavel_so_para_crianca` — acima do limiar, as quatro colunas
**precisam** estar nulas.

**Rationale**: FR-008 ("para maior de idade, os campos de responsável DEVEM ficar vazios") e
SC-002 não são consequência da primeira constraint. A primeira só exige presença **abaixo** do
limiar; sem a segunda, nada impede um adulto de gravar nome de responsável — por bug de tela,
por `insert` direto, ou por um formulário que esqueceu de limpar o estado ao subir a idade.

E há um caso concreto que não é hipotético: no formulário atual, trocar a Igreja de origem já
zera o consentimento anterior de propósito (`profile_signup_page.dart:178-181`). O mesmo
cuidado precisa existir ao **subir** a idade acima do limiar — os campos do responsável têm que
ser descartados, não carregados adiante. A constraint é a rede que pega esse esquecimento.

**O que essa constraint custa, e é honesto dizer agora**: ela **impede** o cenário que
`REVISAO-JURIDICA.md:102-105` sugere para 12-17 anos ("aplicar o mesmo campo de contato do
responsável quando o campo sensível Igreja de origem for preenchido"). A spec decidiu, em
Assumptions, que adolescente segue apenas **recomendado** — então a constraint está alinhada
com a spec de hoje. Se essa decisão mudar, é **esta** constraint que muda junto. Registrado
como risco 4 do plano.

---

## D-005 — Um gatilho protege o registro, senão a US2 não significa nada

**Decisão**: gatilho `before update` em `public.perfis` recusando alteração de
`responsavel_nome`, `responsavel_contato`, `autorizacao_responsavel_em` e
`autorizacao_responsavel_versao`, com escape por GUC de transação —
`app.bypass_autorizacao_responsavel`.

**Rationale**: a US2 diz, em uma frase, o problema inteiro: "uma autorização que não deixa
rastro tem o mesmo valor probatório de nenhuma autorização". A constraint garante que o
registro **exista**; não garante que ele continue sendo o que foi.

**Medido**, como a própria criança, com o JWT dela:

```
set local role authenticated;
set local request.jwt.claims = '{"sub":"<uid da criança>","role":"authenticated"}';
update public.perfis set responsavel_nome = 'Fulano Inventado' where id = '<uid da criança>';
-->  UPDATE 1
select responsavel_nome ...  -->  Fulano Inventado
```

Passou. A política `perfis_update_own` é `using (auth.uid() = id)` e **não tem `with check`**
(confirmado em `\dp public.perfis`) — ela confere **quem** mexe na linha, nunca **o quê** muda.

**Por que não endurecer a política em vez do gatilho**: `WITH CHECK` só enxerga a linha **nova**.
Não existe `OLD` em política RLS, então é impossível escrever "esta coluna não pode mudar" ali.
Gatilho é o único lugar onde `OLD` existe.

**Precedente exato na casa**: este é o mesmo bug e o mesmo remédio do **BUG 3** da auditoria de
2026-07-24 (`20260724130000_fix_rls_security_bugs.sql:53-85`) — "as policies de UPDATE de
`acoes` nunca tiveram `WITH CHECK` explícito", resolvido com
`acoes_protege_campos_internos` + GUC `app.bypass_acoes_protecao`. Copiar a forma é mais
barato do que inventar outra, e quem já leu aquele arquivo entende este de graça.

**Para que serve o escape por GUC**: dois usos legítimos, e só eles.

1. `excluir_minha_conta()` precisa **zerar** essas colunas ao anonimizar (D-007).
2. Correção pedida pelo próprio responsável (US3, LGPD art. 18 III) — feita à mão pelo
   responsável pelo app, que precisa ligar o bypass explicitamente. Bypass explícito é
   auditável; ausência de proteção não é.

**Alternativa descartada** — *proteger só a data e a versão, deixando nome e contato editáveis
para permitir correção*: um registro em que o nome pode virar outro nome não prova quem
autorizou. Correção continua possível, pelo caminho explícito acima.

---

## D-006 — Quem pode ler: ninguém precisou ser proibido, porque ninguém tinha acesso

**Decisão**: **nenhuma política, RPC ou `grant` novo.** As quatro colunas nascem legíveis
apenas por (a) a própria linha, via `perfis_select_own`, e (b) `service_role` — o responsável
pelo app, pelo painel do Supabase.

**Rationale**: a spec declara "quem pode ver: ninguém além do responsável pelo app. **Nunca**
exibido a outros Usuários, nem a Visitante" (SC-004). O caminho mais simples de garantir isso é
não abrir caminho nenhum — e o estado atual do banco já é esse.

**Medido**:

| Verificação | Saída real |
|---|---|
| Outro `authenticated` faz `select` na linha da criança | `linhas_visiveis = 0` |
| `\dp public.perfis`, privilégios de `anon` | `anon=Dxtm/postgres` — **sem `r`**. `anon` não tem `select` em `perfis`, nem com RLS desligada |
| `perfil_publico('<uid da criança>')` chamada por outro Usuário | `id | nome_exibido | igreja_id` → `Cri` — a projeção é **fixa**, não tem `select *` |
| `grep` por outra leitura de `perfis` nas migrations | duas ocorrências, ambas internas: `dupla_missionaria.sql:63` lê só `genero`; `exclusao_de_conta.sql:76` faz `select 1` |
| `ProfileRepository` | lê `perfis` uma única vez, com `.select('id')` — `profile_repository.dart` |

**Onde isso pode quebrar depois, e é o que precisa de olho**: `perfil_publico` é
`security definer` e devolve colunas **nomeadas uma a uma**. Enquanto for assim, não há
vazamento possível. O risco real é a **feature 016 (meu perfil)**: uma tela que faça
`select *` em `perfis` para preencher um formulário passa a trazer os dados do responsável
para a memória do cliente. Não é vazamento para terceiro (a RLS continua limitando à própria
linha), mas é o primeiro passo para um. Fica registrado aqui e na ordem entre features do
plano.

**A verificação de SC-004 vira duas tarefas**: um teste de integração que prova as três linhas
da tabela acima, e uma varredura em `lib/` provando que nenhuma consulta lê as colunas novas
(T026). Um teste prova o banco; a varredura prova o cliente.

---

## D-007 — A anonimização precisa aprender as colunas novas

**Decisão**: `excluir_minha_conta()` (feature 009) passa a zerar as quatro colunas junto com o
resto, com o bypass do gatilho ligado ao redor do `update`.

**Rationale**: é o único ponto em que esta feature pode violar o Princípio II sem que nada
grite. A função anonimiza `nome`, `apelido`, `telefone`, `igreja_id`, `genero` e `idade`
(`20260806140000_exclusao_de_conta.sql:142-150`) — uma lista **explícita**, escrita antes destas
colunas existirem. Sem tocá-la, a conta da criança é excluída, o Perfil dela é anonimizado, e o
nome e o telefone da mãe **continuam no banco**, indefinidamente.

Esse dado é de **terceiro**: a mãe não é usuária do app, não tem conta, não tem tela, não tem
como pedir exclusão. A LGPD art. 16 só dispensa a exclusão quando o dado está de fato
anonimizado — e um telefone identificável ao lado de uma linha "anonimizada" derruba
justamente a base que a feature 009 usou para conservar a linha.

**Ordem dentro da função importa pouco, mas a semântica do `CHECK` importa muito**: o mesmo
`update` zera `idade` **e** as quatro colunas. Com `idade` nula, as duas constraints resultam em
`NULL` e passam — foi o que o experimento de D-003 mostrou (`UPDATE 1`).

**O gatilho de D-005 bloquearia esse `update`**, inclusive rodando como dono — gatilho não é RLS,
`security definer` não pula gatilho. Daí o `set_config('app.bypass_autorizacao_responsavel',
'true', true)` antes e `'false'` depois, exatamente como `fechar_rodada_se_devido` faz com
`app.bypass_acoes_protecao` (`20260724130000_fix_rls_security_bugs.sql:127-131`).

**Prova**: `test/integration/account_deletion_test.dart` ganha uma asserção — depois de excluir
a conta de uma criança, as quatro colunas estão nulas. Os testes que já existem nesse arquivo
passam sem edição.
