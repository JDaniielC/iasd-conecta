---

description: "Task list for Dupla Missionária"
---

# Tasks: Dupla Missionária

**Input**: Design documents from `/specs/007-dupla-missionaria/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md — depende do schema das features 001/003/004 já aplicado

**Tests**: incluídos e obrigatórios — Princípio IV exige teste automatizado pra composição de gênero, limite fixo de 2 vagas, e fila de espera pulando inválido.

**Organization**: tarefas agrupadas por user story (US1 Criar, US2 Confirmar respeitando composição).

**Convenção de idioma**: campos novos em `Acao`/`NovaAcao` já nascem em
inglês (`isMissionaryPair`, `visitedGender`) — o resto da classe permanece
em português (ver Summary do plan.md).

## Format: `[ID] [P?] [Story] Description`

## Path Conventions

Mesmo projeto Flutter único; nenhuma pasta nova — estende
`lib/features/acao/` já existente.

---

## Phase 1: Foundational (Blocking Prerequisites)

**Purpose**: schema de banco (colunas + funções estendidas) e modelo Dart.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase estar completa

- [X] T001 Criar migration `supabase/migrations/<timestamp>_dupla_missionaria.sql` seguindo exatamente `contracts/schema.sql` (colunas `eh_dupla_missionaria`/`genero_visitado` em `acoes`, `CHECK` novo, `confirmacoes_acao_decidir_status()` e `promover_fila_acao()` substituídas)
- [X] T002 Estender `Acao`/`NovaAcao` em `lib/features/acao/domain/acao.dart` com `isMissionaryPair`/`visitedGender`; `NovaAcao.toInsertMap` força `limite_vagas: 2` quando `isMissionaryPair` é `true`, ignorando qualquer valor de `limiteVagas` passado

**Checkpoint**: fundação pronta.

---

## Phase 2: User Story 1 - Criar Dupla Missionária (Priority: P1) 🎯 MVP

**Goal**: quem cria uma Ação (avulsa ou candidata) marca como Dupla Missionária e informa o gênero da pessoa visitada; a Ação nasce com exatamente 2 vagas.

**Independent Test**: criar uma Dupla Missionária e confirmar que ela nasce com 2 vagas e o gênero do visitado salvo.

### Tests for User Story 1

- [X] T003 [P] [US1] Teste de contrato: `genero_visitado` nulo com `eh_dupla_missionaria = true` viola `acoes_dupla_missionaria_check` (FR-002), em `test/integration/dupla_missionaria_exige_genero_test.dart`
- [X] T004 [P] [US1] Teste de contrato: `limite_vagas` diferente de 2 com `eh_dupla_missionaria = true` viola o `CHECK` (FR-003), em `test/integration/dupla_missionaria_limite_fixo_test.dart`
- [X] T005 [P] [US1] Teste unitário: `NovaAcao.toInsertMap` força `limite_vagas: 2` quando `isMissionaryPair` é `true`, em `test/unit/acao_dupla_missionaria_model_test.dart`

### Implementation for User Story 1

- [X] T006 [US1] Estender `CriarAcaoPage` (`lib/features/acao/presentation/criar_acao_page.dart`) com toggle "Dupla Missionária" + seletor de gênero do visitado; campo de limite de vagas escondido/desabilitado quando o toggle está ligado
- [X] T007 [US1] Estender `CriarCandidataPage` (`lib/features/acao/presentation/criar_candidata_page.dart`) com o mesmo toggle + seletor, idêntico a T006

**Checkpoint**: criar Dupla Missionária funciona — MVP navegável.

---

## Phase 3: User Story 2 - Confirmar presença respeitando a composição de gênero (Priority: P1)

**Goal**: confirmações numa Dupla Missionária só são aceitas se formarem composição válida; a fila de espera existente é reusada pra capacidade, e a promoção pula quem seria inválido.

**Independent Test**: com uma Dupla Missionária já criada, confirmar presença de uma pessoa e depois tentar confirmar uma segunda de gênero inválido pra composição.

### Tests for User Story 2

- [X] T008 [P] [US2] Teste de contrato: primeira confirmação sempre aceita, qualquer gênero (FR-007), em `test/integration/dupla_missionaria_primeira_confirmacao_test.dart`
- [X] T009 [P] [US2] Teste de contrato: 2 homens visitando homem é aceita; 2 mulheres visitando mulher é aceita (FR-004), em `test/integration/dupla_missionaria_composicao_valida_mesmo_genero_test.dart`
- [X] T010 [P] [US2] Teste de contrato: 1 homem + 1 mulher é sempre aceita, qualquer visitado (FR-004), em `test/integration/dupla_missionaria_composicao_valida_genero_misto_test.dart`
- [X] T011 [P] [US2] Teste de contrato: 2 homens visitando mulher é recusada; 2 mulheres visitando homem é recusada (FR-005/FR-006), em `test/integration/dupla_missionaria_composicao_invalida_test.dart`
- [X] T012 [P] [US2] Teste de contrato: com as 2 vagas válidas preenchidas, uma 3ª tentativa (qualquer gênero) entra na fila, não é recusada por gênero (Edge Case), em `test/integration/dupla_missionaria_fila_por_capacidade_test.dart`
- [X] T013 [P] [US2] Teste de contrato: ao desistir, a promoção da fila pula quem formaria composição inválida e promove o próximo válido; se ninguém servir, a vaga fica aberta (FR-009), em `test/integration/dupla_missionaria_promocao_pula_invalido_test.dart`

### Implementation for User Story 2

- [X] T014 [US2] Estender `DetalheAcaoPage` (`lib/features/acao/presentation/detalhe_acao_page.dart`): exibir "Dupla Missionária — visita a um(a) [gênero]" quando `acao.isMissionaryPair`; envolver `_confirmar` em `try/catch` mostrando uma mensagem amigável quando a composição for recusada pelo banco

**Checkpoint**: US1 e US2 juntas — Dupla Missionária funciona de ponta a ponta.

---

## Phase 4: Polish & Cross-Cutting Concerns

- [X] T015 [P] Rodar o roteiro de validação de `quickstart.md` de ponta a ponta e registrar os resultados
- [X] T016 [P] Atualizar `README.md` (nenhuma pasta nova, mas menção à extensão de `acao/` nesta feature)
- [X] T017 `flutter analyze` e suíte completa (`flutter test`) sem regressão nas features 001-006

---

## Dependencies & Execution Order

- **Foundational (Fase 1)**: bloqueia tudo
- **US1**: só depende da Fase 1
- **US2**: depende da Fase 1; não depende de US1 estar com UI pronta (os
  triggers valem pra qualquer insert em `acoes`/`confirmacoes_acao`, mas o
  teste manual completo de ponta a ponta usa a UI de US1)

## Notes

- Nenhuma tabela nem função nova — `confirmacoes_acao_decidir_status()` e
  `promover_fila_acao()` são substituídas (`create or replace`), mantendo
  o nome e o ponto de chamada (ver research.md).
