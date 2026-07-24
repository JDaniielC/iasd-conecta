# Research: Rodada de Votação

## Ação candidata reusa a tabela `acoes`, não uma tabela nova

**Decision**: `acoes` ganha três colunas: `grupo_id` (nullable — nulo pra
Ação avulsa), `rodada_id` (nullable — preenchido enquanto é candidata),
`confirmada` (boolean, default `true`). Uma Ação candidata é uma linha de
`acoes` com `confirmada = false` e `rodada_id` apontando pra Rodada. Ao
vencer, vira `confirmada = true` — nesse ponto é indistinguível de uma Ação
de Grupo "normal", reusando 100% do `AcaoRepository`,
`confirmacoes_acao`, `DetalheAcaoPage`, etc. da feature 003.

**Rationale**: Princípio V (simplicidade) — evita duplicar toda a máquina
de confirmação de presença (fila de espera, idempotência) que já existe e
já foi testada pra Ação avulsa. "Ação candidata" e "Ação de Grupo
confirmada" são o MESMO dado num estado diferente, não duas entidades.

**Alternatives considered**: tabela `acoes_candidatas` separada com sua
própria FK de confirmação (rejeitado — duplicaria fila de espera,
idempotência e toda a UI de detalhe já construídas).

## Fechamento preguiçoso: função chamada no início de toda operação relevante

**Decision**: `fechar_rodada_se_devido(p_rodada_id uuid, p_forcar boolean
default false)` é uma função `SECURITY DEFINER` chamada explicitamente pelo
repositório Dart antes de: buscar detalhes de uma Rodada, votar, propor
candidata. Se `fechada_em` já está preenchido, não faz nada. Se não está e
(`p_forcar` ou `now() >= prazo`), executa a apuração.

**Rationale**: decisão de clarify — evita depender de `pg_cron` ou
qualquer job em segundo plano só pra fechar Rodadas vencidas. O trade-off
(uma Rodada vencida só "fecha de verdade" quando alguém interage) já está
documentado como Assumption aceita.

**Alternatives considered**: `pg_cron` rodando a cada minuto (rejeitado —
infraestrutura extra pra um app desse porte, Princípio V); fechar só na
tela de detalhe da Rodada, sem cobrir a tentativa de votar/propor
diretamente (rejeitado — deixaria brecha pra votar/propor numa Rodada já
vencida se o client não tivesse acabado de abrir a tela).

## `SECURITY DEFINER` pra apuração: mexe em Ações e votos de outras pessoas

**Decision**: `fechar_rodada_se_devido()` é `SECURITY DEFINER`. Ela: conta
votos por candidata, escolhe a vencedora (`ORDER BY random() LIMIT 1`
entre as com mais votos — cobre empate automaticamente, inclusive o caso
de zero votos totais, ver abaixo), faz `UPDATE acoes SET confirmada = true`
na vencedora, e `DELETE FROM acoes WHERE rodada_id = ... AND id <>
vencedora` nas perdedoras (cascade limpa `confirmacoes_acao` e `votos`
delas). Nenhuma dessas escritas pertence à sessão de quem disparou o
fechamento.

**Rationale**: mesmo raciocínio de `perfil_publico()` (001) e
`promover_fila_acao()` (003) — efeito colateral do sistema que precisa
tocar dado de terceiros não deve depender de um `GRANT` amplo pra
qualquer `authenticated`.

**Alternatives considered**: exigir que só o Dono do Grupo possa disparar o
fechamento (rejeitado — o fechamento por prazo vencido precisa acontecer
pra QUALQUER pessoa que interaja com a Rodada, não só o Dono; só o
fechamento *forçado antes do prazo* é exclusivo do Dono, e isso é validado
dentro da própria função via parâmetro `p_forcar` + checagem de
`auth.uid() = grupos.dono_id`).

## Empate (incluindo empate com zero votos) resolvido pela mesma query

**Decision**: a apuração agrupa candidatas por contagem de voto (`LEFT
JOIN votos`, então candidatas sem nenhum voto contam 0), pega o máximo, e
sorteia (`ORDER BY random() LIMIT 1`) entre as que batem esse máximo. Se
ninguém votou em nada, todas as candidatas empatam em 0 e o sorteio vale
pra todas igualmente — sem caso especial.

**Rationale**: FR-012 exige sorteio só entre empatadas; usar `LEFT JOIN` +
`GROUP BY` + `MAX` já cobre o caso de zero-votos-totais como só mais um
empate, sem `IF` especial pra esse cenário — mais simples e menos
propenso a bug de borda.

**Alternatives considered**: tratar "zero votos totais" como "sem
vencedora" (rejeitado — a spec não distingue esse caso de um empate
comum; se há candidatas, alguma delas deve virar Ação confirmada, mesmo
que ninguém tenha votado).

## Voto: `UPSERT`, não `INSERT` + `DELETE`

**Decision**: `votos` tem PK `(rodada_id, usuario_id)`. Trocar de escolha é
`INSERT ... ON CONFLICT (rodada_id, usuario_id) DO UPDATE SET candidata_id
= excluded.candidata_id, updated_at = now()`.

**Rationale**: FR-006 ("só a última conta") fica estruturalmente garantido
— só existe UMA linha por Usuário por Rodada, então não tem como duas
escolhas coexistirem nem precisar "invalidar" a antiga manualmente.

**Alternatives considered**: manter histórico de todos os votos e apurar só
o mais recente por `MAX(created_at)` (rejeitado — mais complexo pra
apurar, e a spec não pede histórico de mudança de voto).

## Só participante do Grupo abre/propõe/vota: trigger, não só RLS

**Decision**: além do `GRANT`, um trigger `BEFORE INSERT` em
`rodadas_votacao`, `acoes` (quando `rodada_id` não é nulo) e `votos` checa
`EXISTS (SELECT 1 FROM participacoes_grupo WHERE grupo_id = ... AND
usuario_id = auth.uid())` e recusa com `RAISE EXCEPTION` se não participa.

**Rationale**: RLS sozinha (`WITH CHECK (auth.uid() = aberta_por)`, etc.)
garante "é você mesmo fazendo a ação em seu nome", mas não garante
"você participa deste Grupo específico" — isso é uma regra de negócio
que cruza tabelas (`participacoes_grupo`), mais natural como trigger,
igual o padrão já usado nas invariantes de posse de Grupo (002).

**Alternatives considered**: policy RLS com sub-`EXISTS` direto na cláusula
`WITH CHECK` (viável, mas gera uma policy bem mais difícil de ler que o
trigger equivalente — optei por manter o padrão já estabelecido no
projeto de "regra de negócio cross-table vira trigger", Princípio I
consistência de convenção).
