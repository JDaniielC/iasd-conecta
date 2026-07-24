# Research: Ação Sugerida

## Tabela nova, sem edição — mesmo padrão de `igrejas`/`categorias_grupo`

**Decision**: `acoes_sugeridas (id, categoria_id references
categorias_grupo(id), nome)`. Só `INSERT`/`DELETE` pelo Administrador do
distrito, sem `UPDATE` — corrigir um erro é remover e cadastrar de novo.

**Rationale**: é uma lista de referência pura (Princípio V) — mesmo nível
de simplicidade já usado em `igrejas` (feature 001, sem edição de nome) e
`categorias_grupo` (feature 002, cadastro simples). Adicionar `UPDATE`
seria mais uma superfície de regra sem necessidade pedida pela spec.

**Alternatives considered**: permitir editar nome/categoria (rejeitado —
FR nenhum da spec pede isso, e o Assumption da spec já descarta
explicitamente).

## Sugestão pra Ação candidata: `join` por texto entre `grupos.categoria` e `categorias_grupo.nome`

**Decision**: a consulta de sugestões pra uma candidata filtra
`acoes_sugeridas` por `categoria_id` cujo `categorias_grupo.nome` seja
igual a `grupos.categoria` (texto) do Grupo pai — não por uma FK direta
entre `acoes`/`grupos` e `acoes_sugeridas`.

**Rationale**: `grupos.categoria` já é texto livre desde a feature 002 (o
seletor de Criar Grupo grava o nome escolhido, sem coluna de FK) — mudar
isso pra uma FK seria uma migração retroativa fora do escopo desta
feature. O `join` por igualdade de texto resolve sem tocar em `grupos`.

**Alternatives considered**: adicionar `grupos.categoria_id` (FK)
retroativamente (rejeitado — mudaria o modelo de dados de uma feature já
squashed e testada, risco desproporcional ao ganho pra esta feature).

## Categoria de filtro na Ação avulsa: só client-side, nunca persistida

**Decision**: a tela de Criar Ação avulsa usa a Categoria escolhida
apenas como parâmetro de uma consulta (`fetchSuggestions(categoriaId)`) —
nenhum campo novo em `acoes`, nenhum dado enviado ao `criarAcao`
relacionado à Categoria.

**Rationale**: é exatamente o que a spec pede (FR-006) — Ação avulsa não
tem Categoria como atributo de domínio (`CONTEXT.md` não define isso), e
inventar uma coluna só pra guardar um filtro de tela violaria Princípio
V.

**Alternatives considered**: guardar a Categoria escolhida em
`acoes.categoria_filtro_criacao` só pra fins de analytics (rejeitado —
nenhuma spec/glossário pede isso; dado sem uso definido é o tipo de
coisa que o Princípio II pede pra evitar coletar).

## Leitura pública, sem `SECURITY DEFINER`

**Decision**: `SELECT` em `acoes_sugeridas` é público (`anon,
authenticated`, `USING (true)`) — mesma política de `categorias_grupo` e
`igrejas`. Nenhuma função `SECURITY DEFINER` necessária, porque não há
regra condicional pra escrita além de "só Administrador", já resolvida
por uma `policy` simples comparando `auth.uid()` contra
`administradores_distrito` (mesmo padrão de `igrejas_insert_admin`,
feature 005) — sem precisar ler nenhum dado fora do alcance de RLS.

**Rationale**: diferente de `declarar_lideranca`/`decidir_lideranca`
(feature 006) ou da validação de gênero de Dupla Missionária (feature
007), aqui não há necessidade de ler uma linha de OUTRO usuário — só
checar se `auth.uid()` está em `administradores_distrito` (sua própria
sessão), o que já é público via `administradores_distrito_select_public`.

**Alternatives considered**: nenhuma — é a aplicação direta do padrão já
estabelecido em `igrejas_insert_admin`.
