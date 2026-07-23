# Data Model: Cadastro de Perfil e Upgrade para Conta

## `public.igrejas`

Lista mínima do distrito. Gestão completa (adicionar/remover) é feature futura
do Administrador do distrito; aqui só existe pra ser referenciada no cadastro.

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `nome` | `text` | `NOT NULL`, `UNIQUE` |
| `created_at` | `timestamptz` | default `now()` |

## `public.perfis`

Um Usuário, em um dos dois níveis (Perfil ou Conta — diferença é só
`auth.users.is_anonymous`, não uma coluna nesta tabela).

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, `REFERENCES auth.users(id) ON DELETE CASCADE` |
| `nome` | `text` | `NOT NULL`, `CHECK (nome_valido(nome))` — moderação contra palavrões |
| `apelido` | `text` | nullable, sem informação identificável (regra de UI/produto, não de banco) |
| `igreja_id` | `uuid` | nullable, `REFERENCES igrejas(id)` |
| `telefone` | `text` | nullable |
| `genero` | `text` | `NOT NULL`, `CHECK (genero IN ('masculino','feminino'))` |
| `idade` | `integer` | `NOT NULL`, `CHECK (idade >= 0)` — **nunca lida fora do dono**, ver RLS |
| `consentimento_lgpd_aceito_em` | `timestamptz` | `NOT NULL` — data do aceite, obrigatório pra existir a linha |
| `created_at` | `timestamptz` | default `now()` |

**Invariante estrutural (FR-005)**: `CHECK (idade >= 18 OR apelido IS NOT NULL)`.

**Relacionamentos**: `igreja_id` → `igrejas.id` (opcional). `id` → `auth.users.id`
(1:1, ciclo de vida do Perfil == ciclo de vida do usuário Auth).

**Transições de estado**:
- Criação: `auth.users` (anônimo) existe primeiro → depois `perfis` é inserido
  pelo próprio dono (`auth.uid() = id`).
- Upgrade pra Conta: `auth.users.is_anonymous` vira `false` via `updateUser`;
  `perfis` não muda (mesmo `id`).
- Não há soft-delete nem hard-delete nesta feature (fora de escopo).

## `public.palavras_bloqueadas`

Lista de moderação de nome, mantida por quem administra o app (fora do escopo
desta feature: seed inicial via `supabase/seed.sql`).

| Coluna | Tipo | Regra |
|---|---|---|
| `palavra` | `text` | PK |

## Função `public.nome_valido(nome text) returns boolean`

`SECURITY INVOKER` (pode rodar como qualquer papel; só lê `palavras_bloqueadas`,
que é de leitura pública). Normaliza (`lower`, `unaccent`) e verifica se
alguma palavra bloqueada aparece como substring do nome.

## Função `public.perfil_publico(p_id uuid) returns table(id uuid, nome_exibido text, igreja_id uuid)`

`SECURITY DEFINER`. Único caminho de leitura de dados de outro Usuário
(usado por Grupo/Ação em features futuras). Calcula
`nome_exibido = COALESCE(apelido, nome)`. Nunca seleciona `idade` nem
`telefone`.

## RLS (Row Level Security)

Ambas as tabelas com `ENABLE ROW LEVEL SECURITY`.

**`igrejas`**: `SELECT` liberado a qualquer papel (`anon`, `authenticated`) —
é lista pública de referência. Sem policy de `INSERT`/`UPDATE`/`DELETE`
(gestão é feature futura, via `service_role`).

**`perfis`**:
- `select_own`: `FOR SELECT USING (auth.uid() = id)`
- `insert_own`: `FOR INSERT WITH CHECK (auth.uid() = id)`
- `update_own`: `FOR UPDATE USING (auth.uid() = id)`
- Sem policy de `DELETE` (fora de escopo).
- Leitura de outros Usuários só via `perfil_publico()`, nunca via `SELECT`
  direto na tabela.
