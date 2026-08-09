# Tasks: Visibilidade das declarações de Líder/Diretor

**Input**: Design documents from `/specs/018-visibilidade-de-liderancas/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

**Tests**: obrigatórios. SC-001 exige verificação por **consulta direta à API**, e a
constituição (Princípio IV) exige teste automatizado antes de a regra contar como pronta.
Sem `data-model.md` — ver plan.md, seção Documentation.

## Format: `[ID] [P?] [Story] Descrição`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência)
- **[Story]**: US1 ou US2

## Regra de idioma (vale para toda tarefa abaixo)

- **Banco em português**: tabela, coluna, função, trigger e **nome de política**. A política
  desta feature chama-se `liderancas_select_confirmada_propria_ou_admin` — é objeto de banco.
- **Identificador Dart em inglês**, inclusive em arquivo de teste: classe, enum e seus valores,
  método, função, variável local, parâmetro, campo, provider, helper e mock.
- **Única exceção**: o **nome do arquivo** de teste continua em português —
  `visibilidade_liderancas_test.dart`.
- **Português também em**: chave de leitura/gravação no banco (`'grupo_id'`, `'confirmado_em'`),
  string visível ao usuário, comentário e documentação.
- Cada tarefa que cria identificador **nomeia o identificador explicitamente, já em inglês**.
  A feature 011 não fez isso e custou 315 renomeações depois.

---

## Fase 1: Premissas (bloqueante — antes de escrever qualquer SQL)

**Purpose**: as três premissas do contrato são o que separa "consertar um vazamento" de
"criar um bug de exclusão de conta".

- [ ] T001 Verificar as **três premissas** de `specs/018-visibilidade-de-liderancas/contracts/schema.sql` contra o banco local, com os comandos da Parte 0 de `specs/018-visibilidade-de-liderancas/quickstart.md`: (1) `public.liderancas` com `relforcerowsecurity = false`; (2) `anon`/`authenticated` com **apenas** `SELECT` em `public.liderancas`; (3) `administradores_distrito_select_public` ainda existente. Registrar a saída literal dos três comandos. **Se `force=t`, ou se aparecer `INSERT`/`UPDATE`/`DELETE`: parar e revisar o contrato** — seguir troca um vazamento de privacidade por um bug de LGPD em `public.excluir_minha_conta` (`supabase/migrations/20260806140000_exclusao_de_conta.sql:137`). Ver `research.md` D-009

- [ ] T002 [US1] **Reproduzir o vazamento antes de consertar**, com o bloco SQL da Parte 1 de `specs/018-visibilidade-de-liderancas/quickstart.md`: semear no mesmo Grupo uma declaração confirmada, uma pendente e uma rejeitada, e ler como `set role anon`. **Esperado: 3 linhas**, incluindo a `REJEITADA`. Se vierem menos de 3, o ambiente não reproduz o problema e o resto do trabalho não prova nada — investigar antes de seguir

---

## Fase 2: Fundação (bloqueante para US1 e US2)

- [ ] T003 [US1] Criar `supabase/migrations/<timestamp>_liderancas_visibilidade.sql` com o conteúdo **integral** de `specs/018-visibilidade-de-liderancas/contracts/schema.sql`, comentários inclusive — o porquê mora no arquivo, não no commit. A migration faz `drop policy if exists liderancas_select_public` e cria `liderancas_select_confirmada_propria_ou_admin` (nome **em português**, é objeto de banco) com os três disjuntos: `(confirmado_em is not null and rejeitado_em is null)` `or usuario_id = auth.uid()` `or exists (select 1 from public.administradores_distrito where usuario_id = auth.uid())`; e um `comment on table public.liderancas`. **Cobre FR-001, FR-002, FR-003, FR-004, FR-005** — e é a única tarefa que cobre FR-004, porque é a única que põe a regra no banco em vez da tela

- [ ] T004 [US1] Aplicar com `supabase db reset` e confirmar em `pg_policy` que `liderancas_select_public` **não existe mais** e que `liderancas_select_confirmada_propria_ou_admin` existe (comando na Parte 2 de `quickstart.md`). Registrar a saída literal. Uma política antiga sobrevivente é um `or true` invisível: bastaria ela para o vazamento continuar, porque políticas de select se somam

---

## Fase 3: US1 — declaração rejeitada ou pendente para de ser pública (P1)

**Goal**: provar por **consulta à API** que Visitante e Usuário comum só recebem confirmadas, e
que a própria pessoa e o Administrador continuam vendo o que precisam.

**Independent Test**: `dart test test/integration/visibilidade_liderancas_test.dart` — 6 casos,
nenhum deles olhando tela.

- [ ] T005 [US1] Criar `test/integration/visibilidade_liderancas_test.dart` com o **arranjo compartilhado** (nome de arquivo em português; **todo identificador dentro dele em inglês**). Reutilizar de `test/integration/db_test_helper.dart` os helpers já existentes (`openTestConnection`, `criarPerfilDeTeste`, `criarAdministradorDistritoDeTeste`, `limparUsuarioDeTeste` — nomes legados, não renomear). Identificadores **novos**, em inglês: constantes `_confirmedUserId`, `_pendingUserId`, `_rejectedUserId`, `_otherUserId`, `_adminUserId`; variáveis `conn`, `groupId`; helpers `Future<void> asVisitor(Future<void> Function() action)` (faz `set role anon`, e no `finally` `reset role` **e** `reset request.jwt.claims`) e `Future<void> asUser(String userId, Future<void> Function() action)` (faz `set role authenticated` + `set request.jwt.claims`, mesmos dois resets no `finally`); e `Future<int> countVisibleDeclarations()`. No `setUpAll`, semear no mesmo Grupo uma declaração **confirmada**, uma **pendente** e uma **rejeitada** do ano corrente; `tearDownAll` limpa `liderancas`, `grupos`, `administradores_distrito` e os cinco usuários. **Os dois `reset` não são opcionais**: `reset role` não limpa GUC customizado, e sem `reset request.jwt.claims` o `set role anon` seguinte enxerga o `sub` antigo e o teste mente (`test/integration/church_archive_visibility_test.dart:18-22`)

- [ ] T006 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'FR-001/FR-005/SC-001: Visitante sem cadastro só recebe a confirmada'`: dentro de `asVisitor`, selecionar todas as linhas do Grupo e esperar **exatamente 1**, com `confirmado_em` não nulo; e esperar **0** linhas ao filtrar por `usuario_id in (_pendingUserId, _rejectedUserId)`. **Cobre FR-001, FR-005, SC-001, SC-002** — é o caso que fecha o achado

