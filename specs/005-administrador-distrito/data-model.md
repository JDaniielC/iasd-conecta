# Data Model: Administrador do Distrito

## `public.administradores_distrito`

| Coluna | Tipo | Regra |
|---|---|---|
| `usuario_id` | `uuid` | PK, `REFERENCES perfis(id)` |
| `promovido_por` | `uuid` | `NOT NULL`, `REFERENCES perfis(id)` |
| `created_at` | `timestamptz` | default `now()` |

## `public.igrejas` (coluna nova, estende a feature 001)

| Coluna | Tipo | Regra |
|---|---|---|
| `arquivada_em` | `timestamptz` | nullable — presente = Igreja arquivada |

## Invariantes estruturais

- `administradores_distrito_checar_regras` (`BEFORE INSERT ON
  administradores_distrito`): recusa se `auth.uid()` não está na própria
  tabela (só Administrador promove, FR-001/FR-003 — nunca autodeclaração);
  recusa se `auth.users.is_anonymous` do `usuario_id` promovido não for
  `false` (FR-002 — precisa ter Conta).

## RLS (Row Level Security)

**`administradores_distrito`**:
- `select_public`: `FOR SELECT USING (true)` — mesma transparência de
  outras tabelas de associação do app (`participacoes_grupo`,
  `confirmacoes_acao`).
- `insert_promovido_por_self`: `FOR INSERT WITH CHECK (auth.uid() =
  promovido_por)` — quem promove é sempre a própria sessão fazendo a
  chamada; o trigger garante que essa sessão já é Administrador.
- Sem policy de `UPDATE`/`DELETE` (sem revogação nesta feature).

**`igrejas`** (policy de select da feature 001 substituída):
- `select_ativas_publico` (substitui `igrejas_select_public`): `FOR SELECT
  USING (arquivada_em IS NULL OR EXISTS (SELECT 1 FROM
  administradores_distrito WHERE usuario_id = auth.uid()))` — FR-007/
  FR-008.
- `insert_admin`: `FOR INSERT WITH CHECK (EXISTS (SELECT 1 FROM
  administradores_distrito WHERE usuario_id = auth.uid()))` — FR-004/
  FR-006.
- `update_admin`: `FOR UPDATE USING (EXISTS (SELECT 1 FROM
  administradores_distrito WHERE usuario_id = auth.uid()))` — FR-005/
  FR-006 (arquivar é a única escrita esperada, mas a policy não restringe
  a coluna especificamente — mesmo nível de confiança já aplicado a outras
  policies de update no projeto).

**`acoes`** (policy de update da feature 004 substituída):
- `update_criador_dono_grupo_ou_admin` (substitui
  `acoes_update_criador_ou_dono_grupo`): adiciona `OR EXISTS (SELECT 1 FROM
  administradores_distrito WHERE usuario_id = auth.uid())` — FR-009.
