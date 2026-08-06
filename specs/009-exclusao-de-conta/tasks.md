---

description: "Task list — Exclusão de conta (009)"
---

# Tasks: Exclusão de conta

**Input**: Design documents from `/specs/009-exclusao-de-conta/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

**Tests**: obrigatórios. O Princípio IV da constituição é NON-NEGOTIABLE e
esta feature toca quatro das regras que ele lista nominalmente — promoção da
fila de espera, revogação de presença, revogação de voto e composição de
Dupla Missionária. Teste não é opção aqui.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: a qual user story a tarefa pertence (US1, US2, US3)
- Caminho de arquivo exato em toda descrição

## Path Conventions

Projeto Flutter único (mobile-app). Schema em `supabase/migrations/`, código
em `lib/features/`, testes em `test/{unit,widget,integration}/`. Ver
"Source Code" em [plan.md](./plan.md).

---

## Phase 1: Setup

**Purpose**: preparar o terreno. Não há projeto novo a inicializar.

- [X] T001 Criar o arquivo de migration vazio `supabase/migrations/20260806140000_exclusao_de_conta.sql` com o cabeçalho de comentário explicando o problema que a feature resolve, seguindo o padrão de `supabase/migrations/20260806090000_nome_valido_security_definer.sql`
- [X] T002 [P] Confirmar que o Supabase local está de pé e limpo com `supabase db reset`, e registrar a contagem atual de testes (`flutter test test/unit test/widget` e `dart test test/integration`) como linha de base

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: mudanças de schema e de modelo das quais **todas** as stories dependem.

**⚠️ CRITICAL**: nenhuma user story começa antes desta fase fechar.

- [X] T003 Em `supabase/migrations/20260806140000_exclusao_de_conta.sql`, derrubar a constraint `perfis_id_fkey`, comentando no próprio SQL por que nenhuma variação de `ON DELETE` resolve (ver [research.md](./research.md) § 2)
- [X] T004 No mesmo arquivo, relaxar `not null` de `perfis.genero` e `perfis.idade` e adicionar a coluna `perfis.anonimizado_em timestamptz`, conforme [contracts/schema.sql](./contracts/schema.sql) § 2
- [X] T005 Aplicar com `supabase db reset` e verificar no banco que as três mudanças existem e que as 15 migrations anteriores continuam aplicando limpo
- [X] T006 Traduzir `lib/features/perfil/domain/perfil.dart` para inglês (`perfil.dart`→`profile.dart`, `Perfil`→`Profile`, `genero`→`gender`, `idade`→`age`, `apelido`→`nickname`, `igrejaId`→`churchId`, `menorDeIdade`→`isMinor`) e propagar aos 29 arquivos que o referenciam. **Commit separado**, sem mudança de comportamento: o Princípio I manda traduzir o arquivo que se toca, e 211 renomeações no mesmo commit da mudança de nulidade tornariam o diff da feature ilegível e o `git bisect` inútil. Gate: `flutter analyze` limpo e a suíte inteira verde antes e depois, com a mesma contagem de testes
- [X] T007 ~~Tornar `gender` e `age` anuláveis em `profile.dart`~~ **CANCELADA na implementação.** `Profile` é write-only: só é construído pelo formulário de cadastro (`cadastro_perfil_page.dart:52`), `hasPerfil()` seleciona apenas `id`, e leitura de terceiros passa por `perfil_publico` → `PublicProfile`, que por design não devolve gênero nem idade (FR-004). O nulo existe só na linha do banco, que o Dart nunca carrega. Torná-los anuláveis enfraqueceria a invariante do cadastro sem nenhum ganho
- [X] T008 Em `test/unit/profile_model_test.dart`, cobrir o que de fato chega ao Dart de um Perfil anonimizado: `PublicProfile.fromMap` com `nome_exibido = 'Membro removido'` e `igreja_id` nulo — a projeção pública é o único caminho pelo qual o app enxerga quem saiu
- [X] T009 Rodar `flutter analyze` e a suíte, confirmando que a Fase 2 não mudou comportamento nenhum no app

**Checkpoint**: schema novo aplicado, modelo Dart compilando, testes unitários verdes.

---

## Phase 3: User Story 1 — Sair do app e não deixar rastro pessoal (P1) 🎯 MVP

**Goal**: um Usuário sem posse nenhuma exclui a própria conta pelo app; o Perfil vira `'Membro removido'`, o login morre, os vínculos futuros somem e o histórico de terceiros fica intacto.

**Independent Test**: criar Perfil sem Grupo próprio e sem Rodada aberta, chamar a exclusão pelo app, e conferir no banco que `auth.users` sumiu, `perfis` permaneceu anonimizado, confirmação em Ação passada ficou e em Ação futura sumiu.

### Banco

- [X] T010 [US1] Em `supabase/migrations/20260806140000_exclusao_de_conta.sql`, criar `public.excluir_minha_conta()` `SECURITY DEFINER` com `set search_path = public, pg_temp`, validando `auth.uid()` não nulo e existência do Perfil, conforme [contracts/schema.sql](./contracts/schema.sql) § 3
- [X] T011 [US1] Na mesma função, adicionar uma guarda temporária que recusa a exclusão quando a pessoa é Dona de Grupo ou tem Rodada aberta — a herança chega em US2, e sem isso US1 sozinha deixaria Grupo com dono anonimizado. **Esta guarda é removida em T021.**
- [X] T012 [US1] Na mesma função, apagar os vínculos vivos: votos em Rodadas com `fechada_em is null`, confirmações de Ações com `data_hora > now()`, participações em Grupo, declarações próprias de Líder/Diretor e a linha de `administradores_distrito`
- [X] T013 [US1] Na mesma função, anonimizar `perfis` (`nome = 'Membro removido'`, `apelido`/`telefone`/`igreja_id`/`genero`/`idade` nulos, `anonimizado_em = now()`) e apagar `auth.users`, nessa ordem
- [X] T014 [US1] Na mesma função, `revoke all ... from public` e `grant execute ... to authenticated`

### Testes de integração

- [X] T015 [P] [US1] Em `test/integration/account_deletion_test.dart`, cenários 1 e 2 do [quickstart](./quickstart.md): exclusão de Perfil sem posse anonimiza a linha, apaga `auth.users`, e `perfil_publico(uid)` devolve `'Membro removido'` — este último trava o `coalesce(apelido, nome)` contra "simplificação" futura
- [X] T016 [P] [US1] No mesmo arquivo, cenário 3: confirmação em Ação passada permanece, confirmação em Ação futura some
- [X] T017 [P] [US1] No mesmo arquivo, cenário 4 (**Princípio IV — fila de espera**): Ação futura lotada com alguém na fila; depois da exclusão, quem estava na fila está confirmado, provando que `confirmacoes_acao_promover_fila` disparou sem código novo nesta feature
- [X] T018 [P] [US1] No mesmo arquivo, **Princípio IV — Dupla Missionária**: Perfil anonimizado não permanece em vaga de Dupla futura, e a validação de composição por gênero continua recusando dupla inválida

Todos os testes desta seção rodam como role `authenticated`, nunca como superusuário — superusuário tem `BYPASSRLS` e não veria falha de policy. Padrão em `test/integration/security_nome_valido_rls_test.dart`.

### App

- [X] T019 [US1] Em `lib/features/perfil/data/perfil_repository.dart`, adicionar `deleteMyAccount()` chamando `rpc('excluir_minha_conta')` e, no sucesso, `signOut()` — sem o `signOut()` o JWT já emitido segue válido até expirar e o app parece logado (FR-004)
- [X] T020 [US1] Criar `lib/features/perfil/presentation/delete_account_page.dart` com confirmação explícita, descrevendo o que é apagado, o que fica como histórico e que não tem volta (FR-002), e registrar a rota `/delete-account` em `lib/app.dart`. **Acrescentado na implementação**: o ponto de entrada. Rota registrada sem link nenhum deixaria a tela inalcançável e FR-001 descumprida — o botão vive no fim da Política de Privacidade, ao lado do texto que descreve o direito e longe de toque acidental na barra principal

**Checkpoint**: MVP entregue — a maioria dos Usuários já consegue exercer o art. 18, VI sozinha.

---

## Phase 4: User Story 2 — Sair sendo Dono de Grupo, sem derrubar o Grupo (P2)

**Goal**: quem é Dona de Grupo ou abriu Rodada consegue sair; Grupos e Rodadas abertas passam ao Administrador do distrito mais antigo, e nenhum participante perde nada.

**Independent Test**: Dona de Grupo com participantes e uma Rodada aberta pede exclusão; conferir que o Grupo segue com os mesmos participantes sob o novo Dono, e que a Rodada segue aberta sob o novo responsável.

### Banco

- [X] T021 [US2] Em `supabase/migrations/20260806140000_exclusao_de_conta.sql`, remover a guarda temporária de T011 e adicionar a eleição do herdeiro: Administrador mais antigo entre os que ficam, `order by created_at, usuario_id` (o desempate por id existe para o bootstrap, onde dois Administradores podem nascer no mesmo instante)
- [X] T022 [US2] Na mesma função, inserir a participação do herdeiro nos Grupos que ele vai receber **antes** de trocar `dono_id`. `grupos_dono_vira_participante` é `AFTER INSERT` apenas e `grupos_dono_deve_participar` é `BEFORE UPDATE` — inverter a ordem faz o banco recusar e a transação inteira desfazer
- [X] T023 [US2] Na mesma função, transferir `grupos.dono_id` e, em seguida, `rodadas_votacao.aberta_por` das Rodadas com `fechada_em is null`
- [X] T024 [US2] Aplicar com `supabase db reset` e confirmar que a função criada bate com [contracts/schema.sql](./contracts/schema.sql) — o contrato é a fonte de verdade, a migration o segue

### Testes de integração

- [X] T025 [P] [US2] Em `test/integration/account_deletion_test.dart`, cenários 5 e 7: Grupo sobrevive com os participantes originais sob o herdeiro, e Rodada aberta segue aberta sob ele com candidatas e votos de terceiros intactos
- [X] T026 [P] [US2] No mesmo arquivo, cenário 6 — **o teste que trava a ordem das operações**: herdeiro que *não* participava do Grupo passa a participar. Se T022 for invertido, este teste falha alto, que é exatamente o desejado
- [X] T027 [P] [US2] No mesmo arquivo, cenário 8: Rodadas já fechadas e Ações criadas por ela continuam com o id dela, agora anonimizado — não trocam de autor
- [X] T028 [P] [US2] No mesmo arquivo, cenário 9 (**Princípio IV — revogação de voto**): votos dela em Rodada aberta somem e não contam na apuração; votos em Rodada fechada permanecem
- [X] T029 [P] [US2] No mesmo arquivo, cenários 10 e 11: declaração de Líder/Diretor dela some enquanto as que ela confirmou para outros continuam válidas; e quando ela é o Administrador mais antigo, a herança vai para o segundo

**Checkpoint**: a lacuna jurídica que motivou a feature está fechada.

---

## Phase 5: User Story 3 — Recusa quando não há quem herde (P3)

**Goal**: quando não sobra Administrador para herdar, a exclusão recusa, explica o porquê em português e não altera nada.

**Independent Test**: distrito com um único Administrador; pedir exclusão e conferir que a mensagem é explicativa e que o banco não mudou uma linha.

### Banco

- [X] T030 [US3] Em `supabase/migrations/20260806140000_exclusao_de_conta.sql`, adicionar as duas recusas com mensagens distintas: (a) quem sai é o único Administrador do distrito — recusa **mesmo sem nada a herdar**, porque `administradores_distrito_checar_regras` exige um admin pré-existente para promover outro e o distrito ficaria sem saída; (b) há o que herdar e não existe Administrador nenhum

### Testes de integração

- [X] T031 [P] [US3] Em `test/integration/account_deletion_test.dart`, cenários 12 e 13: único Administrador é recusado com e sem posse, e o estado do banco fica idêntico ao anterior (`anonimizado_em` ainda nulo, `auth.users` intacto)
- [X] T032 [P] [US3] No mesmo arquivo, cenário 14: depois de promover um segundo Administrador, a mesma chamada conclui. **Atomicidade (FR-015) coberta pelos cenários 12 e 13**, que provam que a recusa não deixa `anonimizado_em` preenchido nem `auth.users` apagado — a transação desfaz tudo. Não foi preciso injetar falha artificial

### App

- [X] T033 [US3] Em `lib/features/perfil/presentation/delete_account_page.dart`, traduzir a recusa vinda do Postgres para mensagem em português dizendo o que fazer (promover outro Administrador), nunca exibindo erro cru do banco
- [X] T034 [P] [US3] Em `test/widget/delete_account_page_test.dart`, cobrir os cenários 15 a 17: nada dispara sem confirmação explícita, sucesso leva ao estado de Visitante, e a recusa aparece traduzida

---

## Phase 6: Polish & Cross-Cutting

- [X] T035 [P] Em `lib/features/legal/presentation/privacy_policy_page.dart`, reescrever a ressalva de que pode ser necessário transferir responsabilidades antes de sair — ela deixa de ser verdade (FR-016)
- [X] T036 [P] Em `lib/features/legal/presentation/terms_of_use_page.dart`, alinhar a seção "Encerramento de conta" ao comportamento real
- [X] T037 Atualizar a versão e a data em `lib/features/legal/legal_metadata.dart`, já que a Política mudou de conteúdo material
- [X] T038 [P] Conferir com `grep` que nenhum texto legal ainda promete a ressalva antiga — cenário 18 do [quickstart](./quickstart.md); verificar, não confiar na memória
- [X] T039 [P] Adicionar ao `README.md` a rota `/delete-account` na seção Rotas
- [X] T040 Rodar os gates completos e registrar os números reais: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration`
- [X] T041 Atualizar `MAPA-DE-DADOS.md` § Retenção e exclusão, que hoje documenta o bloqueio de chave estrangeira como problema em aberto

