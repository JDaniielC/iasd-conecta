# Data Model: Grupos

## `public.categorias_grupo`

Lista de referência (seed de `CATEGORIAS-DE-ACAO.md`), só pra sugestão no
picker — `grupos.categoria` não tem FK pra cá (FR-004 permite texto livre).

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `nome` | `text` | `NOT NULL`, `UNIQUE` |

## `public.grupos`

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `nome` | `text` | `NOT NULL`, `CHECK (length(trim(nome)) > 0)` |
| `categoria` | `text` | `NOT NULL` — livre ou da lista de referência |
| `horario` | `text` | `NOT NULL` — descrição do encontro recorrente (ex.: "toda terça, 19h") |
| `local` | `text` | `NOT NULL` |
| `detalhes` | `text` | nullable |
| `igreja_id` | `uuid` | nullable, `REFERENCES igrejas(id)` — herdada do criador, pode ser nula |
| `dono_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id)` |
| `created_at` | `timestamptz` | default `now()` |

**Invariante estrutural (FR-011)**: trigger `grupos_dono_deve_participar`
impede `UPDATE` de `dono_id` pra alguém que não tem linha em
`participacoes_grupo` pra esse grupo (ver contracts/schema.sql).

## `public.participacoes_grupo`

| Coluna | Tipo | Regra |
|---|---|---|
| `grupo_id` | `uuid` | `NOT NULL`, `REFERENCES grupos(id) ON DELETE CASCADE` |
| `usuario_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id) ON DELETE CASCADE` |
| `created_at` | `timestamptz` | default `now()` |

**PK composta**: `(grupo_id, usuario_id)` — mesma pessoa não participa duas
vezes do mesmo Grupo (garante FR-013 no nível de schema; idempotência real
via `upsert ... ON CONFLICT DO NOTHING` no client).

**Invariante estrutural (FR-012)**: trigger
`participacoes_grupo_dono_nao_sai_sem_transferir` impede `DELETE` da linha
que corresponde ao `dono_id` atual do grupo.

**Relacionamentos**: `grupo_id` → `grupos.id`; `usuario_id` → `perfis.id`.
Quando um Perfil é apagado (não acontece nesta feature, mas por CASCADE já
correto), suas participações somem junto.

## RLS (Row Level Security)

Todas as três tabelas com `ENABLE ROW LEVEL SECURITY`.

**`categorias_grupo`**: `SELECT` liberado a `anon`, `authenticated` (lista
pública de sugestão). Sem policy de escrita (seed via migration/`service_role`).

**`grupos`**:
- `select_public`: `FOR SELECT USING (true)` — FR-005, igual a `igrejas`.
- `insert_dono`: `FOR INSERT WITH CHECK (auth.uid() = dono_id)` — quem cria
  só pode criar como o próprio Dono (FR-003).
- `update_dono`: `FOR UPDATE USING (auth.uid() = dono_id) WITH CHECK (true)`
  — só o Dono atual edita ou transfere (FR-009, FR-011); `WITH CHECK (true)`
  é necessário porque, numa transferência, a linha nova tem `dono_id`
  diferente de `auth.uid()` — sem isso o Postgres reusaria `USING` também
  pra validar a linha nova e bloquearia a própria transferência. O trigger
  cobre a invariante extra (só pra quem já participa).
- Sem policy de `DELETE` (sem exclusão de Grupo nesta feature).

**`participacoes_grupo`**:
- `select_public`: `FOR SELECT USING (true)` — participante é público
  (FR-005/FR-006).
- `insert_self`: `FOR INSERT WITH CHECK (auth.uid() = usuario_id)` —
  Participar é sempre auto-serviço (FR-006).
- `delete_self_or_dono`: `FOR DELETE USING (auth.uid() = usuario_id OR EXISTS
  (SELECT 1 FROM grupos g WHERE g.id = grupo_id AND g.dono_id = auth.uid()))`
  — cobre sair (FR-007) e remover participante (FR-010); o trigger bloqueia
  o caso do Dono removendo a si mesmo sem transferir antes (FR-012).
