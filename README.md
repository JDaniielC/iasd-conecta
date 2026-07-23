# Rede IASD Vitória de Santo Antão

Rede social para os membros ativos da Igreja Adventista do Sétimo Dia do
distrito de Vitória de Santo Antão descobrirem e se conectarem através de
Grupos e Ações. Domínio e vocabulário completos em [CONTEXT.md](./CONTEXT.md).

Stack: Flutter + Dart + Supabase (Postgres com Row Level Security).

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

## Testes

```bash
flutter test
```

Requer o Supabase local rodando (`supabase start`) — os testes de contrato em
`test/integration/` conectam direto no Postgres e no Auth local, sem
depender de device/emulador.

## Estrutura

- `lib/core/` — cliente Supabase, tema (estética 7me: azul marinho + branco,
  minimalista), providers Riverpod compartilhados
- `lib/features/perfil/` — cadastro de Perfil, upgrade para Conta (feature
  001, ver [specs/001-cadastro-usuario](./specs/001-cadastro-usuario))
- `lib/features/grupo/` — criar/descobrir/participar de Grupo, Dono
  administra (feature 002, ver [specs/002-grupos](./specs/002-grupos))
- `supabase/migrations/` — schema versionado (fonte de verdade em
  `specs/<feature>/contracts/schema.sql` de cada feature)

## Rotas

`/home` (lista de Grupos, pública) · `/cadastro` · `/login` ·
`/upgrade-conta` · `/grupos/novo` · `/grupos/:id` · `/grupos/:id/editar`

## Documentação de processo

Cada feature segue o fluxo do Spec Kit (spec → clarify → plan → tasks →
implement), documentado em `specs/<feature>/`. Constituição do projeto em
[.specify/memory/constitution.md](./.specify/memory/constitution.md).
