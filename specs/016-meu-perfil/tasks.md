# Tasks: Meu Perfil — ver e corrigir os próprios dados

**Input**: Design documents from `/specs/016-meu-perfil/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[data-model.md](./data-model.md), [quickstart.md](./quickstart.md)

**Tests**: incluídos, e nos três níveis. `research.md` D-008 define a estratégia e
`quickstart.md` lista o que cada teste prova. **Integração é obrigatória aqui** — diferente da
feature 010, esta toca RLS e constraints em `UPDATE`, um caminho que nenhuma linha de código
do repositório exercita hoje.

**Organization**: tarefas agrupadas por user story. Cada história é entregável e verificável
sozinha, depois da Fase 2.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: a qual user story a tarefa pertence (US1, US2, US3)

## Regra de idioma que vale para TODAS as tarefas (Princípio I)

Todo identificador Dart criado aqui está **nomeado explicitamente e em inglês** dentro da
tarefa — classe, método, função, variável, parâmetro, campo, provider e nome de arquivo
`.dart`. **Vale igualmente em teste**: helper, mock, variável local e constante de arquivo de
teste também são em inglês; a **única** exceção é o **nome do arquivo** de teste, que continua
em português.

Continuam em português, sem exceção: nome de tabela/coluna/função/policy no banco, as chaves
de leitura e gravação (`map['nome']`, `'igreja_id'`, `'consentimento_lgpd_aceito_em'`), toda
string visível ao Usuário, e comentários.

**Não copiar** o helper `_comoUsuario` de
`test/integration/security_acoes_protege_campos_test.dart:8`: o helper novo se chama `asUser`.
`db_test_helper.dart` continua com os nomes em português que já tem — nenhuma tarefa precisa
alterá-lo, e traduzir arquivo que não se está tocando não é escopo desta feature.

## Path Conventions

App Flutter organizado por feature: `lib/features/<nome>/{domain,data,presentation}/`. Testes
em `test/unit/`, `test/widget/` e `test/integration/`. Caminhos abaixo são reais, conferidos
no repositório.

---

## Phase 1: Setup

- [X] T001 Criar `lib/features/profile/presentation/my_profile_page.dart` com o esqueleto: classe `MyProfilePage` (`ConsumerStatefulWidget`) e estado `_MyProfilePageState`, `Scaffold` com `AppBar(title: Text('Meu Perfil'))` → `SingleChildScrollView` → `Form(key: _formKey)` → `Column`, corpo vazio. Padrão copiado de `lib/features/profile/presentation/profile_signup_page.dart`. Identificadores em inglês; rótulos de UI em português (decisão D-002)
- [X] T002 [P] Criar `test/widget/meu_perfil_page_test.dart` com o harness, todo em inglês: `class MockProfileRepository extends Mock implements ProfileRepository`, `const testChurch = Church(id: 'igreja-1', name: 'Igreja Teste')`, `Profile buildProfile({...})`, `Future<void> pumpMyProfilePage(WidgetTester tester, {...})` e `ElevatedButton saveButton(WidgetTester tester)`. `test/widget/cadastro_perfil_page_test.dart` serve de modelo de estrutura — **não** de nomenclatura, os nomes novos são em inglês

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: pôr a regra num lugar só, ensinar o repositório a ler e escrever o próprio Perfil,
e abrir a rota. **⚠️ Nenhuma user story começa antes desta fase fechar.**

**Nenhuma tarefa desta fase cria migration.** Se alguma parecer precisar, pare: a premissa da
feature (research D-001) caiu e o plano precisa voltar.

- [X] T003 [P] Em `lib/features/profile/domain/name_moderation.dart`: adicionar `static const NameModeration cached = NameModeration(['idiota', 'burro', 'estupido', 'imbecil', 'babaca'])` — a mesma lista que hoje é literal em `profile_signup_page.dart:31`. É o que faz FR-008 continuar verdadeiro depois da entrega, e não só no dia dela (decisão D-004)
- [X] T004 [P] Criar `lib/features/profile/domain/profile_error_message.dart` com `String profileErrorMessage(PostgrestException error, {required String fallback})`, movendo as três traduções de constraint de `profile_signup_page.dart:102-113`: `nome_valido` → `'Esse nome não pode ser usado. Tente outro.'`, `apelido_obrigatorio_menor` → `'Menores de idade precisam definir um Apelido.'`, `consentimento_igreja_destacado` → `'Marque o consentimento específico para usar a igreja de origem.'`. A frase genérica vem por parâmetro, porque cadastro e edição dizem coisas diferentes quando não é constraint (FR-008, decisão D-004)
- [X] T005 Em `lib/features/profile/domain/profile.dart`: (a) `final int? age` e `final Gender? gender` — o schema os nulificou em `20260806140000:45-46`; (b) `isMinor` vira `age != null && age! < _ageOfMajority`; (c) `readyToSubmit` ganha `age != null`, preservando o comportamento atual do botão de cadastro; (d) `toInsertMap` usa `gender?.dbValue`; (e) novos campos `final DateTime? lgpdConsentAcceptedAt` e `final DateTime? churchLgpdConsentAcceptedAt` (FR-002 exige exibir a data do consentimento) (decisão D-003)
- [X] T006 Em `lib/features/profile/domain/profile.dart`: adicionar `factory Profile.fromMap(Map<String, dynamic> map)` lendo `'nome'`, `'apelido'`, `'igreja_id'`, `'telefone'`, `'genero'`, `'idade'`, `'consentimento_lgpd_aceito_em'` e `'consentimento_lgpd_igreja_aceito_em'`, com `lgpdConsentAccepted: true` (a coluna é `not null`: linha que existe é linha que consentiu) e `churchLgpdConsentAccepted` derivado de a data ser não-nula (FR-002, SC-001)
- [X] T007 Em `lib/features/profile/domain/profile.dart`: adicionar `Map<String, dynamic> toUpdateMap()` com **exatamente cinco** chaves — `'nome'`, `'apelido'`, `'igreja_id'`, `'telefone'`, `'consentimento_lgpd_igreja_aceito_em'` — convertendo Apelido e telefone vazios em `null` como `toInsertMap` já faz. **Nunca** incluir `'id'`, `'idade'`, `'genero'`, `'consentimento_lgpd_aceito_em'` nem `'anonimizado_em'`: reusar `toInsertMap` no `UPDATE` reescreveria a data do consentimento LGPD a cada correção de telefone (FR-007, FR-009, FR-010, decisão D-006, tabela em `data-model.md`)
- [X] T008 Em `lib/features/profile/presentation/profile_signup_page.dart`: trocar o campo `_moderation` (linha 31) por `NameModeration.cached` e o método `_errorMessage` (linhas 102-113) por `profileErrorMessage(e, fallback: 'Não deu pra concluir o cadastro agora. Tente de novo.')`. **Zero mudança de comportamento** — `test/widget/cadastro_perfil_page_test.dart` deve continuar verde sem uma linha de alteração; se não continuar, a extração mudou algo que não devia (FR-008)
- [X] T009 Em `lib/features/profile/data/profile_repository.dart`: adicionar `Future<Profile> fetchMyProfile()` (`select()` em `'perfis'` com `.eq('id', uid).maybeSingle()`, no padrão de `hasProfile()` nas linhas 17-25, e `Profile.fromMap` no resultado) e `Future<void> updateMyProfile(Profile profile)` (`from('perfis').update(profile.toUpdateMap()).eq('id', uid)`). **Uma chamada só** em `updateMyProfile` — é ela que responde FR-012 sem transação nem RPC. Comentário de topo do arquivo: dizer que esta é a primeira consumidora de `perfis_update_own`, criada em 2026-07-23 e nunca usada (FR-001, FR-007, FR-012)
- [X] T010 Em `lib/core/providers.dart`: adicionar `final myProfileProvider = FutureProvider<Profile>((ref) async { ref.watch(authStateChangesProvider); return ref.watch(profileRepositoryProvider).fetchMyProfile(); });`, logo abaixo de `hasProfileProvider` (FR-001)
- [X] T011 Em `lib/app.dart`: adicionar `GoRoute(path: '/perfil', builder: (context, state) => const MyProfilePage())` e, no `redirect` (junto dos dois que já existem nas linhas 58 e 62), `if (hasProfile == false && state.matchedLocation == '/perfil') return '/cadastro';`. **`== false`, não `!hasProfile`**: com `hasProfile == null` (carregando) a função já saiu na linha 49, e inverter isso empurraria ao cadastro quem só está esperando a rede. O redirect é o que cumpre FR-005 em web, onde `/perfil` é digitável na barra de endereço (FR-005, risco 1 do plano)
- [X] T012 [P] Em `test/unit/profile_model_test.dart`, acrescentar (todos os helpers e variáveis em inglês): `Profile.fromMap` lê as sete colunas pessoais e a data do consentimento (FR-002, SC-001); `fromMap` aceita `'idade'` e `'genero'` nulos sem estourar (Perfil anonimizado, decisão D-003); `toUpdateMap()` tem exatamente 5 chaves e **nenhuma** delas é `'idade'`, `'genero'`, `'consentimento_lgpd_aceito_em'` ou `'anonimizado_em'` — **é o teste que trava a decisão D-006 contra um "só mais um campinho" futuro**; Apelido e telefone vazios viram `null` e nunca `''`, porque `apelido_obrigatorio_menor` checa `is not null` e `''` passaria (FR-009, FR-010); trocar de Igreja carimba `'consentimento_lgpd_igreja_aceito_em'`, manter a mesma não recarimba, remover zera (FR-011, decisão D-005)
- [X] T013 [P] Em `test/widget/router_visitante_test.dart`: acrescentar dois casos — sem Perfil, navegar para `/perfil` cai em `/cadastro` (FR-005); com Perfil, `/perfil` constrói `MyProfilePage` (FR-001). Lembrar do override de `isAnonymousProvider`, pelo motivo registrado no relatório de execução da feature 010 (o `redirect` lê esse provider sempre, e ele chega ao cliente Supabase, que não existe em teste)

**Checkpoint**: `flutter analyze` limpo, `flutter test test/unit test/widget` verde (152 da base
continuam passando + os novos), `git status` em `supabase/migrations/` limpo, `/perfil` abre
uma tela vazia e recusa quem não tem Perfil.

---

## Phase 3: User Story 1 — Ver o que o app sabe sobre mim (Priority: P1) 🎯 MVP

**Goal**: a pessoa vê, num lugar só, tudo que está guardado sobre ela — sem escrever e-mail
para ninguém.

**Independent Test**: entrar no app com um Perfil e verificar que a tela mostra os mesmos
dados que estão gravados no banco.

> As tarefas de implementação desta fase mexem todas em `my_profile_page.dart`, e as de teste
> todas em `meu_perfil_page_test.dart` — por isso **nenhuma é [P]** dentro da fase.

### Tests for User Story 1

- [X] T014 [US1] Em `test/widget/meu_perfil_page_test.dart`: com `myProfileProvider` resolvido num Perfil completo, os sete campos aparecem com os rótulos do glossário — `Nome`, `Apelido`, `Igreja de origem`, `Telefone`, `Gênero`, `Idade`, `Consentimento aceito em` (FR-001, FR-002, SC-001)
- [X] T015 [US1] Em `test/widget/meu_perfil_page_test.dart`: com um Perfil sem Apelido, sem telefone e sem Igreja, cada um aparece como **explicitamente vazio** — o texto exato escolhido em T017 é encontrado três vezes, não um espaço em branco (FR-003)
- [X] T016 [US1] Em `test/widget/meu_perfil_page_test.dart`: a tela monta com override apenas de `myProfileProvider` e `churchesProvider`, sem nenhum repositório de Grupo, Ação ou de Perfil de terceiro — provando que ela não consulta dado de mais ninguém. Assertar também que `perfil_publico` não é chamada (FR-004)

### Implementation for User Story 1

- [X] T017 [US1] Em `lib/features/profile/presentation/my_profile_page.dart`: observar `myProfileProvider` e renderizar as sete linhas na ordem da spec (nome, Apelido, Igreja de origem, telefone, gênero, idade, data do consentimento). Gênero como `Masculino`/`Feminino` (mesmo mapeamento de `profile_signup_page.dart:149`), Igreja pelo nome vindo de `churchesProvider`, data do consentimento formatada como data legível. **Campo opcional vazio exibe o texto `não informado`**, nunca string vazia (FR-001, FR-002, FR-003, SC-001)
- [X] T018 [US1] Em `lib/features/profile/presentation/my_profile_page.dart`: tratar carregando e erro de `myProfileProvider` com `.when` — diferente da Home (feature 010), aqui a tela **é** o dado, então indicador de carregamento e mensagem de erro são o comportamento correto. Erro exibe `'Não deu pra carregar seus dados agora. Verifique sua conexão e tente de novo.'` e **nenhum dado de mais ninguém** (FR-004)
- [X] T019 [US1] Em `lib/features/home/presentation/home_page.dart`: acrescentar em `_MainCallToAction` um caminho rotulado em texto — `Meu Perfil` → `context.push('/perfil')` — visível somente quando `hasProfileProvider` resolve em `true`. Rótulo em texto, não só ícone; se usar ícone, `Icons.person_outline`, da mesma família Material do resto do app (FR-006)

**Checkpoint**: US1 pronta e demonstrável sozinha. O direito de acesso (LGPD art. 18, II) já
está atendido, mesmo antes de existir edição.

---

## Phase 4: User Story 2 — Corrigir um dado errado, sem pedir para ninguém (Priority: P2)

**Goal**: nome, Apelido, Igreja de origem e telefone corrigidos pela própria pessoa, com as
mesmas regras do cadastro e sem risco de deixar o Perfil pela metade.

**Independent Test**: corrigir o nome na tela e ver o nome novo aparecer onde o nome dela
aparece (lista de participantes de um Grupo).

### Tests for User Story 2

- [X] T020 [US2] Em `test/widget/meu_perfil_page_test.dart`: nome recusado pela moderação mostra **a frase exata do cadastro** — `Esse nome não pode ser usado. Tente outro.` — comparada caractere a caractere. Cobrir os dois caminhos: pré-checagem no cliente (`NameModeration.cached`) e `PostgrestException` com `nome_valido` na mensagem (FR-008)
- [X] T021 [US2] Em `test/widget/meu_perfil_page_test.dart`: com um Perfil de idade abaixo de 18, esvaziar o Apelido desabilita o botão `Salvar` e mostra a mensagem do cadastro. Testar também a `PostgrestException` com `apelido_obrigatorio_menor` (FR-009)
- [X] T022 [US2] Em `test/widget/meu_perfil_page_test.dart`: apagar o telefone mantém `Salvar` habilitado, e o `Profile` recebido por `updateMyProfile` tem `phone` vazio/nulo. Mesmo caso para o Apelido de um Perfil **maior** de idade (FR-010)
- [X] T023 [US2] Em `test/widget/meu_perfil_page_test.dart`: escolher uma Igreja de origem onde não havia faz aparecer a caixa destacada, desmarcada, e desabilita `Salvar` até ela ser marcada. Trocar para outra Igreja **volta** a desmarcá-la. Remover a Igreja faz a caixa sumir (FR-011)
- [X] T024 [US2] Em `test/widget/meu_perfil_page_test.dart`: `updateMyProfile` lançando `SocketException` → o aviso aparece, `tester.takeException()` é `null`, `myProfileProvider` **não** é invalidado, e os valores exibidos continuam sendo os que vieram do banco. É a metade cliente de FR-012 (FR-012, SC-005)
- [X] T025 [US2] Criar `test/integration/perfil_edicao_rls_test.dart` com o helper de sessão **em inglês** — `Future<void> asUser(Connection conn, String uid, Future<void> Function() action)`, no formato de `security_acoes_protege_campos_test.dart:8-17` mas com nome traduzido — e dois casos: (a) Usuário A tentando `update public.perfis set nome = ... where id = <B>` afeta **0 linhas** e o Perfil de B continua idêntico; (b) Usuário A tentando `update public.perfis set id = <B> where id = <A>` é **recusado** — é a prova de que o `using` de `perfis_update_own` vale também como `with check` para a linha nova, que é a razão de nenhuma migration ser necessária (FR-013, SC-004, decisão D-001)
- [X] T026 [US2] Em `test/integration/perfil_edicao_rls_test.dart`: as três constraints reavaliadas no `UPDATE` — nome com palavra bloqueada é recusado (FR-008); esvaziar o Apelido de um Perfil de idade < 18 é recusado (FR-009); pôr `igreja_id` sem `consentimento_lgpd_igreja_aceito_em` é recusado (FR-011). **Depois de cada recusa, reler a linha e assertar que ela está exatamente como antes** — é a metade banco de FR-012 (FR-008, FR-009, FR-011, FR-012, SC-005)
- [X] T027 [US2] Em `test/integration/perfil_edicao_rls_test.dart`: o caminho legítimo — o próprio Usuário altera nome, Apelido, `igreja_id`, telefone e `consentimento_lgpd_igreja_aceito_em` numa instrução só, e as cinco colunas mudam juntas. Assertar no mesmo teste que `idade`, `genero` e `consentimento_lgpd_aceito_em` continuam **inalteradas** (FR-007, FR-012)

### Implementation for User Story 2

- [X] T028 [US2] Em `lib/features/profile/presentation/my_profile_page.dart`: transformar em `TextFormField` os campos de nome, Apelido e telefone, e em `DropdownButtonFormField<String>` a Igreja de origem, inicializados com os valores vindos de `myProfileProvider`. Gênero, idade e data do consentimento **continuam sendo texto**, sem editor (decisão D-006). Acrescentar o `ElevatedButton` com rótulo `Salvar`. Controladores: `_nameController`, `_nicknameController`, `_phoneController`; estado `_churchId`, `_churchConsent`, `_submitting`, `_error` (FR-007)
- [X] T029 [US2] Em `lib/features/profile/presentation/my_profile_page.dart`: aplicar a moderação com `NameModeration.cached` antes de enviar, e traduzir a falha do banco com `profileErrorMessage(e, fallback: 'Não deu pra salvar agora. Verifique sua conexão e tente de novo.')`. **Nenhuma lista de palavras e nenhuma frase de constraint literal neste arquivo** — se aparecer alguma, FR-008 já quebrou (FR-008)
- [X] T030 [US2] Em `lib/features/profile/presentation/my_profile_page.dart`: habilitar `Salvar` por `Profile.readyToSubmit` do `Profile` montado a partir do formulário — sem reimplementar nada. É `readyToSubmit` que já cobre "nome não vazio", "menor precisa de Apelido" e "Igreja escolhida precisa de consentimento destacado". Apelido e telefone vazios continuam válidos para quem é maior (FR-009, FR-010, decisão D-003)
- [X] T031 [US2] Em `lib/features/profile/presentation/my_profile_page.dart`: no `onChanged` do seletor de Igreja, zerar `_churchConsent` — mesma decisão e mesmo comentário de `profile_signup_page.dart:176-181` ("Trocar ou remover a igreja invalida o consentimento anterior — força reafirmar"). A caixa destacada usa o **mesmo texto** do cadastro (`profile_signup_page.dart:196-199`). Ao montar o `Profile` para salvar: Igreja nova ou trocada → `churchLgpdConsentAcceptedAt = DateTime.now().toUtc()`; mesma Igreja → repassar a data que veio do banco, **sem recarimbar**; Igreja removida → `null` nos dois (FR-011, decisão D-005, tabela em `data-model.md`)
- [X] T032 [US2] Em `lib/features/profile/presentation/my_profile_page.dart`: no sucesso do `updateMyProfile`, invalidar `myProfileProvider` **e** `publicProfileProvider`. O segundo é `autoDispose.family` e fica em cache enquanto alguma tela o observa (`group_detail_page.dart:159`, `create_action_page.dart:245`, `create_candidate_page.dart:229`) — sem invalidar, o nome corrigido não aparece na página do Grupo e o cenário 1 da US2 falha **sem erro e sem teste vermelho** (risco 2 do plano). Na falha, **não invalidar nada**: o Perfil no banco não mudou, e o exibido não deve mudar (FR-012, SC-005)
- [X] T033 [US2] Conferir que `updateMyProfile` nunca envia `'id'`: `toUpdateMap()` (T007) não o inclui e o filtro é `.eq('id', uid)`. A garantia de verdade é `perfis_update_own` no banco, provada em T025 — esta tarefa é só a metade cliente, e é assim que FR-013 pede ("garantido no banco, não só na tela") (FR-013)

**Checkpoint**: US1 + US2 funcionando. O direito de correção (LGPD art. 18, III) está atendido
dentro do app.

---

## Phase 5: User Story 3 — A Política deixa de descrever uma ausência (Priority: P3)

**Goal**: quem lê a Política encontra o caminho dentro do app, não uma desculpa.

**Independent Test**: ler a seção "Seus direitos e como usar cada um" e não achar nenhuma
frase dizendo que a tela não existe.

- [X] T034 [US3] Em `test/widget/` (arquivo novo `test/widget/politica_privacidade_perfil_test.dart` ou o teste existente de páginas legais, o que já houver): assertar que os trechos `ainda não existe uma tela própria` e `enquanto não existe tela de edição de perfil` **não aparecem** em `PrivacyPolicyPage`, e que a página cita "Meu Perfil". É o teste que impede a frase de voltar numa edição futura (FR-014, SC-006)
- [X] T035 [US3] Em `lib/features/legal/presentation/privacy_policy_page.dart:170-179`: reescrever os dois `LegalBullet`. O de **acesso** passa a dizer que a pessoa vê nome, Apelido, Igreja de origem, telefone, gênero, idade e a data do consentimento em "Meu Perfil", dentro do app, e mantém o e-mail como canal para o que a tela não cobre. O de **correção** passa a dizer que nome, Apelido, Igreja de origem e telefone se corrigem na própria tela, e que **idade e gênero continuam sendo corrigidos por e-mail** — a Política tem de descrever o app como ele é, inclusive o que ele ainda não faz (FR-014, SC-006, Assumptions da spec)
- [X] T036 [US3] Em `lib/features/legal/presentation/privacy_policy_page.dart`: acrescentar um caminho para `/perfil`, no mesmo padrão do botão que já leva a `/delete-account` na linha 263 (FR-006, FR-014)

**Checkpoint**: as três histórias funcionando, e o app deixa de descrever errado a si mesmo.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T037 Rodar os quatro gates e **anotar os números reais**, comparando com a base em `main` (`flutter analyze` 0 issues, `flutter test test/unit test/widget` **152**, `dart test test/integration` **127**, `flutter build web` ✅). Nunca reportar "os testes passaram" sem o número
- [X] T038 **Conferir que `git status` em `supabase/migrations/` está limpo.** É a verificação da premissa central da feature (research D-001): se nasceu migration, a feature deixou de ser cliente puro e o plano precisa voltar antes de fechar
- [ ] T039 **PARCIAL em 2026-08-10**: item 4 (digitar `/perfil` sem Perfil) **passou** — cai no cadastro. Faltam os itens 6 (nome corrigido propagando no Grupo) e 14 (data do consentimento intacta ao corrigir o telefone) pela tela; o 14 já foi provado por SQL. Os dois exigem concluir um formulário, e o botão de enviar não responde a automação no canvas do Flutter. Original: Executar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 16. **Três são obrigatórios**: item 4 (digitar `/perfil` sem Perfil — o gate que passa despercebido em app web, FR-005), item 6 (corrigir o nome e vê-lo propagar na página de um Grupo — o cache de `publicProfileProvider`), e item 14 (`consentimento_lgpd_aceito_em` não muda ao corrigir o nome — o dado de base legal)
- [X] T040 [P] **Coberto por `test/integration/perfil_edicao_rls_test.dart` (6 casos), que fala com o Postgres direto e não passa pela tela — é a mesma prova que o quickstart pedia por psql à mão.** Executar a verificação de RLS por fora do app descrita no fim da Parte 2 do quickstart (`set request.jwt.claims` + dois `update`). É o único requisito que fala explicitamente de "chamada direta que não passe pela tela" (SC-004)
- [X] T041 [P] Confirmar que `CONTEXT.md` **não** precisou de alteração — nenhum termo novo de domínio foi introduzido (Princípio I). Se precisou, a feature vazou de escopo
- [X] T042 [P] Conferir que nenhuma cor, tamanho ou espaçamento literal entrou em `my_profile_page.dart` — tudo por `AppSpacing`/`Theme.of(context).textTheme`, como no resto do app

### Critérios que só gente mede — abertos de propósito, não esquecidos

- [ ] T043 **SC-002** — cronometrar 3 pessoas que nunca viram a tela, do abrir o app até o nome corrigido. Se passar de 1 minuto, o suspeito é o caminho até `/perfil` (FR-006), não o formulário. Não vira teste automatizado: cronometrar `pumpAndSettle` mediria a máquina, não a pessoa (SC-002)
- [ ] T044 **SC-003** — conferir a caixa de `jdaniielc@gmail.com` 30 dias depois do lançamento: quantos pedidos de acesso ou correção chegaram sobre nome, Apelido, Igreja de origem ou telefone. Qualquer um é sinal de que a tela não foi **encontrada** — problema de FR-006, não de FR-007. Depende de caixa de entrada, fora do repositório (SC-003)

### Dívidas registradas, não consertadas aqui

- [X] T045 Registrar como achado (para virar feature própria, **não** fazer nesta): o `grant` de `perfis` é de tabela inteira (`20260723191202:56`), sem recorte de coluna. `perfis_update_own` protege a **linha**, não a **coluna** — por chamada direta, o Usuário consegue escrever `idade`, `genero` e `consentimento_lgpd_aceito_em` do próprio Perfil. É anterior a esta feature, nenhum FR pede o conserto, e consertar exigiria migration, o que a spec exclui. Conserto identificado: `revoke update on public.perfis from authenticated` + `grant update (nome, apelido, igreja_id, telefone, consentimento_lgpd_igreja_aceito_em) on public.perfis to authenticated` (risco 3 do plano)
- [X] T046 Registrar no bloco de execução no fim deste arquivo que a **feature 017** precisa cobrir também o `UPDATE` desta tela: escolher a Igreja de origem aqui é um aceite novo e precisa gravar a versão do texto (017 FR-001/FR-003), com a versão vindo do banco e não do cliente (017 FR-004). A spec da 017 já prevê o caso nos Edge Cases; o que falta é a tarefa lá. **Não editar nada em `specs/017-versao-do-consentimento/`** a partir daqui

---

## Cobertura de requisitos

Cada FR e cada SC citado em pelo menos uma tarefa. **14/14 FR, 6/6 SC.**

| Req | Tarefas |
|---|---|
| FR-001 | T009, T010, T013, T014, T017 |
| FR-002 | T005, T006, T012, T014, T017 |
| FR-003 | T015, T017 |
| FR-004 | T016, T018 |
| FR-005 | T011, T013 |
| FR-006 | T019, T036, T043 |
| FR-007 | T007, T009, T027, T028 |
| FR-008 | T003, T004, T008, T020, T026, T029 |
| FR-009 | T007, T012, T021, T026, T030 |
| FR-010 | T007, T012, T022, T030 |
| FR-011 | T012, T023, T026, T031 |
| FR-012 | T009, T024, T026, T027, T032 |
| FR-013 | T025, T033 |
| FR-014 | T034, T035, T036 |
| SC-001 | T006, T012, T014, T017 |
| SC-002 | **T043 (aberta — só gente mede)** |
| SC-003 | **T044 (aberta — só gente mede)** |
| SC-004 | T025, T040 |
| SC-005 | T024, T026, T032 |
| SC-006 | T034, T035 |

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001–T002)**: sem dependência
- **Foundational (T003–T013)**: T005→T006→T007 em sequência (mesmo arquivo, e `fromMap`/`toUpdateMap` dependem dos campos novos); T008 depende de T003 e T004; T009 depende de T006 e T007; T010 depende de T009; T011 depende de T001 e T010. **Bloqueia todas as user stories**
- **US1 (T014–T019)**: depende da Fase 2
- **US2 (T020–T033)**: depende da Fase 2 e de T017 (os campos precisam existir antes de virarem editáveis)
- **US3 (T034–T036)**: depende da Fase 2 apenas — a rota `/perfil` precisa existir para a Política apontar para ela. **Independente de US1 e US2** no código, mas é desonesto entregá-la antes: a Política passaria a apontar para uma tela vazia
- **Polish (T037–T046)**: depende das histórias desejadas estarem prontas

### Parallel Opportunities

- **T003 e T004** — arquivos diferentes, um não toca o outro
- **T012 e T013** — arquivos de teste diferentes, ambos só dependem da Fase 2 estar fechada
- **T025, T026 e T027** vivem no mesmo arquivo de integração: escrever em sequência, mas são independentes dos testes de widget da US2 — **duas pessoas podem tocar US2 em paralelo se uma ficar com a integração e a outra com o widget**
- **T040, T041, T042** no polimento — verificações que não se estorvam

Todas as tarefas de implementação de US1 e US2 vivem em `my_profile_page.dart`. Marcá-las como
paralelas seria mentira — dariam conflito. O corte que funciona com mais de uma pessoa é
**por fase**, e dentro da US2, **por nível de teste**.

---

## Conflito com as features abertas em paralelo

| Arquivo | O que esta feature faz | Quem mais toca | Risco |
|---|---|---|---|
| `lib/features/profile/domain/profile.dart` | T005–T007: campos nulos, `fromMap`, `toUpdateMap` | **017** vai acrescentar a versão do consentimento ao caminho de escrita | **Médio** — mesmo arquivo, mesma região. Se a versão vier de `default` no banco (017 FR-004 empurra para isso), `toUpdateMap()` não muda e o conflito é trivial |
| `lib/features/profile/data/profile_repository.dart` | T009: dois métodos novos | **017**, pelo mesmo motivo | **Baixo** — métodos diferentes |
| `lib/features/legal/presentation/privacy_policy_page.dart` | T035–T036: dois bullets e um botão | **017** mexe em `legal_metadata.dart` e `MAPA-DE-DADOS.md`, não nesta página | **Baixo** |
| `lib/features/profile/presentation/profile_signup_page.dart` | T008: duas linhas (lista e mensagem compartilhadas) | **015** vai acrescentar a autorização do responsável ao cadastro | **Baixo** — T008 é substituição de duas expressões |

**Ordem recomendada**: fechar a 016 primeiro. Ela é cliente puro, não tem migration, e deixa
`profile.dart` já com o `toUpdateMap()` que a 017 vai precisar carimbar.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 → T013 (Setup + Foundational)
2. T014 → T019 (US1)
3. **PARAR e VALIDAR**: abrir o app com um Perfil e conferir a tela contra
   `select * from public.perfis where id = '<uid>'` (item 2 do quickstart)
4. Já entrega o direito de acesso da LGPD (art. 18, II) inteiro. A correção continua por
   e-mail, como hoje — mas a Política **ainda não pode** ser alterada, porque ela fala das duas
   coisas

### Entrega incremental

1. Setup + Foundational → regra num lugar só, rota aberta, nada quebrado
2. + US1 → o titular vê os próprios dados (MVP, demonstrável)
3. + US2 → o titular corrige sozinho; e é aqui que a integração precisa rodar
4. + US3 → a Política para de descrever uma ausência
5. + Polimento → gates, quickstart, e os dois critérios que só gente mede

---

## Notes

- `[P]` = arquivo diferente, sem dependência pendente
- **Nenhuma tarefa de migration, nenhuma tarefa de `CONTEXT.md`**: a feature é cliente puro e
  não introduz termo novo. Se qualquer uma das duas aparecer, o escopo vazou
- Commit por tarefa ou por grupo lógico; a Fase 2 deve ir junta — deixar T003/T004 sem T008 dá
  duas fontes da mesma lista de palavras, que é exatamente o que D-004 evita
- Regra que vale para toda a fase de implementação: **nenhuma frase de erro de constraint e
  nenhuma palavra bloqueada literal** em `my_profile_page.dart`
