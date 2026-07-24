# Data Model: Ação Sugerida

## `public.acoes_sugeridas` (tabela nova)

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `categoria_id` | `uuid` | `NOT NULL`, `REFERENCES categorias_grupo(id)` |
| `nome` | `text` | `NOT NULL`, `check (length(trim(nome)) > 0)` |

Sem `UNIQUE` em `(categoria_id, nome)` — FR-009 permite explicitamente
duplicar o mesmo nome em Categorias diferentes; nada na spec pede impedir
duplicar dentro da mesma Categoria também, então nenhuma constraint extra
(Princípio V).

## Consultas (sem função nova — `select` direto, RLS pública)

- **Sugestões pra Ação candidata** (FR-004): `select nome from
  acoes_sugeridas s join categorias_grupo c on c.id = s.categoria_id where
  c.nome = <grupos.categoria do Grupo pai>`.
- **Sugestões pra Ação avulsa** (FR-005): mesma consulta, com
  `<grupos.categoria>` substituído pela Categoria escolhida como filtro na
  tela (nunca persistida, FR-006).

## RLS (Row Level Security)

- `ENABLE ROW LEVEL SECURITY` em `acoes_sugeridas`.
- `SELECT`: público (`anon, authenticated`, `USING (true)`) — mesma
  política de `categorias_grupo`/`igrejas`.
- `INSERT`/`DELETE`: só quem está em `administradores_distrito`
  (`auth.uid()`), mesmo padrão de `igrejas_insert_admin` (feature 005).
- Sem `UPDATE` — nenhuma policy, nenhum `GRANT` (FR nenhum pede edição).
