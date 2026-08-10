# Tasks: Novidades — o que mudou no app

**Input**: Design documents from `/specs/022-novidades/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [contracts/news_content.md](./contracts/news_content.md),
[quickstart.md](./quickstart.md)

## Antes de começar: o que torna esta feature diferente

**Ela é cliente puro.** Nenhuma migration, nenhuma coluna, nenhuma chamada ao servidor. Se
nascer arquivo em `supabase/migrations/`, ou se `dart test test/integration` ganhar um teste
novo, a feature vazou do escopo — as duas ausências são verificação, não descuido.

**A tela nasce vazia.** O marco é 6 de outubro de 2026 e hoje é 10 de agosto de 2026. No dia
em que isto entrar não haverá item nenhum, e é por isso que T017 (o estado vazio) não é
polimento: é a única coisa que a pessoa vai ver por dois meses.

**A armadilha desta feature é o TEXTO, não o código.** A tela é simples. O que apodrece é a
lista virar changelog técnico, escrita por quem tem o commit fresco na cabeça. T003 e T027
existem por isso, e T027 roda sobre o conteúdo **real**, não sobre exemplo.

**O erro caro seria gravar "já vi" no servidor.** É o caminho óbvio: sobrevive à troca de
aparelho. E criaria dado de comportamento sem finalidade autorizada. Por isso a US3 é P2
**junto** com a US2, não depois — a decisão de privacidade se toma enquanto o aviso está sendo
feito.

**Idioma** (Princípio I): todo identificador Dart em **inglês**, inclusive dentro de arquivos
de teste. Só o **nome do arquivo** de teste fica em português. Cada tarefa abaixo nomeia
explicitamente o que cria, já em inglês — a feature 011 não fez isso e custou 315 renomeações.

---

## Phase 1: Setup

- [X] T001 Em `CONTEXT.md`, adicionar a entrada **Novidade** com `_EN_`: `NewsItem` / `news` e `_Avoid_` dizendo que **não** é changelog (aquilo é técnico), **não** é release note (aquilo é de versão) e **não** é aviso do sistema (o app não tem canal de notificação). Acrescentar à tabela de conceitos operacionais: Marco de lançamento → `launchDate`, Marcador de leitura → `lastSeenNewsDate`. **Commitar antes de qualquer código** (Princípio I)
- [X] T002 Em `pubspec.yaml`, promover `shared_preferences` de transitivo para **direto**, com comentário de uma linha dizendo por quê: ele já vem por `supabase_flutter` e o custo de bundle é zero, mas dependência que a gente usa a gente declara — senão ela some no dia em que `supabase_flutter` trocar de mecanismo de persistência, e quebra uma feature que ninguém tocou (research D-001). Rodar `flutter pub get` e conferir que a versão resolvida não mudou
- [X] T003 [P] Criar `CRITERIO-DE-NOVIDADE.md` na raiz do repositório com o conteúdo revisado de [contracts/news_content.md](./contracts/news_content.md) — a regra de admissão, as cinco regras de escrita e a tabela do mesmo fato escrito das duas formas. Fica na raiz, não em `specs/`, porque quem escreve a novidade precisa tropeçar nele (FR-017)

---

## Phase 2: Foundational (bloqueia todas as histórias)

- [X] T004 Criar `lib/features/news/domain/news_item.dart` com: `class NewsItem { final DateTime date; final String text; const NewsItem({required this.date, required this.text}); }`; `const launchDate = DateTime.utc(2026, 10, 6)` com comentário explicando que é o lançamento ao distrito e que é filtro de **exibição**, não regra de escrita; e `const allNews = <NewsItem>[]` — **a lista nasce vazia de propósito** (spec, primeira Assumption). Dois campos e nenhum a mais: sem `id`, sem `title`, sem `category`, sem `version` — cada um tem o motivo escrito em [data-model.md](./data-model.md)
- [X] T005 No mesmo arquivo, adicionar `List<NewsItem> visibleNews(List<NewsItem> items)` — descarta o que é anterior a `launchDate` e ordena da data mais recente para a mais antiga (FR-001, FR-006). Função pura, sem estado: é o que permite testá-la com listas montadas à mão em vez de depender do conteúdo real
- [X] T006 Criar `lib/features/news/data/news_repository.dart` com `class NewsRepository`, `Future<DateTime?> readLastSeenDate()` e `Future<void> writeLastSeenDate(DateTime date)`, guardando **texto ISO** sob a chave `'novidades_ultima_vista'` (chave em português, é dado de armazenamento, não identificador Dart). Comentário de topo: este é o único estado persistido da feature, ele fica **no aparelho**, e gravá-lo no servidor criaria dado de comportamento — ver research D-001 (FR-012, FR-013)
- [X] T007 Criar `lib/features/news/news_providers.dart` com `newsRepositoryProvider`, `visibleNewsProvider` (aplica `visibleNews` sobre `allNews`) e `hasUnseenNewsProvider` (`FutureProvider<bool>`): sem marcador guardado, **grava a data mais recente na hora e devolve `false`** (FR-011, research D-003); com marcador, devolve `true` só se a data mais recente da lista for posterior à guardada (FR-008, FR-010). Com a lista vazia, devolve `false` sem gravar nada

**Checkpoint**: `flutter analyze` limpo, 204 testes de unidade e widget seguem verdes, nada mudou na tela.

---

## Phase 3: User Story 1 — Descobrir o que mudou (P1) 🎯 MVP

**Goal**: a lista existe, ordenada, legível, alcançável, e se explica quando está vazia.

**Independent Test**: abrir a tela e ver os itens do mais recente para o mais antigo, com data,
sem nenhum termo técnico.

### Tests

- [X] T008 [P] [US1] Criar `test/unit/novidades_test.dart` com helpers locais em inglês (`buildItem({required DateTime date, String text})`): `visibleNews` ordena do mais recente para o mais antigo (FR-001); descarta item anterior a `launchDate` e **mantém** item exatamente na data do marco — é o Edge Case de que lado o marco cai, e o teste é quem documenta a resposta (FR-006); lista vazia devolve lista vazia sem estourar
- [X] T009 [US1] Criar `test/widget/novidades_page_test.dart` com `pumpNewsPage(tester, {required List<NewsItem> items})` sobrescrevendo `visibleNewsProvider` — o teste de widget não lê armazenamento nem servidor. Casos: três itens aparecem na ordem certa, cada um com data legível (FR-001, FR-002); a data é exibida em formato brasileiro, não ISO
- [X] T010 [US1] No mesmo arquivo, o caso `empty state explains itself`: com lista vazia, a tela mostra o texto explicando o que é Novidades e por que ainda não há nada, e **não** uma área em branco (FR-007). É o estado que vai valer por dois meses

### Implementation

- [X] T011 [US1] Criar `lib/features/news/presentation/news_page.dart` com `class NewsPage` (`ConsumerWidget`), `AppBar(title: Text('Novidades'))`, observando `visibleNewsProvider`. Cada item mostra a data formatada com `intl` (padrão `dd/MM/yyyy`) e o texto. Sem cor, tamanho ou espaçamento literal — tudo por `AppSpacing` e `Theme.of(context).textTheme`, como o resto do app
- [X] T012 [US1] No mesmo arquivo, o estado vazio: texto dizendo o que a tela é e que as mudanças a partir do lançamento aparecerão ali. **Não** usar palavra que soe a erro ("nada encontrado", "vazio") — não há nada errado; o app é novo (FR-007)
- [X] T013 [US1] Em `lib/app.dart`, adicionar `GoRoute(path: '/novidades', builder: (context, state) => const NewsPage())`, junto das demais rotas públicas. **Sem redirect e sem gate de Perfil**: Visitante vê o mesmo (FR-005)
- [X] T014 [US1] Em `lib/features/home/presentation/home_page.dart`, adicionar a entrada para `/novidades` dentro de `_MainCallToAction`, com **rótulo em texto** — `Novidades` — e não só ícone (FR-004). Visível a todo mundo, com ou sem Perfil, diferente do caminho de "Meu Perfil" que é condicionado a `hasProfileProvider`

**Checkpoint**: US1 pronta e demonstrável sozinha. A tela existe, é encontrável e se explica vazia.

---

## Phase 4: User Story 2 — Saber que há algo novo (P2)

**Goal**: quem tem novidade não vista percebe ao abrir o app; quem leu, não.

**Independent Test**: com marcador antigo, abrir o app e ver o aviso; abrir a tela; reabrir e
não ver mais.

**Depende da US1** — aviso apontando para tela que não existe é pior que aviso nenhum.

- [X] T015 [US2] Em `test/widget/novidades_page_test.dart`, sobrescrevendo `hasUnseenNewsProvider`: com `true`, a Home mostra o aviso; com `false`, não mostra (FR-008). Testar pela Home, não pela tela de Novidades — é lá que o aviso vive
- [X] T016 [US2] Em `test/unit/novidades_test.dart`, os quatro casos do marcador, com um `NewsRepository` falso em memória (`FakeNewsRepository`, em inglês): (a) sem marcador guardado → sem aviso, **e o marcador é gravado** (FR-011); (b) marcador anterior à data mais recente → com aviso (FR-008); (c) marcador igual à data mais recente → sem aviso (FR-010); (d) lista vazia → sem aviso e **sem gravar nada** — gravar com lista vazia deixaria o app achando que "viu" um futuro que não existe
- [X] T017 [US2] Em `lib/features/home/presentation/home_page.dart`, mostrar o aviso quando `hasUnseenNewsProvider` resolver `true` — um ponto ou selo junto do rótulo `Novidades`. Enquanto o provider carrega, **não** mostrar aviso: um aviso que pisca a cada abertura é pior que nenhum (FR-008)
- [X] T018 [US2] Em `lib/features/news/presentation/news_page.dart`, gravar o marcador ao abrir a tela e invalidar `hasUnseenNewsProvider`, para o aviso sumir sem precisar reabrir o app (FR-009). Com a lista vazia, não gravar nada

**Checkpoint**: US1 + US2. A lista comunica.

---

## Phase 5: User Story 3 — Nada é registrado sobre quem leu (P2)

**Goal**: provar que a leitura não virou dado.

**Independent Test**: usar a tela com o tráfego aberto e ver zero requisições.

> As três tarefas abaixo são **verificação**, não implementação — se alguma falhar, a
> implementação das fases anteriores é que precisa mudar. É por isso que esta história é P2
> junto com a US2 e não um item de polimento.

- [X] T019 [US3] Varredura de código: `grep -rn "supabase\|Supabase\|rpc(\|\.from(" lib/features/news/` deve retornar **zero** ocorrências. A feature inteira não conhece o servidor (FR-012)
- [X] T020 [US3] Confirmar que `git status` em `supabase/migrations/` está limpo e que `dart test test/integration` **não ganhou nenhum teste novo** e continua nos 197 de antes. As duas ausências são a prova de que a feature é cliente puro
- [X] T021 [US3] Confirmar que `git diff` **não toca** `lib/features/legal/presentation/privacy_policy_page.dart` nem `lib/features/legal/legal_metadata.dart` (FR-014, SC-007). É a verificação mais barata da feature e a que mais diz: se a Política precisou de frase nova, algo passou a ser coletado e o desenho errou

**Checkpoint**: as três histórias fechadas, e a decisão de privacidade provada em vez de afirmada.

---

## Phase 6: Polish & verificação

- [X] T022 Rodar os gates e **anotar os números reais**: `flutter analyze` (base 0 issues), `flutter test test/unit test/widget` (base **204**), `dart test test/integration` (base **197**, inalterado), `flutter build web`
- [X] T023 [P] Varredura de identificador em português nos arquivos novos, inclusive os de teste (Princípio I). Só o nome do arquivo de teste fica em português
- [X] T024 [P] Conferir que nenhuma cor, tamanho ou espaçamento literal entrou em `news_page.dart` — tudo por `AppSpacing` e `Theme.of(context).textTheme`
- [ ] T025 Executar a Parte 3 de [quickstart.md](./quickstart.md), itens 3.1 a 3.5. **O 3.1 é obrigatório**: com o DevTools na aba Network filtrando `supabase`, abrir a Home e a tela de Novidades e confirmar **zero** requisições. É a prova de FR-012 que nenhum teste automatizado dá
- [ ] T026 Executar o item 3.7 do quickstart — navegador com armazenamento bloqueado. A tela precisa **abrir e listar normalmente**; só o aviso é que reaparece a cada visita. Não pode dar erro. É o caso que `research.md` registra como não verificado

### O que só gente mede

- [ ] T027 **Bloqueada até existir o primeiro item** — a varredura de jargão sobre a lista real já roda em `test/unit/novidades_test.dart` (grupo `CRITERIO-DE-NOVIDADE`) e passa vacuamente com a lista vazia; a leitura por três pessoas depende de haver o que ler. **SC-001/SC-002 com o conteúdo real**: quando o primeiro item entrar na lista, rodar a varredura de jargão sobre o **texto real** (`.dart`, nome de tabela, `v1.`, `RLS`, `policy`, `constraint`) e pedir a **três pessoas do distrito** que leiam e digam com as palavras delas o que mudou. Enquanto a lista estiver vazia, esta tarefa fica aberta — e é a primeira a fazer no dia do primeiro item
- [ ] T028 **SC-006**: cronometrar alguém achando a tela a partir da Home, sem ajuda. Meta: menos de 15 segundos. Se passar, o problema é o caminho (FR-004), não a tela

### Decisão em aberto, registrada e não resolvida

- [ ] T029 **Confirmar com o dono do app** se a lista nasce vazia (marco em 6/10/2026, como especificado) ou se ele quer as 21 features já entregues listadas retroativamente. **O código não muda com a resposta** — `launchDate` é uma constante e o filtro já existe. O que muda é o trabalho de escrita: 0 itens ou ~15 itens escritos à mão segundo `CRITERIO-DE-NOVIDADE.md`. Registrar a resposta aqui

---

## Dependências

```text
T001 (glossário) ──► bloqueia todo o código
      │
      ├─► T002, T003  (setup, paralelos entre si)
      │
      └─► T004 ──► T005 ──► T006 ──► T007      (fundação)
                                        │
                                        ├─► US1: T008-T014
                                        │        │
                                        │        └─► US2: T015-T018
                                        │                  │
                                        │                  └─► US3: T019-T021
                                        │
                                        └─► Polish: T022-T029
