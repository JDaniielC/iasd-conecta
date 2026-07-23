---

description: "Task list for Ação Avulsa"
---

# Tasks: Ação Avulsa

**Input**: Design documents from `/specs/003-acao-avulsa/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema da feature 001 (`perfis`) já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV da constituição exige teste automatizado pra criador confirmado automático, fila de espera, promoção automática, e só-criador cancela.

**Organization**: tarefas agrupadas por user story (US1 Criar Ação, US2 Confirmar/desistir, US3 Fila de espera, US4 Cancelar).

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único das features 001/002: `lib/`, `supabase/`, `test/`.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, modelos, repositório e providers.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/20260723230639_acoes.sql` seguindo exatamente `contracts/schema.sql` (`acoes`, `confirmacoes_acao`, os 3 triggers, RLS + GRANTs) — validado empiricamente contra Postgres local (commit `8639fe5`)
- [X] T002 [P] Criar modelo `Acao`/`NovaAcao` em `lib/features/acao/domain/acao.dart`
- [X] T003 Implementar `AcaoRepository` (listar/criar/cancelar Ação, confirmar/desistir, listar confirmados via `perfil_publico`) em `lib/features/acao/data/acao_repository.dart` (depende de T002)
- [X] T004 [P] Providers Riverpod (`acaoRepositoryProvider`, `acoesProvider`, `acaoProvider`, `confirmadosProvider`) em `lib/features/acao/acao_providers.dart`

**Checkpoint**: fundação pronta.

---

## Phase 2: User Story 1 - Criar Ação avulsa (Priority: P1) 🎯 MVP

**Goal**: Usuário com Perfil cria uma Ação já confirmada, sem votação; vira confirmado automaticamente.

**Independent Test**: criar uma Ação do zero e confirmar que ela aparece já confirmada, com o criador na lista de confirmados.

### Tests for User Story 1

- [X] T005 [P] [US1] Teste de contrato: `insert` em `acoes` com nome em branco falha, em `test/integration/acoes_constraints_test.dart` (inclui também `limite_vagas <= 0`)
- [X] T006 [P] [US1] Teste de contrato: criar Ação insere automaticamente uma `confirmacoes_acao` (status `confirmado`) pro `criador_id` (FR-013), em `test/integration/acao_criador_confirmado_test.dart`
- [X] T007 [P] [US1] Teste unitário: modelo `Acao`/`NovaAcao` valida campos obrigatórios, em `test/unit/acao_model_test.dart`

### Implementation for User Story 1

- [X] T008 [US1] Implementar `CriarAcaoPage` (nome, data/hora, local, detalhes, limite de vagas opcional) em `lib/features/acao/presentation/criar_acao_page.dart`
- [X] T009 [US1] Ligar rota `/acoes/novo` em `lib/app.dart` (navegação protegida por `PerfilGuard.exigirPerfil` chega junto com o botão na `ListaAcoesPage`, US2/T014)

**Checkpoint**: Ação pode ser criada — MVP navegável.

---

## Phase 3: User Story 2 - Confirmar presença e desistir (Priority: P1)

**Goal**: qualquer Usuário confirma/desiste; Visitante vê livremente mas não confirma; confirmar é idempotente.

**Independent Test**: confirmar presença numa Ação e depois desistir, verificando reflexo imediato na lista.

### Tests for User Story 2

- [X] T010 [P] [US2] Teste de contrato: confirmar presença duas vezes não duplica nem falha (FR-012), em `test/integration/confirmar_idempotente_test.dart`
- [X] T011 [P] [US2] Teste de contrato: papel `anon` (Visitante) vê `acoes`/`confirmacoes_acao` sem sessão (FR-010), em `test/integration/acoes_select_publico_test.dart`
- [X] T012 [P] [US2] Teste de widget: `ListaAcoesPage` exibe Ações sem exigir Perfil, em `test/widget/lista_acoes_page_test.dart`
- [X] T013 [P] [US2] Teste de widget: `DetalheAcaoPage` sem Perfil direciona pro cadastro ao tentar confirmar, em `test/widget/detalhe_acao_page_test.dart`

