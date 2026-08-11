## Why

Consequência conhecida e aceita da feature 015: um cadastro de criança feito
**antes** dela não tem os dados do responsável, e a check constraint recusa
**qualquer** `update` naquela linha — inclusive de campo sem relação nenhuma,
como o telefone. A pessoa fica somente-leitura no próprio cadastro.

Ela não fica presa: a tela traduz a recusa numa frase pedindo que escreva para o
e-mail de contato, e a **exclusão de conta continua funcionando** (a anonimização
zera `idade` e as constraints passam), então o art. 18, VI da LGPD está a salvo.

Localmente são **0** cadastros nessa situação. **Em produção, desconhecido** — e
é a primeira coisa que esta change precisa descobrir, porque se o número for
zero, ela se fecha sem escrever uma linha de código.

`PENDENCIAS.md` § 2.3.

## What Changes

Primeiro, contar. Depois, aplicar a decisão do dono do app sobre o que fazer com
quem estiver nessa situação.

> ⚠️ **Decisão em aberto, do dono do app.** Esta change não pode ser
> implementada antes dela, e a spec abaixo cobre apenas o que vale nas duas
> saídas. As opções, com o que cada uma custa, estão em `design.md`.

## Capabilities

### Modified Capabilities
- `cadastro-de-crianca`: o que acontece com um cadastro de menor de 13 que
  antecede a exigência de autorização do responsável.

## Impact

- Depende da decisão. No mínimo, uma consulta em produção e o registro do
  resultado. No máximo, migration, tela para pedir a autorização a quem já está
  cadastrado, e texto novo — que a spec da 015 excluiu de propósito.