```

- **T001 antes de tudo**: Princípio I, termo novo entra em `CONTEXT.md` antes de virar código.
- **US2 depois da US1**: aviso sem tela é pior que nada.
- **US3 depois da US2**: ela verifica o que a US2 construiu.

## Oportunidades de paralelismo

- **T002 e T003** — arquivos diferentes, sem dependência.
- **T008 e T009** — unidade e widget, arquivos diferentes.
- **T023 e T024** — verificações que não se estorvam.
- **T004 a T007 não são paralelizáveis**: cada um usa o anterior.
- **T011 e T012 tocam o mesmo arquivo**; T015 a T018 idem.

## Escopo de MVP

**US1 sozinha** (T001–T014) já entrega valor: a tela existe, é encontrável, lista o que houver
e se explica vazia. São 14 tarefas.

Parar aí é defensável enquanto a lista estiver vazia — aviso de novidade sem novidade não faz
nada. **Mas a US2 precisa entrar antes do primeiro item real**, senão a primeira novidade da
história do app é publicada e ninguém percebe, que é exatamente o problema que a feature veio
resolver.

A US3 não é opcional em nenhum cenário: ela é a prova da decisão de privacidade, e prova que
não se faz vira afirmação que ninguém checou.

## Cobertura requisito → tarefa

| Requisito | Tarefas |
|---|---|
| FR-001 lista do mais recente ao mais antigo | T005, T008, T009 |
| FR-002 data e texto para quem usa | T009, T011 |
| FR-003 sem jargão técnico | T003, T027 |
| FR-004 alcançável a partir da Home | T014, T028 |
| FR-005 Visitante vê o mesmo | T013 |
| FR-006 marco de 6/10/2026 | T004, T005, T008 |
| FR-007 lista vazia se explica | T010, T012 |
| FR-008 indicação de novidade | T007, T015, T016, T017 |
| FR-009 abrir faz sumir | T018 |
| FR-010 não volta sem novidade nova | T007, T016 |
| FR-011 primeira instalação sem aviso | T007, T016 |
| FR-012 nada no servidor sobre leitura | T006, T019, T025 |
| FR-013 marcador no aparelho | T006, T026 |
| FR-014 nenhuma frase nova na Política | T021 |
| FR-015 escritas à mão | T003 |
| FR-016 remoção também é descrita | T003 |
| FR-017 critério escrito no repositório | T003 |
| SC-001 texto compreensível | T027 |
| SC-002 zero termos técnicos | T003, T027 |
| SC-003 zero informação ao servidor | T019, T025 |
| SC-004 quem leu tudo não vê aviso | T016 |
| SC-005 primeira instalação sem aviso | T016 |
| SC-006 achar a tela em 15s | T028 |
| SC-007 zero frases novas na Política | T021 |

17/17 requisitos funcionais e 7/7 critérios de sucesso, cada um em ≥1 tarefa.

---

## Phase 7: Convergence

Achados de `/speckit-converge` em 2026-08-10, depois do primeiro `/speckit-implement`.
Nenhum destes está coberto pelas tarefas já abertas (T025–T029).

- [X] T030 Reescrever os casos do grupo "há novidade não vista?" em `test/unit/novidades_test.dart` para exercitar `hasUnseenNewsProvider` de verdade — montando um `ProviderContainer` com `newsRepositoryProvider` e `visibleNewsProvider` sobrescritos — e **apagar o helper `decideUnseen`**, que hoje é uma cópia da lógica do provider e faz os testes passarem mesmo se o provider mudar per FR-008, FR-010, FR-011 (partial)
- [X] T031 Cobrir em `test/widget/novidades_page_test.dart` que abrir `NewsPage` com lista não vazia grava o marcador e invalida `hasUnseenNewsProvider`, e que com lista vazia **não** grava nada — usando um `NewsRepository` falso injetado por override. É o que faz o aviso sumir, e hoje não tem teste nenhum per FR-009, US2/AC2 (missing)
- [X] T032 Acrescentar a `test/widget/router_visitante_test.dart` o caso de um Visitante sem Perfil navegando para `/novidades` e alcançando `NewsPage` — a rota não é gateada, mas nada afirma isso, e o `redirect` de `lib/app.dart` já surpreendeu antes per FR-005, US1/AC3 (missing)
- [X] T033 Registrar no relatório de execução que `NewsPage` é `ConsumerStatefulWidget`, e não `ConsumerWidget` como `plan.md` previa: `initState` é necessário para gravar o marcador ao abrir a tela, e `ConsumerWidget` não tem ciclo de vida. O desvio é deliberado e o código está certo; o texto do plano é que ficou velho per plan: NewsPage como ConsumerWidget (partial)
