# Data Model: Dupla Missionária

Não há entidade nova — `public.acoes` e `public.confirmacoes_acao`
(features 003/004) ganham colunas e comportamento novo.

## `public.acoes` (colunas novas)

| Coluna | Tipo | Regra |
|---|---|---|
| `eh_dupla_missionaria` | `boolean` | `NOT NULL default false` |
| `genero_visitado` | `text` | nullable; mesmos valores de `perfis.genero` (`'masculino'`/`'feminino'`) |

**CHECK novo** (substitui a ausência de regra anterior):
```
(eh_dupla_missionaria = false and genero_visitado is null)
or
(eh_dupla_missionaria = true and genero_visitado is not null
 and limite_vagas is not null and limite_vagas = 2)
```
FR-001/FR-002/FR-003: marca o tipo, exige gênero do visitado quando
marcada, e fixa `limite_vagas` em exatamente 2 — tudo na própria linha, sem
depender de outra tabela.

## `public.confirmacoes_acao` (comportamento estendido, sem coluna nova)

Nenhuma coluna nova — o gênero de quem confirma já existe em
`perfis.genero`, lido via `join` nas funções abaixo.

**Estado derivado**: composição atual de uma Dupla Missionária é sempre 0,
1 ou 2 pessoas com `status = 'confirmado'` (nunca mais, por causa do
`CHECK` de `limite_vagas = 2` combinado com a regra de capacidade já
existente) — nunca uma coluna própria, sempre uma consulta em
`confirmacoes_acao` filtrando `status = 'confirmado'`.

## Funções estendidas (sem função nova)

- `confirmacoes_acao_decidir_status()` (feature 003, `BEFORE INSERT` em
  `confirmacoes_acao`): depois de decidir `'confirmado'`/`'fila'` pela
  capacidade já existente, se a Ação é Dupla Missionária e o resultado
  seria `'confirmado'`, valida a composição de gênero com quem já está
  confirmado (FR-004/FR-005/FR-006/FR-007); inválida levanta exceção — não
  vira `'fila'` silenciosamente.
- `promover_fila_acao()` (feature 003, `SECURITY DEFINER`, `AFTER DELETE`
  em `confirmacoes_acao`): se a Ação é Dupla Missionária, percorre a fila
  em ordem de chegada e promove o primeiro que formaria composição válida
  com quem ainda está confirmado, pulando os inválidos (FR-009); Ação
  comum mantém o comportamento inalterado (promove sempre o primeiro).

## Regras de composição (referência)

| Confirmado existente | Visitado | Nova confirmação | Resultado |
|---|---|---|---|
| ninguém | qualquer | qualquer gênero | aceita (FR-007) |
| homem | homem | homem | aceita (2H visitando homem) |
| homem | homem | mulher | aceita (1H+1M) |
| homem | mulher | homem | **recusada** (2H visitando mulher) |
| homem | mulher | mulher | aceita (1H+1M) |
| mulher | mulher | mulher | aceita (2M visitando mulher) |
| mulher | mulher | homem | aceita (1H+1M) |
| mulher | homem | mulher | **recusada** (2M visitando homem) |
| mulher | homem | homem | aceita (1H+1M) |