---

## Dependencies

```text
Phase 1 (Setup)
      │
      ▼
Phase 2 (Foundational)  ← BLOQUEIA TUDO
      │
      ├──────────────► Phase 3 (US1, P1)  ── MVP
      │                       │
      │                       ▼
      │                Phase 4 (US2, P2)  ── remove a guarda de T011
      │                       │
      │                       ▼
      │                Phase 5 (US3, P3)
      │                       │
      └───────────────────────┴──► Phase 6 (Polish)
```

**Por que US2 e US3 não são paralelas a US1**: as três editam a mesma função
no mesmo arquivo de migration. A independência delas é de *teste e valor*,
não de arquivo — cada fase entrega um incremento demonstrável, mas a ordem
de edição é sequencial. T011 existe justamente para US1 ser segura sozinha.

**Phase 6 depende de US1..US3** porque o texto legal só pode descrever o
comportamento depois que ele existe. Escrever a promessa antes da execução é
o erro que esta feature está corrigindo.

## Parallel Execution

Dentro de cada fase, os testes de integração são o grande bloco paralelo —
arquivos e cenários independentes:

- **US1**: T015, T016, T017, T018 em paralelo depois de T014
- **US2**: T025, T026, T027, T028, T029 em paralelo depois de T024
- **US3**: T031, T032 em paralelo depois de T030; T034 em paralelo com eles
- **Polish**: T035, T036, T038, T039 em paralelo; T037 depois de T035/T036; T040 por último

T010 a T014, e T021 a T023, **não** são paralelizáveis entre si: mesma
função, mesmo arquivo.

## Implementation Strategy

**MVP = Phase 1 + 2 + 3.** Entrega o direito de exclusão para a maioria dos
Usuários, que não é Dona de nada, com a guarda de T011 impedindo o caso que
ainda não é suportado. É demonstrável e seguro em produção.

**Incremento 2 = Phase 4.** Fecha a lacuna que motivou a feature. A partir
daqui a Política de Privacidade pode ser reescrita com honestidade.

**Incremento 3 = Phase 5 + 6.** Cobre o caso raro e alinha promessa com
execução.

**Não ir para produção sem Phase 6.** Enquanto o texto legal descrever um
comportamento que o código não tem mais, a feature está incompleta —
independentemente de todos os testes passarem.