- [ ] T007 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'FR-002/SC-001: Usuário cadastrado que não é o autor vê o mesmo que o Visitante'`: dentro de `asUser(_otherUserId, ...)`, esperar **1** linha (a confirmada) e **0** linhas para pendente/rejeitada. **Cobre FR-002 (metade negativa), FR-005, SC-001** — ser cadastrado não dá motivo

- [ ] T008 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'FR-002/FR-008: a própria pessoa vê a própria declaração em qualquer estado'`: dentro de `asUser(_rejectedUserId, ...)`, esperar **2** linhas — a confirmada (que é pública para todos) mais a **própria rejeitada**; repetir com `asUser(_pendingUserId, ...)` esperando **2**, sendo uma com `confirmado_em` e `rejeitado_em` nulos. **Cobre FR-002 (metade positiva), FR-008** — sem isso a pessoa não sabe se foi confirmada, rejeitada ou se ainda espera

- [ ] T009 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'FR-003/FR-007: Administrador do distrito vê todas'`: dentro de `asUser(_adminUserId, ...)`, esperar **3** linhas — confirmada, pendente e rejeitada. **Cobre FR-003, FR-007** — é ele quem decide sobre elas, e a tela de pendências depende deste disjunto

- [ ] T010 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'SC-001: a contagem não vaza o que a linha esconde'`: dentro de `asVisitor`, rodar `select count(*)` no Grupo via `countVisibleDeclarations()` e esperar **1**. A RLS filtra antes da agregação, então nem o tamanho da resposta nem um `count` revelam que existem 3 linhas. **Cobre SC-001** e fecha o edge case "Contagem" da spec

