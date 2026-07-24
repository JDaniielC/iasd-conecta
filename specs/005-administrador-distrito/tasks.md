---

description: "Task list for Administrador do Distrito"
---

# Tasks: Administrador do Distrito

**Input**: Design documents from `/specs/005-administrador-distrito/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema das features 001/002/004 já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV exige teste automatizado pra só-admin-promove, promovido precisa ter Conta, arquivar preserva histórico, visibilidade de arquivadas, admin cancela qualquer Ação.

**Organization**: tarefas agrupadas por user story (US1 Promover Administrador, US2 Gerenciar Igrejas, US3 Cancelar qualquer Ação).

**Convenção de idioma**: primeira feature com código Dart em inglês
(classes/variáveis/métodos/arquivos) — banco de dados continua em
português. `Igreja` é traduzido pra `Church` por ser diretamente tocado
aqui; `Perfil`/`Grupo`/`Acao` não são tocados por esta feature.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único; `lib/features/district_admin/` é pasta nova em
inglês. `lib/features/perfil/domain/igreja.dart` vira `church.dart`.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, tradução de `Igreja`→`Church`, modelo/repositório/providers de Administrador do distrito.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/20260724092132_district_admin.sql` seguindo exatamente `contracts/schema.sql` — validado empiricamente contra Postgres local, incluindo a correção `SECURITY DEFINER` (commit `3faf08d`)
- [X] T002 Renomear `lib/features/perfil/domain/igreja.dart` → `church.dart` (classe `Igreja`→`Church`, campo `nome`→`name`, mais `archivedAt`/`isArchived`); `fetchIgrejas()`→`fetchChurches()`; `igrejasProvider`→`churchesProvider`; usos em `cadastro_perfil_page.dart` e no teste de widget correspondente atualizados — 111/111 sem regressão
- [X] T003 [P] Criar modelo `DistrictAdmin` em `lib/features/district_admin/domain/district_admin.dart`
- [X] T004 Implementar `DistrictAdminRepository` (checar se é admin, promover, adicionar/arquivar Church — reusa `PerfilRepository.fetchChurches` pra listar, RLS já resolve visibilidade) em `lib/features/district_admin/data/district_admin_repository.dart`
- [X] T005 [P] Providers Riverpod (`districtAdminRepositoryProvider`, `isDistrictAdminProvider`) em `lib/features/district_admin/district_admin_providers.dart`

**Checkpoint**: fundação pronta; `Church` traduzido; suíte inteira sem regressão.

---

## Phase 2: User Story 1 - Promover Usuário a Administrador do distrito (Priority: P1) 🎯 MVP

**Goal**: Administrador existente promove um Usuário com Conta a Administrador.

**Independent Test**: com um Administrador semeado, promover um Usuário com Conta e confirmar que ele vira Administrador.

### Tests for User Story 1

- [X] T006 [P] [US1] Teste de contrato: quem não é Administrador não consegue inserir em `administradores_distrito` (FR-003), em `test/integration/district_admin_promote_authorization_test.dart`
- [X] T007 [P] [US1] Teste de contrato: promover um Usuário sem Conta falha (FR-002), em `test/integration/district_admin_requires_account_test.dart`
- [X] T008 [P] [US1] Teste unitário: modelo `DistrictAdmin`, em `test/unit/district_admin_model_test.dart`

### Implementation for User Story 1

- [X] T009 [US1] Implementar `PromoteAdminPage` (campo de ID do Perfil a promover) em `lib/features/district_admin/presentation/promote_admin_page.dart`
- [X] T010 [US1] Ligar rota `/district-admin/promote` em `lib/app.dart`; ícone visível só a quem já é Administrador na `ListaGruposPage`

**Checkpoint**: promoção funciona — MVP navegável.

---

## Phase 3: User Story 2 - Gerenciar lista de Igrejas (Priority: P1)

**Goal**: Administrador adiciona/arquiva Church; arquivada some da lista pra quem não é Administrador mas continua visível pra quem é.

**Independent Test**: adicionar uma Church nova e arquivar outra, confirmando que a arquivada some da lista de opções mas continua intacta.

### Tests for User Story 2

- [X] T011 [P] [US2] Teste de contrato: quem não é Administrador não consegue inserir/arquivar Church (FR-006), em `test/integration/church_manage_authorization_test.dart`
- [X] T012 [P] [US2] Teste de contrato: Church arquivada some do `select` de não-admin mas continua visível pra admin (FR-007/FR-008), em `test/integration/church_archive_visibility_test.dart`
- [X] T013 [P] [US2] Teste de widget: `ManageChurchesPage` lista ativas e arquivadas, botão Arquivar só nas ativas, em `test/widget/manage_churches_page_test.dart`

### Implementation for User Story 2

- [X] T014 [US2] Implementar `ManageChurchesPage` (listar ativas/arquivadas, adicionar, arquivar) em `lib/features/district_admin/presentation/manage_churches_page.dart`
- [X] T015 [US2] Ligar rota `/district-admin/churches` em `lib/app.dart`; ícone visível só a Administrador na `ListaGruposPage`

**Checkpoint**: US1 e US2 juntas — gestão de Administrador e Church funcionando.

---

## Phase 4: User Story 3 - Cancelar qualquer Ação (Priority: P2)

**Goal**: Administrador cancela qualquer Ação, somando-se a quem já podia.

**Independent Test**: Administrador cancela uma Ação que não criou e cujo Grupo não administra.

### Tests for User Story 3

- [X] T016 [P] [US3] Teste de contrato: Administrador cancela Ação avulsa e Ação de Grupo que não criou/não administra (FR-009), em `test/integration/district_admin_cancel_any_action_test.dart`

### Implementation for User Story 3

- [X] T017 [US3] `Acao.podeCancelar` ganha `souAdministradorDoDistrito`; `DetalheAcaoPage` resolve via `isDistrictAdminProvider`

**Checkpoint**: todas as user stories funcionam de forma independente.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T018 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados (122/122 testes + `flutter build macos --debug`); corrigido o snippet de bootstrap do primeiro admin (precisa disable/enable trigger, não só `service_role`)
- [X] T019 [P] Atualizar `README.md` (rotas novas, nota sobre `Church`/convenção de idioma)
- [X] T020 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001-005 — 122/122 verde contra schema recém-resetado

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo — inclui a tradução `Igreja`→`Church`, que toca arquivos das features 001/002 (risco de regressão, testar com atenção)
- **US1/US2**: podem rodar em paralelo depois da Fase 1
- **US3**: independente de US1/US2 no código, mas conceitualmente depende de já existir ao menos um Administrador pra testar

## Notes

- `Church` é o primeiro modelo traduzido sob a nova convenção de idioma —
  qualquer arquivo que o referencie precisa compilar com o novo nome, daí
  T002 estar na fase Foundational (bloqueante) em vez de dentro de uma
  user story.
