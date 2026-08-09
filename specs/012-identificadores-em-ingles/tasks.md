# Tasks: Identificadores Dart em inglês

**Input**: Design documents from `/specs/012-identificadores-em-ingles/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [quickstart.md](./quickstart.md)

**Tests**: **nenhum teste novo é escrito.** Os testes existentes *são* o teste desta feature —
a prova de que a refatoração não mudou nada é que as mesmas asserções, na mesma quantidade,
continuam passando (FR-016, FR-019). Escrever teste novo aqui seria mudar o que se está
tentando manter constante.

**Organization**: agrupadas por user story. A US2 tem cinco etapas de módulo; cada uma fecha
compilando e com os gates passando.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: US1, US2, US3

## Regra que vale para toda tarefa de rename

Ciclo de `research.md` D-001, sem exceção:

1. renomear a **declaração** → 2. `flutter analyze` → 3. corrigir só o que ele apontar →
4. repetir até limpo → 5. rodar testes e comparar a contagem.

**Proibido**: `sed`, `grep -rl | xargs`, substituição em massa por texto. As mesmas palavras
portuguesas são identificador em um lugar, chave de banco em outro e texto de UI em um
terceiro, e nenhuma ferramenta textual distingue os três. Só o analisador distingue.

---

## Phase 1: Setup

**Purpose**: capturar a régua. Sem ela, nenhuma verificação posterior significa nada.

- [X] T001 Capturar a linha de base conforme a seção "Linha de base" de [quickstart.md](./quickstart.md), gravando em `/tmp/012-baseline/`: (a) contagem de testes que passam em `flutter test test/unit test/widget`; (b) conjunto ordenado dos literais de string de `lib/`; (c) rotas declaradas em `lib/app.dart`; (d) hash da árvore `supabase/`. **Anotar os quatro valores** — são a régua de todas as etapas

---

## Phase 2: Foundational

**Vazia, de propósito.** Não há infraestrutura a construir: esta feature só renomeia o que já
existe. O que seria "fundação" — o mapa de tradução — tem valor por si e por isso é a US1, não
uma tarefa de bastidor.

---

## Phase 3: User Story 1 — Existe um mapa de tradução único e oficial (Priority: P1) 🎯 MVP

**Goal**: quem for renomear qualquer coisa encontra em `CONTEXT.md` a tradução oficial de cada
termo, sem adivinhar.

**Independent Test**: abrir `CONTEXT.md` e verificar que cada termo do glossário tem uma e
apenas uma tradução declarada, e que nenhuma tradução serve a dois termos.

- [X] T002 [US1] Em `CONTEXT.md`, adicionar a tradução em inglês de cada termo do glossário, usando a tabela "Termos do glossário" de [research.md](./research.md) D-002. Registrar as traduções **já em uso no código** como estão (Perfil→`Profile`, Conta→`Account`, Apelido→`Nickname`, Igreja→`Church`, Ação sugerida→`SuggestedAction`, Dupla Missionária→`MissionaryPair`, Administrador do distrito→`DistrictAdmin`, Líder/Diretor→`Leader`) em vez de propor alternativas (FR-001, FR-003)
- [X] T003 [US1] Em `CONTEXT.md`, adicionar também os conceitos operacionais recorrentes da segunda tabela de `research.md` D-002 (confirmar presença→`confirmAttendance`, desistir→`withdraw`, fila de espera→`waitlist`, data e hora→`dateTime`, limite de vagas→`capacity`, e os demais), e registrar as duas colisões conhecidas com decisão já tomada: `Action` colide com `Action` do Flutter (resolver por prefixo de import, nunca renomeando o conceito de domínio) e `User` colide com o `User` do Supabase (prefixar `AppUser` se a ambiguidade aparecer de fato) — FR-002, FR-004
- [X] T004 [US1] Verificar o mapa: cada termo do glossário tem tradução, nenhuma tradução aparece para dois termos, e nenhum termo tem duas traduções. **Commitar antes de qualquer rename** — FR-005 exige que o mapa exista primeiro

**Checkpoint**: US1 pronta e entregável sozinha. Mesmo sem uma linha renomeada, o mapa já impede que features futuras criem traduções divergentes.

---

## Phase 4: User Story 2 — Cada módulo passa a falar inglês, sem mudar comportamento (Priority: P2)

**Goal**: `lib/` inteiro em inglês, um módulo por vez, sem que nada observável mude.

**Independent Test**: escolher um módulo, aplicar o rename, e verificar que compila, que a
contagem de testes que passam é idêntica, e que nenhuma string de UI mudou.

**Ordem obrigatória**: da menor superfície para a maior (`research.md` D-003). Cada etapa é um
par de commits — `git mv` primeiro, conteúdo depois — para o `git log --follow` continuar
funcionando e para a revisão conseguir separar "renomeou arquivo" de "mudou conteúdo".

### Etapa 1 — `acao_sugerida/` → `suggested_action/` (superfície ~9)

Ensaio do método com risco quase zero: o interior do módulo **já está em inglês**, só a pasta
está em português.

- [X] T005 [US2] `git mv lib/features/acao_sugerida lib/features/suggested_action` e ajustar os caminhos de import em todos os arquivos que apontam para o módulo (3 arquivos de `lib/` fora dele, 2 de teste). Commit isolado, só caminhos
- [X] T006 [US2] Rodar os gates da seção "Por etapa" de [quickstart.md](./quickstart.md): `flutter analyze` (0 issues), `flutter test test/unit test/widget` (mesma contagem da linha de base), `flutter build web`, mais as verificações negativas A (literais), B (rotas) e C (`supabase/` intocado). **No diff A, a única diferença aceitável é caminho de import**

### Etapa 2 — `grupo/` → `group/` (superfície ~22)

- [X] T007 [US2] `git mv` da pasta `lib/features/grupo` para `lib/features/group` e dos 8 arquivos para os nomes em inglês (`grupo.dart`→`group.dart`, `categoria_grupo.dart`→`group_category.dart`, `grupo_repository.dart`→`group_repository.dart`, `grupo_providers.dart`→`group_providers.dart`, `criar_grupo_page.dart`→`create_group_page.dart`, `detalhe_grupo_page.dart`→`group_detail_page.dart`, `editar_grupo_page.dart`→`edit_group_page.dart`, `lista_grupos_page.dart`→`group_list_page.dart`), ajustando só os caminhos de import. Commit isolado
- [X] T008 [US2] Renomear os identificadores do módulo pelo ciclo do analisador: `Grupo`→`Group`, `NovoGrupo`→`NewGroup`, `CategoriaGrupo`→`GroupCategory`, `GrupoRepository`→`GroupRepository`, as 4 páginas e seus `State`, `_GrupoCard`→`_GroupCard`, `_OrdenacaoGrupo`→`_GroupSortOrder`, os providers (`grupoProvider`, `gruposProvider`, `grupoRepositoryProvider`, `categoriasGrupoProvider`, `participantesProvider`), e os métodos (`criarGrupo`→`createGroup`, `editarGrupo`→`updateGroup`, `participar`→`join`, `sair`→`leave`, `removerParticipante`→`removeMember`, `transferirPosse`→`transferOwnership`, `souDono`→`isOwner`, `podeDeclararLideranca`, `podeSerPromovidoAdministrador`), tudo conforme o mapa. Consumidores em `leadership/`, `district_admin/`, `acao/` e `core/` são corrigidos aqui, apontados pelo analisador. **Chaves de mapa (`'nome'`, `'igreja_id'`, `'horario'`…) e strings de UI: intocadas**
- [X] T009 [US2] Rodar os gates e as verificações negativas A/B/C de [quickstart.md](./quickstart.md)

### Etapa 3 — `acao/` → `action/` (superfície ~21)

- [X] T010 [US2] Confirmar que **nenhuma** feature de comportamento está em voo sobre o módulo de Ação — 010, 011, 013 e 014 estão especificadas mas não implementadas, e esta feature vem antes de todas (ver `plan.md`, "Ordem entre as features abertas"). Se alguma tiver começado, **parar esta etapa** e seguir para a Etapa 4 (`perfil/`): renomear e mudar comportamento no mesmo módulo em paralelo produz um conflito de merge irrevisável, que é o motivo de esta feature existir
- [X] T011 [US2] `git mv` da pasta `lib/features/acao` para `lib/features/action` e dos 13 arquivos para inglês (`acao.dart`→`action.dart`, `rodada.dart`→`voting_round.dart`, `acao_repository.dart`→`action_repository.dart`, `rodada_repository.dart`→`voting_round_repository.dart`, `acao_providers.dart`→`action_providers.dart`, `rodada_providers.dart`→`voting_round_providers.dart`, `criar_acao_page.dart`→`create_action_page.dart`, `criar_candidata_page.dart`→`create_candidate_page.dart`, `criar_rodada_page.dart`→`create_voting_round_page.dart`, `detalhe_acao_page.dart`→`action_detail_page.dart`, `detalhe_rodada_page.dart`→`voting_round_detail_page.dart`, `lista_acoes_page.dart`→`action_list_page.dart`, `lista_rodadas_page.dart`→`voting_round_list_page.dart`), ajustando só os caminhos. Commit isolado
- [X] T012 [US2] Renomear os identificadores do módulo pelo ciclo do analisador: `Acao`→`Action`, `NovaAcao`→`NewAction`, `AcaoComIgreja`→`ActionWithChurch`, `Rodada`→`VotingRound`, `NovaRodada`→`NewVotingRound`, `Voto`→`Vote`, `PeriodoAcao`→`ActionPeriod`, `StatusConfirmacao`→`AttendanceStatus`, `ConfirmacaoComPerfil`→`AttendanceWithProfile`, `_AcaoCard`→`_ActionCard`, `_OrdenacaoAcao`→`_ActionSortOrder`, `_CabecalhoSecao`→`_SectionHeader`, `_FiltrosBar`→`_FilterBar`, os providers e os métodos (`criarAcao`→`createAction`, `cancelarAcao`→`cancelAction`, `confirmarPresenca`→`confirmAttendance`, `desistir`→`withdraw`, `votar`→`vote`, `abrirRodada`→`openRound`, `proporCandidata`→`proposeCandidate`, `fecharSeDevido`→`closeIfDue`, `acaoNoSabado`→`isOnSabbath`, `periodoDaAcao`→`actionPeriod`, `souCriador`→`isCreator`, `podeCancelar`→`canCancel`), e os campos (`nome`→`name`, `dataHora`→`dateTime`, `local`→`location`, `detalhes`→`details`, `limiteVagas`→`capacity`, `criadorId`→`creatorId`, `canceladaEm`→`cancelledAt`, `cancelada`→`isCancelled`, `confirmada`→`isConfirmed`, `prazo`→`deadline`). **`Action` colide com `Action` do Flutter — resolver por prefixo no import do Flutter, conforme T003.** As chaves `'nome'`, `'data_hora'`, `'local'`, `'detalhes'`, `'limite_vagas'`, `'criador_id'`, `'cancelada_em'`, `'genero_visitado'`, `'confirmado'`, `'fila'` **permanecem em português**
- [X] T013 [US2] Rodar os gates, as verificações negativas A/B/C, **e também** `dart test test/integration` (exige `supabase start`) — este módulo concentra as regras do Princípio IV, e nenhuma asserção pode ter mudado

### Etapa 4 — `perfil/` → `profile/` (superfície ~36)

- [X] T014 [US2] `git mv` da pasta `lib/features/perfil` para `lib/features/profile` e dos 12 arquivos para inglês (`perfil_repository.dart`→`profile_repository.dart`, `perfil_guard.dart`→`profile_guard.dart`, `conta_guard.dart`→`account_guard.dart`, `nome_moderation.dart`→`name_moderation.dart`, `cadastro_perfil_page.dart`→`profile_signup_page.dart`, `upgrade_conta_page.dart`→`upgrade_account_page.dart`, `perfil_ausente_banner.dart`→`missing_profile_banner.dart`, e os já em inglês mantidos), ajustando só os caminhos. Commit isolado
- [X] T015 [US2] Renomear os identificadores do módulo pelo ciclo do analisador: `PerfilRepository`→`ProfileRepository`, `PerfilGuard`→`ProfileGuard`, `ContaGuard`→`AccountGuard`, `NomeModeration`→`NameModeration`, `PerfilAusenteBanner`→`MissingProfileBanner`, `CadastroPerfilPage`→`ProfileSignupPage`, `UpgradeContaPage`→`UpgradeAccountPage`, e os métodos (`criarPerfil`→`createProfile`, `hasPerfil`→`hasProfile`, `fetchPerfilPublico`→`fetchPublicProfile`, `exigirPerfil`→`requireProfile`, `upgradeParaConta`→`upgradeToAccount`, `temConta`→`hasAccount`, `valido`→`isValid`). **A regra de exibir menor de idade por Apelido não muda de comportamento, só de nome de símbolo** (Princípio II). Chaves e strings de UI intocadas
- [X] T016 [US2] Rodar os gates e as verificações negativas A/B/C

### Etapa 5 — `core/` (superfície ~36)

- [ ] T017 [US2] `git mv lib/core/agrupar_por_igreja.dart lib/core/group_by_church.dart` e ajustar os caminhos de import. `providers.dart`, `supabase_client.dart` e `theme/app_theme.dart` mantêm o nome — já estão em inglês. Commit isolado
- [ ] T018 [US2] Renomear em `lib/core/group_by_church.dart` e `lib/core/providers.dart`: `agruparPorIgreja`→`groupByChurch`, `SecaoPorIgreja`→`ChurchSection`, `igrejaIdDe`→`churchIdOf`, `nomePorIgrejaId`→`nameByChurchId`, `igrejaInvisivel`→`hiddenChurch`, `hasPerfilProvider`→`hasProfileProvider`, `perfilRepositoryProvider`→`profileRepositoryProvider`, `perfilPublicoProvider`→`publicProfileProvider`. Estes providers são referenciados por ~32 arquivos — o analisador aponta todos. Os 17 providers que já estão em inglês (`churchesProvider`, `currentUserIdProvider`, `isAnonymousProvider`, e os demais listados em `research.md` D-004) **não mudam**
- [ ] T019 [US2] Rodar os gates completos, incluindo `dart test test/integration`, e as verificações negativas A/B/C

**Checkpoint**: `lib/` inteiro em inglês. Nada que o usuário vê mudou.

---

## Phase 5: User Story 3 — Quem revisa consegue provar que nada mudou (Priority: P3)

**Goal**: sair da confiança e entrar na evidência.

**Independent Test**: para qualquer módulo renomeado, demonstrar que nenhum literal mudou e
que nenhum arquivo de banco foi tocado.

- [ ] T020 [US3] Executar as 8 verificações finais da tabela "Ao fim de tudo" de [quickstart.md](./quickstart.md), **anotando o número real de cada uma**: 0 identificadores em português em `lib/`; 0 arquivos e 0 pastas com nome português (de 37 e 4, para 0); contagem de testes idêntica à linha de base; conjunto de literais idêntico exceto imports; `supabase/` intocado; rotas idênticas; mapa completo em `CONTEXT.md`; cada etapa compilando sozinha
- [ ] T021 [US3] Justificar por escrito **cada linha** do diff de literais (verificação A) que sobrou. A única justificativa aceitável é "caminho de import mudou porque o arquivo foi renomeado". Qualquer outra é bug — provavelmente uma chave de banco ou string de UI alterada por engano, que é o único dano real que esta feature pode causar
- [ ] T022 [US3] Confirmar com `git diff --name-only main...HEAD | grep '^supabase/'` que nenhum arquivo de migração entrou no diff total da feature (FR-015, SC-006)
- [ ] T023 [US3] Executar a verificação manual de [quickstart.md](./quickstart.md), itens 1 a 7: lista de Grupos, lista de Ações, detalhe de Ação com fila de espera, Rodada de votação, cadastro de Perfil, **Política de Privacidade e Termos palavra por palavra**, e um link `/grupos/<id>` antigo ainda abrindo o mesmo Grupo

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T024 Conferir que `specs/011-acoes-titulo-e-encerramento/plan.md` não tem mais pendência de tradução no Complexity Tracking, e que a T027 do `tasks.md` dela não manda mais criar ticket em `.tickets/`. Com a 012 vindo primeiro, a 011 nasce em módulo já traduzido e o desvio nunca chega a existir — os dois arquivos já foram ajustados quando a ordem mudou; esta tarefa só verifica
- [ ] T025 Registrar em `CONTEXT.md`, junto ao mapa, que `test/` mantém nomes de arquivo em português por decisão deliberada — senão quem chegar depois vai tratar o repositório meio-a-meio como bug e "consertar" (risco 6 do plano)
- [ ] T026 Rodar os gates completos uma última vez, na ponta da feature, e anotar os números: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration`, `flutter build web`
- [ ] T027 Conferir que os caminhos e símbolos citados em `specs/010-pagina-home/tasks.md`, `specs/011-acoes-titulo-e-encerramento/tasks.md` e `specs/013-foto-de-capa/tasks.md` batem com os nomes **reais** produzidos pelo rename. Esses três arquivos foram atualizados para os nomes previstos pelo mapa quando a ordem das features mudou; se alguma tradução saiu diferente do previsto, é aqui que aparece. Caminho errado dentro de uma tarefa é instrução errada que ninguém percebe até executar

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: sem dependência. **Bloqueia toda a US3** — sem linha de base não há o que comparar
- **US1 (T002–T004)**: sem dependência. **Bloqueia toda a US2** (FR-005: o mapa vem antes do código)
- **US2 (T005–T019)**: depende de T001 e da US1. As cinco etapas são **estritamente sequenciais**
- **US3 (T020–T023)**: depende de T001 e das etapas da US2 que se quer verificar
- **Polish (T024–T026)**: depende de tudo

