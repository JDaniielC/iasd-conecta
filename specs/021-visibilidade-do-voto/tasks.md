# Tasks: Quem pode ver em quem você votou

**Feature**: 021-visibilidade-do-voto | **Data**: 2026-08-09

**Input**: [spec.md](./spec.md), [plan.md](./plan.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql),
[quickstart.md](./quickstart.md)

## Antes de começar: o que torna esta feature diferente

**Ela é quase toda banco e documento.** O app já lê só o próprio voto
(`voting_round_repository.dart:78-86`). Nenhum widget, provider ou método de repositório
muda. A única linha de `lib/` que muda é uma string de texto legal.

**Duas armadilhas, e a segunda mata em silêncio:**

1. O risco que a spec apontava — fechar a leitura quebrar o `upsert` de troca de voto —
   **foi medido e não existe** (research.md, Decisão 4). Os testes de troca de voto
   continuam obrigatórios, mas como regressão, não como investigação. Se algum deles ficar
   vermelho, a política ficou mais apertada que o desenho.
2. O risco que ninguém tinha visto — esta feature **arma** uma dependência que hoje está
   desarmada. Se `fechar_rodada_se_devido` deixar de ser `security definer`, a apuração
   passa a contar só os votos de quem chamou e elege a candidata dessa pessoa. Silencioso,
   irreversível. T014 é a única coisa que detecta isso, e **ela só detecta se for montada
   do jeito certo** — leia a tarefa inteira antes de escrevê-la.

**Idioma** (Princípio I): todo identificador Dart criado por estas tarefas é escrito em
**inglês**, inclusive dentro dos arquivos de teste. A única exceção é o **nome do arquivo**
de teste, que segue a convenção portuguesa já usada em `test/integration/`. Cada tarefa
abaixo que cria um identificador o nomeia explicitamente, já em inglês.

**Ordem obrigatória**: a Fase 2 captura a prova de que o vazamento existe. Ela **precisa**
rodar antes da migration — depois, é impossível produzir essa evidência.

---

## Phase 1: Setup

- [ ] T001 Confirmar que o Postgres local está de pé rodando `docker ps --filter name=supabase_db --format "{{.Names}} {{.Status}}"` e, se não estiver, `supabase start`; anotar o status real na saída, não presumir
- [ ] T002 Aplicar o estado atual do schema com `supabase db reset` e confirmar que `votos_select_public` existe, com `docker exec -i supabase_db_iasd psql -U postgres -d postgres -c "\dp public.votos"`

---

## Phase 2: Foundational — capturar a prova ANTES de consertar

**Bloqueia todas as user stories.** Esta evidência deixa de ser produzível depois da T005.

- [ ] T003 Semear no Postgres local uma Rodada de votação com duas candidatas e votos de pelo menos três pessoas distintas, usando os helpers de `test/integration/db_test_helper.dart`; guardar o script em `specs/021-visibilidade-do-voto/quickstart.md` como referência ou num arquivo temporário, e anotar os UUIDs usados
- [ ] T004 Registrar o vazamento **atual** rodando `curl -s "http://127.0.0.1:54321/rest/v1/votos?select=*" -H "apikey: $ANON_KEY"` sem nenhum cadastro e colar a saída real (com os pares `usuario_id`/`candidata_id` visíveis) na descrição do commit da migration — é o contraste que prova a feature, e some depois da T005

---

## Phase 3: User Story 1 — O voto deixa de ser legível pela internet (P1) 🎯 MVP

**Meta**: um Visitante sem cadastro para de conseguir ler qualquer voto; a pessoa continua
lendo o próprio.

**Teste independente**: consultar `votos` como `anon` e receber lista vazia — ver T004 para
o antes e T009 para o depois.

