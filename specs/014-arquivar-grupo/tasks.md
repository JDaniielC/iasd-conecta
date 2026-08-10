# Tasks: Arquivar Grupo

**Input**: Design documents from `/specs/014-arquivar-grupo/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

> **Padrão de idioma (Princípio I, e vale para código de teste também).** Todo identificador
> Dart criado aqui — classe, enum e seus valores, método, função, variável local, parâmetro,
> campo, provider e nome de arquivo — é escrito **em inglês**, seguindo o mapa de `CONTEXT.md`.
> Só o **nome do arquivo** de teste continua em português. Banco, chaves de leitura/gravação
> e strings de UI continuam em português. A feature 011 errou nisso e precisou de um passe de
> correção depois.

**Tests**: obrigatórios, e não por gosto. Esta feature toca **quatro das cinco** regras
centrais do Princípio IV — fila de espera, desempate, descarte de candidatas e revogação de
Participar. A constituição exige teste automatizado antes de considerar pronto, e
`dart test test/integration` é gate de CI.

**Organization**: por user story. As três são entregáveis em sequência; a US2 é o que faz o
arquivamento significar alguma coisa.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: arquivo diferente, sem dependência pendente
- **[Story]**: US1, US2, US3

## Serialização inerente

Uma única migration (`supabase/migrations/<timestamp>_arquivar_grupo.sql`) recebe conteúdo em
**quatro** tarefas (T002, T007, T016, T022). São o mesmo arquivo — nunca em paralelo. A
alternativa seria quatro migrations para uma feature, contra o padrão do repositório.

---

## Phase 1: Setup

**Purpose**: o vocabulário antes do código. A constituição exige, e é uma tarefa de minutos.

- [X] T001 Em `CONTEXT.md`, adicionar as entradas **Arquivar o Grupo** e **Grupo arquivado**, cada uma com `_EN_` (`archiveGroup` / `ArchivedGroup`) e `_Avoid_`. Grupo arquivado ≠ Grupo apagado — apagar Grupo **não existe** no app, e a entrada precisa dizer isso para ninguém confundir os dois (FR-023, Princípio I). **Commitar antes de qualquer código**

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: o estado existir. Sem isto, nenhuma história começa.

- [X] T002 Criar `supabase/migrations/<timestamp>_arquivar_grupo.sql` com a seção 1 de [contracts/schema.sql](./contracts/schema.sql): colunas `arquivado_em` e `arquivado_por` em `public.grupos` — são elas que registram quem arquivou e quando (FR-008) —, os dois `comment on column`, e o índice parcial `grupos_ativos`. Aplicar com `supabase db reset` e conferir que as 17 migrations anteriores continuam subindo
- [X] T003 Em `lib/features/group/domain/group.dart`, adicionar `archivedAt`, `archivedBy` e o derivado `bool get isArchived`, mais o mapeamento em `Group.fromMap` (`'arquivado_em'`, `'arquivado_por'` — chaves em português, são o contrato com o banco)
- [X] T004 [P] Criar `test/unit/group_archive_test.dart`: `isArchived` é falso com `archivedAt` nulo e verdadeiro com data; `fromMap` lê as duas chaves novas (FR-010)

**Checkpoint**: `flutter analyze` limpo, `dart test test/integration` nos 127 de antes, nada mudou de comportamento.

---

## Phase 3: User Story 1 — Arquivar o próprio Grupo, sabendo o estrago (Priority: P1) 🎯 MVP

**Goal**: o Dono arquiva, e antes de confirmar vê exatamente quantas Ações serão canceladas,
quantas presenças estavam confirmadas nelas, quantas Rodadas serão encerradas e quantas
pessoas participam.

**Independent Test**: como Dono de um Grupo com 2 Ações futuras, 5 presenças e 1 Rodada
aberta, acionar arquivar e verificar que a confirmação mostra esses quatro números **antes**
de qualquer coisa acontecer.

### Tests for User Story 1

- [X] T005 [US1] Criar `test/integration/arquivar_grupo_efeitos_test.dart` — **o teste que mais importa da feature**, escrito para falhar agora. Sete asserções: (a) Ações futuras ficam canceladas e Ação **passada** fica intacta (FR-014); (b) contagem de presenças **idêntica** antes e depois (FR-015, SC-006); (c) **ninguém promovido da fila** (Princípio IV); (d) Rodada antes aberta fecha com **`vencedora_id` nulo** (FR-007, SC-005); (e) **todas** as candidatas descartadas, nenhuma virou Ação confirmada; (f) Rodada **já fechada** e sua apuração inalteradas (SC-009); (g) `participacoes_grupo` com contagem idêntica (FR-017). **A asserção (d) é a única que percebe se alguém um dia "simplificar" a função reusando `fechar_rodada_se_devido`**
- [X] T006 [US1] Criar `test/integration/arquivar_grupo_permissao_test.dart`: participante comum é recusado (FR-002); Dono arquiva o próprio; Administrador do distrito arquiva qualquer um (FR-001); Grupo já arquivado é recusado (FR-009)

### Implementation for User Story 1

- [X] T007 [US1] Acrescentar à migration a seção 2 de [contracts/schema.sql](./contracts/schema.sql): `public.arquivar_grupo(uuid)`, `security definer`, com a validação de papel na primeira linha e os quatro passos numa transação. **Não chamar `fechar_rodada_se_devido`** — ela apura, e apurar aqui criaria uma Ação confirmada num Grupo que acabou de sair do ar (research D-003). O encerramento é escrito à mão: `fechada_em = now()`, `vencedora_id` nulo, `delete` de todas as candidatas
- [X] T008 [P] [US1] Criar `lib/features/group/domain/archive_preview.dart` com `ArchivePreview` (`futureActions`, `confirmedAttendances`, `openVotingRounds`, `members`) e o derivado `bool get nothingWillBeLost`
- [X] T009 [US1] Em `lib/features/group/data/group_repository.dart`, adicionar `fetchArchivePreview(groupId)` — quatro consultas de leitura, **sem RPC nova**: as tabelas já têm select público e os números não são segredo (research D-004) — e `archiveGroup(groupId)` chamando a RPC
- [X] T010 [US1] Em `lib/features/group/group_providers.dart`, adicionar `archivePreviewProvider(groupId)`
- [X] T011 [US1] Criar `test/widget/archive_group_sheet_test.dart`: a confirmação mostra os quatro números reais (FR-003, SC-001); com tudo zerado diz **em palavras** que nada será perdido, não quatro zeros (FR-004); Ministério com Líder/Diretor confirmado ganha o aviso extra sobre a identificação pública sair do ar (FR-005); **desistir não dispara chamada nenhuma** (FR-006, SC-002)
- [X] T012 [US1] Criar `lib/features/group/presentation/archive_group_sheet.dart` com a confirmação. A prévia é só leitura — é isso que torna FR-006 verdadeiro por construção
- [X] T013 [US1] Em `lib/features/group/presentation/group_detail_page.dart`, oferecer arquivar ao Dono do Grupo e ao Administrador do distrito, e a **ninguém mais** (FR-001, FR-002). Grupo já arquivado não oferece a opção de novo (FR-009)

**Checkpoint**: US1 pronta. Já dá para arquivar, com o estrago declarado antes. O Grupo ainda não sumiu de lugar nenhum — é a US2.

---

## Phase 4: User Story 2 — O Grupo arquivado sai do caminho de todo mundo (Priority: P2)

**Goal**: quem participava abre o app e o Grupo não está mais lá; nenhuma operação sobre ele é
aceita; e o que já aconteceu continua tendo acontecido.

**Independent Test**: arquivar um Grupo e verificar, como outro Usuário, que ele sumiu da lista
e que participar, propor candidata, abrir Rodada e votar são todos recusados.

### Tests for User Story 2

- [X] T014 [US2] Em `test/integration/arquivar_grupo_permissao_test.dart`, adicionar: Grupo arquivado recusa participar, propor Ação candidata, abrir Rodada de votação e votar (FR-011, FR-012, SC-004). São as políticas que executam — a tela é cortesia
- [X] T015 [US2] **Feito em `test/integration/arquivar_grupo_permissao_test.dart`, não em widget**: o filtro vive no SQL de `GroupRepository.fetchGroups`, não na página, e um teste de widget que mockasse `fetchGroups` não provaria nada. Filtrar também na tela criaria duas cópias da mesma regra. Original: Em `test/widget/lista_grupos_page_test.dart`, adicionar: Grupo arquivado não aparece, sob **nenhuma** combinação de filtro de Igreja e ordenação (FR-010, SC-003)

### Implementation for User Story 2

- [X] T016 [US2] Acrescentar à migration a seção 4 de [contracts/schema.sql](./contracts/schema.sql): as políticas de insert de `participacoes_grupo`, `rodadas_votacao`, `votos` e Ação candidata passam a exigir Grupo não arquivado. Reler as definições atuais antes de reescrever — o contrato registra a **regra**, não o texto exato das políticas que já existem
- [X] T017 [US2] Em `lib/features/group/group_providers.dart` e `lib/features/group/presentation/group_list_page.dart`, filtrar `arquivado_em is null` na listagem (FR-010)
- [X] T018 [US2] **Filtrar Grupo arquivado na exibição do Líder/Diretor.** `liderancas` não é tocada pelo arquivamento, de propósito (é histórico), então **nada no banco impede** que um Ministério arquivado continue mostrando publicamente quem é o responsável — visível a Visitante sem cadastro. É o risco 4 do plano e a **única falha desta feature que não grita**: nenhum teste de unidade a pega, e o dado exposto é exatamente o que FR-016 diz que sai do ar. Conferir `lib/features/leadership/data/leadership_repository.dart` e quem consome `currentLeadersProvider`
- [X] T019 [US2] Conferir **os demais consumidores** de Grupo, um a um (research D-006): `lib/features/action/action_providers.dart` resolve a Igreja da Ação lendo `grupos.igreja_id` e **NÃO deve filtrar** — senão Ações passadas do Grupo arquivado perdem a Igreja e saem do agrupamento. Telas de Rodada por link **não** filtram (FR-014). A spec só cita a listagem; cobrir só ela deixaria buraco
- [X] T020 [US2] Em `lib/features/group/presentation/group_detail_page.dart`, exibir que o Grupo está arquivado quando alcançado por link direto, em vez de erro (FR-013), e esconder participar / propor / abrir Rodada / votar

**Checkpoint**: US1 + US2. Arquivar significa alguma coisa.

---

## Phase 5: User Story 3 — O Administrador do distrito conserta o engano (Priority: P3)

**Goal**: desarquivar devolve o Grupo e os participantes — e a tela diz, antes, que as Ações
canceladas não voltam.

**Independent Test**: arquivar um Grupo e, como Administrador do distrito, desarquivá-lo,
verificando que ele volta à lista com os participantes.

### Tests for User Story 3

- [X] T021 [US3] Em `test/integration/arquivar_grupo_permissao_test.dart`, adicionar: só o Administrador do distrito desarquiva, o Dono é recusado (FR-018); depois de desarquivar, o Grupo volta à listagem e volta a aceitar participação, proposta de Ação candidata, Rodada e voto (FR-020); os participantes voltam **sem ação deles** (FR-021, SC-007); e as Ações canceladas **continuam canceladas** (FR-022) — as participações voltam de graça porque nunca foram apagadas (research D-005)

### Implementation for User Story 3

- [X] T022 [US3] Acrescentar à migration a seção 3 de [contracts/schema.sql](./contracts/schema.sql): `public.desarquivar_grupo(uuid)`, `security definer`, restrita ao Administrador do distrito. Zera `arquivado_em` e `arquivado_por`; **não ressuscita nada**
- [X] T023 [US3] Em `lib/features/group/data/group_repository.dart` e `group_providers.dart`, adicionar `unarchiveGroup(groupId)`, `fetchArchivedGroups()` e `archivedGroupsProvider`
- [X] T024 [US3] Criar `lib/features/group/presentation/archived_groups_page.dart` — lista de arquivados com quem arquivou e quando, visível **só ao Administrador do distrito** (FR-019) — e registrar a rota em `lib/app.dart`, junto às demais de Administrador
- [X] T025 [US3] Na tela de desarquivar, avisar **antes de confirmar** que as Ações canceladas e as Rodadas encerradas não voltam (FR-022). É a segunda metade da honestidade que FR-003 começou

**Checkpoint**: as três histórias funcionando.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T026 Rodar os gates e **anotar o número real** de cada suíte: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration` (exige `supabase start`), `flutter build web`. Linha de base em `main` ao começar: 0 issues, **152** unit/widget, **127** integração
- [X] T027 Confirmar que os **7 testes de integração pré-existentes** listados em [quickstart.md](./quickstart.md) passam **sem edição de asserção** — apuração, empate, presença, sem-candidata, idempotência, Dupla Missionária e Ação encerrada. Se algum precisou mudar, a feature vazou do escopo
- [X] T028 **FEITO em 2026-08-10.** Contagem antes/depois: presenças 5→5, participações 2→2, Rodadas abertas 1→0, duas Ações futuras canceladas e a passada com `cancelada_em` nulo. A Rodada que estava aberta fechou com `vencedora_id` **nulo** — encerrou sem apurar. Original: Executar a **Parte 3** de [quickstart.md](./quickstart.md) à mão — contar presenças, Rodadas e participações antes e depois de arquivar. Estado parcial é o modo de falha desta feature, e contagem é o único jeito de vê-lo
- [ ] T028a Medir SC-008 com gente: cronometrar um Dono arquivando o próprio Grupo, do toque inicial à confirmação — precisa ficar abaixo de 1 minuto. É o único critério de sucesso que não vira teste, e some da lista se não estiver escrito (a 011 perdeu o SC-003 assim)
- [ ] T029 **PARCIAL em 2026-08-10**: o **item 8**, que era o único a falhar em silêncio, **passou** — o Ministério arquivado mostra o aviso e o Líder some da tela, com a linha ainda no banco. Faltam os outros 16 itens da Parte 2. Original: Executar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 17, **com o item 8 conferido especificamente**: como Visitante, procurar o Líder/Diretor de um Ministério arquivado. É o único item que falha em silêncio
- [X] T030 Varredura de identificador em português nos arquivos Dart tocados pela feature, **inclusive nos de teste** (Princípio I). A 011 passou por isso; esta não precisa

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: sem dependência. **Bloqueia todo o código** (Princípio I)
- **Foundational (T002–T004)**: depende de T001. **Bloqueia todas as histórias**
- **US1 (T005–T013)**: depende da Fase 2
- **US2 (T014–T020)**: depende da US1 — não faz sentido esconder o que ainda não pode ser arquivado
- **US3 (T021–T025)**: depende da US1. Independente da US2
- **Polish (T026–T030)**: depende das histórias desejadas

