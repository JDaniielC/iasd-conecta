# IASD Conecta

Rede social para os membros ativos da Igreja Adventista do Sétimo Dia
descobrirem e se conectarem através de Grupos e Ações. A primeira implantação
é o distrito de Vitória de Santo Antão (PE); cada distrito roda o próprio
deploy, com o próprio banco. Domínio e vocabulário completos em
[CONTEXT.md](./CONTEXT.md).

Stack: Flutter + Dart + Supabase (Postgres com Row Level Security).

Projeto independente, mantido por [@JDaniielC](https://github.com/JDaniielC).
Não é software oficial da Igreja Adventista do Sétimo Dia nem de nenhuma de
suas entidades administrativas.

## Arquitetura

Não existe servidor de aplicação próprio. O app Flutter fala direto com o
Supabase, que empacota três papéis:

- **Banco**: Postgres. Schema versionado em `supabase/migrations/`, fonte de
  verdade em `specs/<feature>/contracts/schema.sql` de cada feature.
- **Auth**: GoTrue (serviço de autenticação do Supabase). Todo Perfil começa
  com uma sessão anônima (`signInAnonymously`, `lib/core/supabase_client.dart`)
  — sem senha, sem tela de login — e pode fazer "upgrade" pra Conta com
  email/senha depois. Regra de negócio (FR-001) descrita em
  [specs/001-cadastro-usuario](./specs/001-cadastro-usuario).
- **API**: PostgREST, gerado automaticamente a partir do schema — não tem
  rota escrita à mão nem Edge Function no projeto. Toda leitura/escrita do
  app é: `select`/`insert`/`update` direto numa tabela, ou chamada a uma
  função Postgres (`rpc()`) quando a lógica precisa rodar no banco (ex.:
  `perfil_publico(uuid)`, que expõe só id/nome/igreja e nunca idade/telefone).

Segurança e regra de negócio moram no banco, não no client: Row Level
Security decide quem lê/escreve cada linha, e funções `SECURITY DEFINER` +
triggers cobrem os casos que RLS sozinha não modela (ex.: constraint
`idade >= 18 OR apelido IS NOT NULL`, decisão em
[specs/001-cadastro-usuario/research.md](./specs/001-cadastro-usuario/research.md)).
O client Dart confia nisso e não revalida — é defesa em profundidade, a
validação do lado do app é só UX.

No app, `lib/core/supabase_client.dart` inicializa e expõe o
`SupabaseClient` único (`AppSupabase.client`); `lib/core/providers.dart`
publica esse client e os repositórios (`*_repository.dart`, um por feature
em `lib/features/*/data/`) via Riverpod. Uma tela (`presentation/`) observa
um provider, o provider chama o repositório, o repositório fala com o
Supabase — sem camada de rede própria no meio.

Local (`supabase start`) e produção usam a mesma peça: Postgres + GoTrue +
PostgREST em containers Docker. A diferença é só onde os containers moram —
decidido: **Supabase Cloud gerenciado** (região `sa-east-1`), não
self-hosted (ver `.tickets/IASD-03.md`, descartado 2026-08-05).
A região é requisito de provisionamento, não default do fornecedor — a
exigência, e a verificação do ambiente atual, estão em
[`INFRA-PRODUCAO.md`](INFRA-PRODUCAO.md).

## Rodando localmente

Pré-requisitos: Flutter 3.x, Docker (pro Supabase local), Supabase CLI.

```bash
supabase start          # sobe Postgres+Auth+API local e aplica migrations+seed
cp .env.example .env    # preencha SUPABASE_PUBLISHABLE_KEY com o valor que "supabase start" imprimiu
flutter pub get
flutter run
```

Pra reaplicar o schema do zero (depois de mudar uma migration):

```bash
supabase db reset
```

## Testando manualmente

Além de `flutter run`, útil pra explorar o app com a mão:

- **Supabase Studio** (`http://127.0.0.1:54323`): inspeciona/edita qualquer
  tabela direto, sem SQL — o jeito mais rápido de conferir o que uma ação
  gravou de verdade.
- **Semear Administrador do distrito**: nenhum Perfil vira Administrador
  pelo fluxo normal do app (só admin promove admin) — a primeira linha é
  bootstrap (ver `docs/plans/2026-08-04-bootstrap-admin-design.md`).
  Preencha `ADMIN_EMAIL`/`ADMIN_SENHA`/`ADMIN_NOME`/`ADMIN_GENERO`/
  `ADMIN_IDADE` e `SUPABASE_SERVICE_ROLE_KEY` (valor de `supabase status`)
  no `.env` e rode:

  ```bash
  ./scripts/bootstrap_admin.sh
  ```

  Idempotente — rodar de novo com o mesmo `ADMIN_EMAIL` não faz nada. Mesmo
  script serve pra produção self-hosted quando D-1/IASD-03 decidir onde a
  instância mora.
- **Testar com múltiplos usuários** (fila de espera, votação, Dupla
  Missionária/codireção, Líder confirmando outro Líder): Perfil vive local
  na sessão/device — use abas anônimas do Chrome (`flutter run -d chrome`,
  cada aba anônima = sessão nova) pra simular pessoas diferentes ao mesmo
  tempo, já que reinstalar o app no macOS entre testes perde o Perfil
  atual.

## Testes

```bash
flutter test
```

Requer o Supabase local rodando (`supabase start`) — os testes de contrato em
`test/integration/` conectam direto no Postgres e no Auth local, sem
depender de device/emulador.

## Deploy

Front (Flutter Web) publica em Cloud Storage atrás de Cloud CDN — não mais em branch de git.
O banco continua em Supabase Cloud gerenciado, camada separada (feature 019), não tocada por
isto.

**Publicação é MANUAL, temporariamente.** Push em `main` dispara
`.github/workflows/deploy-web.yml`, que só compila e sobe `build/web` como artifact do GitHub
Actions — não publica sozinho. O plano original era o CI publicar direto, mas o projeto GCP
tem a política `iam.disableServiceAccountKeyCreation` ("Secure by Default"), que bloqueia criar
a chave de conta de serviço que o CI precisaria. Workaround pedido ao Google Cloud Support,
resposta pendente — detalhe em `.tickets/IASD-CI-GCS-UPLOAD.md`.

Enquanto isso, quem publica roda, na própria máquina:

```bash
gcloud auth login   # uma vez, com conta que tem permissão no bucket/CDN
make deploy-web
```

`make deploy-web` builda, confere que só as duas chaves públicas do Supabase foram para o
bundle, e publica em duas passadas (sobe tudo, só depois apaga o que sumiu) — o alvo está no
`Makefile` da raiz, comentado. Site em `http://35.211.105.176` (sem domínio próprio ainda).

Nomes de projeto, bucket e url map: `.tickets/IASD-CI-GCS-UPLOAD.md`. Desenho original (para
quando a política de organização for resolvida e o CI voltar a publicar sozinho), decisões e
runbook: `specs/020-deploy-gcs-cdn/` (ver `quickstart.md` — descreve o fluxo automático, ainda
não o que roda hoje).

A branch `dist-web`, usada pelo deploy anterior, está descontinuada.

**Lacunas conhecidas**: a publicação não é atômica por conjunto — interromper `make deploy-web`
no meio deixa o bucket misturado até alguém rerodar; não há verificação automática de que o
site responde depois de publicar; nada liga a publicação ao resultado de `ci.yml` — um commit
com teste vermelho vira artifact do mesmo jeito.

## Estrutura

- `lib/core/` — cliente Supabase, tema (estética 7me: azul marinho + branco,
  minimalista), providers Riverpod compartilhados
- `lib/features/perfil/` — cadastro de Perfil, upgrade para Conta (feature
  001, ver [specs/001-cadastro-usuario](./specs/001-cadastro-usuario))
- `lib/features/grupo/` — criar/descobrir/participar de Grupo, Dono
  administra (feature 002, ver [specs/002-grupos](./specs/002-grupos))
- `lib/features/acao/` — criar Ação avulsa, confirmar presença, fila de
  espera, cancelar (feature 003); Rodada de votação, Ação candidata, votar,
  apuração com sorteio de empate (feature 004); Dupla Missionária —
  composição por gênero, 2 vagas fixas (feature 007) — ver
  [specs/003-acao-avulsa](./specs/003-acao-avulsa),
  [specs/004-rodada-votacao](./specs/004-rodada-votacao) e
  [specs/007-dupla-missionaria](./specs/007-dupla-missionaria)
- `lib/features/district_admin/` — promover Administrador do distrito,
  gerenciar Igrejas (adicionar/arquivar), cancelar qualquer Ação (feature
  005, primeira com código Dart em inglês) — ver
  [specs/005-administrador-distrito](./specs/005-administrador-distrito)
- `lib/features/leadership/` — autodeclarar Líder/Diretor de Ministério,
  Administrador do distrito confirma/rejeita, identificação pública na
  página do Grupo, expiração anual preguiçosa (feature 006, código Dart em
  inglês) — ver [specs/006-lider-diretor](./specs/006-lider-diretor)
- `lib/features/acao_sugerida/` — atalho de nome pré-cadastrado por
  Categoria de Grupo ao criar Ação avulsa ou propor Ação candidata,
  mantido pelo Administrador do distrito (feature 008, código Dart em
  inglês) — ver [specs/008-acao-sugerida](./specs/008-acao-sugerida)
- `supabase/migrations/` — schema versionado (fonte de verdade em
  `specs/<feature>/contracts/schema.sql` de cada feature)

## Rotas

`/home` (lista de Grupos, pública) · `/cadastro` · `/login` ·
`/upgrade-conta` · `/delete-account` · `/grupos/novo` · `/grupos/:id` · `/grupos/:id/editar` ·
`/acoes` (lista, pública) · `/acoes/novo` · `/acoes/:id` ·
`/grupos/:id/rodadas` · `/grupos/:id/rodadas/novo` · `/rodadas/:id` ·
`/rodadas/:id/candidatas/novo` · `/district-admin/promote` ·
`/district-admin/churches` · `/grupos/:id/leadership/declare` ·
`/leadership/pending` · `/district-admin/suggested-actions`

## Convenção de idioma

Banco de dados (tabelas/colunas/funções) e toda string visível ao usuário:
**português**, seguindo o glossário em `CONTEXT.md`. Identificadores em Dart
(classes/variáveis/métodos/arquivos): **inglês**, a partir da feature 005
(`district_admin/`, `Church`) — código Dart das features 001-004 ainda está
majoritariamente em português e é traduzido gradualmente, ao tocar cada
arquivo (ver Princípio I da
[constituição](./.specify/memory/constitution.md)).

## Documentação de processo

Cada feature segue o fluxo do Spec Kit (spec → clarify → plan → tasks →
implement), documentado em `specs/<feature>/`. Constituição do projeto em
[.specify/memory/constitution.md](./.specify/memory/constitution.md).