- [ ] T005 [US1] Criar a migration `supabase/migrations/<timestamp>_votos_visibilidade.sql` seguindo [contracts/schema.sql](./contracts/schema.sql): `drop policy if exists votos_select_public on public.votos` e `create policy votos_select_own on public.votos for select to authenticated using (auth.uid() = usuario_id)` — usar o formato de timestamp das migrations existentes (`20260809174740_...`)
- [ ] T006 [US1] Na mesma migration, **não** revogar o `grant select on public.votos to anon` de `20260724084300_rodada_votacao.sql:190`, e escrever o comentário explicando por quê: sem política de select, `anon` recebe conjunto vazio; sem o grant, receberia erro de permissão, que vira canal lateral revelando que há votos escondidos (invariante 5 do data-model)
- [ ] T007 [US1] Na mesma migration, incluir o bloco de aviso da seção 4 de [contracts/schema.sql](./contracts/schema.sql) — a dependência de `fechar_rodada_se_devido` continuar `security definer`, com os números medidos e o apontamento para o teste que falha; o comentário vai **nesta** migration, não no arquivo da função, porque é aqui que a dependência nasce
- [ ] T008 [US1] Aplicar com `supabase db reset` e confirmar que a política nova existe e a antiga sumiu, com `docker exec -i supabase_db_iasd psql -U postgres -d postgres -c "\dp public.votos"`
- [ ] T009 [US1] Criar `test/integration/votos_visibilidade_test.dart` com o helper de identidade `_asUser(Connection conn, String uid, Future<void> Function() action)` copiado do padrão de `test/integration/acao_encerrada_nao_promove_fila_test.dart:24-36`, e as constantes de UUID `_uidVoterMajorityA`, `_uidVoterMajorityB`, `_uidVoterMinority` e `_uidOutsider` — identificadores em inglês, nome do arquivo em português
- [ ] T010 [US1] No mesmo arquivo, o caso `visitor sees no votes`: consultar `public.votos` com `set role anon` e afirmar **0 linhas e nenhuma exceção** — se levantar erro de permissão em vez de devolver vazio, a invariante 5 quebrou e o teste deve falhar (FR-001)
- [ ] T011 [US1] No mesmo arquivo, o caso `outsider sees no votes`: como `authenticated` com `_uidOutsider`, que não participa do Grupo, afirmar 0 linhas (FR-002)
- [ ] T012 [US1] No mesmo arquivo, os casos `group member cannot read others votes` e `voter reads own vote`: um participante do Grupo consulta e recebe **só** a própria linha, com a `candidata_id` correta — cobre FR-003 e FR-004 no mesmo cenário, provando que o filtro não é "tudo ou nada"
- [ ] T013 [US1] No mesmo arquivo, o caso `restriction survives round closing`: fechar a Rodada e repetir a consulta como `anon` e como `_uidOutsider`, afirmando 0 linhas — a visibilidade vale depois do fechamento, quando sobram justamente os votos da vencedora (FR-006, ver data-model)

**Checkpoint US1**: `dart test test/integration/votos_visibilidade_test.dart` verde e o
`curl` da T004 devolvendo `[]`.

---

## Phase 4: User Story 2 — Votar, trocar e apurar continuam funcionando (P1)

**Meta**: nenhuma regra do Princípio IV regride.

**Teste independente**: votar, trocar de candidata e fechar a Rodada, conferindo que a
vencedora é a mais votada.

**Depende da Phase 3** (a política precisa estar aplicada — testar antes não prova nada).

