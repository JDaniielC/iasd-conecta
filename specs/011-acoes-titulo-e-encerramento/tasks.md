# Tasks: Ação — encerramento, contagem de confirmados e clareza do título

**Input**: Design documents from `/specs/011-acoes-titulo-e-encerramento/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

> ⚠️ **Caminhos e símbolos abaixo são os pós-rename da feature 012.** A ordem das features é
> `012 → 010 → 011 → 013 → 014`, então quando estas tarefas forem executadas o módulo já se
> chamará `lib/features/action/` e os tipos já estarão em inglês. Se a 012 **não** tiver
> rodado, traduzir de volta pelo mapa de `specs/012-identificadores-em-ingles/research.md`
> D-002 — ou, melhor, rodar a 012 primeiro, que é a ordem decidida.

**Tests**: incluídos, e para US1 são **obrigatórios por constituição**. A fila de espera está
na lista do Princípio IV ("toda regra de negócio central tem teste automatizado antes de ser
considerada pronta"), e FR-007 muda o comportamento dela na borda. `dart test test/integration`
é gate de CI (`.github/workflows/ci.yml:44`).

**Organization**: agrupadas por user story. As quatro histórias são fatias quase
independentes — dá para entregar US1 sozinha e parar.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: US1, US2, US3, US4

## Path Conventions

App Flutter por feature (`lib/features/action/`), banco em `supabase/migrations/`, testes em
`test/unit/`, `test/widget/`, `test/integration/`. Nomes de arquivo de teste permanecem em
português por decisão registrada na feature 012.

---

## Phase 1: Setup

**Purpose**: derrubar a premissa da migration **antes** de escrever código em cima dela.

- [X] T001 Verificar as duas premissas de `specs/011-acoes-titulo-e-encerramento/contracts/schema.sql` contra o banco local (`supabase start` primeiro), com as consultas da Parte 0 de [quickstart.md](./quickstart.md): (a) `public.excluir_conta` tem `prosecdef = t`; (b) `public.confirmacoes_acao` tem `relforcerowsecurity = f`. **Anotar a saída real das duas consultas.** Se `relforcerowsecurity = t`, PARAR e trocar para o plano B de `research.md` D-003 — seguir mesmo assim cria um bug de exclusão de conta (LGPD), não um bug de UX

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: relógio injetável. É fino de propósito — esta feature são quatro fatias
independentes, não um alicerce compartilhado.

- [X] T002 Em `lib/core/providers.dart`, adicionar `final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);`, com comentário explicando que existe para tornar o encerramento testável (decisão D-006). Fica em `core/` porque tempo não é assunto do módulo de Ação

**Checkpoint**: `flutter analyze` limpo. Nenhum comportamento mudou ainda.

---

## Phase 3: User Story 1 — Ação que já aconteceu sai da lista (Priority: P1) 🎯 MVP

**Goal**: Ação encerrada some da listagem, continua acessível por link, e não aceita mais
confirmar/desistir — com a fila congelada de verdade, não só na UI.

**Independent Test**: criar Ação com data 4h01 no passado, abrir a lista e verificar que
sumiu; abrir o link direto e verificar que abre marcada como encerrada, sem botão de
confirmar presença.

### Tests for User Story 1

- [X] T003 [P] [US1] Criar `test/unit/acao_encerramento_test.dart` cobrindo as quatro fronteiras de `actionTimeStatus`: `dateTime - 1s` → `upcoming`; `dateTime + 0s` → `happeningNow`; `dateTime + 4h` cravado → `happeningNow`; `dateTime + 4h + 1s` → `ended` (FR-001, FR-002, decisão D-001)
- [X] T004 [US1] Em `test/widget/lista_acoes_page_test.dart`, adicionar os casos que devem falhar agora, sobrescrevendo `clockProvider` com instante fixo: (a) Ação de 4h01 atrás não aparece em nenhuma seção de período; (b) a mesma Ação não aparece com o filtro "Só Sábado" ligado; (c) Ação de 1h atrás aparece, sinalizada como acontecendo agora (FR-002, FR-003, SC-001)
- [X] T005 [US1] Em `test/widget/detalhe_acao_page_test.dart`, adicionar: (a) Ação encerrada abre e mostra o rótulo de encerrada; (b) não existe botão de confirmar, desistir, sair da fila nem cancelar; (c) Ação cancelada **e** encerrada mostra "Cancelada" (FR-004, FR-005, FR-008, SC-004)

### Implementation for User Story 1

- [X] T006 [US1] Em `lib/features/action/domain/action.dart`, adicionar `const defaultActionDuration = Duration(hours: 4)` (com comentário apontando para a gêmea `interval '4 hours'` em SQL), o enum `ActionTimeStatus { upcoming, happeningNow, ended }` e a função pura `ActionTimeStatus actionTimeStatus(DateTime dateTime, DateTime now)`
- [X] T007 [US1] Em `lib/features/action/presentation/action_list_page.dart`, trocar `DateTime.now()` por `ref.watch(clockProvider)()` e filtrar as Ações com `ActionTimeStatus.ended` antes do agrupamento por período — depois do filtro de Igreja e de "Só Sábado", para que nenhuma combinação de filtro deixe uma encerrada passar (FR-003). Sinalizar visualmente as `happeningNow` (FR-002)
- [X] T008 [US1] Em `lib/features/action/presentation/action_detail_page.dart`, ler o instante de `clockProvider`, exibir o rótulo de encerrada e esconder os controles de confirmar/desistir/sair da fila/cancelar quando `ended` (FR-004, FR-005). Precedência: se estiver cancelada **e** encerrada, o rótulo é "Cancelada" (FR-008). **Não** filtrar a Ação encerrada aqui — o detalhe tem de abrir (decisão D-002)
- [X] T009 [US1] Criar `supabase/migrations/<timestamp>_acao_encerrada_bloqueia_presenca.sql` com o conteúdo de `specs/011-acoes-titulo-e-encerramento/contracts/schema.sql`: função `public.acao_encerrada(uuid)` e as políticas `confirmacoes_acao_insert_self` e `confirmacoes_acao_delete_self` recriadas com a condição de tempo. **Não** tocar `confirmacoes_acao_select_public` — é ela que deixa a contagem ser pública (FR-014). **Nomes de banco continuam em português** — a feature 012 não traduz banco
- [X] T010 [US1] Criar `test/integration/acao_encerrada_nao_promove_fila_test.dart` com três casos: (a) em Ação encerrada, o `delete` em `confirmacoes_acao` é recusado e ninguém sobe da fila (**FR-007, Princípio IV**); (b) em Ação **não** encerrada, desistir ainda promove o próximo da fila — não-regressão de `confirmacoes_acao_promover_fila`; (c) `excluir_conta` continua apagando `confirmacoes_acao` de quem tem confirmação em Ação encerrada (risco 1 do plano — é este caso que impede o bloqueio de virar bug de LGPD)

**Checkpoint**: US1 pronta. A informação errada da listagem sumiu, e FR-007 é execução, não promessa.

---

## Phase 4: User Story 2 — Ver quantas pessoas confirmaram, direto na lista (Priority: P2)

**Goal**: decidir de qual Ação participar sem abrir uma por uma.

**Independent Test**: com duas Ações, uma com 3 confirmados e outra com 0, abrir a lista e
verificar as contagens sem abrir nenhuma.

### Tests for User Story 2

- [X] T011 [US2] Em `test/widget/lista_acoes_page_test.dart`, adicionar: 3 confirmados → "3 confirmados"; 1 → singular; 0 → "Ninguém confirmou ainda" (nunca "0"); com limite → "4 de 10 vagas"; lotada com fila → indicação de lotada e tamanho da fila, separado da contagem (FR-009 a FR-013)

### Implementation for User Story 2

- [X] T012 [US2] Em `lib/features/action/domain/action.dart`, adicionar `class ConfirmationCounts { final int confirmed; final int waiting; }`. `waiting` **nunca** é somado a `confirmed` (data-model.md §2)
- [X] T013 [US2] Em `lib/features/action/data/action_repository.dart`, adicionar o método de contagem com **uma** consulta para a listagem inteira: `from('confirmacoes_acao').select('acao_id, status')`, agrupada em Dart por `acao_id`. **A projeção é explícita de propósito**: `select()` puro traria `usuario_id` de todo mundo do distrito para o cliente. Copiar o padrão de `fetchActions()` aqui é vazamento de identidade (Princípio II, risco 4 do plano)
- [X] T014 [US2] Em `lib/features/action/action_providers.dart`, adicionar o provider que expõe as contagens por Ação para a listagem
- [X] T015 [US2] Em `lib/features/action/presentation/action_list_page.dart`, exibir a contagem no `_ActionCard` com concordância de número, sem depender de cor ou ícone isolado para ser compreendida (FR-010), e com vagas restantes quando houver limite (FR-012)

**Checkpoint**: US1 + US2. A lista virou ferramenta de decisão.

---

## Phase 5: User Story 3 — O nome da Ação diz o que vai acontecer (Priority: P3)

**Goal**: impedir que a lista de Ações do distrito vire uma lista de nomes de pessoas.

**Independent Test**: no formulário de criar Ação, digitar exatamente o próprio nome de
cadastro e verificar que o app recusa com mensagem explicativa.

### Tests for User Story 3

- [ ] T016 [P] [US3] Criar `test/unit/acao_nome_criador_test.dart`: recusa quando igual após normalizar caixa, acentuação e espaços das pontas; recusa quando igual ao Apelido; **aceita** "Visita a José" (igualdade, nunca `contains` — FR-017, FR-019, SC-006)
- [ ] T017 [US3] Criar `test/widget/criar_acao_page_nome_test.dart`: (a) nome igual ao do criador é recusado com a mensagem de FR-018, exibida junto ao campo; (b) com o nome do criador indisponível (RPC falhando), a criação **não** é bloqueada (decisão D-005 — recusar por falta de rede seria acusar o Usuário de um problema de conexão)

### Implementation for User Story 3

- [ ] T018 [US3] Em `lib/features/action/domain/action.dart`, adicionar a normalização (trim, caixa baixa, colapso de espaços internos, remoção de acentuação) e o predicado de igualdade com o nome de exibição do criador. Função pura, sem dependência nova — `NameModeration` em `lib/features/profile/domain/name_moderation.dart` só faz `toLowerCase` e não serve
- [ ] T019 [P] [US3] Em `lib/features/action/presentation/create_action_page.dart`: rótulo e `helperText` persistente no campo de nome, com exemplo concreto ("Ex.: Visita a afastado, Ensaio, Culto Jovem"), e a validação de T018 no `validator` (FR-016, FR-017, FR-018). O nome de exibição do criador vem de `publicProfileProvider` — pela RPC `perfil_publico`, nunca `select` direto em `perfis`, e é ela que devolve o Apelido para menor de idade
- [ ] T020 [P] [US3] Em `lib/features/action/presentation/create_candidate_page.dart`, aplicar o mesmo texto de apoio e a mesma validação no campo "Nome da candidata" — FR-016 e FR-017 valem para Ação candidata também

**Checkpoint**: US1 + US2 + US3.

---

## Phase 6: User Story 4 — Saber quantos somos, na lista de Confirmados (Priority: P4)

**Goal**: ver de relance quantas pessoas confirmaram, sem contar de cabeça.

**Independent Test**: abrir uma Ação com 3 confirmados e verificar 1., 2., 3. na ordem de
confirmação.

### Tests for User Story 4

- [ ] T021 [US4] Em `test/widget/detalhe_acao_page_test.dart`, adicionar: confirmados numerados 1., 2., 3. na ordem de confirmação; fila numerada recomeçando em 1., separada; sem ninguém confirmado, mensagem de vazio em vez de lista numerada vazia (FR-020, FR-021, FR-023)

### Implementation for User Story 4

- [ ] T022 [US4] Em `lib/features/action/presentation/action_detail_page.dart`, numerar as duas listas pelo índice renderizado + 1, calculado separadamente para confirmados e para fila. `fetchAttendees` já devolve ordenado por `created_at`, que é a ordem de confirmação de FR-020 — a contiguidade após desistência (FR-022) sai de graça do índice. Anunciar a posição junto do nome para leitor de tela (FR-024)

**Checkpoint**: as quatro histórias funcionando.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [ ] T023 Rodar os gates e **anotar os números reais** de cada suíte: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration` (exige `supabase start`), `flutter build web`. Nunca "os testes passaram" sem o número
- [ ] T024 Confirmar que os cinco testes de integração pré-existentes passam **sem edição**: `test/integration/confirmar_idempotente_test.dart`, `apuracao_empate_test.dart`, `cancelar_acao_grupo_test.dart`, `dupla_missionaria_promocao_pula_invalido_test.dart`, `dupla_missionaria_composicao_valida_mesmo_genero_test.dart`. Se algum precisou mudar, esta feature vazou do escopo
- [ ] T025 Inspecionar o tráfego real da listagem (DevTools → Network, quickstart item 8): a resposta de `confirmacoes_acao` traz **só** `acao_id` e `status`. Se aparecer `usuario_id`, parar — é vazamento de identidade, e é o único jeito de provar a invariante de privacidade
- [ ] T026 Executar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 18, incluindo o item 1 (a Ação real "José Danilo Silva do Carmo" de 08/08/2026 sumiu da listagem) e o item 18 (a Ação não some sozinha embaixo do dedo do Usuário)
- [ ] T027 Confirmar que `CONTEXT.md` **não** precisou de alteração — nenhum termo novo de domínio foi introduzido (Princípio I). O mapa de tradução já entrou pela feature 012; esta feature só usa o que já está lá

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: sem dependência. **Bloqueia T009/T010** — e só eles
- **Foundational (T002)**: sem dependência. **Bloqueia US1**
- **US1 (T003–T010)**: depende de T001 e T002
- **US2 (T011–T015)**: independente de US1
- **US3 (T016–T020)**: independente de tudo
- **US4 (T021–T022)**: independente de tudo
- **Polish (T023–T027)**: depende das histórias desejadas

