---

description: "Task list for Cadastro de Perfil e Upgrade para Conta"
---

# Tasks: Cadastro de Perfil e Upgrade para Conta

**Input**: Design documents from `/specs/001-cadastro-usuario/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: incluídos e obrigatórios — Princípio IV da constituição ("Integridade das Regras de Domínio Testada") exige teste automatizado para as regras não-negociáveis desta feature (Apelido obrigatório, idade nunca exposta, Perfil persiste, upgrade preserva o id).

**Organization**: tarefas agrupadas por user story (spec.md) para permitir implementação e teste independentes.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência entre si)
- **[Story]**: US1 (Criação de Perfil), US2 (Apelido obrigatório), US3 (Upgrade para Conta)

## Path Conventions

Projeto Flutter único (ver plan.md § Project Structure): `lib/`, `supabase/`, `test/`, `integration_test/` na raiz do repositório.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: inicialização do projeto Flutter e do projeto Supabase

- [X] T001 Rodar `flutter create .` na raiz e configurar `pubspec.yaml` com `supabase_flutter`, `flutter_riverpod`, `go_router`
- [X] T002 [P] Rodar `supabase init` e configurar `supabase/config.toml`
- [X] T003 [P] Configurar `analysis_options.yaml` (lint) e `.env`/`.env.example` com `SUPABASE_URL`/`SUPABASE_ANON_KEY`

**Checkpoint**: `flutter run` e `supabase start` sobem sem erro.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, cliente Supabase, tema visual e roteamento — tudo que toda user story usa

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T004 Criar `supabase/migrations/20260723191202_perfis_igrejas.sql` seguindo exatamente `contracts/schema.sql` (tabelas `igrejas`, `palavras_bloqueadas`, `perfis`; funções `nome_valido`, `perfil_publico`; RLS + GRANTs)
- [X] T005 [P] Criar `supabase/seed.sql` com lista inicial de igrejas do distrito (16) e lista inicial de `palavras_bloqueadas` para dev/test
- [X] T006 Implementar `lib/core/supabase_client.dart`: inicializa `supabase_flutter`, chama `signInAnonymously()` se não houver sessão
- [X] T007 [P] Implementar `lib/core/theme/app_theme.dart`: `ColorScheme` azul marinho + branco, tipografia e espaçamento no estilo 7me (ver plan.md § Visual)
- [X] T008 Implementar `lib/app.dart`: `MaterialApp.router` + `go_router` com redirect baseado em estado (sem perfil → cadastro; perfil existe → home)
- [X] T009 [P] Implementar `lib/core/providers.dart`: `ProviderScope`-friendly providers + stream do estado de auth (`onAuthStateChange`) + `hasPerfilProvider`/`igrejasProvider`

**Checkpoint**: fundação pronta — user stories podem começar.

---

## Phase 3: User Story 1 - Criação de Perfil (Priority: P1) 🎯 MVP

**Goal**: qualquer pessoa cria um Perfil (nome, gênero, idade, Igreja opcional, telefone opcional, consentimento LGPD) sem e-mail nem senha, e continua reconhecida ao reabrir o app.

**Independent Test**: abrir o app do zero, preencher o formulário sem e-mail/senha, confirmar Perfil criado; fechar e reabrir o app e confirmar que não pede cadastro de novo.

### Tests for User Story 1

> Escrever estes testes primeiro; confirmar que falham antes de implementar.

- [X] T010 [P] [US1] Teste de contrato: `insert` em `perfis` sem `consentimento_lgpd_aceito_em` falha, em `test/integration/perfis_constraints_test.dart` (movido de `integration_test/` — não depende de widget tree/device, roda direto no Postgres local via `package:postgres`)
- [X] T011 [P] [US1] Teste de contrato: `nome_valido()` rejeita nome com palavra da lista de bloqueio, em `test/integration/nome_valido_test.dart`
- [X] T012 [P] [US1] Teste unitário: modelo `Perfil` valida campos obrigatórios (nome, gênero, idade, consentimento), em `test/unit/perfil_model_test.dart`
- [X] T013 [US1] Teste de widget: `CadastroPerfilPage` bloqueia envio sem marcar consentimento LGPD, em `test/widget/cadastro_perfil_page_test.dart`

### Implementation for User Story 1

- [X] T014 [P] [US1] Criar modelo `Perfil` em `lib/features/perfil/domain/perfil.dart`
- [X] T015 [P] [US1] Criar modelo `Igreja` em `lib/features/perfil/domain/igreja.dart`
- [X] T016 [US1] Implementar `PerfilRepository` (buscar igrejas, inserir perfil) em `lib/features/perfil/data/perfil_repository.dart` (depende de T014, T015)
- [X] T017 [US1] Checagem "sessão existe mas não há linha em `perfis`" via `PerfilRepository.hasPerfil()` + `hasPerfilProvider`
- [X] T018 [US1] Implementar `CadastroPerfilPage` (formulário completo) em `lib/features/perfil/presentation/cadastro_perfil_page.dart`
- [X] T019 [US1] Implementar pré-checagem client-side de moderação de nome (cache local da lista) em `lib/features/perfil/domain/nome_moderation.dart`
- [X] T020 [US1] Ligar redirect do `go_router` (T008): sem linha em `perfis` → `CadastroPerfilPage`; linha existe → home
- [X] T021 [US1] Tratar erros de constraint (LGPD ausente, nome inválido) com mensagem clara em `cadastro_perfil_page.dart`

**Checkpoint**: User Story 1 completa e testável de forma independente — MVP navegável.

---

## Phase 4: User Story 2 - Apelido obrigatório para menor de idade (Priority: P2)

**Goal**: cadastro com idade abaixo de 18 exige Apelido antes de concluir; Apelido substitui o nome real em toda exibição pública.

**Independent Test**: cadastrar com idade <18, confirmar que a etapa de Apelido é obrigatória; consultar `perfil_publico()` desse Perfil e confirmar que devolve o Apelido, nunca o nome real nem a idade.

### Tests for User Story 2

- [X] T022 [P] [US2] Teste de contrato: `insert` em `perfis` com `idade < 18` e `apelido null` viola a constraint `apelido_obrigatorio_menor`, em `test/integration/apelido_obrigatorio_test.dart`
- [X] T023 [P] [US2] Teste de widget: fluxo de cadastro mostra e exige etapa de Apelido quando idade <18 — incluído em `test/widget/cadastro_perfil_page_test.dart` (caso "US2/FR-005")
- [X] T024 [P] [US2] Teste de contrato: `perfil_publico(id)` de um Perfil de menor retorna `nome_exibido = apelido` e nunca inclui `idade`, em `test/integration/perfil_publico_apelido_test.dart` (inclui também SC-003 via RLS)

### Implementation for User Story 2

- [X] T025 [US2] Adicionar etapa de Apelido (condicional a `idade < 18`) em `lib/features/perfil/presentation/cadastro_perfil_page.dart` (estende T018)
- [X] T026 [US2] Adicionar campo/validação de Apelido (sem informação identificável) em `lib/features/perfil/domain/perfil.dart`
- [X] T027 [US2] Implementar `PerfilRepository.fetchPerfilPublico(id)` usando a RPC `perfil_publico`, nunca `select` direto, em `lib/features/perfil/data/perfil_repository.dart`

**Checkpoint**: User Stories 1 e 2 funcionam juntas e de forma independente.

---

## Phase 5: User Story 3 - Upgrade de Perfil para Conta (Priority: P3)

**Goal**: Usuário vincula credencial de login (Conta) preservando o mesmo `auth.uid()`, recupera o Perfil em outro aparelho, e a autodeclaração de Líder/Diretor passa a exigir Conta.

**Independent Test**: criar Perfil, fazer upgrade para Conta, logar com a mesma credencial em outro aparelho/simulador e confirmar que o mesmo Perfil (dados, Apelido) aparece.

### Tests for User Story 3

- [X] T028 [P] [US3] Teste de contrato: `updateUser(email, senha)` sobre sessão anônima preserva `auth.uid()` e a linha em `perfis`, em `test/integration/upgrade_conta_test.dart`
- [X] T029 [P] [US3] Teste de contrato: login com credencial errada retorna erro genérico (sem indicar qual campo errou), em `test/integration/login_erro_generico_test.dart`
- [X] T030 [P] [US3] Teste de widget: `UpgradeContaPage` pode ser cancelada sem bloquear navegação, em `test/widget/upgrade_conta_page_test.dart`

### Implementation for User Story 3

- [X] T031 [P] [US3] Implementar `AuthRepository.upgradeParaConta(credencial, senha)` em `lib/features/perfil/data/auth_repository.dart`
- [X] T032 [P] [US3] Implementar `AuthRepository.login(credencial, senha)` em `lib/features/perfil/data/auth_repository.dart`
- [X] T033 [US3] Implementar `UpgradeContaPage` (acessível a qualquer momento, nunca bloqueante) em `lib/features/perfil/presentation/upgrade_conta_page.dart`
- [X] T034 [US3] Implementar `LoginPage` para recuperar Perfil em outro aparelho em `lib/features/perfil/presentation/login_page.dart`
- [X] T035 [US3] Implementar `ContaGuard` (exige `is_anonymous == false` antes de prosseguir; placeholder para as features futuras de autodeclaração de Líder/Diretor e promoção a Administrador do distrito) em `lib/features/perfil/domain/conta_guard.dart` — testado em `test/unit/conta_guard_test.dart`

**Checkpoint**: todas as user stories funcionam de forma independente.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T036 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados (27/27 testes automatizados + `flutter build macos --debug`; ver `quickstart.md` § Resultados)
- [X] T037 [P] Documentar como rodar localmente (`supabase start`, `flutter run`) no README do projeto
- [X] T038 Verificação de privacidade (SC-003): confirmado via `test/integration/perfil_publico_apelido_test.dart` (0 linhas vazadas) contra schema recém-resetado (`supabase db reset`)
- [ ] T039 [P] Registrar em `quickstart.md` os tempos medidos de cadastro (<2min, SC-001) e reabertura (<5s, SC-004) — **bloqueado**: ambiente sem display pra rodar o app interativamente; documentado como lacuna conhecida em `quickstart.md`, precisa de QA manual num dispositivo/simulador real

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Fase 1)**: sem dependências
- **Foundational (Fase 2)**: depende da Fase 1 — bloqueia todas as user stories
- **User Stories (Fase 3-5)**: todas dependem da Fase 2; podem rodar em paralelo entre si, mas a ordem recomendada é P1 → P2 → P3
- **Polish (Fase 6)**: depende de todas as user stories desejadas estarem completas

### User Story Dependencies

- **US1 (P1)**: sem dependência de outra story
- **US2 (P2)**: estende a tela de cadastro da US1 (T018), mas é testável isoladamente via os testes de contrato T022/T024
- **US3 (P3)**: independente de US1/US2 no código (repositório de auth próprio), mas pressupõe que um Perfil já exista para fazer upgrade

### Within Each User Story

- Testes escritos e falhando antes da implementação
- Modelos antes de repositórios
- Repositórios antes de telas
- Story completa antes de avançar pra próxima prioridade

---

## Parallel Example: User Story 1

```bash
# Testes da US1 em paralelo:
Task: "Teste de contrato: insert sem consentimento LGPD falha em integration_test/perfis_constraints_test.dart"
Task: "Teste de contrato: nome_valido rejeita palavrão em integration_test/nome_valido_test.dart"
Task: "Teste unitário: modelo Perfil valida campos obrigatórios em test/unit/perfil_model_test.dart"

# Modelos da US1 em paralelo:
Task: "Criar modelo Perfil em lib/features/perfil/domain/perfil.dart"
Task: "Criar modelo Igreja em lib/features/perfil/domain/igreja.dart"
```

---

## Implementation Strategy

### MVP First (User Story 1 Only)

1. Fase 1: Setup
2. Fase 2: Foundational (bloqueia tudo)
3. Fase 3: User Story 1
4. **Parar e validar**: testar US1 isoladamente (cenários 1-5 de spec.md)
5. Demonstrar/avaliar antes de seguir pra US2

### Incremental Delivery

1. Setup + Foundational → fundação pronta
2. US1 → validar → MVP
3. US2 → validar → protege menores de idade
4. US3 → validar → habilita persistência entre aparelhos e pré-requisito de Líder/Diretor

---

## Notes

- [P] = arquivos diferentes, sem dependência entre si
- Rótulo [Story] mapeia a tarefa à user story correspondente
- Confirmar que os testes falham antes de implementar (Princípio IV, TDD leve nesta feature)
- Commitar após cada tarefa ou grupo lógico coeso
- Parar em cada checkpoint pra validar a story isoladamente