- [ ] T014 [US2] Em `test/integration/votos_visibilidade_test.dart`, o caso `tally counts every vote, not only the callers`: `_uidVoterMajorityA` e `_uidVoterMajorityB` votam na candidata X, `_uidVoterMinority` vota na candidata Y, e **é `_uidVoterMinority` quem chama `fechar_rodada_se_devido`**; afirmar que a vencedora é **X**. ⚠️ Montar ao contrário — quem fecha tendo votado na vencedora — faz o teste passar verde numa apuração quebrada e é pior que não ter teste (FR-009)
- [ ] T015 [US2] No mesmo arquivo, o caso `first vote is recorded`: com a política nova aplicada, uma pessoa vota pela primeira vez e a linha é criada (FR-007)
- [ ] T016 [US2] No mesmo arquivo, o caso `changing vote replaces the previous one`: a mesma pessoa vota noutra candidata usando `insert ... on conflict (rodada_id, usuario_id) do update`, exatamente como `voting_round_repository.dart:72-75` faz, e afirmar que resta **uma** linha, com a segunda candidata — regressão da revogabilidade do Princípio IV (FR-008)
- [ ] T017 [US2] No mesmo arquivo, o caso `nobody overwrites another persons vote`: `_uidOutsider` tenta o mesmo `upsert` na linha de outra pessoa e recebe `new row violates row-level security policy for table "votos"` — prova que fechar a leitura não afrouxou a escrita
- [ ] T018 [US2] No mesmo arquivo, o caso `tie is broken by draw`: montar empate entre duas candidatas, fechar a Rodada e afirmar que **uma** vencedora foi eleita e as perdedoras descartadas, sem exigir qual — o desempate é aleatório por desenho (`rodada_votacao.sql:174`) e um teste que exija uma candidata específica fica intermitente (FR-011)
- [ ] T019 [US2] Rodar `flutter test test/unit test/widget` e confirmar que **nenhum** teste mudou de resultado; anotar as contagens reais — qualquer mudança aqui significa que alguém tocou `lib/` além da string legal, o que esta feature não pede (FR-010)

**Checkpoint US2**: as regras de borda do Princípio IV — revogabilidade, apuração e
desempate — provadas com a política nova no lugar.

---

## Phase 5: User Story 3 — A Política passa a descrever o que acontece (P2)

**Meta**: nenhum documento afirma o que o banco não faz.

**Teste independente**: ler o item de voto na Política e conferir que ele descreve o mesmo
resultado que o `curl` da T009 produz.

- [ ] T020 [P] [US3] Em `lib/features/legal/presentation/privacy_policy_page.dart:131-133`, substituir "o voto não é anônimo entre os participantes do Grupo" por texto que descreva a regra real — só a própria pessoa lê o voto, e a apuração conta sem expor quem votou em quê; manter a linguagem simples do resto da página e os termos do glossário (Rodada de votação, Ação candidata) (FR-012)
- [ ] T021 [P] [US3] Em `MAPA-DE-DADOS.md:66`, trocar `votos_select_public` por `votos_select_own` com a nova referência de arquivo:linha e descrever a regra vigente; conferir se o parágrafo sobre `liderancas` logo abaixo continua correto — ele fala de RLS descrever o acesso real, e agora `votos` deixou de ser exemplo do problema (FR-013)
- [ ] T022 [US3] Registrar a decisão em `CONTEXT.md`, na entrada **Votar**: quem enxerga o voto e **por que** é só a própria pessoa — nenhuma tela consome voto alheio, então abrir para o Grupo seria exposição sem finalidade; sem o motivo escrito, `using (true)` volta na próxima feature que precisar ler a tabela, que é exatamente como ele sobreviveu até aqui (FR-014)
- [ ] T023 [US3] Verificar que a versão do texto legal em `lib/features/legal/legal_metadata.dart` precisa ou não subir por causa da T020 e agir conforme; se subir, isto interage com a feature 017 (versão do consentimento) — anotar qual decisão foi tomada e por quê

---

## Phase 6: Polish & Cross-Cutting

