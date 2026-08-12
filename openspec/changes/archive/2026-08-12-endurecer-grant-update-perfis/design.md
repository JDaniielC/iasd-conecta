## Context

`grant` e `policy` respondem perguntas diferentes, e este projeto já pagou por
confundi-las: uma policy sem `grant` produz `permission denied` (feature 013,
`fotos_capa`), e um `grant` largo com policy correta produz exatamente o buraco
descrito aqui. A policy filtra **qual linha**; o `grant` decide **qual coluna**.

## Goals / Non-Goals

**Goals:**
- Fechar a escrita de `idade` e `genero` pela própria titular.
- Provar, por teste de integração, que as colunas legítimas continuam graváveis.

**Non-Goals:**
- Mudar qualquer tela.
- Decidir como uma correção legítima de `idade` seria feita depois. Hoje ninguém
  a faz pelo app; se essa necessidade aparecer, é outra change.

## Decisions

**`revoke update` seguido de `grant update (colunas)`, e não uma policy com
`with check`.** Uma policy conseguiria comparar `old` e `new` e recusar quando a
coluna mudasse, mas isso é regra escrita em dois lugares — e o `grant` já é o
mecanismo que o Postgres oferece para exatamente esta pergunta. Menos código,
mesma garantia, e a recusa vem antes da policy rodar.

**A lista de colunas é explícita e nomeada na migration**, não derivada. Coluna
nova em `perfis` nasce **sem** permissão de escrita, e alguém precisa decidir
conscientemente incluí-la. É o padrão que falha para o lado seguro.

## Risks / Trade-offs

**Uma tela pode depender de escrever uma coluna que ficou de fora e ninguém
lembrou.** O sintoma seria `permission denied` na cara da pessoa. Por isso a
verificação não é só "a recusa funciona": é rodar o fluxo de edição de Perfil
inteiro contra o banco com a migration aplicada, antes de produção.

**Coluna nova esquecida.** O padrão seguro tem custo: quem acrescentar coluna
gravável a `perfis` precisa lembrar do `grant`. Fica registrado no comentário da
migration, junto da tabela.
