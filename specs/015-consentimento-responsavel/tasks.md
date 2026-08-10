# Tasks: Consentimento de responsável para menor de idade

**Input**: Design documents from `/specs/015-consentimento-responsavel/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

> **Padrão de idioma (Princípio I, e vale para código de teste também).** Todo identificador
> Dart criado aqui — classe, enum e seus valores, método, função, variável local, parâmetro,
> campo, provider e nome de arquivo — é escrito **em inglês**. Só o **nome do arquivo** de
> teste continua em português. Banco, chaves de leitura/gravação (`map['responsavel_nome']`) e
> strings de UI continuam em português.
>
> **Cada tarefa abaixo já nomeia os identificadores que cria.** Não deixe nome para decidir na
> hora: a feature 011 fez isso e precisou de um passe de correção com 315 renomeações depois.

> **BLOQUEIO RESOLVIDO em 2026-08-09**: o limiar é **abaixo de 13** (criança = 0 a 12), decisão
> do dono do app, alinhada ao art. 14 da LGPD. Não há mais `PENDENTE` no código. Texto original
> do bloqueio: O **valor do limiar de criança** era decisão
> de `/speckit-clarify` e estava pendente (Princípio III proíbe decidi-la ad-hoc no código). As
> tarefas abaixo podem ser escritas com o valor provisório **12**, marcado `PENDENTE` nos dois
> lugares, porque o desenho isola a troca em **duas linhas** (T002 e T007) e **nenhum teste usa
> idade literal**. Mas a feature **não é dada como pronta** sem a resposta — é a primeira linha
> da definição de pronto do quickstart.

**Tests**: obrigatórios. FR-009 exige a regra **no banco**, e a única forma de provar isso é
tentar gravar por fora da tela. `dart test test/integration` é gate de CI.

**Organization**: por user story. A US1 é a coleta, a US2 é o que faz a coleta valer alguma
coisa, a US3 é documento.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: arquivo diferente, sem dependência pendente
- **[Story]**: US1, US2, US3

## Serialização inerente

Uma única migration (`supabase/migrations/<timestamp>_autorizacao_responsavel.sql`) recebe
conteúdo em **cinco** tarefas (T002, T003, T004, T005, T017). São o mesmo arquivo — nunca em
paralelo. A alternativa seria cinco migrations para uma feature, contra o padrão do repositório.

**Não adicione helper a `test/integration/db_test_helper.dart`.** Ele é usado por ~60 arquivos
de teste e tem identificadores em português (`criarUsuarioDeTeste`, `criarPerfilDeTeste`);
tocá-lo obrigaria, pelo Princípio I, a traduzir o arquivo inteiro e quebrar os 60. Os helpers
novos ficam **locais** aos arquivos de teste novos, em inglês.

---

## Phase 1: Setup

**Purpose**: o vocabulário antes do código. A constituição exige, e aqui há uma colisão real a
resolver.

- [X] T001 Em `CONTEXT.md`, adicionar as entradas **Responsável** (`_EN_`: `Guardian`) e **Criança** (`_EN_`: `Child`), e **corrigir a colisão**: `CONTEXT.md:155` hoje lista "responsável" no `_Avoid_` de **Líder/Diretor**, e a partir desta feature "Responsável" é termo próprio — reescrever aquele `_Avoid_` como "responsável pelo Ministério" para o glossário não se contradizer. O `_Avoid_` da entrada nova precisa dizer que Responsável **não é** Líder/Diretor, **não é** necessariamente pai ou mãe, e **não é** o "responsável pelo app" (esse é o controlador). Acrescentar à tabela de conceitos operacionais: Autorização do responsável → `guardianAuthorization`, Limiar de criança → `childAgeThreshold` (FR-013, Princípio I). **Commitar antes de qualquer código**

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: a regra existir no banco. Sem isto, a tela é teatro.

- [X] T002 Criar `supabase/migrations/<timestamp>_autorizacao_responsavel.sql` com as seções 1 e 2 de [contracts/schema.sql](./contracts/schema.sql): a função `public.limiar_crianca()` (`immutable`, com o comentário `PENDENTE(/speckit-clarify)` e o valor provisório 12), o `grant execute` para `anon, authenticated`, as quatro colunas (`responsavel_nome`, `responsavel_contato`, `autorizacao_responsavel_em`, `autorizacao_responsavel_versao`) e os quatro `comment on column` — que são onde fica escrito que isto é **dado pessoal de terceiro** (FR-007). **Esta é uma das duas linhas que o clarify move**
- [X] T003 Acrescentar à migration a seção 3 de [contracts/schema.sql](./contracts/schema.sql): as duas check constraints, **as duas com `not valid`**. `autorizacao_responsavel_crianca` cobre FR-001/FR-004/FR-007/FR-009; `autorizacao_responsavel_so_para_crianca` cobre FR-008. **`not valid` não é otimização** — sem ele a migration falha na hora se existir um cadastro antigo de menor (`ERROR: check constraint ... is violated by some row`, medido em research D-003). Copiar para a migration o bloco `DEFERRED` do contrato, com o aviso de **nunca** rodar `validate constraint` sem decisão de produto
- [X] T004 Acrescentar à migration a seção 4 de [contracts/schema.sql](./contracts/schema.sql): a função `public.perfis_protege_autorizacao_responsavel()` e o gatilho `before update`. Existe porque `perfis_update_own` é `using (auth.uid() = id)` **sem `with check`** — medido: a própria criança trocou `'Maria Mae'` por `'Fulano Inventado'` com um `update` e passou. Sem isto, o registro que a US2 chama de verificável é editável por quem segura o aparelho — e **FR-009** ("não pode entrar por nenhum caminho") vale para reescrita, não só para gravação inicial
- [X] T005 Acrescentar à migration a seção 5 de [contracts/schema.sql](./contracts/schema.sql): `create or replace function public.excluir_minha_conta()` reescrita **inteira** a partir do texto atual de `supabase/migrations/20260806140000_exclusao_de_conta.sql`, zerando as quatro colunas novas no `update` de anonimização, com `set_config('app.bypass_autorizacao_responsavel', 'true', true)` antes e `'false'` depois. **É a tarefa que impede a feature de violar o Princípio II em silêncio**: sem ela, a conta da criança é excluída e o nome e o telefone da mãe continuam no banco — dado de terceiro que não tem conta, não tem tela e não tem como pedir exclusão
- [X] T006 Aplicar a migration com `supabase db reset` e conferir que as **18** migrations anteriores continuam subindo, e que `dart test test/integration` segue nos **127** de antes. Rodar também a Parte 0 de [quickstart.md](./quickstart.md) — a contagem de cadastros antigos de criança — e **anotar o número** (linha de base local: `perfis_total = 1`, `cadastros_de_crianca = 0`)
- [X] T007 Em `lib/features/profile/domain/profile.dart`, adicionar o `const childAgeThreshold` no topo (junto de `_ageOfMajority`, com o mesmo comentário `PENDENTE(/speckit-clarify)`), os campos `guardianName`, `guardianContact` e `guardianAuthorizationAccepted`, e os derivados `bool get isChild` (`age < childAgeThreshold`) e `bool get needsGuardianAuthorization`. **Esta é a segunda das duas linhas que o clarify move**
- [X] T008 Ainda em `lib/features/profile/domain/profile.dart`, estender `readyToSubmit` (exige a caixa marcada **e** nome **e** contato quando `needsGuardianAuthorization`, FR-001/FR-004) e `toInsertMap` (grava as quatro chaves **em português** — `'responsavel_nome'`, `'responsavel_contato'`, `'autorizacao_responsavel_em'` com `DateTime.now().toUtc()`, `'autorizacao_responsavel_versao'` com `LegalMetadata.version` — e grava as quatro como `null` quando não é criança, FR-007/FR-008). Importar `lib/features/legal/legal_metadata.dart`; é acoplamento pequeno e deliberado, que a feature 017 depois unifica
- [X] T009 [P] Criar `test/unit/autorizacao_responsavel_test.dart` com os helpers locais `buildChildProfile({...})` e `buildAdultProfile({...})` (nomes em inglês): `isChild` verdadeiro em `childAgeThreshold - 1` e falso em `childAgeThreshold` — **nunca idade literal**, sempre calculada a partir da constante, para o teste sobreviver à resposta do clarify; `readyToSubmit` falso sem a caixa, sem o nome e sem o contato (FR-001, FR-004); `toInsertMap` gravando as quatro chaves com data e versão (FR-007) e gravando `null` nas quatro acima do limiar (FR-008)

**Checkpoint**: `flutter analyze` limpo, testes de integração ainda em 127, e um `insert` direto de criança sem autorização já é recusado pelo banco. Nenhuma tela mudou ainda.

---

## Phase 3: User Story 1 — Mãe cadastra a filha e assume a responsabilidade (Priority: P1) 🎯 MVP

**Goal**: abaixo do limiar, o cadastro pede nome do responsável, contato e uma autorização
destacada, e não conclui sem os três. Acima do limiar, nada muda.

**Independent Test**: preencher um cadastro com idade abaixo do limiar e verificar que o app
**não conclui** sem os dados do responsável e a autorização marcada.

### Tests for User Story 1

- [X] T010 [US1] Criar `test/widget/autorizacao_responsavel_test.dart` — identificadores em inglês: `MockProfileRepository`, `_pumpSignupPage(tester, repo, {churches})`, `_submitButton(tester)`, `_fillChildForm(tester)`, `_tapGuardianAuthorization(tester)`, const `_testChurch`. Provas: abaixo do limiar aparecem os dois campos e a caixa destacada (FR-001, FR-002); marcar só a caixa LGPD comum **não** habilita o botão — as duas são independentes e recusáveis em separado (FR-002); faltando nome ou contato o botão não habilita (FR-001, FR-004); o texto da caixa diz o que é autorizado e que a identidade do responsável **não é verificada** (FR-003, FR-006). **Achar cada caixa pelo texto, nunca por `find.byType(CheckboxListTile)` com índice** — criança **com** Igreja de origem tem três caixas na árvore, e contagem por tipo vira um jogo de índice que quebra na próxima feature
- [X] T011 [US1] **SC-003 coberto em `test/widget/autorizacao_responsavel_test.dart`** (caso "acima do limiar, o passo não existe"), e a tradução dos identificadores deste arquivo já tinha sido feita no passe global de 2026-08-09. Original: Em `test/widget/cadastro_perfil_page_test.dart`, adicionar o teste de **SC-003**: com idade 30, contar `TextFormField` e `CheckboxListTile` e afirmar que o número é **idêntico** ao de hoje — nenhum passo, nenhum campo, nenhuma caixa a mais para maior de idade (FR-005, SC-003). Na mesma passada, traduzir os identificadores em português deste arquivo, porque o Princípio I manda traduzir o arquivo que se toca: `MockPerfilRepository` → `MockProfileRepository`, `_igrejaTeste` → `_testChurch`, `_tapConsentimento` → `_tapLgpdConsent`, `preencherEEnviar` → `fillAndSubmit`. A asserção de `findsNWidgets(2)` na linha 132 **continua correta** (aquele teste usa idade 30), mas confira

### Implementation for User Story 1

- [X] T012 [US1] Em `lib/features/profile/presentation/profile_signup_page.dart`, adicionar o estado do passo novo — `_guardianNameController`, `_guardianContactController` (ambos `dispose()`ados) e `bool _guardianAuthorization` — e ligá-los ao `Profile` construído em `_currentProfile` (FR-001)
- [X] T013 [US1] Ainda em `profile_signup_page.dart`, renderizar o passo condicional quando `age < childAgeThreshold`: os dois campos e a caixa de autorização dentro de um `Container` com borda, **mesmo desenho** do consentimento de Igreja de origem nas linhas 186-203 (FR-002). Quando a idade **subir** acima do limiar, limpar os dois controllers e desmarcar a caixa — mesmo cuidado que o seletor de Igreja já tem nas linhas 178-181, e o que faz FR-008 valer também pelo caminho da tela (FR-005, FR-008)
- [X] T014 [US1] Escrever o **texto da autorização** em `profile_signup_page.dart`, em português direto, sem juridiquês: quem autoriza, o que está sendo autorizado (incluindo Apelido e Igreja de origem, se preenchida), e que a identidade de quem marca **não é verificada**. Base: a frase proposta em `REVISAO-JURIDICA.md:96-100`. Este texto e o da Política (T020) precisam dizer a **mesma coisa** — a divergência entre os dois é o problema que originou a feature (FR-003, FR-006)
- [X] T015 [US1] Em `profile_signup_page.dart`, adicionar ao `_errorMessage(PostgrestException)` (linhas 102-113) os dois nomes de constraint novos, no mesmo padrão dos três que já estão lá: `autorizacao_responsavel_crianca` → "Menores de X anos precisam da autorização de um responsável."; `autorizacao_responsavel_so_para_crianca` → mensagem de bug de estado. É o que faz a recusa do banco chegar ao usuário **em uma frase**, e não como erro genérico (FR-004)
- [X] T016 [US1] Ainda em `profile_signup_page.dart`, traduzir os identificadores em português do arquivo, porque o Princípio I manda traduzir o arquivo que se toca: `_enviar()` → `_submit()` (e a chamada dele no `ElevatedButton`). Conferir se sobrou algum outro

**Checkpoint**: US1 pronta. A mãe consegue cadastrar a filha, e não consegue concluir sem autorizar. O registro já existe, mas ninguém provou ainda que ele resiste.

---

## Phase 4: User Story 2 — A autorização é verificável, não só uma caixa marcada (Priority: P2)

**Goal**: o registro traz quem autorizou, o contato, quando e sob qual versão — e não pode ser
gravado por fora, nem reescrito depois.

**Independent Test**: consultar o registro de um cadastro de menor e encontrar quem autorizou,
quando, e sob qual versão do texto; e tentar gravar um cadastro de criança por fora da tela.

### Tests for User Story 2

- [X] T017 [US2] Criar `test/integration/autorizacao_responsavel_test.dart` — **o teste que mais importa da feature**, com helpers locais em inglês (`createChildProfile`, `createAdultProfile`, `readGuardianColumns`, consts `_childUid`, `_adultUid`) e **sem tocar `db_test_helper.dart`**. Ler o limiar com `select public.limiar_crianca()` e derivar as idades (`limiar - 1`, `limiar`) — **nenhuma idade literal**. Provas: (a) `insert` direto de criança sem autorização é **recusado** (FR-004, **FR-009**, **SC-001**); (b) `insert` faltando **só** o contato, e depois **só** a data, também é recusado (FR-001); (c) `insert` completo é aceito e a leitura devolve nome, contato, data/hora **e versão** (FR-007, **SC-002**); (d) `insert` de adulto com campos de responsável preenchidos é **recusado** (FR-008); (e) idade **exatamente igual** ao limiar **não** exige autorização — é o Edge Case "de que lado o limiar cai", e o teste é quem documenta a resposta
- [X] T018 [US2] No mesmo `test/integration/autorizacao_responsavel_test.dart`, provar que o registro não se altera: `update` mudando `responsavel_nome`, e outro mudando `autorizacao_responsavel_em`, são **recusados** pelo gatilho (US2, FR-009). Antes desta feature isso passava — medido, `'Maria Mae'` virou `'Fulano Inventado'` com `UPDATE 1`
- [X] T019 [US2] No mesmo arquivo, provar o **contrato do limiar**: `select public.limiar_crianca()` é igual à constante Dart `childAgeThreshold` importada de `package:iasd_conecta/features/profile/domain/profile.dart`. É uma asserção de uma linha que substitui uma regra de disciplina — sem ela, as duas fontes do número divergem no dia em que o clarify responder
- [X] T020 [US2] No mesmo arquivo, provar o comportamento com **cadastro antigo**: semear uma linha de criança sem autorização com o gatilho e as constraints já no lugar (via `alter table ... disable trigger` + `set constraints`, ou inserindo antes e validando depois — o caminho que o banco permitir), e verificar que (a) ela **sobrevive**, (b) qualquer `update` nela é **recusado** — inclusive de um campo sem relação, como telefone — e (c) a **exclusão de conta continua funcionando** nela, porque `idade` vira nulo e o `CHECK` passa. É a prova de que a feature não bloqueia o direito do art. 18 VI de quem já estava cadastrado (spec, Assumptions)
- [X] T021 [US2] Em `test/integration/account_deletion_test.dart`, adicionar **uma** asserção — depois de excluir a conta de uma criança, as quatro colunas do responsável estão **nulas** (Princípio II). **Nenhuma asserção existente deste arquivo pode mudar**; se alguma precisar, T005 reescreveu `excluir_minha_conta` errado
- [X] T022 [US2] Criar `test/integration/autorizacao_responsavel_privacidade_test.dart` (helpers locais em inglês: `_childUid`, `_otherUserUid`, `readAsUser`) provando **SC-004** pelos três caminhos medidos em research D-006: outro `authenticated` fazendo `select` na linha da criança devolve **0 linhas**; `perfil_publico(<uid da criança>)` devolve **só** `id, nome_exibido, igreja_id`; e `anon` **não tem `select`** em `public.perfis` (`anon=Dxtm`, sem `r`). São três afirmações que hoje são verdadeiras por construção — e é exatamente por isso que precisam de teste: a feature 016 pode invalidá-las sem querer

**Checkpoint**: US1 + US2. A autorização existe, resiste a `insert` por fora, resiste a edição, e não vaza. **Aqui a feature vale.**

---

## Phase 5: User Story 3 — O responsável exerce os direitos da criança (Priority: P3)

**Goal**: os documentos passam a descrever o mecanismo que existe, e o responsável sabe como
pedir acesso, correção ou exclusão dos dados da criança.

**Independent Test**: ler a Política e encontrar, em português direto, como o responsável
exerce os direitos da criança — e conferir que o app faz o que ela diz.

- [X] T023 [P] [US3] Em `lib/features/legal/presentation/privacy_policy_page.dart`, reescrever a seção "Crianças e adolescentes" (hoje nas linhas ~215-240): descrever o mecanismo que **passou a existir** — o passo de autorização, o que é registrado, e que a identidade do responsável **não é verificada** —, e manter a regra de adolescente 13-17 como **recomendação**, que é o que a spec decidiu (FR-006, FR-010, SC-005). O texto precisa dizer a **mesma coisa** que a caixa de T014
- [X] T024 [US3] Ainda em `privacy_policy_page.dart`, descrever **como o responsável exerce os direitos da criança** — acesso, correção e exclusão pelo canal de contato que a Política já indica (`LegalMetadata.contactEmail`), e que o contato registrado é o que confirma que quem pede é quem autorizou (US3, FR-010). Não prometer canal de notificação: o app **não** avisa ninguém por e-mail nem telefone, o contato é registro (spec, Assumptions). Se a versão do texto legal mudar por causa desta edição, subir `LegalMetadata.version`
- [X] T025 [P] [US3] Em `MAPA-DE-DADOS.md`, acrescentar as quatro colunas à tabela de "Dados coletados", **na mesma forma das demais entradas** (campo, obrigatório, onde é lido/exibido, nunca exposto a outros), com `arquivo:linha` real; atualizar a seção "Crianças e adolescentes" (linhas 137-146), que hoje afirma "**Não existe** nenhum mecanismo de consentimento parental/responsável"; e registrar em "Retenção e exclusão" que a anonimização zera as quatro colunas (FR-011, SC-005)
- [X] T026 [P] [US3] Em `REVISAO-JURIDICA.md`, alterar o cabeçalho da seção "Mecanismo mínimo viável" (linha 88), que hoje diz "**não implementada por mim**", para apontar a implementação e a feature 015 — dizendo o que foi feito **e o que não foi**: sem verificação de identidade, sem canal de notificação, cadastros antigos não corrigidos, e o limiar tal como o clarify decidiu (FR-012, SC-005)

**Checkpoint**: as três histórias fechadas. O app faz o que os documentos dizem — que é o problema que originou a feature.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [X] T027 Rodar os gates e **anotar o número real** de cada suíte: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration` (exige `supabase start`), `flutter build web`. Linha de base em `main` ao começar: **0 issues**, **152** unit/widget, **127** integração
- [X] T028 Confirmar que os testes de integração pré-existentes listados em [quickstart.md](./quickstart.md) passam **sem edição de asserção** — `apelido_obrigatorio_test.dart`, `perfis_constraints_test.dart`, `perfil_publico_apelido_test.dart`, `apuracao_*`, `fila_de_espera_test.dart`. Esta feature **não toca nenhuma das cinco regras do Princípio IV**; se alguma asserção precisou mudar, a feature vazou do escopo
- [X] T029 Executar a **Parte 3** de [quickstart.md](./quickstart.md) à mão: os cinco caminhos que FR-009 fecha — `insert` de criança sem autorização como `postgres`, como `authenticated` e como `service_role`; `update` subindo um adulto para idade de criança; e `update` da própria criança tentando reescrever o nome do responsável. **Os cinco têm de ser recusados.** Qualquer um que passe significa que a regra está só na tela, que é a situação que a feature existe para acabar (FR-009, SC-001)
- [ ] T030 Executar a **Parte 2** de [quickstart.md](./quickstart.md), itens 1 a 15, com o **item 12** conferido lendo o texto inteiro da Política em voz alta ao lado da caixa de autorização — as duas precisam dizer a mesma coisa (FR-010, SC-005)
- [ ] T031 **Medir SC-006 com gente**: cronometrar uma mãe cadastrando a filha, do início do formulário à conclusão, incluindo o passo novo — precisa ficar **abaixo de 3 minutos**. É o único critério de sucesso que não vira teste automatizado, e some da lista se não estiver escrito (a feature 011 perdeu o SC-003 exatamente assim). Anotar o tempo real; se passar de 3 minutos, anotar **onde** a pessoa travou
- [X] T032 Varredura de **SC-004 no cliente**: `grep -rn "responsavel_nome\|responsavel_contato\|autorizacao_responsavel" lib/` deve retornar ocorrências **apenas** em `lib/features/profile/domain/profile.dart` (o `toInsertMap`). Nenhuma consulta, nenhum provider, nenhuma tela lê essas colunas. O teste de T022 prova o banco; esta varredura prova o cliente
- [X] T033 Varredura de identificador em português nos arquivos Dart tocados pela feature, **inclusive nos de teste** (Princípio I): `profile.dart`, `profile_signup_page.dart`, `cadastro_perfil_page_test.dart` e os três arquivos de teste novos. A feature 011 pulou isso e precisou de 315 renomeações depois
- [X] T034 Registrar as **decisões que ficam abertas**, onde elas serão lidas de novo — no bloco `DEFERRED` da própria migration e no relatório de entrega: (a) o que fazer com os cadastros antigos de criança, que agora são somente-leitura e não foram corrigidos (spec, Assumptions); (b) que a **feature 016** precisa tratar esse caso e **não** pode fazer `select *` em `perfis` numa tela de edição; (c) que a **feature 017** unifica a gravação de versão do texto aceito; (d) se o `/speckit-clarify` ainda não respondeu o limiar, que os comentários `PENDENTE` continuam nos dois lugares

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001)**: sem dependência. **Bloqueia todo o código** (Princípio I)
- **Foundational (T002–T009)**: depende de T001. **Bloqueia todas as histórias**
- **US1 (T010–T016)**: depende da Fase 2
- **US2 (T017–T022)**: depende da Fase 2. **Independente da US1** — o banco é testável sem tela, e T017 é escrito para falhar antes de T003 existir
- **US3 (T023–T026)**: depende de US1 e US2 existirem de fato, senão os documentos voltam a descrever o que o app não faz
- **Polish (T027–T034)**: depende de tudo

