# Data Model: Líder/Diretor de Ministério

## `public.liderancas`

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `grupo_id` | `uuid` | `NOT NULL`, `REFERENCES grupos(id)` |
| `usuario_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id)` |
| `ano` | `integer` | `NOT NULL` |
| `declarado_em` | `timestamptz` | `NOT NULL default now()` |
| `confirmado_por` | `uuid` | nullable, `REFERENCES perfis(id)` — qual Administrador decidiu |
| `confirmado_em` | `timestamptz` | nullable — presente = confirmada |
| `rejeitado_em` | `timestamptz` | nullable — presente = rejeitada |

**UNIQUE** `(grupo_id, usuario_id, ano)` — uma declaração por pessoa, por
Grupo, por ano; redeclarar é `UPDATE` na mesma linha (via
`declarar_lideranca`), nunca uma segunda linha.

**Estado derivado** (nunca uma coluna própria):
- pendente: `confirmado_em IS NULL AND rejeitado_em IS NULL`
- confirmada: `confirmado_em IS NOT NULL`
- rejeitada: `rejeitado_em IS NOT NULL`
- **atual** (o que aparece como "Líder de verdade agora"): confirmada E
  `ano = extract(year from now())` — comparação feita na consulta, sem
  coluna nem processo de expiração (FR-008).

## Funções (únicas escritoras da tabela)

- `declarar_lideranca(p_grupo_id uuid, p_ano integer)` (`SECURITY
  DEFINER`): exige que `auth.uid()` tenha Conta (FR-002); insere a
  declaração como pendente, ou — se já existir uma linha pro mesmo
  Grupo+Usuário+ano e ela **não** estiver confirmada — reseta
  `declarado_em`/`rejeitado_em` (redeclaração após rejeição, FR-010). Se
  já existir confirmada, não faz nada (FR-003).
- `decidir_lideranca(p_lideranca_id uuid, p_aprovar boolean)`
  (`SECURITY DEFINER`): exige que `auth.uid()` seja Administrador do
  distrito (FR-004/FR-005); se `p_aprovar`, seta
  `confirmado_em`/`confirmado_por` e limpa `rejeitado_em`; senão, seta
  `rejeitado_em` e limpa `confirmado_em`/`confirmado_por`.

## RLS (Row Level Security)

- `ENABLE ROW LEVEL SECURITY` em `liderancas`.
- `select_public`: `FOR SELECT USING (true)` a `anon, authenticated` —
  cobre tanto a identificação pública (FR-006) quanto a lista de
  pendentes do Administrador (FR-004), com filtros diferentes no client.
- **Sem** policy de `INSERT`/`UPDATE`/`DELETE`, e **sem** `GRANT
  INSERT/UPDATE` pra `authenticated` — toda escrita é só via as duas
  funções acima (`GRANT EXECUTE` nelas, não na tabela).
