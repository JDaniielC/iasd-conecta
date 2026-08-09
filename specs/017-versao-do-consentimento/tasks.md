# Tasks: Versão do texto aceito no consentimento

**Input**: Design documents from `/specs/017-versao-do-consentimento/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

**Tests**: incluídos e obrigatórios. A regra que esta feature cria — *o banco carimba, o cliente
não* — só é verdade se houver teste de integração provando que o valor mandado pelo cliente é
descartado. `dart test test/integration` é gate de CI (`.github/workflows/ci.yml:44`).
Base em `main`: **0 issues**, **152** unit/widget, **127** integração.

**Organization**: agrupadas por user story. US1 (registro) é entregável sozinha; US2 (consulta)
e US3 (honestidade sobre o passado) são fatias independentes em cima dela.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: US1, US2, US3

## Path Conventions

App Flutter por feature (`lib/features/legal/`, `lib/features/profile/`), banco em
`supabase/migrations/`, testes em `test/unit/`, `test/widget/`, `test/integration/`.

## Fronteira de idioma — vale para toda tarefa abaixo

**Banco em português**: `versoes_texto_legal`, `versao`, `vigente_desde`,
`consentimento_lgpd_versao`, `consentimento_lgpd_igreja_versao`,
`versao_texto_legal_vigente()`, `perfis_carimbar_consentimento()`,
`consentimentos_por_versao()`, valores `'lgpd'` / `'igreja'`, colunas devolvidas `tipo`,
`versao`, `quantidade`.

**Identificador Dart em inglês** — classe, enum e seus valores, método, função, variável local,
parâmetro, campo, provider e nome de arquivo `.dart`: `ConsentKind`, `ConsentKind.lgpd`,
`ConsentKind.church`, `ConsentTally`, `consentedVersion`, `count`, `kind`, `isVersionUnknown`,
`ConsentRepository`, `fetchConsentTally`, `consentRepositoryProvider`, `consentTallyProvider`,
`ConsentVersionsPage`, `consent_versions_page.dart`.

**Chave de `map[...]` em português**: `map['tipo']`, `map['versao']`, `map['quantidade']`.

**String de UI em português**, sem exceção.

**Em código de teste vale a mesma regra**: helper, variável local, mock, parâmetro e constante em
**inglês** (`asUser`, `seedLegacyProfile`, `currentVersion`, `adminUid`, `profileUid`). A
**única** exceção é o **nome do arquivo** de teste, que continua em português — decisão
registrada na feature 012.

> A feature 011 não nomeou os identificadores nas tarefas e custou 315 renomeações depois. Cada
> tarefa abaixo nomeia, em inglês, tudo que ela cria.

---

## Phase 1: Setup

**Purpose**: medir o que a migration vai mexer **antes** de escrevê-la.

- [ ] T001 Rodar `grep -rn "consentimento_lgpd_aceito_em\|consentimento_lgpd_igreja_aceito_em" test/ lib/` e **anotar a saída real**. O gatilho passa a sobrescrever esse timestamp com o `now()` do banco (risco 3 do plano), então toda assertiva sobre o **valor** dele muda junto — assertiva de presença (`isNotNull`/`isNull`) não muda. Pelo levantamento de 2026-08-09 os pontos são `lib/features/profile/domain/profile.dart:70-71`, `test/unit/profile_model_test.dart:85,90,94,96`, `test/integration/db_test_helper.dart:65,113` e `test/integration/perfis_constraints_test.dart:39,80,93`, e **nenhum** compara valor. Se aparecer algum que compare, listar aqui antes de seguir
- [ ] T002 Com `supabase start` no ar, anotar a linha de base do banco local: `select count(*) from public.perfis;` e as colunas `consentimento%` de `information_schema.columns` (Parte 0.b de [quickstart.md](./quickstart.md)). Serve de prova, depois da migration, de que **nenhuma linha existente ganhou versão** (SC-002)

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: o delta de banco que as três histórias usam. Sem isto, nenhuma história existe.

- [ ] T003 Criar `supabase/migrations/<timestamp>_versao_do_consentimento.sql` com os **blocos 1 a 3** de [contracts/schema.sql](./contracts/schema.sql): (a) tabela `public.versoes_texto_legal (versao, vigente_desde, created_at)`, semeada **só** com `('1.1', timestamptz '2026-08-06 00:00:00-03')`, com `grant select` para `anon, authenticated`, RLS ligada e política `versoes_texto_legal_select_public`, e **sem nenhum grant de insert/update/delete** (FR-002, FR-004); (b) `public.versao_texto_legal_vigente()`, que **levanta exceção** quando não há versão vigente em vez de devolver `null` — devolver `null` faria linha nova nascer indistinguível de aceite antigo e destruiria o único significado de `null` (FR-007); (c) as colunas `consentimento_lgpd_versao` e `consentimento_lgpd_igreja_versao` em `public.perfis`, **anuláveis**, com FK para `versoes_texto_legal(versao)`; (d) a função `public.perfis_carimbar_consentimento()` e o gatilho `perfis_carimbar_consentimento_trigger` `before insert or update ... for each row` (FR-001, FR-003, FR-004). **A migration NÃO contém nenhum `update` de backfill** (FR-007, SC-002) e **NÃO contém nenhuma constraint de obrigatoriedade** — ler o bloco de AVISO do contrato: um `check ... not valid` seria verificado em todo `UPDATE` da linha e tiraria de quem se cadastrou antes desta feature o direito de apagar a conta (`excluir_minha_conta` termina num `update public.perfis`). **Nomes de banco em português**, sem exceção
- [ ] T004 Criar `test/integration/versao_texto_legal_registro_test.dart` — é o guarda da duplicação declarada (risco 2 do plano). Três casos: (a) `select public.versao_texto_legal_vigente()` é **igual** a `LegalMetadata.version` importado de `package:iasd_conecta/features/legal/legal_metadata.dart` (**FR-002**); (b) rodando como `authenticated`, `insert`/`update`/`delete` em `public.versoes_texto_legal` são recusados (FR-004); (c) gravar em `perfis` uma versão que não está no catálogo é recusado pela FK (FR-002). Identificadores em inglês: helper `asUser(String uid, Future<void> Function() action)`, variáveis `currentVersion`, `profileUid`

**Checkpoint**: `supabase db reset` aplica a migration; `dart test test/integration/versao_texto_legal_registro_test.dart` verde. Nenhum comportamento de tela mudou.

---

## Phase 3: User Story 1 — Todo aceite novo registra qual texto foi aceito (Priority: P1) 🎯 MVP

**Goal**: a partir de agora, todo consentimento grava **quando** e **sob qual texto** — e o
valor não vem do cliente.

**Independent Test**: cadastrar um Perfil e verificar que a linha traz a versão vigente ao lado
da data; repetir mandando uma versão diferente no `insert` e verificar que ela é descartada.

### Tests for User Story 1

- [ ] T005 [US1] Criar `test/integration/consentimento_versao_carimbada_test.dart` com seis casos, todos como `authenticated` via helper `asUser`: (a) `insert` de Perfil grava `consentimento_lgpd_versao` = versão vigente e `consentimento_lgpd_aceito_em` ≈ `now()` do banco (**FR-001, SC-001**); (b) `insert` que **manda** `consentimento_lgpd_versao` explicitamente tem o valor **descartado** e substituído pela versão vigente — este é o teste central da feature (**FR-004**); (c) `insert` que manda `consentimento_lgpd_aceito_em` de três dias atrás grava o `now()` do banco (FR-004, US1 cenário 3); (d) `insert` com Igreja e consentimento destacado grava também `consentimento_lgpd_igreja_versao` (**FR-003**); (e) `update` que preenche `consentimento_lgpd_igreja_aceito_em` depois do cadastro carimba a versão **daquele instante**, e `update` que o zera zera a versão junto (FR-003, edge case da feature 016); (f) inserir `('1.2-teste', now())` em `versoes_texto_legal`, cadastrar de novo e verificar que grava `1.2-teste` **sem uma linha de código mudar** — limpar a linha do catálogo no `tearDown`, senão T004 passa a falhar, que é exatamente o que ele existe para fazer (**SC-005**). Variáveis em inglês: `currentVersion`, `stampedVersion`, `seededVersion`, `profileUid`

### Implementation for User Story 1

- [ ] T006 [US1] Em `lib/features/profile/domain/profile.dart`, **não acrescentar campo nem chave**: `toInsertMap` continua sem qualquer chave de versão, porque mandar a versão é justamente o que FR-004 proíbe. A mudança é só o comentário acima de `toInsertMap` (hoje sem comentário, linhas 61-74) registrando: o cliente manda `consentimento_lgpd_aceito_em` como **sinal** de que a caixa foi marcada; o **valor** do instante e a versão são gravados pelo gatilho `perfis_carimbar_consentimento` — não "consertar" a ausência numa refatoração futura. `lib/features/profile/presentation/profile_signup_page.dart` **não é tocado** (SC-004)
- [ ] T007 [US1] Ajustar o que a varredura de T001 apontou. Se nenhuma assertiva comparava o **valor** de `consentimento_lgpd_aceito_em` — resultado esperado —, esta tarefa é uma confirmação de que `test/unit/profile_model_test.dart` e `test/integration/perfis_constraints_test.dart` passam **sem edição**, e isso vai anotado. Se alguma comparava, corrigi-la aqui e dizer qual, com o motivo (o carimbo passou a ser do banco)

**Checkpoint**: US1 pronta. A hemorragia parou: todo cadastro novo registra o que foi aceito, e o registro não vale o que o cliente disser.

---

## Phase 4: User Story 2 — Dá para saber quem ainda não aceitou o texto atual (Priority: P2)

**Goal**: uma consulta, um passo, responde quantas pessoas estão sob cada versão e quantas estão
sob versão desconhecida.

**Independent Test**: com cadastros sob versões diferentes, o Administrador do distrito abre a
tela e vê a contagem por versão sem nenhum trabalho manual.

### Tests for User Story 2

- [ ] T008 [US2] Acrescentar ao mesmo `supabase/migrations/<timestamp>_versao_do_consentimento.sql` o **bloco 4** de [contracts/schema.sql](./contracts/schema.sql): `public.consentimentos_por_versao()`, `security definer`, `stable`, `set search_path = ''`, devolvendo `(tipo text, versao text, quantidade bigint)`, que **levanta exceção** se quem chama não estiver em `public.administradores_distrito`; exclui Perfil com `anonimizado_em is not null`; conta `'igreja'` só para quem tem `consentimento_lgpd_igreja_aceito_em is not null`; `revoke all ... from public` + `grant execute ... to authenticated`. **Devolve contagem, nunca identidade** — nada de `id`, `nome` ou `apelido` (Princípio II). Rodar `supabase db reset` depois de editar a migration
- [ ] T009 [US2] Criar `test/integration/consentimentos_por_versao_test.dart` com quatro casos: (a) quem **não** é Administrador do distrito recebe exceção ao chamar a função; (b) Administrador recebe uma linha por versão e os aceites de versão `null` vêm **contados à parte** (**FR-005, FR-006, SC-003**); (c) o conjunto de colunas devolvido é exatamente `tipo`, `versao`, `quantidade` — nenhuma coluna de identidade (**Princípio II**); (d) Perfil com `anonimizado_em` preenchido não entra na contagem. Helper `asUser`, constantes `adminUid`, `plainUserUid`
- [ ] T010 [P] [US2] Criar `test/unit/consentimento_versao_test.dart` (arquivo em português, conteúdo em inglês): `ConsentTally.fromMap` lê `map['tipo']` → `kind`, `map['versao']` → `consentedVersion`, `map['quantidade']` → `count`; `ConsentKind.lgpd.dbValue == 'lgpd'` e `ConsentKind.church.dbValue == 'igreja'`; `isVersionUnknown` é verdadeiro quando `consentedVersion` é `null` e falso para `'1.1'` (FR-006, FR-007)
- [ ] T011 [P] [US2] Criar `test/widget/consentimentos_por_versao_page_test.dart`: (a) com tallies de `1.1` e de versão `null`, a página mostra a contagem de cada uma e rotula a nula como **"Versão desconhecida"**, nunca como "0" nem como célula vazia (FR-006, SC-003); (b) sem nenhum aceite de versão desconhecida, a linha "Versão desconhecida" **não** é inventada; (c) os dois tipos aparecem separados, com rótulos "Consentimento LGPD" e "Consentimento de Igreja de origem". Sobrescrever `consentTallyProvider` com valores fixos — o teste de widget não fala com o banco

### Implementation for User Story 2

- [ ] T012 [P] [US2] Criar `lib/features/legal/domain/consent_tally.dart` com `enum ConsentKind { lgpd('lgpd'), church('igreja') }` (campo `dbValue`, valores em português porque são o contrato com o banco) e `class ConsentTally { final ConsentKind kind; final String? consentedVersion; final int count; bool get isVersionUnknown => consentedVersion == null; factory ConsentTally.fromMap(Map<String, dynamic> map); }`. `consentedVersion` é anulável **de propósito**: `null` é "desconhecida" (FR-006, FR-007)
- [ ] T013 [US2] Criar `lib/features/legal/data/consent_repository.dart` com `class ConsentRepository` e `Future<List<ConsentTally>> fetchConsentTally()` chamando `_client.rpc('consentimentos_por_versao')` e mapeando por `ConsentTally.fromMap`. Segue o padrão de `ProfileRepository.fetchPublicProfile` — RPC, nunca `select` direto em `perfis` (FR-005)
- [ ] T014 [US2] Criar `lib/features/legal/legal_providers.dart` com `consentRepositoryProvider` (a partir de `supabaseClientProvider` de `lib/core/providers.dart`) e `consentTallyProvider` (`FutureProvider.autoDispose<List<ConsentTally>>`), observando `authStateChangesProvider` como `isDistrictAdminProvider` já faz em `lib/features/district_admin/district_admin_providers.dart`
- [ ] T015 [US2] Criar `lib/features/legal/presentation/consent_versions_page.dart` com `class ConsentVersionsPage` — tela **só de leitura**, sem nenhuma ação. Título "Versões de consentimento"; uma seção por `ConsentKind` com rótulos em português ("Consentimento LGPD", "Consentimento de Igreja de origem"); cada linha mostra "Versão X — N pessoas" e, para `isVersionUnknown`, **"Versão desconhecida — N pessoas"**, com uma frase explicando que são aceites anteriores ao registro de versão (FR-005, FR-006, FR-007, SC-003). Fica em `features/legal/` porque o assunto é o consentimento; `district_admin/` é sobre gerir Igreja e promover Administrador
- [ ] T016 [US2] Em `lib/app.dart`, acrescentar a `GoRoute(path: '/district-admin/consentimentos')` apontando para `ConsentVersionsPage`; e em `lib/features/group/presentation/group_list_page.dart`, acrescentar o `IconButton` de entrada **dentro do bloco `if (isDistrictAdmin)` que já existe** (linhas 57-78), com `tooltip: 'Versões de consentimento'`, ao lado de "Igrejas do Distrito" e "Promover Administrador". Sem link para quem não é Administrador — e, mesmo alcançando a rota na mão, a função do banco recusa

**Checkpoint**: US1 + US2. A coluna virou resposta.

---

## Phase 5: User Story 3 — Os aceites antigos são tratados com honestidade (Priority: P3)

**Goal**: quem aceitou antes fica explicitamente **desconhecido**, e os documentos dizem por quê
e desde quando.

**Independent Test**: consultar um cadastro anterior à migration e encontrar versão nula — nunca
um palpite; e ler em `MAPA-DE-DADOS.md` que esses aceites existem e de que período são.

### Tests for User Story 3

- [ ] T017 [US3] Criar `test/integration/consentimento_versao_desconhecida_test.dart` com quatro casos. Semear o Perfil "pré-feature" com o helper `seedLegacyProfile`, que desliga o gatilho como superusuário (`alter table public.perfis disable trigger perfis_carimbar_consentimento_trigger`), grava a linha com versão nula e religa — o caminho normal é impossível, e é esse o ponto. Casos: (a) o Perfil pré-feature continua com `consentimento_lgpd_versao` nula depois da migration, e nenhuma linha existente foi preenchida (**FR-007, SC-002**); (b) rodando como `authenticated`, `update public.perfis set consentimento_lgpd_versao = '1.1' where id = auth.uid()` na própria linha antiga **não** tem efeito — o ramo `else` do gatilho restaura o valor antigo e a versão continua nula (**SC-002**: backfill é impossível, não só desaconselhado); (c) mudar o `nome` desse Perfil funciona e a versão continua nula — prova de que não há constraint travando `UPDATE` de linha antiga (risco 1 do plano, caminho da feature 016); (d) `select public.excluir_minha_conta()` sobre esse Perfil conclui, e a linha anonimizada conserva `consentimento_lgpd_aceito_em` e a versão nula (**risco 1 do plano — LGPD art. 18, VI**). O caso (d) é o teste mais importante da feature: é ele que impede uma feature de conformidade de criar um bug de LGPD

### Implementation for User Story 3

- [ ] T018 [P] [US3] Em `MAPA-DE-DADOS.md`: (a) acrescentar `consentimento_lgpd_versao` e `consentimento_lgpd_igreja_versao` à tabela de "Dados coletados", com `arquivo:linha` da migration nova, na mesma forma das demais entradas; (b) reescrever a seção "Consentimento" (linhas 124-135) para dizer o que passou a existir: a versão é gravada pelo banco, e **existem aceites sem versão conhecida, colhidos entre 2026-07-23** (`20260723191202_perfis_igrejas.sql`, criação de `perfis`) **e a data de aplicação da migration desta feature**; (c) registrar que 1.0 vigorou até 2026-08-05 e 1.1 desde 2026-08-06 — informação sobre o **documento**, que é conhecida — e que atribuir cada aceite antigo a uma delas seria **estimativa**, possível sob demanda e com as três ressalvas de [research.md](./research.md) D-006 ao lado, **nunca gravada na coluna** (**FR-008**); (d) atualizar o item que hoje diz "sem coluna de versão do texto aceito" e a menção ao achado A-5
- [ ] T019 [P] [US3] Em `lib/features/legal/legal_metadata.dart`, reescrever o comentário de doc das linhas 4-9: hoje ele descreve a dívida ("se o texto mudar, não há como saber quem aceitou qual versão"); passa a descrever o mecanismo — `public.perfis.consentimento_lgpd_versao` e `consentimento_lgpd_igreja_versao` são carimbadas pelo gatilho `perfis_carimbar_consentimento` a partir de `public.versao_texto_legal_vigente()`, e **esta constante é a gêmea de exibição da linha correspondente em `public.versoes_texto_legal`: publicar texto novo muda as duas no mesmo commit, e `test/integration/versao_texto_legal_registro_test.dart` falha se divergirem**. Registrar também que os aceites anteriores à feature 017 ficam com versão nula, de propósito (**FR-009**). `version` continua `'1.1'`

**Checkpoint**: as três histórias funcionando.

---

## Phase 6: Polish & verificação

- [ ] T020 Rodar os quatro gates e **anotar os números reais**: `flutter analyze` (base 0 issues), `flutter test test/unit test/widget` (base **152**), `dart test test/integration` (base **127**), `flutter build web`. Confirmar que os **127** testes de integração pré-existentes passam **sem edição**, com a única exceção possível sendo a prevista em T001/T007
- [ ] T021 Rodar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 12. Os dois que não têm substituto automatizado: **item 6** (o corpo do `insert` no DevTools **não** pode conter chave de versão — é o único jeito de provar que o Dart não voltou a mandar valor, FR-004) e **item 1** (a tela de cadastro não ganhou campo nem passo, **SC-004**)

---

## Dependências

- **T001, T002** antes de tudo: são medição, e T001 decide se T007 tem trabalho.
- **T003** bloqueia todo o resto. **T004** logo depois, porque é o guarda que impede a
  duplicação declarada de virar divergência silenciosa.
- **US1 (T005-T007)** depende só da Fase 2.
- **US2 (T008-T016)** depende da Fase 2. Dentro dela: T008 → T009; T010/T011 em paralelo; T012 →
  T013 → T014 → T015 → T016.
- **US3 (T017-T019)** depende da Fase 2 e é independente de US2. T018 e T019 são arquivos
  diferentes e rodam em paralelo.
- **T020, T021** por último.

## Cobertura — cada FR e cada SC em pelo menos uma tarefa

| Requisito | Tarefas |
|---|---|
| FR-001 (aceite do cadastro registra a versão) | T003, T005 |
| FR-002 (versão vem de fonte única) | T003, T004, T019 |
| FR-003 (consentimento de Igreja também) | T003, T005 |
| FR-004 (gravada pelo banco, não pelo cliente) | T003, T004, T005, T006, T008, T021 |
| FR-005 (dá para distinguir quem está sob qual versão) | T008, T009, T013, T015 |
| FR-006 (consulta separa desconhecida de conhecida) | T008, T009, T010, T011, T012, T015 |
| FR-007 (antigos ficam explicitamente desconhecidos, sem palpite) | T003, T012, T015, T017, T018 |
| FR-008 (`MAPA-DE-DADOS.md` registra os aceites sem versão e o período) | T018 |
| FR-009 (comentário de `legal_metadata.dart:4-9` atualizado) | T019 |
| SC-001 (100% dos cadastros novos registram a versão) | T005, T020 |
| SC-002 (0 registros preenchidos retroativamente) | T002, T003, T017 |
| SC-003 (uma consulta responde em um passo) | T009, T011, T015 |
| SC-004 (0 mudanças no que o Usuário vê no cadastro) | T006, T021 |
| SC-005 (0 alterações de código quando a versão muda) | T005 |

**9 FR e 5 SC — todos cobertos.** 21 tarefas: 2 de medição, 2 de fundação, 3 de US1, 9 de US2,
3 de US3, 2 de verificação. 7 tarefas criam ou alteram teste (T004, T005, T007, T009, T010,
T011, T017); 2 escrevem banco (T003, T008); 2 escrevem documento (T018, T019).