- [ ] T011 [US1] Em `test/integration/visibilidade_liderancas_test.dart`, caso `'FR-005: linha com confirmado_em E rejeitado_em preenchidos não é pública'`: como `postgres` (bypass de RLS), inserir uma linha com **os dois** timestamps para um sexto usuário `_bothStampsUserId`, e então, dentro de `asVisitor`, esperar que ela **não** apareça. Hoje essa combinação é inalcançável pelos caminhos com grant (`decidir_lideranca` zera sempre o campo oposto), mas a tabela não tem `check` que a proíba — este caso é o que justifica a conjunção `rejeitado_em is null` na política e impede que alguém a "simplifique" depois. Ver `research.md` D-001. **Cobre FR-005**

**Checkpoint US1**: `dart test test/integration/visibilidade_liderancas_test.dart` → **6 casos
passando**. O vazamento da spec está fechado e provado por consulta, não por tela.

---

## Fase 4: US2 — nada quebra no que já funciona (P2)

**Goal**: as três telas que leem a mesma tabela continuam funcionando, e a expiração anual
continua intocada.

- [ ] T012 [US2] Alinhar o predicado do cliente ao da política em `lib/features/leadership/data/leadership_repository.dart`, método `fetchCurrentLeaders` (linhas 31-37): acrescentar `.filter('rejeitado_em', 'is', null)` depois do `.not('confirmado_em', 'is', null)` — chaves de coluna **em português**, como toda leitura do banco; nenhum identificador Dart novo é criado. Atualizar o comentário do método para dizer que o predicado é gêmeo do da política `liderancas_select_confirmada_propria_ou_admin` e que os dois mudam juntos. **Por quê**: sem isso, os dois lados dizem coisas diferentes, e a divergência é silenciosa — a RLS remove a linha antes de o Dart ver, então some da tela sem erro nenhum. Duplicação declarada, no estilo de `specs/011-acoes-titulo-e-encerramento/contracts/schema.sql:27-31`. **Cobre FR-006**

- [ ] T013 [US2] Rodar a suíte de leadership existente **sem alterá-la** — `dart test test/integration/leadership_public_current_test.dart test/integration/leadership_decide_test.dart test/integration/leadership_decide_authorization_test.dart test/integration/leadership_declare_idempotent_test.dart test/integration/leadership_redeclare_after_reject_test.dart test/integration/leadership_requires_account_test.dart` — e confirmar 0 falha. O caso mais informativo é `leadership_public_current_test.dart:66-79`, que lê **duas** confirmadas (ano corrente e ano anterior) como `anon` e espera as duas: se ele passar, o 1º disjunto está certo e a página do Ministério continua pública. **Cobre FR-006, SC-003**

- [ ] T014 [US2] Confirmar que **FR-009 é verdade por omissão**: rodar `dart test test/integration/leadership_yearly_expiry_test.dart` e verificar que nenhum arquivo de expiração foi tocado — `lib/features/leadership/leadership_providers.dart` (que monta `DateTime.now().year`, linhas 13-14) e `lib/features/leadership/domain/leadership_declaration.dart` (`isCurrentFor`, linhas 34-36) permanecem **byte a byte iguais**. A política não menciona `ano` de propósito: a expiração é comparação preguiçosa no cliente, não estado no banco, e por isso uma declaração confirmada de 2025 continua legível por `anon` em 2026, exatamente como a spec assume. **Cobre FR-009**

- [ ] T015 [US2] Conferência manual das quatro telas pela Parte 5 de `specs/018-visibilidade-de-liderancas/quickstart.md` (`flutter run -d chrome`): (1) Visitante vê o Líder confirmado na página do Ministério; (2) quem se declarou vê o estado da própria declaração; (3) Administrador vê as pendentes em `/leadership/pending`; (4) Usuário comum que digitar `/leadership/pending` vê "Nenhuma declaração pendente.", **sem erro e sem tela vermelha** — comportamento novo e desejado, porque a rota não é gateada por `isDistrictAdminProvider` (`lib/app.dart:150-152`, risco 3 do plano). **Isto é regressão visual, não prova de SC-001** — a prova é a Fase 3. **Cobre FR-006, FR-007, FR-008, SC-003**

