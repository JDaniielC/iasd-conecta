# Tasks: Página Home de propósito

**Input**: Design documents from `/specs/010-pagina-home/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [quickstart.md](./quickstart.md)

**Tests**: incluídos. Não é preferência de estilo — `research.md` D-006 define a estratégia e
`quickstart.md` lista os gates. `flutter test test/unit test/widget` é gate de CI
(`.github/workflows/ci.yml:25`), então teste que não existe é requisito que ninguém protege.

**Organization**: tarefas agrupadas por user story. Cada história é entregável e verificável
sozinha, depois da Fase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: a qual user story a tarefa pertence (US1, US2, US3)

## Path Conventions

App Flutter organizado por feature: `lib/features/<nome>/presentation/`, testes em
`test/widget/`. Caminhos abaixo são reais, conferidos no repositório.

---

## Phase 1: Setup

**Purpose**: criar o arquivo onde tudo o mais vai morar.

- [ ] T001 Criar `lib/features/home/presentation/home_page.dart` com o esqueleto de `HomePage`: `ConsumerWidget` → `Scaffold` → `SafeArea` → `SingleChildScrollView` → `Column(crossAxisAlignment: start)`, corpo vazio, sem `AppBar`. Padrão copiado de `lib/features/legal/presentation/privacy_policy_page.dart` (decisão D-002). Identificadores em inglês (Princípio I): classe `HomePage`, arquivo `home_page.dart`

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: trocar a rota inicial e consertar tudo que aponta pra ela. **Precisa entrar
junto** — deixar metade aplicada dá um app com botão "Grupos" que leva à Home.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase fechar.

- [ ] T002 Em `lib/app.dart`: trocar o `builder` da rota `/home` (linha ~74) de `GroupListPage` para `HomePage`, e adicionar `GoRoute(path: '/grupos', builder: GroupListPage)`. A rota `/grupos` DEVE ser declarada **antes** de `/grupos/:id` (decisão D-001) — `go_router` casa na ordem de declaração. Não mexer nos dois `redirect` das linhas 57 e 63: apontar pra Home depois do cadastro e depois de entrar na Conta é o comportamento desejado
- [ ] T003 [P] Em `lib/features/action/presentation/action_list_page.dart:60`: trocar `context.go('/home')` por `context.go('/grupos')` no `IconButton` com tooltip "Grupos". **Sem isso o app compila e o botão fica errado** — é o bug silencioso registrado no risco 2 do plano
- [ ] T004 [P] Em `lib/features/group/presentation/group_list_page.dart`: corrigir o comentário de topo, que hoje diz "Home do app: lista de Grupos". Só o comentário — nenhuma mudança de comportamento nesta tela
- [ ] T005 Atualizar `test/widget/router_visitante_test.dart`: a asserção `expect(find.text('Grupos'), findsOneWidget)` na rota inicial passa a ser falsa. Afirmar que a rota inicial constrói a Home, e mover a verificação de "Visitante alcança a lista de Grupos" para depois da navegação. **Não apagar o caso** — o que ele protege (Visitante não é empurrado ao cadastro) continua valendo (FR-001)
- [ ] T006 [P] Criar `test/widget/home_page_test.dart` com o helper de montagem: `ProviderScope` com `hasProfileProvider` sobrescrito, envolvendo `HomePage`. Os overrides de `groupRepositoryProvider`/`authRepositoryProvider` usados em `router_visitante_test.dart` servem de modelo

**Checkpoint**: `flutter analyze` limpo, `flutter test test/widget` verde, app abre na Home vazia e a lista de Grupos continua alcançável por `/grupos`.

---

## Phase 3: User Story 1 — Visitante entende para que serve o app (Priority: P1) 🎯 MVP

**Goal**: quem abre o app entende, sem interação nenhuma, o que ele é e para quem é, e vê
"A Deus seja a glória".

**Independent Test**: abrir o app sem Perfil e verificar que o propósito e a frase estão
visíveis sem rolar.

> Todas as tarefas desta fase mexem em `home_page.dart` ou em `home_page_test.dart`, então
> **nenhuma é [P]** — são o mesmo arquivo.

### Tests for User Story 1

- [ ] T007 [US1] Em `test/widget/home_page_test.dart`, escrever os testes que devem falhar agora: (a) a frase exata `A Deus seja a glória` está presente — comparar caractere a caractere, com acento; (b) o nome do app e a frase de propósito estão presentes; (c) os textos citam **Grupo** e **Ação** com os termos exatos do glossário (FR-002, FR-003, FR-004, Princípio I)
- [ ] T008 [US1] Em `test/widget/home_page_test.dart`, escrever o teste de ausência de dado pessoal: a Home monta e renderiza sem nenhum override de repositório de Perfil além de `hasProfileProvider`, provando que não consulta mais nada (FR-006, Princípio II)

### Implementation for User Story 1

- [ ] T009 [US1] Em `lib/features/home/presentation/home_page.dart`, implementar o bloco de identidade no topo: nome do app, frase de propósito citando o distrito de Vitória de Santo Antão e o que se faz ali, e `A Deus seja a glória` como `Text` comum — **não** marcar como `ExcludeSemantics`, a frase é lida por leitor de tela (FR-002, FR-003, decisão D-005). Bloco compacto: é ele que precisa caber sem rolagem em paisagem
- [ ] T010 [US1] Em `lib/features/home/presentation/home_page.dart`, implementar os blocos curtos explicando **Grupo** (comunidade permanente em torno de atividade recorrente) e **Ação** (evento pontual com data, hora e local), e a frase dizendo que Visitante vê livremente mas participar/votar/criar exige cadastro (FR-004, FR-005). Usar só os termos do glossário — nada de "evento", "atividade", "comunidade" (Princípio I)
- [ ] T011 [US1] Conferir o espaçamento com `AppSpacing` de `lib/core/theme/app_theme.dart` e a tipografia com `Theme.of(context).textTheme` — nenhuma cor nem tamanho literal na Home. O tema azul-marinho existente é o único (FR-018)

**Checkpoint**: US1 pronta. A Home já cumpre o motivo da feature existir, mesmo sem os caminhos de navegação.

---

## Phase 4: User Story 2 — Chegar às atividades a partir da Home (Priority: P2)

**Goal**: a Home deixa de ser beco sem saída — leva a Grupos e a Ações em um toque.

**Independent Test**: da Home, alcançar as duas listas e voltar de cada uma.

### Tests for User Story 2

- [ ] T012 [US2] Em `test/widget/home_page_test.dart`, testar que existem controles rotulados com **texto** para Grupos e para Ações, e que acioná-los navega para `/grupos` e `/acoes` (FR-007)

### Implementation for User Story 2

- [ ] T013 [US2] Em `lib/features/home/presentation/home_page.dart`, implementar os dois caminhos. Rótulo em texto, não só ícone (FR-007). Ícone, se houver, só da família Material já usada no app — `Icons.groups_outlined` e `Icons.event_outlined`, os mesmos de `group_list_page.dart:51` e `action_list_page.dart:59`. Nada de emoji (FR-017). Alvo de toque ≥44×44pt e ≥8pt de separação: os botões do tema já entregam isso (FR-013, decisão D-005)

**Checkpoint**: US1 + US2 funcionando. Navegação completa, ainda sem chamada principal nem links legais.

---

## Phase 5: User Story 3 — Saber como participar e o que o app faz com meus dados (Priority: P3)

**Goal**: quem quer participar sabe que precisa de Perfil e chega ao cadastro; quem quer
saber sobre dados chega às páginas legais.

**Independent Test**: da Home, alcançar o cadastro, a Política de Privacidade e os Termos de Uso.

**⚠️ É esta fase que traz risco a SC-005** (renderizar offline): é o único ponto da Home que
observa um provider de rede. As fases anteriores são estáticas por construção.

### Tests for User Story 3

- [ ] T014 [US3] Em `test/widget/home_page_test.dart`, testar a chamada principal nos três estados: `hasProfileProvider` resolvido em `false` → "Criar Perfil"; resolvido em `true` → "Ver Grupos"; **em erro** (`overrideWith((ref) async => throw Exception('offline'))`) → "Ver Grupos" **e todos os textos fixos da Home continuam presentes**. O terceiro caso é o que impede alguém, numa refatoração futura, de embrulhar a Home inteira num `.when` e quebrar o comportamento offline sem quebrar nenhum outro teste (FR-008, SC-005, decisão D-003)

### Implementation for User Story 3

- [ ] T015 [US3] Em `lib/features/home/presentation/home_page.dart`, implementar a chamada principal única (FR-008) observando `hasProfileProvider` **num bloco isolado**, com a tabela de D-003: carregando ou erro → "Ver Grupos"; sem Perfil → "Criar Perfil"; com Perfil → "Ver Grupos". Todo o resto da Home fica **fora** de qualquer `AsyncValue`. A ação secundária acompanha, visualmente subordinada
- [ ] T016 [US3] Em `lib/features/home/presentation/home_page.dart`, adicionar os caminhos para `/privacidade` e `/termos`, rotulados com texto (FR-009)

**Checkpoint**: as três histórias funcionando de forma independente.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [ ] T017 Rodar os gates de CI e **anotar os números reais**: `flutter analyze` (0 issues), `flutter test test/unit test/widget` (N testes passando), `flutter build web`. Nunca reportar "os testes passaram" sem o número
- [ ] T018 Executar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 14. **O item 13 é obrigatório**: da Home → Ações → tocar "Grupos" e confirmar que vai para a lista de Grupos, não de volta à Home. É a verificação da T003, e nenhum teste automatizado a cobre
- [ ] T019 Conferir a interpretação de SC-002 registrada no risco 1 do plano: em paisagem a ~375px de altura, com **fonte padrão**, a doxologia está visível sem rolar; com fonte no máximo, nada é cortado e a página rola (FR-014). Se a doxologia não couber nem em fonte padrão, encurtar o bloco de identidade — não reduzir tamanho de fonte
- [ ] T020 Medir contraste dos pares texto/fundo e conferir alvos de toque (quickstart itens 7 e 8, FR-012, FR-013, SC-004). `AppColors.navy` sobre branco fica em torno de 13:1; a conferência importa se algum cinza claro tiver entrado
- [ ] T021 Conferir leitor de tela (quickstart item 10, FR-020, FR-024): ordem de leitura acompanha a ordem visual e "A Deus seja a glória" é lida como texto
- [ ] T022 Confirmar que `CONTEXT.md` **não** precisou de alteração — nenhum termo novo de domínio foi introduzido (Princípio I). Se precisou, a Home vazou de escopo

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: sem dependência
- **Foundational (T002–T006)**: depende de T001 — **bloqueia todas as user stories**
- **US1 (T007–T011)**: depende da Fase 2
- **US2 (T012–T013)**: depende da Fase 2. Independente de US1
- **US3 (T014–T016)**: depende da Fase 2. Independente de US1 e US2
- **Polish (T017–T022)**: depende das histórias desejadas estarem prontas

### Parallel Opportunities

Poucas, e por um motivo estrutural: **as três histórias vivem no mesmo arquivo**
(`home_page.dart`) e são testadas no mesmo arquivo (`home_page_test.dart`). Marcar tarefas
como paralelas ali seria mentira — dariam conflito.

O que é genuinamente paralelo:

- **T003 e T004** — arquivos diferentes, um o outro não toca (`action_list_page.dart` e `group_list_page.dart`)
- **T006** — arquivo de teste novo, independente de T002–T005
- **T020 e T021** na fase de polimento — verificações manuais que não se estorvam

Se houver mais de uma pessoa, o corte que funciona é **por fase**, não por tarefa: uma pessoa
fecha a Fase 2 inteira, e só então as histórias podem ir para pessoas diferentes — desde que
combinem quem escreve em `home_page.dart` primeiro.

---

## Conflito com a feature 011 (aberta em paralelo)

**T003** toca `lib/features/action/presentation/action_list_page.dart`, o mesmo arquivo que a
feature `011-acoes-titulo-e-encerramento` vai alterar (filtro de Ação encerrada e contagem de
confirmados no card).

- Regiões diferentes do arquivo: T003 mexe em uma linha do `AppBar`; a 011 mexe no corpo da
  lista e no `_ActionCard`. Conflito de merge, se houver, é trivial.
- **Ordem recomendada**: fechar esta feature primeiro. T003 é uma linha e sai da frente.
- Se a 011 entrar antes, T003 continua sendo uma linha, aplicada sobre o arquivo já mudado.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 → T006 (Setup + Foundational)
2. T007 → T011 (US1)
3. **PARAR e VALIDAR**: abrir o app, ver a Home explicando o propósito com a doxologia
4. Já entrega o motivo da feature existir. A navegação continua funcionando por
   `/grupos` e `/acoes` mesmo sem US2 — só não há caminho a partir da Home

### Entrega incremental

1. Setup + Foundational → base pronta, nada quebrado
2. + US1 → Home explica o propósito (MVP, demonstrável)
3. + US2 → Home vira porta de entrada de verdade
4. + US3 → Home converte e é transparente sobre dados
5. + Polimento → os 6 itens que só o olho e a medição resolvem

---

## Notes

- `[P]` = arquivo diferente, sem dependência pendente
- Nenhuma tarefa de banco, migration ou `CONTEXT.md`: esta feature não toca dado nem domínio
- Commit por tarefa ou por grupo lógico; a Fase 2 deve ir em um commit só
- Regra que vale para toda a fase de implementação: **nenhuma cor, tamanho ou espaçamento
  literal** em `home_page.dart` — tudo por `AppTheme`/`AppSpacing`
