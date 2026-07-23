---

description: "Task list for Grupos"
---

# Tasks: Grupos

**Input**: Design documents from `/specs/002-grupos/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema da feature 001 (`perfis`, `igrejas`) já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV da constituição exige teste automatizado pra dono automático, invariantes de posse (transferir só pra participante, dono não sai sem transferir), e Participar idempotente.

**Organization**: tarefas agrupadas por user story (US1 Criar Grupo, US2 Descobrir/Participar, US3 Dono administra).

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único da feature 001: `lib/`, `supabase/`, `test/`.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, modelos, repositório e providers — tudo que toda user story usa. Inclui uma correção no router da feature 001: Visitante precisa navegar Home/Grupos sem ser forçado ao cadastro (só bloqueado ao tentar uma ação).

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/20260723220703_grupos.sql` seguindo exatamente `contracts/schema.sql` (`categorias_grupo`, `grupos`, `participacoes_grupo`, os 3 triggers de invariante, RLS + GRANTs) — validado empiricamente contra Postgres local (ver commit `64de17c`)
- [X] T002 [P] Adicionar seed das 18 categorias de `CATEGORIAS-DE-ACAO.md` em `supabase/seed.sql`
- [X] T003 [P] Criar modelo `Grupo`/`NovoGrupo` em `lib/features/grupo/domain/grupo.dart`
- [X] T004 [P] Criar modelo `CategoriaGrupo` em `lib/features/grupo/domain/categoria_grupo.dart`
- [X] T005 Implementar `GrupoRepository` (listar/criar/editar grupos, participar/sair, transferir posse, listar participantes via `perfil_publico`, listar categorias) em `lib/features/grupo/data/grupo_repository.dart` (depende de T003, T004)
- [X] T006 [P] Providers Riverpod (`grupoRepositoryProvider`, `gruposProvider`, `categoriasGrupoProvider`, `grupoProvider`, `participantesProvider`) em `lib/features/grupo/grupo_providers.dart`
- [X] T007 **Corrigir** `lib/app.dart`: removido o redirect que forçava `/cadastro` pra quem não tem Perfil — Visitante navega `/home` e as telas de Grupo livremente (FR-005/FR-008); mantido só o redirect de `/cadastro` → `/home` quando o Perfil já existe — testado em `test/widget/router_visitante_test.dart`
- [X] T008 CTA "Criar Perfil" implementado dentro de `lib/features/grupo/presentation/lista_grupos_page.dart` (que substituiu o placeholder `home_page.dart`, removido) — ponto de entrada manual pro cadastro
- [X] T009 Implementar `PerfilGuard.exigirPerfil(context, ref)` em `lib/features/perfil/domain/perfil_guard.dart`

**Checkpoint**: fundação pronta — user stories podem começar.

---

## Phase 2: User Story 1 - Criar Grupo (Priority: P1) 🎯 MVP

**Goal**: Usuário com Perfil cria um Grupo (nome, Categoria, horário, local, detalhes) e vira Dono automaticamente.

**Independent Test**: criar um Grupo do zero e confirmar que aparece na lista com o criador como Dono e já como participante.

### Tests for User Story 1

- [X] T010 [P] [US1] Teste de contrato: `insert` em `grupos` com nome em branco falha (`CHECK length(trim(nome)) > 0`), em `test/integration/grupos_constraints_test.dart`
- [X] T011 [P] [US1] Teste de contrato: criar grupo insere automaticamente uma `participacoes_grupo` pro `dono_id` (trigger `grupos_dono_vira_participante`), em `test/integration/grupo_dono_participante_test.dart`
- [X] T012 [P] [US1] Teste unitário: modelo `Grupo`/`NovoGrupo` valida campos obrigatórios, em `test/unit/grupo_model_test.dart`

### Implementation for User Story 1

- [X] T013 [US1] Implementar `CriarGrupoPage` (formulário nome/Categoria/horário/local/detalhes) em `lib/features/grupo/presentation/criar_grupo_page.dart`
- [X] T014 [US1] Ligar rota `/grupos/novo` em `lib/app.dart`, protegida por `PerfilGuard.exigirPerfil` (checado no FAB da `ListaGruposPage`)

**Checkpoint**: Grupo pode ser criado e aparece na lista com Dono correto.

---

## Phase 3: User Story 2 - Descobrir e participar de Grupo (Priority: P1)

**Goal**: qualquer pessoa vê a lista de Grupos e detalhes livremente; Usuário com Perfil participa/sai quando quiser.

**Independent Test**: abrir a lista de Grupos sem Perfil (confirma visibilidade), virar Usuário, Participar de um Grupo, sair, participar de novo.