- [ ] T024 [P] Rodar os quatro gates e anotar os **números reais**: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration`, `flutter build web` — "passou" sem contagem não é verificação
- [ ] T025 [P] Executar a Parte 3 do [quickstart.md](./quickstart.md), itens 3.1, 3.3, 3.4 e 3.5, marcando cada caixa; o item 3.2 (produção) fica pendente até haver deploy
- [ ] T026 Confirmar que nenhuma outra política de `select` sobrou em `public.votos` com `docker exec -i supabase_db_iasd psql -U postgres -d postgres -c "\dp public.votos"` — políticas RLS se somam por `OR`, e uma segunda política permissiva esquecida anula toda a feature em silêncio
- [ ] T027 Procurar por outras referências ao nome antigo com `grep -rn "votos_select_public" . --exclude-dir=.git` e corrigir o que sobrou fora de `specs/` (dentro de `specs/` o nome antigo é registro histórico e fica)
- [ ] T028 Registrar no arquivo de estado do projeto o que ficou aberto: a verificação em produção (item 3.2 do quickstart), e o fato de não haver como saber se a exposição foi explorada, por não existir log de acesso (`REVISAO-JURIDICA.md`, Marco Civil art. 15 pendente de parecer)

---

## Dependências

```text
Phase 1 (T001-T002)
  └─> Phase 2 (T003-T004)          ← captura o "antes"; IRREVERSÍVEL depois da T005
        └─> Phase 3 / US1 (T005-T013)   ← a migration + a prova de que fechou
              └─> Phase 4 / US2 (T014-T019)  ← precisa da política aplicada
                    └─> Phase 6 (T024-T028)
        └─> Phase 5 / US3 (T020-T023)   ← independente da US2; depende só de T005
```

`T005` é o gargalo real: quase tudo depende dela, e a Fase 2 precisa vir antes.

## Oportunidades de paralelismo

- **T020 e T021** — arquivos diferentes (`privacy_policy_page.dart` e `MAPA-DE-DADOS.md`),
  sem dependência entre si.
- **T024 e T025** — gates automatizados e verificação manual não se atrapalham.
- **US3 inteira em paralelo com a US2**: assim que T005 estiver aplicada, os documentos
  podem ser corrigidos enquanto os testes de regressão são escritos. São arquivos
  disjuntos.
- **T010 a T013 não são paralelizáveis entre si** — todas editam
  `votos_visibilidade_test.dart`. O mesmo vale para T014–T018.

## Escopo de MVP

**US1 sozinha** (T001–T013) já entrega o valor inteiro: o voto para de ser legível pela
internet. São 13 tarefas.

Mas **não pare aí**. A US2 é P1 junto com a US1, não depois — em particular a **T014**, que
é a única coisa entre esta feature e uma apuração que elege a candidata errada em silêncio.
Entregar a US1 sem a T014 troca um problema de privacidade por um problema de integridade,
e o segundo é pior: o primeiro expõe dado, o segundo apaga candidatas e não deixa rastro.

A US3 pode ficar para um segundo commit sem risco técnico — mas enquanto ela não entrar, a
Política continua descrevendo errado o app, que a constituição trata como violação. É
dívida com prazo, não item opcional.

## Cobertura requisito → tarefa

| Requisito | Tarefas |
|---|---|
| FR-001 Visitante não lê voto | T005, T010, T025 |
| FR-002 Usuário de fora não lê | T005, T011 |
| FR-003 Lê o próprio voto | T005, T012 |
| FR-004 Não lê o de terceiro | T005, T012 |
| FR-005 Garantido no banco | T005, T008, T025, T026 |
| FR-006 Vale depois do fechamento | T005, T013 |
| FR-007 Registrar voto funciona | T015 |
| FR-008 Trocar de voto funciona | T016, T017 |
| FR-009 Apuração conta todos | T007, T014 |
| FR-010 Tela marca a escolhida | T019, T025 |
| FR-011 Desempate intacto | T018 |
| FR-012 Política corrigida | T020, T023, T025 |
| FR-013 MAPA-DE-DADOS corrigido | T021, T025 |
| FR-014 Decisão registrada | T022, T025 |
| SC-001 0 votos a Visitante | T004 (antes), T010, T025 |
| SC-002 0 votos de terceiros | T011, T012 |
| SC-003 100% leem o próprio | T012 |
| SC-004 100% das trocas funcionam | T015, T016 |
| SC-005 Mesma vencedora apurada | T014, T018 |
| SC-006 0 afirmações desatualizadas | T020, T021, T022, T027 |

14/14 requisitos funcionais e 6/6 critérios de sucesso, cada um em ≥1 tarefa; os de maior
risco em ≥2.