### Dependência externa

**Nenhuma.** Esta feature vem primeiro: `012 → 010 → 011 → 013 → 014` (ver `plan.md`, "Ordem
entre as features abertas"). As outras quatro estão especificadas e planejadas, mas nenhuma
linha de código foi escrita — é por isso que este é o momento mais barato do rename.

T010 continua existindo como conferência, não como espera: se alguma feature tiver começado
sem que este plano soubesse, a Etapa 3 para e o trabalho segue pela Etapa 4.

### Parallel Opportunities

**Praticamente nenhuma, e isso é a decisão de design, não uma limitação.**

Cada etapa da US2 renomeia símbolos que a etapa seguinte referencia; rodar duas em paralelo
gera conflito garantido em `core/providers.dart`, `lib/app.dart` e nos testes. A serialização
é o que faz cada commit ser revisável e cada etapa fechar compilando (FR-010, SC-009).

O que é genuinamente paralelo:

- **T002 e T003** — duas tabelas distintas do mesmo documento, se duas pessoas combinarem as seções
- **T021, T022 e T023** — três verificações independentes sobre o mesmo estado final

Nem tente paralelizar as etapas de rename.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 (linha de base) → T002–T004 (mapa em `CONTEXT.md`)
2. **PARAR e VALIDAR**: o mapa está completo e sem ambiguidade
3. Já entrega valor real: a partir daqui, nenhuma feature nova cria tradução divergente, mesmo
   que o código antigo continue em português por meses

### Entrega incremental

1. + Etapa 1 (`suggested_action/`) → método validado com risco quase zero
2. + Etapa 2 (`group/`) → primeiro módulo de verdade em inglês
3. + Etapa 3 (`action/`) → o maior, depois da 011
4. + Etapa 4 (`profile/`) → o de maior fan-in
5. + Etapa 5 (`core/`) → fecha `lib/`
6. + US3 e polimento → a evidência de que nada mudou

Parar depois de qualquer etapa deixa o repositório íntegro, compilando e com os gates
passando. Módulos em inglês e em português coexistem sem problema (FR-011).

---

## Notes

- Nenhum teste novo. Os existentes são a prova; mudança de asserção significa que a
  refatoração deixou de ser refatoração
- Nenhuma dependência nova, nenhum arquivo dividido, unido ou movido de camada
- Comentários e documentação em português permanecem em português (FR-018)
- Dois commits por etapa: `git mv` primeiro, conteúdo depois — é o que mantém
  `git log --follow` útil e a revisão possível
- A tarefa mais perigosa da feature é a T012: é onde estão os campos (`nome`, `dataHora`,
  `local`) cujas chaves homônimas (`'nome'`, `'data_hora'`, `'local'`) **não** podem mudar. Um
  erro ali não quebra a compilação — quebra em produção