### Tests for User Story 2

- [X] T015 [P] [US2] Teste de contrato: `select` em `grupos`/`participacoes_grupo` sem sessão autenticada (papel `anon`) retorna os registros, em `test/integration/grupos_select_publico_test.dart`
- [X] T016 [P] [US2] Teste de contrato: `upsert` em `participacoes_grupo` com `ON CONFLICT DO NOTHING` não duplica nem falha se já participa (FR-013), em `test/integration/participar_idempotente_test.dart`
- [X] T017 [P] [US2] Teste de widget: `ListaGruposPage` exibe grupos sem exigir Perfil, em `test/widget/lista_grupos_page_test.dart`
- [X] T018 [P] [US2] Teste de widget: `DetalheGrupoPage` sem Perfil direciona pro cadastro ao tentar Participar, em `test/widget/detalhe_grupo_page_test.dart`

### Implementation for User Story 2

- [X] T019 [P] [US2] Implementar `ListaGruposPage` em `lib/features/grupo/presentation/lista_grupos_page.dart`
- [X] T020 [US2] Implementar `DetalheGrupoPage` (detalhes + lista de participantes via `perfil_publico` + botão Participar/Sair) em `lib/features/grupo/presentation/detalhe_grupo_page.dart`
- [X] T021 [US2] Ligar rotas `/home` (lista) e `/grupos/:id` (detalhe) em `lib/app.dart`, ambas públicas (sem `PerfilGuard`)

**Checkpoint**: US1 e US2 funcionam juntas — Grupo criado é descobrível e as pessoas participam/saem.

---

## Phase 4: User Story 3 - Dono do Grupo administra (Priority: P2)

**Goal**: Dono edita o Grupo, remove participante, transfere a posse — com as duas invariantes garantidas no banco.

**Independent Test**: como Dono, editar um campo, remover um participante de teste, e transferir a posse — confirmando que quem não é Dono não consegue nenhuma dessas ações.

### Tests for User Story 3

- [X] T022 [P] [US3] Teste de contrato: `update` de `grupos.dono_id` pra alguém que não participa falha (trigger `grupos_dono_deve_participar`), em `test/integration/transferir_posse_test.dart`
- [X] T023 [P] [US3] Teste de contrato: `delete` da participação do Dono atual falha (trigger `participacoes_grupo_dono_nao_sai_sem_transferir`), em `test/integration/dono_nao_sai_sem_transferir_test.dart`
- [X] T024 [P] [US3] Teste de contrato: `update`/`delete` por quem não é Dono é recusado pela RLS (`grupos_update_dono`, `participacoes_grupo_delete_self_or_dono`), em `test/integration/apenas_dono_administra_test.dart`
- [X] T025 [P] [US3] Teste de widget: `EditarGrupoPage` só acessível/efetiva pro Dono, em `test/widget/editar_grupo_page_test.dart`

### Implementation for User Story 3

- [X] T026 [US3] Implementar `EditarGrupoPage` (editar campos, remover participante, transferir posse) em `lib/features/grupo/presentation/editar_grupo_page.dart`
- [X] T027 [US3] Ligar rota `/grupos/:id/editar` em `lib/app.dart` (visível só ao Dono via ícone de edição na `DetalheGrupoPage`; a própria `EditarGrupoPage` recusa quem não é Dono como defesa em profundidade)

**Checkpoint**: todas as user stories funcionam de forma independente.

---

## Phase 5: Polish & Cross-Cutting Concerns

- [X] T028 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados (61/61 testes + `flutter build macos --debug`)
- [X] T029 [P] Atualizar `README.md` (estrutura `lib/features/grupo/`, seção de Rotas)
- [X] T030 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001/002 — 61/61 verde contra schema recém-resetado (`supabase db reset`)

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo, inclui a correção do router (T007) que também beneficia a feature 001 (Visitante navegando Home)
- **US1/US2**: podem rodar em paralelo entre si depois da Fase 1 (US2 não depende de Grupo já existir pra testar visibilidade — só depende do schema)
- **US3**: depende de US1 (precisa de Grupo/Dono existentes) e US2 (precisa de participante pra transferir)
- **Polish**: depende de todas as user stories completas

## Notes

- Reusa `perfil_publico()` da feature 001 pra exibir participantes — nenhuma
  nova função de leitura pública de dado pessoal é criada aqui.
- T007-T009 são uma correção retroativa na feature 001 (o redirect forçado
  fazia sentido quando não existia nada pra Visitante ver; agora que Grupos
  existe, vira bug real contra FR-008 da 001).