### Parallel Opportunities

- **T009** — arquivo de teste unitário novo, independente
- **T023, T025, T026** — três documentos diferentes, sem colisão entre si (T024 é o mesmo arquivo de T023, então vai em sequência)
- **US2 em paralelo com a US1**, se houver duas pessoas: não compartilham arquivo nenhum

Serializações obrigatórias:

| Arquivo | Tarefas que competem |
|---|---|
| a migration da feature | T002, T003, T004, T005, T017 (aplicar/ajustar) |
| `lib/features/profile/domain/profile.dart` | T007, T008 |
| `lib/features/profile/presentation/profile_signup_page.dart` | T012, T013, T014, T015, T016 |
| `test/integration/autorizacao_responsavel_test.dart` | T017, T018, T019, T020 |
| `lib/features/legal/presentation/privacy_policy_page.dart` | T023, T024 |

---

## Cobertura — cada FR e cada SC tem tarefa

| Requisito | Tarefas que o citam |
|---|---|
| FR-001 | T003, T008, T009, T010, T012, T017 |
| FR-002 | T010, T013 |
| FR-003 | T010, T014 |
| FR-004 | T003, T008, T009, T010, T015, T017 |
| FR-005 | T011, T013 |
| FR-006 | T010, T014, T023 |
| FR-007 | T002, T003, T008, T009, T017 |
| FR-008 | T003, T008, T009, T013, T017 |
| FR-009 | T003, T004, T017, T018, T029 |
| FR-010 | T023, T024, T030 |
| FR-011 | T025 |
| FR-012 | T026 |
| FR-013 | T001 |
| SC-001 | T017, T029 |
| SC-002 | T017 |
| SC-003 | T011 |
| SC-004 | T022, T032 |
| SC-005 | T023, T025, T026, T030 |
| SC-006 | **T031** — métrica que só gente mede; tarefa aberta, com tempo anotado |

