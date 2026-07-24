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

## Testando manualmente

Além de `flutter run`, útil pra explorar o app com a mão:

- **Supabase Studio** (`http://127.0.0.1:54323`): inspeciona/edita qualquer
  tabela direto, sem SQL — o jeito mais rápido de conferir o que uma ação
  gravou de verdade.
- **Semear Administrador do distrito**: nenhum Perfil vira Administrador
  pelo fluxo normal do app (só admin promove admin). Cadastre um Perfil,
  vire Conta ("Virar Conta" no app — precisa ter Conta, Perfil sozinho o
  trigger recusa), pegue o `id` no Studio (tabela `perfis`) e rode:

  ```bash
  docker exec -i supabase_db_iasd psql -U postgres -d postgres <<'SQL'
  alter table public.administradores_distrito disable trigger administradores_distrito_checar_regras_trigger;
  insert into public.administradores_distrito (usuario_id, promovido_por)
  values ('<seu-uuid-aqui>', '<seu-uuid-aqui>')
  on conflict (usuario_id) do nothing;
  alter table public.administradores_distrito enable trigger administradores_distrito_checar_regras_trigger;
  SQL
  ```
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
`/upgrade-conta` · `/grupos/novo` · `/grupos/:id` · `/grupos/:id/editar` ·
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
