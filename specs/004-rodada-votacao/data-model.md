# Data Model: Rodada de Votação

## `public.rodadas_votacao`

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `grupo_id` | `uuid` | `NOT NULL`, `REFERENCES grupos(id)` |
| `aberta_por` | `uuid` | `NOT NULL`, `REFERENCES perfis(id)` |
| `prazo` | `timestamptz` | `NOT NULL` |
| `fechada_em` | `timestamptz` | nullable — presente = Rodada fechada |
| `vencedora_id` | `uuid` | nullable, `REFERENCES acoes(id)` — definida só ao fechar |
| `created_at` | `timestamptz` | default `now()` |

## `public.acoes` (colunas novas, estende a feature 003)

| Coluna | Tipo | Regra |
|---|---|---|
| `grupo_id` | `uuid` | nullable, `REFERENCES grupos(id)` — nulo = Ação avulsa |
| `rodada_id` | `uuid` | nullable, `REFERENCES rodadas_votacao(id)` — preenchido enquanto é candidata |
| `confirmada` | `boolean` | `NOT NULL default true` — `false` só enquanto é candidata em votação |

Uma Ação candidata é `confirmada = false` com `rodada_id` apontando pra
Rodada; ao vencer, vira `confirmada = true` e passa a ser indistinguível de
qualquer outra Ação de Grupo (reusa 100% de `AcaoRepository`,
`confirmacoes_acao`, `DetalheAcaoPage`).

## `public.votos`

| Coluna | Tipo | Regra |
|---|---|---|
| `rodada_id` | `uuid` | `NOT NULL`, `REFERENCES rodadas_votacao(id) ON DELETE CASCADE` |
| `usuario_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id) ON DELETE CASCADE` |
| `candidata_id` | `uuid` | `NOT NULL`, `REFERENCES acoes(id) ON DELETE CASCADE` |
| `updated_at` | `timestamptz` | default `now()` |

**PK composta**: `(rodada_id, usuario_id)` — uma pessoa tem no máximo um
voto por Rodada; trocar de escolha é `UPSERT` na mesma linha (FR-006
garantido estruturalmente, ver research.md).

## Invariantes estruturais

- `rodadas_votacao_checar_participante` (`BEFORE INSERT ON
  rodadas_votacao`): recusa se `auth.uid()` não participa de `grupo_id`
  (FR-004).
- `acoes_candidata_checar_regras` (`BEFORE INSERT ON acoes`, só quando
  `rodada_id` não é nulo): deriva `grupo_id` a partir da Rodada (nunca
  confia no valor enviado pelo client), força `confirmada = false`, recusa
  se a Rodada já está fechada, recusa se `auth.uid()` não participa do
  Grupo (FR-003/FR-004).
- `votos_checar_regras` (`BEFORE INSERT OR UPDATE ON votos`): recusa se a
  Rodada já está fechada, se `auth.uid()` não participa do Grupo, ou se
  `candidata_id` não é uma candidata válida (`confirmada = false`) daquela
  Rodada (FR-005/FR-007).
- `fechar_rodada_se_devido(p_rodada_id, p_forcar default false)`
  (`SECURITY DEFINER`): função explícita (não trigger) chamada pelo
  repositório antes de ler/votar/propor numa Rodada. Não-operação se já
  fechada. Se `p_forcar`, exige `auth.uid() = grupos.dono_id` (FR-009/
  FR-010); senão, não-operação se `now() < prazo` (fechamento preguiçoso,
  FR-008). Ao fechar de fato: apura a candidata com mais votos
  (`LEFT JOIN votos` + `ORDER BY count DESC, random() LIMIT 1` — cobre
  empate e o caso de zero votos totais na mesma query, sem caso especial,
  FR-011/FR-012/FR-018), marca a vencedora `confirmada = true` (FR-013),
  apaga as demais candidatas daquela Rodada (`ON DELETE CASCADE` limpa
  `confirmacoes_acao` e `votos` delas, FR-014), e grava `fechada_em`/
  `vencedora_id`.

## RLS (Row Level Security)

**`rodadas_votacao`**:
- `select_public`: `FOR SELECT USING (true)` — FR-017.
- `insert_participante`: `FOR INSERT WITH CHECK (auth.uid() = aberta_por)`
  — quem participa (checado pelo trigger) e abre em próprio nome.
- Sem policy de `UPDATE`/`DELETE` direta — todo fechamento passa por
  `fechar_rodada_se_devido()` (`SECURITY DEFINER`), nunca por `UPDATE`
  direto do client.

**`acoes`** (policy de update da feature 003 estendida):
- `update_criador_ou_dono_grupo` (substitui `acoes_update_criador`):
  `FOR UPDATE USING (auth.uid() = criador_id OR (grupo_id IS NOT NULL AND
  EXISTS (SELECT 1 FROM grupos g WHERE g.id = acoes.grupo_id AND
  g.dono_id = auth.uid())))` — cobre FR-016 (quem propôs a vencedora OU o
  Dono do Grupo cancela a Ação de Grupo), sem quebrar o cancelamento de
  Ação avulsa já existente (`grupo_id IS NULL` cai só na primeira
  condição, igual antes).

**`votos`**:
- `select_public`: `FOR SELECT USING (true)` — mesma transparência já
  aplicada a participantes de Grupo/confirmados de Ação.
- `insert_self` / `update_self`: `WITH CHECK (auth.uid() = usuario_id)` —
  auto-serviço; o trigger cobre as regras de negócio mais profundas.

`fechar_rodada_se_devido` recebe `GRANT EXECUTE` pra `authenticated` (é
`SECURITY DEFINER`, então não precisa de `GRANT UPDATE`/`DELETE` amplo em
`acoes`/`rodadas_votacao`/`votos` pra ninguém além do dono das funções).
