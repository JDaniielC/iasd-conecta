# Research: Dupla Missionária

## 2 vagas fixas + gênero do visitado: `CHECK constraint` declarativo, sem trigger

**Decision**: `acoes` ganha `eh_dupla_missionaria boolean not null default
false` e `genero_visitado text` (mesmos valores de `perfis.genero`), com um
único `CHECK` cobrindo FR-002/FR-003:

```sql
check (
  (eh_dupla_missionaria = false and genero_visitado is null)
  or
  (eh_dupla_missionaria = true and genero_visitado is not null
   and limite_vagas is not null and limite_vagas = 2)
)
```

**Rationale**: as duas regras ("exige gênero do visitado" e "limite fixo em
2") são validáveis inteiramente na própria linha, sem depender de nenhuma
outra tabela — um `CHECK` é mais simples que um trigger `BEFORE
INSERT`/`UPDATE` pra fazer a mesma coisa (Princípio V).

**Gotcha real encontrado na validação empírica**: um `CHECK` cujo termo usa
`limite_vagas = 2` sozinho passa silenciosamente quando `limite_vagas` é
`NULL` — em SQL, comparação com `NULL` resulta em `NULL`, e o Postgres só
rejeita um `CHECK` quando o resultado é `FALSE` (nunca quando é `NULL`).
Por isso o termo precisa do `limite_vagas is not null` explícito antes da
comparação — sem ele, uma Dupla Missionária sem limite de vagas passaria
despercebida.

**Alternatives considered**: trigger dedicado pra Dupla Missionária
(rejeitado — o Postgres já garante a mesma coisa com um `CHECK`, sem
função nem `SECURITY DEFINER` extra).

## Validação de composição de gênero: estende `confirmacoes_acao_decidir_status`, não um trigger novo

**Decision**: a função `confirmacoes_acao_decidir_status()` (feature 003,
já `BEFORE INSERT` em `confirmacoes_acao`) ganha um bloco extra: depois de
decidir se a nova confirmação seria `'confirmado'` ou `'fila'` pela regra
de capacidade já existente, se a Ação é Dupla Missionária e o resultado
seria `'confirmado'`, verifica o gênero de quem já está confirmado (0 ou 1
pessoa, nunca mais, por causa do limite fixo de 2). Se já existe 1
confirmado do mesmo gênero da nova tentativa, e esse gênero é diferente do
`genero_visitado`, a função levanta exceção — a confirmação é recusada, não
vira `'fila'` (ver Edge Cases da spec: só capacidade vira fila, gênero
inválido é recusa direta).

**Rationale**: reusa 100% a mesma trava de concorrência (`for update` na
linha de `acoes`) e o mesmo ponto único de decisão já usado pra
capacidade — Dupla Missionária não precisa de um caminho de código
paralelo, só de mais uma condição dentro do mesmo `if`.

**Alternatives considered**: trigger separado, específico de Dupla
Missionária, rodando depois do trigger de capacidade (rejeitado — dois
triggers `BEFORE INSERT` na mesma tabela têm ordem não garantida de forma
explícita sem nomear convenção adicional; um único bloco na função já
existente é mais previsível e mais simples).

## Promoção da fila: estende `promover_fila_acao` pra pular composição inválida

**Decision**: `promover_fila_acao()` (feature 003, `SECURITY DEFINER`,
`AFTER DELETE` em `confirmacoes_acao`) ganha um branch: se a Ação é Dupla
Missionária, em vez de promover cegamente o primeiro da fila, percorre a
fila em ordem de chegada (`order by created_at`) e promove o primeiro cujo
gênero formaria uma composição válida com quem ainda está confirmado
(0 ou 1 pessoa restante); se ninguém servir, a vaga fica aberta.

**Rationale**: é exatamente a Assumption que o usuário confirmou na spec —
"percorre a fila até achar válido, sem reordenar por outro critério". Um
loop simples (`for ... in select ... loop`) resolve sem estruturas novas.

**Alternatives considered**: promover sempre o primeiro da fila e deixar a
composição inválida acontecer, exigindo que alguém cancele manualmente
depois (rejeitado — violaria FR-005/FR-006 tão claramente quanto aceitar a
confirmação direta inválida, só que via caminho indireto).

## Gênero de quem confirma: lido do banco, nunca do client

**Decision**: tanto `confirmacoes_acao_decidir_status()` quanto
`promover_fila_acao()` leem `perfis.genero` diretamente via `join`, dentro
da própria função — nunca recebem o gênero como parâmetro do client.

**Rationale**: mesmo princípio já usado em `district_admin` (feature 005):
regra de negócio verificada no banco, não confiada ao client, que poderia
mentir. `perfis` já tem RLS restringindo `select` direto a linhas próprias,
mas a função roda como dona da tabela (contorna RLS), igual
`promover_fila_acao` já fazia antes desta feature.

**Alternatives considered**: nenhuma — é o mesmo padrão já estabelecido,
sem alternativa a avaliar.
