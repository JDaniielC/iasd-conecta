## Why

`perfis_update_own` protege a **linha**, não a **coluna**. Quem está autenticado
alcança a própria linha e, por chamada direta à API — fora de qualquer tela —
escreve a própria `idade` e o próprio `genero`.

Não é vazamento: o dado é da própria pessoa. É **contorno de regra de domínio**,
e duas regras deste projeto dependem dessas colunas. Mudar a `idade` foge da
exigência de Apelido e de autorização de responsável para menor de 13 (feature
015). Mudar o `genero` forja a composição de uma Dupla Missionária.

Registrado em `SECURITY-AUDIT.md`, achado 5, e em `PENDENCIAS.md` § 2.1.

## What Changes

O privilégio de `update` em `public.perfis` passa a ser concedido **coluna a
coluna**, e as colunas que carregam regra de domínio ficam de fora. A policy
continua como está — ela filtra a linha; quem decide a coluna é o `grant`.

Nenhuma tela muda. Quem edita o próprio Perfil hoje continua editando o mesmo
conjunto de campos, porque a tela nunca ofereceu `idade` nem `genero` para
edição depois do cadastro.

## Capabilities

### Modified Capabilities
- `perfil-proprio`: o que a titular pode escrever no próprio Perfil deixa de ser
  "a linha inteira" e passa a ser um conjunto nomeado de colunas.

## Impact

- `supabase/migrations/` — uma migration nova com `revoke update` + `grant update (colunas)`.
- Sem mudança em `lib/`. Se alguma tela precisar escrever uma coluna fora da
  lista, ela falha com `permission denied` — e é isso que o teste tem de provar
  antes de a migration ir para produção.
