---

description: "Task list for Rodada de Votação"
---

# Tasks: Rodada de Votação

**Input**: Design documents from `/specs/004-rodada-votacao/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema das features 001/002/003 já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV exige teste automatizado pra participante-only, voto revogável, fechamento preguiçoso, sorteio de empate, vencedora confirmada, perdedoras descartadas, só quem propôs/Dono cancela.

**Organization**: tarefas agrupadas por user story (US1 Abrir+Propor, US2 Votar, US3 Fechar+Apurar, US4 Confirmar presença em candidata, US5 Cancelar Ação de Grupo).

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único; esta feature estende `lib/features/acao/` em vez de criar uma pasta nova (Ação candidata reusa a entidade Ação).

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco, modelos, repositório e providers.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/20260724084300_rodada_votacao.sql` seguindo exatamente `contracts/schema.sql` — validado empiricamente contra Postgres local (commit `e75fcfc`)
- [X] T002 [P] Criar modelo `Rodada`/`NovaRodada`/`Voto` em `lib/features/acao/domain/rodada.dart`
- [X] T003 Estender modelo `Acao` (`lib/features/acao/domain/acao.dart`) com `grupoId`, `rodadaId`, `confirmada`, `podeCancelar`
- [X] T004 Implementar `RodadaRepository` (abrir Rodada, propor candidata via `AcaoRepository`, votar, listar, fechar/forçar) em `lib/features/acao/data/rodada_repository.dart`
- [X] T005 [P] Providers Riverpod (`rodadaRepositoryProvider`, `rodadasDoGrupoProvider`, `rodadaProvider`, `candidatasProvider`, `meuVotoProvider`) em `lib/features/acao/rodada_providers.dart`

**Checkpoint**: fundação pronta.

---

## Phase 2: User Story 1 - Abrir Rodada e propor Ação candidata (Priority: P1) 🎯 MVP

**Goal**: participante de um Grupo abre Rodada com prazo; qualquer participante propõe candidatas nela.

**Independent Test**: abrir uma Rodada e propor duas candidatas, confirmando que ambas aparecem listadas.

### Tests for User Story 1

- [X] T006 [P] [US1] Teste de contrato: quem não participa do Grupo não abre Rodada (trigger `rodadas_votacao_checar_participante`), em `test/integration/rodada_abrir_participante_test.dart`
- [X] T007 [P] [US1] Teste de contrato: propor candidata deriva `grupo_id` da Rodada e recusa não-participante (trigger `acoes_candidata_checar_regras`), em `test/integration/candidata_propor_test.dart`
- [X] T008 [P] [US1] Teste unitário: modelo `NovaRodada`/`Voto` valida campos obrigatórios, em `test/unit/rodada_model_test.dart`

### Implementation for User Story 1

- [X] T009 [US1] Implementar `CriarRodadaPage` (prazo) em `lib/features/acao/presentation/criar_rodada_page.dart`
- [X] T010 [US1] Implementar `ListaRodadasPage` (Rodadas de um Grupo) em `lib/features/acao/presentation/lista_rodadas_page.dart`
- [X] T011 [US1] Implementar `CriarCandidataPage` (mesmo formulário de `CriarAcaoPage`, mas vinculada a uma Rodada) em `lib/features/acao/presentation/criar_candidata_page.dart`
- [X] T012 [US1] Ligar rotas `/grupos/:id/rodadas` (lista), `/grupos/:id/rodadas/novo`, `/rodadas/:id/candidatas/novo` em `lib/app.dart`; ícone de acesso em `DetalheGrupoPage`

**Checkpoint**: Rodada e candidatas existem — MVP navegável.

---

## Phase 3: User Story 2 - Votar numa candidata (Priority: P1)

**Goal**: participante do Grupo vota; trocar de voto conta só a última escolha.

**Independent Test**: votar, trocar de candidata, confirmar que só a última conta.

### Tests for User Story 2

- [X] T013 [P] [US2] Teste de contrato: `upsert` em `votos` — trocar de candidata atualiza a mesma linha, só a última conta (FR-006), em `test/integration/voto_revogavel_test.dart`
- [X] T014 [P] [US2] Teste de contrato: quem não participa do Grupo não vota (trigger `votos_checar_regras`), em `test/integration/votar_participante_test.dart`

### Implementation for User Story 2

- [X] T015 [US2] Implementar `DetalheRodadaPage` (lista candidatas + votar; já inclui botão "Encerrar Rodada" da US3) em `lib/features/acao/presentation/detalhe_rodada_page.dart`
- [X] T016 [US2] Ligar rota `/rodadas/:id` em `lib/app.dart`

**Checkpoint**: US1 e US2 juntas — votação funciona de ponta a ponta (sem fechar ainda).

---

## Phase 4: User Story 3 - Fechar Rodada e apurar a vencedora (Priority: P2)

**Goal**: fechamento preguiçoso por prazo vencido, ou forçado pelo Dono; apuração com sorteio de empate; vencedora confirmada, perdedoras descartadas.

**Independent Test**: forçar fechamento com empate proposital, confirmar que uma vencedora emerge e as demais somem.

### Tests for User Story 3

