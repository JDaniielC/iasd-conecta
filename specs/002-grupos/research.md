# Research: Grupos

## Categoria de Grupo: FK ou texto livre?

**Decision**: coluna `grupos.categoria` é `text` puro (sem FK). Tabela
`categorias_grupo` existe só como lista de sugestão pro picker da UI, igual
`igrejas` na feature 001.

**Rationale**: FR-004 exige aceitar nome livre quando a pessoa não encontra
categoria adequada — uma FK obrigaria a categoria a existir na tabela de
referência, quebrando esse requisito. `CATEGORIAS-DE-ACAO.md` vira só dado de
seed pra sugestão, não uma restrição.

**Alternatives considered**: FK com `ON DELETE SET NULL` + coluna extra pra
"categoria livre" (rejeitado — dois campos pra um conceito só é complexidade
sem necessidade, Princípio V).

## Invariantes de posse do Grupo: trigger, não só app

**Decision**: dois triggers em Postgres:
1. `BEFORE UPDATE ON grupos` — se `dono_id` mudar, verifica que o novo
   `dono_id` já tem linha em `participacoes_grupo` pra aquele grupo; senão,
   `RAISE EXCEPTION`.
2. `BEFORE DELETE ON participacoes_grupo` — se a linha sendo apagada é do
   `dono_id` atual do grupo, `RAISE EXCEPTION` (Dono não sai sem transferir
   primeiro, FR-012).

**Rationale**: mesmo padrão de `apelido_obrigatorio_menor` na feature 001 —
regra de negócio crítica (SC-005: "0% dos Grupos sem Dono") garantida
estruturalmente, não dependente do client se comportar direito.

**Alternatives considered**: checar só no client antes de chamar a API
(rejeitado — chamada direta à API do Supabase contornaria a regra).

## Participar idempotente (FR-013)

**Decision**: `INSERT ... ON CONFLICT (grupo_id, usuario_id) DO NOTHING` —
via `upsert(..., ignoreDuplicates: true)` no client Supabase.

**Rationale**: participar de um Grupo do qual já se participa não deve
gerar erro pro Usuário; upsert idempotente resolve isso numa única chamada,
sem round-trip extra de "já participa?" antes de inserir.

**Alternatives considered**: checar existência antes de inserir (rejeitado —
duas queries em vez de uma, e ainda teria race condition sem o `ON CONFLICT`).

## Leitura pública de Grupos e participantes

**Decision**: `grupos` e `participacoes_grupo` têm RLS com `SELECT` liberado
a `anon` e `authenticated` (igual `igrejas` na feature 001) — Grupo e a
lista de quem participa são públicos por design (FR-005). Exibição de
*quem* participa (nome/Apelido) continua indo por `perfil_publico()`, nunca
`select` direto em `perfis` — `participacoes_grupo` guarda só o
`usuario_id` (um UUID não é dado sensível por si só).

**Rationale**: reaplica o invariante de privacidade já estabelecido (idade
nunca exposta) sem precisar reinventar nada — `perfil_publico()` já existe.

**Alternatives considered**: criar uma segunda função `SECURITY DEFINER`
específica pra participantes de Grupo (rejeitado — `perfil_publico()`
genérica já serve, chamada uma vez por participante).