### Dependência externa

**A feature 012 (identificadores em inglês) vem antes desta.** Ordem decidida:
`012 → 010 → 011 → 013 → 014`. Os caminhos e símbolos citados acima já são os pós-rename.
A T027 da 012 confere que eles batem com os nomes reais.

### Within Each User Story

- Teste primeiro, falhando, depois implementação
- Domínio (`action.dart`) antes de repositório, repositório antes de provider, provider antes de tela
- Migration (T009) antes do teste de integração (T010)

### Parallel Opportunities

Reais, e por arquivo:

- **T003 e T016** — dois arquivos de teste unitário novos e distintos
- **T019 e T020** — `create_action_page.dart` e `create_candidate_page.dart`, depois de T018
- **US3 e US4 inteiras** podem ir em paralelo com US1 e US2: não compartilham arquivo, exceto `action.dart` (T006, T012, T018) e `action_detail_page.dart` (T008, T022)

Serializações obrigatórias — mesmo arquivo:

| Arquivo | Tarefas que competem |
|---|---|
| `lib/features/action/domain/action.dart` | T006 (US1), T012 (US2), T018 (US3) |
| `lib/features/action/presentation/action_list_page.dart` | T007 (US1), T015 (US2) |
| `lib/features/action/presentation/action_detail_page.dart` | T008 (US1), T022 (US4) |
| `test/widget/lista_acoes_page_test.dart` | T004 (US1), T011 (US2) |
| `test/widget/detalhe_acao_page_test.dart` | T005 (US1), T021 (US4) |

