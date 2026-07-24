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
- `lib/features/acao/` — criar Ação avulsa, confirmar presença, fila de
  espera, cancelar (feature 003); Rodada de votação, Ação candidata, votar,
  apuração com sorteio de empate (feature 004) — ver
  [specs/003-acao-avulsa](./specs/003-acao-avulsa) e
  [specs/004-rodada-votacao](./specs/004-rodada-votacao)
- `lib/features/district_admin/` — promover Administrador do distrito,
  gerenciar Igrejas (adicionar/arquivar), cancelar qualquer Ação (feature
  005, primeira com código Dart em inglês) — ver
  [specs/005-administrador-distrito](./specs/005-administrador-distrito)
- `lib/features/leadership/` — autodeclarar Líder/Diretor de Ministério,
  Administrador do distrito confirma/rejeita, identificação pública na
  página do Grupo, expiração anual preguiçosa (feature 006, código Dart em
  inglês) — ver [specs/006-lider-diretor](./specs/006-lider-diretor)
- `supabase/migrations/` — schema versionado (fonte de verdade em
  `specs/<feature>/contracts/schema.sql` de cada feature)

## Rotas

`/home` (lista de Grupos, pública) · `/cadastro` · `/login` ·
`/upgrade-conta` · `/grupos/novo` · `/grupos/:id` · `/grupos/:id/editar` ·
`/acoes` (lista, pública) · `/acoes/novo` · `/acoes/:id` ·
`/grupos/:id/rodadas` · `/grupos/:id/rodadas/novo` · `/rodadas/:id` ·
`/rodadas/:id/candidatas/novo` · `/district-admin/promote` ·
`/district-admin/churches` · `/grupos/:id/leadership/declare` ·
`/leadership/pending`

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