### Parallel Opportunities

- **T004** — arquivo de teste unitário novo, independente
- **T008** — `archive_preview.dart` é arquivo novo, não colide com nada
- **US3 em paralelo com a US2**, se houver duas pessoas: compartilham só `group_repository.dart` e `group_providers.dart`, em pontos distintos

Serializações obrigatórias:

| Arquivo | Tarefas que competem |
|---|---|
| a migration da feature | T002, T007, T016, T022 |
| `lib/features/group/data/group_repository.dart` | T009 (US1), T023 (US3) |
| `lib/features/group/group_providers.dart` | T010 (US1), T017 (US2), T023 (US3) |
| `lib/features/group/presentation/group_detail_page.dart` | T013 (US1), T020 (US2) |
| `test/integration/arquivar_grupo_permissao_test.dart` | T006 (US1), T014 (US2), T021 (US3) |

---

## Conflito com a feature 013

Ordem: **013 → 014**. A 013 entra antes e altera `group_detail_page.dart` e
`group_list_page.dart` para exibir a Foto de capa; esta feature lê os arquivos já
modificados. Risco baixo — regiões diferentes.

**Interação de comportamento**: Grupo arquivado **mantém** a capa, porque o Grupo não é
apagado. E o FR-021 da 013 — "quando um Grupo é apagado, sua capa deixa de existir" —
continua descrevendo um evento que não acontece: esta feature arquiva, não apaga.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 (vocabulário) → T002–T004 (o estado existir)
2. T005–T013 (arquivar, com a prévia e os dois testes de integração)
3. **PARAR e VALIDAR**: itens 1 a 3 da Parte 2 e a Parte 3 inteira do quickstart
4. Entrega o poder de arquivar com o estrago declarado antes. O Grupo ainda aparece nas
   listas — inútil sozinho na prática, mas é o incremento que dá para validar isolado

**Na prática, US1 + US2 é o menor conjunto que entrega valor.** Arquivar sem sumir não
resolve o problema de ninguém.

### Entrega incremental

1. Setup + Foundational → o estado existe, nada mudou
2. + US1 → arquiva, com a prévia honesta
3. + US2 → o Grupo some do caminho e recusa operação (**aqui a feature vale**)
4. + US3 → existe rede de segurança para o engano
5. + Polimento → os números conferidos, incluindo o item 8

---

## Notes

- `[P]` = arquivo diferente, sem dependência pendente
- **T018 é a tarefa que eu conferiria duas vezes**: é a única falha da feature que não
  aparece em teste de unidade, e o que vaza é identificação pública de pessoa
- **T005 asserção (d)** é a guarda contra reusar `fechar_rodada_se_devido` — sem ela, nada
  impede alguém de "simplificar" a função um dia e criar Ação confirmada em Grupo arquivado
- Commit por tarefa ou grupo lógico; T007 e T005 devem ir juntos, T016 e T014 também
- Nenhuma tarefa de notificação: ninguém é avisado do arquivamento, e isso é decisão
  registrada em Assumptions, não esquecimento