**Checkpoint US2**: as três telas funcionam e nenhum teste anterior quebrou.

---

## Fase 5: Documentação e gates

- [ ] T016 [P] Atualizar `MAPA-DE-DADOS.md`: (a) na linha da tabela `liderancas` (linha 68), trocar "**sem filtro por `confirmado_em`**: declaração pendente/rejeitada também é publicamente selecionável" pela regra que passa a existir — só a confirmada é pública, a própria pessoa vê a sua em qualquer estado, o Administrador do distrito vê todas — apontando para a policy `liderancas_select_confirmada_propria_ou_admin` e o novo `arquivo:linha` da migration; (b) ajustar o parágrafo de linhas 70-73, que hoje afirma que "a RLS acima permite ler a tabela inteira", para descrever a regra vigente sem apagar o registro de que já foi assim; (c) conferir que a frase de abertura de linhas 60-62 ("Todas as policies abaixo concedem `select` ... com `using (true)`") deixa de valer para a tabela toda e passa a ter a exceção nomeada. **Cobre FR-010, SC-004** — a política de privacidade descreve o nível de acesso real, e uma afirmação desatualizada nela é uma promessa falsa ao titular

- [ ] T017 Rodar os quatro gates e registrar **número real**, não "passou": `flutter analyze` (esperado **0 issues**), `flutter test test/unit test/widget` (esperado **152**, inalterado — nenhum teste de widget novo, de propósito), `dart test test/integration` (esperado **133** = 127 da base + 6 de T006-T011), `flutter build web` (sem erro). **133 sem os 6 casos novos significa que o arquivo de teste não rodou** — investigar antes de dar a feature por pronta

---

## Dependências

```
T001 ──► T002 ──► T003 ──► T004 ──┬──► T005 ──► T006, T007, T008, T009, T010, T011  (US1)
                                  │              (mesmo arquivo, sequenciais)
                                  └──► T012 ──► T013 ──► T014 ──► T015              (US2)

T016 [P] — independente, pode rodar a qualquer momento depois de T004
T017 — último, depois de tudo
```

- **T001 e T002 antes de T003**: verificar premissa e reproduzir o vazamento antes de escrever
  o SQL. Consertar sem ver o problema é validar por tela com outro nome.
- **T004 antes de tudo mais**: sem a política aplicada, os testes de US1 passariam pelo motivo
  errado e as telas de US2 seriam medidas contra o comportamento antigo.
- **T006-T011 não são [P]**: mesmo arquivo.
- **US1 e US2 são independentes entre si** depois de T004 — dá para paralelizar as duas trilhas.

## Estratégia de entrega incremental

**MVP = Fase 1 + Fase 2 + Fase 3 (US1)**. Nesse ponto o vazamento está fechado e provado; a
US2 é verificação de que nada quebrou, não implementação. Se T012 ficar para depois, a única
consequência é o predicado do cliente ser mais frouxo que o da política — a política ainda
protege, porque é ela que decide.

---

## Cobertura (autoverificação)

**Requisitos funcionais — 10 de 10 cobertos:**

| Req | Tarefas |
|---|---|
| FR-001 | T003, T006 |
| FR-002 | T003, T007, T008 |
| FR-003 | T003, T009 |
| FR-004 | T003 |
| FR-005 | T003, T006, T007, T011 |
| FR-006 | T012, T013, T015 |
| FR-007 | T009, T015 |
| FR-008 | T008, T015 |
| FR-009 | T014 |
| FR-010 | T016 |

**Critérios de sucesso — 4 de 4 cobertos:**

| SC | Tarefas |
|---|---|
| SC-001 | T006, T007, T010 |
| SC-002 | T006, T013 |
| SC-003 | T013, T015 |
| SC-004 | T016 |

**User stories**: US1 → T002-T011 (10 tarefas). US2 → T012-T015 (4 tarefas).
Sem story → T001, T016, T017 (3 tarefas).

**Total: 17 tarefas.** 1 arquivo de migration novo, 1 arquivo de teste novo (6 casos),
1 linha em `lib/`, 1 bloco em `MAPA-DE-DADOS.md`.
