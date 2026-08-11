## Context

O default do fornecedor concede esses três privilégios no schema `public`. Cada
tabela criada por migration os herda no momento em que nasce, então revogar
tabela a tabela conserta o presente e não o futuro.

## Goals / Non-Goals

**Goals:**
- Fechar as 14 tabelas abertas hoje.
- Fazer com que tabela nova nasça fechada, sem depender de memória.

**Non-Goals:**
- Revisar as policies existentes. Isso é outro assunto e já foi conferido
  (`PENDENCIAS.md` § 5: as nove policies `using (true)` correspondem ao que a
  Política de Privacidade declara público).

## Decisions

**Revogar em todas as tabelas E alterar o default para as futuras.** Só o
primeiro deixa a próxima migration reabrindo o buraco em silêncio; só o segundo
deixa as 14 atuais abertas. `alter default privileges` é o que fecha o futuro.

**A prova é a suíte inteira, não um teste do TRUNCATE.** Provar que a recusa
funciona é fácil e quase inútil — o risco real desta change não é a revogação
falhar, é ela quebrar um caminho legítimo que ninguém sabia que dependia
daqueles privilégios. Por isso o critério é a suíte de integração completa
passando com a contagem de antes.

## Risks / Trade-offs

**`REFERENCES` e `TRIGGER` entram junto porque vieram juntos no default**, mas
nenhum dos dois tem o efeito dramático do TRUNCATE. Se algum caminho legítimo
depender deles, aparece na suíte — e aí a decisão é revogar só `TRUNCATE`.

**Nada disso é urgente**, e descrever como urgente seria errado. É higiene de
menor privilégio numa porta que hoje ninguém alcança.