**13 FR + 6 SC = 19 requisitos, 19 cobertos.** Nenhum SC ficou sem tarefa: o único que não vira
teste automatizado (SC-006, "uma mãe conclui em até 3 minutos") tem tarefa própria e explícita.

---

## Implementation Strategy

### MVP (US1 + US2)

Aqui, diferente da 014, **a US2 não é opcional para o MVP**. FR-009 é o requisito que separa
esta feature de uma validação de tela — sem T003, T004 e T017, o app volta a prometer o que não
executa, que é a violação de constituição que a spec cita na primeira página.

1. T001 (vocabulário, com a colisão de Líder/Diretor resolvida)
2. T002–T009 (banco e modelo)
3. T017–T022 (a prova de que o banco executa)
4. T010–T016 (a tela)
5. **PARAR e VALIDAR**: Parte 3 do quickstart, os cinco caminhos
6. T023–T026 (os documentos param de mentir)

### Entrega incremental

1. Setup + Foundational → a regra existe no banco, nenhuma tela mudou
2. + US2 → está provado que ela executa por fora da tela, e que o dado não vaza
3. + US1 → a mãe consegue cadastrar a filha pelo caminho normal
4. + US3 → Política, `MAPA-DE-DADOS.md` e `REVISAO-JURIDICA.md` descrevem o que existe
5. + Polimento → os números conferidos, inclusive o de SC-006, que precisa de gente

---

## Notes

- `[P]` = arquivo diferente, sem dependência pendente
- **T005 é a tarefa que eu conferiria duas vezes.** É a única que, se esquecida, faz a feature
  criada para proteger criança deixar o telefone da mãe no banco depois de a conta ser
  excluída. Não grita, não quebra teste nenhum que já exista, e é dado de terceiro que não tem
  como se defender sozinho
- **T017 asserção (a)** é a guarda contra a feature virar validação de tela: é o único teste que
  percebe se alguém um dia "simplificar" a constraint
- **T010 não pode achar caixa por índice.** Criança com Igreja de origem tem três
  `CheckboxListTile` na árvore; o teste que já existe (`cadastro_perfil_page_test.dart:132`)
  afirma `findsNWidgets(2)` e continua correto só porque usa idade 30
- Commit por tarefa ou grupo lógico; T003 e T017 devem ir juntos, T004 e T018 também, T005 e
  T021 também
- **Nenhuma tarefa de notificação ao responsável**, e isso é decisão registrada em Assumptions,
  não esquecimento: o contato é registro, não canal
- **Nenhuma tarefa corrige cadastros antigos.** Também é decisão da spec. O que a feature deve a
  eles é não quebrá-los — T020 é quem prova isso