### Implementation for User Story 2

- [X] T014 [P] [US2] Implementar `ListaAcoesPage` em `lib/features/acao/presentation/lista_acoes_page.dart` (extraído `PerfilAusenteBanner` compartilhado com `ListaGruposPage` em `lib/features/perfil/presentation/widgets/`)
- [X] T015 [US2] Implementar `DetalheAcaoPage` (detalhes + lista de confirmados/fila via `perfil_publico` + botão confirmar/desistir) em `lib/features/acao/presentation/detalhe_acao_page.dart`
- [X] T016 [US2] Ligar rotas `/acoes` (lista) e `/acoes/:id` (detalhe) em `lib/app.dart`, ambas públicas; navegação cruzada Grupos↔Ações via ícone na AppBar

**Checkpoint**: US1 e US2 funcionam juntas.

---

## Phase 4: User Story 3 - Vaga lotada e fila de espera (Priority: P2)

**Goal**: confirmação em Ação lotada vira fila; desistência promove o próximo automaticamente.

**Independent Test**: Ação com limite 1, dois Usuários confirmam (2º cai na fila), 1º desiste → 2º promovido automaticamente.

### Tests for User Story 3

- [X] T017 [P] [US3] Teste de contrato: confirmar em Ação lotada vira `fila` em vez de `confirmado` (FR-005), em `test/integration/fila_de_espera_test.dart`
- [X] T018 [P] [US3] Teste de contrato: desistência de um `confirmado` promove o `fila` mais antigo (FR-006), em `test/integration/promover_fila_test.dart`
- [X] T019 [P] [US3] Teste de contrato: sair da fila (sem ser `confirmado`) não promove ninguém, em `test/integration/sair_da_fila_test.dart`

### Implementation for User Story 3

- [X] T020 [US3] Exibir status (confirmados vs. fila de espera, separados) na `DetalheAcaoPage` (já incluído em T015)

**Checkpoint**: todas as três user stories de confirmação funcionam.

---

## Phase 5: User Story 4 - Cancelar Ação avulsa (Priority: P3)

**Goal**: só quem criou cancela; Ação cancelada não aceita novas confirmações.

**Independent Test**: criar, cancelar, confirmar que ninguém mais confirma e que quem não criou não consegue cancelar.

### Tests for User Story 4

- [X] T021 [P] [US4] Teste de contrato: `update` de `cancelada_em` por quem não é criador é recusado pela RLS (FR-008), em `test/integration/apenas_criador_cancela_test.dart`
- [X] T022 [P] [US4] Teste de contrato: confirmar presença numa Ação cancelada falha (FR-009), em `test/integration/acao_cancelada_bloqueia_test.dart`

### Implementation for User Story 4

- [X] T023 [US4] Botão "Cancelar Ação" na `DetalheAcaoPage`, visível só ao criador (já incluído em T015)

**Checkpoint**: todas as user stories funcionam de forma independente.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T024 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados (89/89 testes + `flutter build macos --debug`)
- [X] T025 [P] Atualizar `README.md` (estrutura `lib/features/acao/`, rotas)
- [X] T026 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001/002/003 — 89/89 verde contra schema recém-resetado

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo
- **US1/US2**: podem rodar em paralelo depois da Fase 1
- **US3**: depende de US1 (Ação com limite) e US2 (confirmar/desistir) já existirem
- **US4**: depende de US1 (Ação existir); independente de US2/US3
- **Polish**: depende de todas as user stories completas

## Notes

- Reusa `perfil_publico()` das features anteriores pra exibir confirmados —
  nenhuma nova função de leitura pública de dado pessoal é criada aqui.
- Reusa `PerfilGuard.exigirPerfil` da feature 002 pra proteger a ação de
  criar/confirmar — nenhum gate novo é necessário.
