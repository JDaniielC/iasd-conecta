---

description: "Task list for Ação Sugerida"
---

# Tasks: Ação Sugerida

**Input**: Design documents from `/specs/008-acao-sugerida/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema das features 002/005 já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV exige teste automatizado pra só-admin-escreve, join por categoria, não-persistência do filtro.

**Organization**: tarefas agrupadas por user story (US1 Sugestão na candidata, US2 Filtro na Ação avulsa, US3 Administrador mantém a lista).

**Convenção de idioma**: `lib/features/acao_sugerida/` inteira em inglês.
`criar_acao_page.dart`/`criar_candidata_page.dart` (português) ganham um
campo novo cada.

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único; `lib/features/acao_sugerida/` é pasta nova.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, modelo/repositório/providers.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/<timestamp>_acao_sugerida.sql` seguindo exatamente `contracts/schema.sql` (`acoes_sugeridas`, RLS select público + insert/delete admin)
- [X] T002 [P] Criar modelo `SuggestedAction` em `lib/features/acao_sugerida/domain/suggested_action.dart`
- [X] T003 Implementar `SuggestedActionRepository` (`fetchByCategoryName(String categoriaNome)`, `fetchByCategoryId(String categoriaId)`, `create`, `delete`) em `lib/features/acao_sugerida/data/suggested_action_repository.dart`
- [X] T004 [P] Providers Riverpod (`suggestedActionRepositoryProvider`, `suggestionsForGroupProvider(grupoId)`, `suggestionsForCategoryProvider(categoriaId)`, `allSuggestedActionsProvider`) em `lib/features/acao_sugerida/suggested_action_providers.dart`

**Checkpoint**: fundação pronta.

---

## Phase 2: User Story 1 - Sugestão automática ao propor Ação candidata (Priority: P1) 🎯 MVP

**Goal**: ao propor uma Ação candidata, as sugestões da Categoria do Grupo pai aparecem automaticamente.

**Independent Test**: com sugestões cadastradas pra uma Categoria, propor candidata num Grupo dessa Categoria e conferir que aparecem.

### Tests for User Story 1

- [X] T005 [P] [US1] Teste de contrato: `fetchByCategoryName` retorna só as sugestões da Categoria informada (FR-004), em `test/integration/acao_sugerida_join_categoria_test.dart`
- [X] T006 [P] [US1] Teste de contrato: Categoria sem nenhuma Ação sugerida retorna lista vazia, sem erro (FR-008), em `test/integration/acao_sugerida_categoria_vazia_test.dart`
- [X] T007 [P] [US1] Teste unitário: `SuggestedAction.fromMap`, em `test/unit/suggested_action_model_test.dart`

### Implementation for User Story 1

- [X] T008 [US1] Estender `CriarCandidataPage` (`lib/features/acao/presentation/criar_candidata_page.dart`): mostrar chips/lista de sugestões da Categoria do Grupo pai (via `suggestionsForGroupProvider`); tocar numa sugestão preenche o campo de nome, sem obrigar

**Checkpoint**: sugestão na candidata funciona — MVP navegável.

---

## Phase 3: User Story 2 - Sugestão filtrada por Categoria ao criar Ação avulsa (Priority: P2)

**Goal**: ao criar Ação avulsa, escolher uma Categoria filtra as sugestões exibidas, sem persistir a escolha.

**Independent Test**: escolher uma Categoria na tela de criar Ação avulsa e conferir que só as sugestões daquela Categoria aparecem, e que a Ação avulsa salva não tem Categoria nenhuma.

### Tests for User Story 2

- [X] T009 [P] [US2] Teste unitário: `NovaAcao.toInsertMap` nunca inclui categoria, mesmo quando construído a partir de um filtro de Categoria escolhido na tela (FR-006), em `test/widget/criar_acao_page_categoria_filtro_test.dart`

### Implementation for User Story 2

- [X] T010 [US2] Estender `CriarAcaoPage` (`lib/features/acao/presentation/criar_acao_page.dart`): `DropdownButtonFormField` de Categoria (reusa `categoriasGrupoProvider`, feature 002) só como filtro de tela; lista de sugestões via `suggestionsForCategoryProvider`, sem enviar a Categoria escolhida em `NovaAcao`

**Checkpoint**: US1 e US2 juntas — sugestão funciona nos dois fluxos de criação.

---

## Phase 4: User Story 3 - Administrador mantém a lista de Ações sugeridas (Priority: P2)

**Goal**: Administrador do distrito cadastra e remove Ações sugeridas.

**Independent Test**: cadastrar uma Ação sugerida numa Categoria e conferir que ela aparece nas sugestões dessa Categoria.

### Tests for User Story 3

- [X] T011 [P] [US3] Teste de contrato: não-Administrador não consegue cadastrar nem remover Ação sugerida (FR-003), em `test/integration/acao_sugerida_authorization_test.dart`
- [X] T012 [P] [US3] Teste de contrato: Administrador cadastra e remove com sucesso; remover não afeta Ação já criada a partir da sugestão (FR-001/FR-002), em `test/integration/acao_sugerida_admin_crud_test.dart`
- [X] T013 [P] [US3] Teste de contrato: mesmo nome em Categorias diferentes é permitido (FR-009), em `test/integration/acao_sugerida_nome_duplicado_test.dart`

### Implementation for User Story 3

- [X] T014 [US3] Implementar `ManageSuggestedActionsPage` (lista por Categoria, formulário de cadastro, remover) em `lib/features/acao_sugerida/presentation/manage_suggested_actions_page.dart`, seguindo o layout de `ManageChurchesPage` (feature 005)
- [X] T015 [US3] Ligar rota `/district-admin/suggested-actions` em `lib/app.dart`; ícone em `ListaGruposPage` visível só a Administrador (mesmo padrão de `/district-admin/churches`)

**Checkpoint**: ciclo completo — Administrador cadastra, US1/US2 consomem.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T016 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados
- [X] T017 [P] Atualizar `README.md` (rotas novas, estrutura `lib/features/acao_sugerida/`)
- [X] T018 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001-007

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo
- **US1**: só depende da Fase 1
- **US2**: só depende da Fase 1 (independente de US1)
- **US3**: só depende da Fase 1; US1/US2 ficam mais fáceis de demonstrar
  com US3 pronta (dados pra sugerir), mas não dependem dela tecnicamente
  (podem ser testadas com dados semeados direto no banco)

## Notes

- Nenhuma função `SECURITY DEFINER` — a autorização de escrita é uma
  policy simples (`exists (... administradores_distrito ...)`), sem
  necessidade de ler dado de outro usuário (ver research.md).