---

## Conflito com as outras features abertas

Ordem decidida: **012 → 010 → 011 → 013 → 014**.

| Arquivo | Esta feature | Outra | Risco |
|---|---|---|---|
| `lib/features/action/presentation/action_list_page.dart` | T007, T015 | 010 (1 linha no `AppBar`), 013 (capa no card) | **Baixo com a 010 antes; médio com a 013 depois** — a 013 mexe no mesmo `_ActionCard` |
| `lib/features/action/presentation/action_detail_page.dart` | T008, T022 | 013 (capa no detalhe) | Médio, mesma razão |

Como a 013 vem **depois** desta, o conflito é problema dela, não desta — e o `tasks.md` da 013
já registra isso.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 (premissas do banco) → T002 (relógio)
2. T003 → T010 (US1 completa, incluindo migration e teste de integração)
3. **PARAR e VALIDAR**: itens 1 a 5 da Parte 2 do quickstart
4. Já corrige o único item que fazia o app mostrar informação errada. As outras três
   histórias são melhoria, não correção

### Entrega incremental

1. Setup + Foundational → nada mudou ainda
2. + US1 → a lista para de anunciar evento que já passou (MVP, demonstrável)
3. + US2 → a lista vira ferramenta de decisão
4. + US3 → o nome da Ação para de virar nome de pessoa
5. + US4 → polimento de leitura
6. + Polimento → gates, privacidade no tráfego

### Se houver mais de uma pessoa

O corte limpo é **US1+US2 para uma pessoa** (dividem `action_list_page.dart`) e
**US3+US4 para outra** (dividem só `action.dart` com a primeira, em pontos distintos do
arquivo). Combinar antes quem escreve em `action.dart` primeiro.

---

## Notes

- `[P]` = arquivo diferente, sem dependência pendente
- T001 é o único ponto onde vale **parar a feature**: premissa falsa ali muda o plano inteiro de US1
- T010 caso (c) e T025 são os dois testes que protegem promessas legais (LGPD), não UX
- Commit por tarefa ou por grupo lógico; T009 e T010 devem ir juntos
- O limiar de 4 horas existe em dois lugares (`defaultActionDuration` no Dart, `interval '4 hours'`
  no SQL). Mudar um sem o outro dá o sintoma cruel: botão some na UI mas o banco ainda aceita,
  ou o contrário
- **Nomes de banco continuam em português** (`acoes`, `confirmacoes_acao`, `acao_encerrada`,
  `data_hora`) — a feature 012 traduz identificador Dart, nunca banco
