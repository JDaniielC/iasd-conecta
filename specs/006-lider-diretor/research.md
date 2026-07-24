# Research: Líder/Diretor de Ministério

## Toda escrita via `SECURITY DEFINER`, sem `GRANT INSERT/UPDATE` pra `authenticated`

**Decision**: `liderancas` não tem nenhuma policy nem `GRANT` de
`INSERT`/`UPDATE` pra `authenticated`. As duas únicas formas de escrever
são as funções `declarar_lideranca()` e `decidir_lideranca()`, ambas
`SECURITY DEFINER` — que, por serem donas de/rodarem como `postgres`
(dono da tabela), contornam RLS (mesmo comportamento já confirmado
empiricamente em `promover_fila_acao`, feature 004).

**Rationale**: a regra "duplicata é não-operação, silenciosa" (FR-003) só
é implementável de forma limpa com um `INSERT ... ON CONFLICT ... DO
UPDATE ... WHERE confirmado_em IS NULL` — uma condição que o helper
`.upsert()` do client Supabase não expõe (ele não aceita `WHERE` na
cláusula de conflito). Uma função de banco resolve isso numa instrução
só, sem exigir round-trip de "já existe? qual o status?" antes de
decidir o que fazer.

**Alternatives considered**: `GRANT INSERT/UPDATE` direto + trigger
`BEFORE INSERT OR UPDATE` fazendo a mesma checagem condicional
(rejeitado — o trigger precisaria `RAISE EXCEPTION` ou silenciosamente
ignorar a escrita conflitante, e Postgres não tem um jeito limpo de um
trigger "cancelar sem erro" uma escrita que já passou pelo `ON CONFLICT`
do client; a função encapsula isso melhor).

## Duas funções separadas, não uma só com parâmetro de "quem está fazendo o quê"

**Decision**: `declarar_lideranca(p_grupo_id, p_ano)` (autodeclaração) e
`decidir_lideranca(p_lideranca_id, p_aprovar)` (decisão do Administrador)
são funções distintas, cada uma checando só a regra que lhe cabe.

**Rationale**: são duas operações com autorização e efeito completamente
diferentes (self-service vs. admin-only) — juntar num parâmetro genérico
("modo") complicaria a leitura sem ganhar simplicidade real (Princípio
V).

**Alternatives considered**: uma função genérica `atualizar_lideranca`
com um enum de ação (rejeitado — esconderia em runtime uma distinção que
já é estrutural em tempo de design).

## Rejeitar reseta `confirmado_em`/`confirmado_por` também

**Decision**: `decidir_lideranca(..., false)` (rejeitar) explicitamente
zera `confirmado_em`/`confirmado_por`, não só seta `rejeitado_em`.

**Rationale**: garante que uma declaração nunca fique com
`confirmado_em` E `rejeitado_em` preenchidos ao mesmo tempo (estado
inconsistente) — mesmo sem uma `CHECK constraint` explícita disso, a
função é a única escritora, então ela sozinha garante a invariante.

**Alternatives considered**: `CHECK (confirmado_em IS NULL OR
rejeitado_em IS NULL)` (considerado, mas redundante já que só a função
escreve; adicionaria uma constraint sem necessidade prática, Princípio
V).

## Identificação pública e lista de pendentes: mesma tabela, filtros diferentes

**Decision**: não existe uma função/view separada pra "Líder confirmado
público" — é um `select` comum em `liderancas` com `confirmado_em is not
null and rejeitado_em is null and ano = <ano corrente>`, e a lista de
pendentes do Administrador é o mesmo `select` com `confirmado_em is null
and rejeitado_em is null`. RLS `SELECT` já é público (sem dado sensível
na tabela).

**Rationale**: Princípio V — os dois casos de uso são só filtros
diferentes sobre a mesma leitura pública, não justificam duas
funções/views.

**Alternatives considered**: view `liderancas_confirmadas` materializando
só as confirmadas do ano corrente (rejeitado — `ano = extract(year from
now())` já é um filtro trivial no client, view seria uma camada extra sem
necessidade).

## "Ministério" e "Líder/Diretor" continuam sem tabela própria

**Decision**: nenhuma coluna nova em `grupos` (tipo "é_ministério"); um
Grupo é um Ministério simplesmente quando existe ao menos uma linha em
`liderancas` confirmada pro ano corrente com aquele `grupo_id`.

**Rationale**: é exatamente a definição do glossário do domínio ("Ministério
é qualquer Grupo que tem Líder/Diretor") — modelar como flag seria
duplicar um dado derivável, indo contra a fonte de verdade.

**Alternatives considered**: `grupos.eh_ministerio boolean` mantido por
trigger sempre que `liderancas` muda (rejeitado — estado derivado
duplicado, mais uma coisa pra manter sincronizada sem necessidade).
