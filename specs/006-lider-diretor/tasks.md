---

description: "Task list for Líder/Diretor de Ministério"
---

# Tasks: Líder/Diretor de Ministério

**Input**: Design documents from `/specs/006-lider-diretor/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema das features 001/002/005 já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV exige teste automatizado pra exige-Conta, duplicata não-operação, só-admin-decide, identificação pública só do ano corrente, codireção, redeclarar após expirar/rejeitar.

**Organization**: tarefas agrupadas por user story (US1 Autodeclarar, US2 Admin confirma/rejeita, US3 Identificação pública, US4 Redeclarar anual).

**Convenção de idioma**: `lib/features/leadership/` inteira em inglês.
`DetalheGrupoPage` (português, feature 002) ganha uma seção nova.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único; `lib/features/leadership/` é pasta nova.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, modelo/repositório/providers.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/<timestamp>_leadership.sql` seguindo exatamente `contracts/schema.sql` (`liderancas`, `declarar_lideranca`, `decidir_lideranca`, RLS + GRANTs)
- [X] T002 [P] Criar modelo `LeadershipDeclaration` (+ `LeadershipStatus` enum, `isCurrentFor(year)`) em `lib/features/leadership/domain/leadership_declaration.dart`
- [X] T003 Implementar `LeadershipRepository` (declarar, decidir, buscar líderes atuais, buscar pendentes, buscar minha declaração, resolver perfil público) em `lib/features/leadership/data/leadership_repository.dart`
- [X] T004 [P] Providers Riverpod (`leadershipRepositoryProvider`, `currentLeadersProvider`, `myDeclarationProvider`, `pendingDeclarationsProvider`) em `lib/features/leadership/leadership_providers.dart`

**Checkpoint**: fundação pronta.

---

## Phase 2: User Story 1 - Autodeclarar Líder/Diretor (Priority: P1) 🎯 MVP

**Goal**: Usuário com Conta se autodeclara Líder/Diretor de um Grupo pro ano corrente.

**Independent Test**: autodeclarar e confirmar que a declaração aparece como pendente.

### Tests for User Story 1

- [X] T005 [P] [US1] Teste de contrato: Usuário sem Conta não consegue chamar `declarar_lideranca` (FR-002), em `test/integration/leadership_requires_account_test.dart`
- [X] T006 [P] [US1] Teste de contrato: chamar `declarar_lideranca` duas vezes pro mesmo Grupo/ano é não-operação (FR-003), em `test/integration/leadership_declare_idempotent_test.dart`
- [X] T007 [P] [US1] Teste unitário: `LeadershipDeclaration.status`/`isCurrentFor`, em `test/unit/leadership_declaration_model_test.dart`

### Implementation for User Story 1

- [X] T008 [US1] Implementar `DeclareLeadershipPage` (botão autodeclarar + status da própria declaração) em `lib/features/leadership/presentation/declare_leadership_page.dart`
- [X] T009 [US1] Ligar rota `/grupos/:id/leadership/declare` em `lib/app.dart`, protegida por `PerfilGuard`

**Checkpoint**: autodeclaração funciona — MVP navegável.

---

## Phase 3: User Story 2 - Administrador confirma ou rejeita (Priority: P1)

**Goal**: Administrador do distrito vê pendentes de todo o distrito e decide cada uma.

**Independent Test**: com uma declaração pendente, confirmar ou rejeitar e checar o resultado.

### Tests for User Story 2

- [X] T010 [P] [US2] Teste de contrato: Dono do Grupo (não-admin) e Usuário comum não conseguem chamar `decidir_lideranca` (FR-005), em `test/integration/leadership_decide_authorization_test.dart`
- [X] T011 [P] [US2] Teste de contrato: Administrador confirma e rejeita corretamente (FR-004), em `test/integration/leadership_decide_test.dart`

### Implementation for User Story 2

- [X] T012 [US2] Implementar `PendingDeclarationsPage` (lista pendentes do distrito, com nome do Grupo e do declarante, botões Confirmar/Rejeitar) em `lib/features/leadership/presentation/pending_declarations_page.dart`
- [X] T013 [US2] Ligar rota `/leadership/pending` em `lib/app.dart`, ícone visível só a Administrador (reusa o padrão da `ListaGruposPage`, feature 005)

**Checkpoint**: US1 e US2 juntas — ciclo de decisão completo.

---

## Phase 4: User Story 3 - Identificação pública do Líder (Priority: P2)

**Goal**: qualquer pessoa vê o Líder/Diretor confirmado do ano corrente na página do Grupo.

**Independent Test**: com uma liderança confirmada, abrir a página do Grupo sem Perfil e ver a identificação.

### Tests for User Story 3

- [X] T014 [P] [US3] Teste de contrato: só declaração confirmada do ano corrente aparece na consulta pública; confirmada de ano anterior não aparece (FR-006/FR-008), em `test/integration/leadership_public_current_test.dart`
- [X] T015 [P] [US3] Teste de widget: `DetalheGrupoPage` exibe Líder(es) confirmados, inclusive mais de um (codireção, FR-007), em `test/widget/detalhe_grupo_page_leadership_test.dart`

### Implementation for User Story 3

- [X] T016 [US3] Estender `DetalheGrupoPage` (feature 002) com seção "Líder/Diretor" usando `currentLeadersProvider`; sem Líder confirmado, seção não aparece (Grupo comum, não Ministério)

**Checkpoint**: identificação pública funciona.

---

## Phase 5: User Story 4 - Redeclarar a cada ano (Priority: P3)

**Goal**: confirmação de ano anterior não conta como atual; redeclarar pro ano corrente funciona.

**Independent Test**: com uma confirmação de ano anterior, verificar que não aparece como atual e que a mesma pessoa redeclara pro ano corrente sem erro.

### Tests for User Story 4

- [X] T017 [P] [US4] Teste de contrato: confirmação de ano anterior não conta como atual, mesma pessoa redeclara pro ano corrente com sucesso (FR-008/FR-009), em `test/integration/leadership_yearly_expiry_test.dart`
- [X] T018 [P] [US4] Teste de contrato: redeclarar depois de rejeitado no mesmo ano volta a ficar pendente (FR-010), em `test/integration/leadership_redeclare_after_reject_test.dart`

### Implementation for User Story 4

*(Nenhuma implementação nova — `declarar_lideranca` e a comparação de `ano` já cobrem isto desde a Fase 1/Fase 4; esta fase é só validação adicional.)*

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T019 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados
- [X] T020 [P] Atualizar `README.md` (rotas novas, estrutura `lib/features/leadership/`)
- [X] T021 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001-006

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo
- **US1/US2**: sequenciais em valor (decidir precisa de declaração existir), mas o código é independente
- **US3**: depende de existir ao menos uma declaração confirmada pra ser demonstrável
- **US4**: reusa a mesma função de US1 — só validação adicional, sem código novo

## Notes

- `declarar_lideranca`/`decidir_lideranca` são `SECURITY DEFINER` — sem
  `GRANT INSERT/UPDATE` na tabela pra `authenticated` (ver research.md).