- [X] T017 [P] [US3] Teste de contrato: `fechar_rodada_se_devido` não faz nada antes do prazo sem forçar (FR-008), em `test/integration/fechamento_preguicoso_test.dart`
- [X] T018 [P] [US3] Teste de contrato: `fechar_rodada_se_devido` fecha e apura quando o prazo já passou, em `test/integration/fechamento_preguicoso_test.dart`
- [X] T019 [P] [US3] Teste de contrato: só o Dono do Grupo força fechamento antes do prazo (FR-009/FR-010), em `test/integration/forcar_fechamento_dono_test.dart`
- [X] T020 [P] [US3] Teste de contrato: empate é resolvido por sorteio entre as candidatas mais votadas (FR-011/FR-012), em `test/integration/apuracao_empate_test.dart`
- [X] T021 [P] [US3] Teste de contrato: vencedora vira `confirmada = true`, perdedoras são apagadas (FR-013/FR-014), em `test/integration/apuracao_vencedora_test.dart`
- [X] T022 [P] [US3] Teste de contrato: Rodada sem candidata fecha sem vencedora (FR-018), em `test/integration/apuracao_sem_candidata_test.dart`

### Implementation for User Story 3

- [X] T023 [US3] Botão "Encerrar Rodada" (Dono do Grupo) em `DetalheRodadaPage` (já incluído em T015); `fechar_rodada_se_devido` chamado em `RodadaRepository.fetchRodada/votar/proporCandidata` (já incluído em T004)

**Checkpoint**: ciclo completo de votação funciona.

---

## Phase 5: User Story 4 - Confirmar presença numa Ação candidata (Priority: P2)

**Goal**: confirmar presença numa candidata funciona igual Ação avulsa, com ou sem voto; presença sobrevive à vitória, some com a derrota.

**Independent Test**: confirmar presença numa candidata, forçar o fechamento, verificar que a presença permanece na vencedora e some nas perdedoras.

### Tests for User Story 4

- [X] T024 [P] [US4] Teste de contrato: confirmar presença numa candidata funciona (reusa `confirmacoes_acao` da 003), em `test/integration/candidata_confirmar_presenca_test.dart`
- [X] T025 [P] [US4] Teste de contrato: presença numa candidata vencedora sobrevive ao fechamento (presença numa perdedora some junto — já coberto por T021/`apuracao_vencedora_test.dart`), em `test/integration/apuracao_presenca_test.dart`

### Implementation for User Story 4

- [X] T026 [US4] `DetalheAcaoPage` (feature 003) exibe uma candidata (`confirmada = false`) com indicação "Ação candidata — ainda em votação" e link pra `DetalheRodadaPage`; botão de cancelar oculto pra candidatas não confirmadas

**Checkpoint**: todas as quatro primeiras user stories funcionam juntas.

---

## Phase 6: User Story 5 - Cancelar Ação de Grupo confirmada (Priority: P3)

**Goal**: quem propôs a vencedora, ou o Dono do Grupo, cancela a Ação de Grupo já confirmada.

**Independent Test**: Dono do Grupo cancela uma Ação de Grupo que não propôs; outro participante não consegue.

### Tests for User Story 5

- [X] T027 [P] [US5] Teste de contrato: Dono do Grupo cancela Ação de Grupo mesmo sem ter proposto (policy `acoes_update_criador_ou_dono_grupo`), em `test/integration/cancelar_acao_grupo_test.dart`
- [X] T028 [P] [US5] Teste de contrato: participante que não é Dono nem propôs não consegue cancelar, em `test/integration/cancelar_acao_grupo_test.dart`

### Implementation for User Story 5

- [X] T029 [US5] `DetalheAcaoPage.podeCancelar` = `Acao.podeCancelar(uid, souDonoDoGrupo:)`, resolvendo o Dono do Grupo via `grupoProvider(acao.grupoId)` quando aplicável

**Checkpoint**: todas as user stories funcionam de forma independente.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T030 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados (111/111 testes + `flutter build macos --debug`)
- [X] T031 [P] Atualizar `README.md` (estrutura estendida de `lib/features/acao/`, rotas novas, convenção de idioma pós-clarify do usuário)
- [X] T032 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001/002/003/004 — 111/111 verde contra schema recém-resetado

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo
- **US1/US2**: sequenciais entre si (votar precisa de candidata existir), mas juntas formam o MVP da votação
- **US3**: depende de US1/US2 (precisa de candidatas e votos pra apurar)
- **US4**: depende de US1 (candidata existir); pode ser testada em paralelo com US2/US3
- **US5**: depende de US3 (precisa de uma Ação de Grupo confirmada pra cancelar)
- **Polish**: depende de todas as user stories completas

## Notes

- Reusa `AcaoRepository`, `confirmacoes_acao`, `DetalheAcaoPage` da feature
  003 quase integralmente — o ganho de simplicidade de "candidata é Ação"
  está documentado em research.md.
- `fechar_rodada_se_devido` é chamada pelo `RodadaRepository` antes de
  qualquer leitura/escrita relevante numa Rodada — não existe job
  agendado nesta feature (decisão de clarify).
