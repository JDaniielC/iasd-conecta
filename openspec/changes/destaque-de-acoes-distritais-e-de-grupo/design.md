## Context

`ActionListPage` (`/acoes`) já busca todas as Ações numa query só
(`actionsWithChurchProvider` → `ActionRepository.fetchActions()`, sem filtro
de `grupo_id`) e já tem um precedente de destaque visual: Sábado adventista
ganha borda+fundo `colorScheme.tertiary` e ícone de lua, tanto no
`_SectionHeader` quanto no `_ActionCard`. A nova faixa de destaque é outra
dimensão (origem da Ação: avulsa vs. Grupo-que-participo), independente da de
Sábado (quando a Ação acontece) — as duas podem valer ao mesmo tempo pra uma
mesma Ação.

Não existe hoje um provider "Grupos que eu participo" — só
`membersProvider(groupId)`, por Grupo. E não existe um marcador de "última
vez que vi X" reutilizável — `NewsRepository.readLastSeenDate`/
`writeLastSeenDate` é o único precedente, específico da tela de Novidades.

Ver `proposal.md` para a motivação; ver `specs/destaque-de-acoes/spec.md`
para o comportamento exigido.

## Goals / Non-Goals

**Goals:**
- Faixa de destaque no topo de `/acoes`, sem tocar a lista por período que já
  existe.
- Reusar os padrões já estabelecidos no repositório (marcador de visto único
  como Novidades; consulta agregada única como `confirmationCountsProvider`)
  em vez de inventar mecanismo novo.

**Non-Goals:**
- Mudar a listagem por período, os filtros de Igreja, ou o destaque de
  Sábado que já existem.
- Notificação push ou qualquer aviso fora da tela `/acoes`.
- Sincronizar o dismiss (fechar item) entre aparelhos — é decisão explícita
  do dono do app que ele seja só de sessão.

## Decisions

**Provider agregado "meus Grupos" (`myGroupIdsProvider` ou equivalente),
uma consulta.** Em vez de checar `membersProvider(groupId)` por card
(N+1 — o próprio código já evita esse padrão explicitamente no comentário de
`fetchConfirmationCounts`), uma consulta só: `select grupo_id from
participacoes_grupo where usuario_id = auth.uid()`. Sem Perfil/Conta, a
consulta não roda (RLS: `auth.uid()` nulo) — resultado vazio, banner sem a
faixa de Grupo, só a de avulsa. Nenhuma migration: a tabela e a RLS já
existem.

**Marcador de "nova" único, no padrão de Novidades — não por Grupo.**
Um `ActionsRepository.readLastSeenDate`/`writeLastSeenDate` gêmeo do de
`NewsRepository`, atualizado quando `/acoes` é aberta. Considerado e
descartado: marcador por `grupo_id` (mais preciso — abrir por causa do
Clube de Aventureiros não consumiria a novidade do Coral), mas foi decisão
explícita do dono do app usar o marcador único, pela simplicidade de reusar
o mecanismo que já existe e já foi testado em produção pela feature de
Novidades.

**Dismiss em memória (Riverpod state, não repositório).** Um
`StateProvider<Set<String>>` (ids de Ação fechada) vivendo só no processo do
app — nunca grava em disco. Decisão do dono do app: reaparecer no próximo
cold start é o comportamento querido, não um efeito colateral a evitar.

**Dois canais visuais distintos para as duas dimensões de destaque.**
Sábado continua em `colorScheme.tertiary` (borda+fundo+ícone), sem mudar.
A faixa nova usa:
- Avulsa (distrital, incondicional): `colorScheme.primary` (navy) — a cor
  de marca, reservada pro que alcança todo o distrito.
- Grupo-que-participo-e-nova: um tom neutro, mais discreto — candidato
  `colorScheme.surfaceContainerHighest` ou `secondaryContainer` com borda
  fina, a decidir na implementação olhando o resultado ao lado do Sábado (as
  três cores não podem ficar parecidas na mesma tela). Não travo o token
  exato aqui — é decisão de acabamento, não de comportamento.

O card de uma Ação avulsa-e-Sábado, ou Grupo-nova-e-Sábado, precisa mostrar
os dois sinais sem se confundir: o desenho visual final (ex.: chip de origem
no topo do card + borda de Sábado already existente) fica pra tarefa de
implementação, com uma verificação manual olhando as quatro combinações
(avulsa/grupo-meu × sábado/não-sábado).

## Risks / Trade-offs

**Marcador único pode "consumir" novidade de Grupo que a pessoa nem reparou**
(a limitação que o marcador-por-Grupo evitaria). Aceito de propósito — ver
Decisions.

**Faixa de destaque pode crescer demais** se muitos Grupos-que-participo
tiverem Ação nova ao mesmo tempo (ex.: alguém em 8 Grupos ativos). Sem corte
de quantidade definido nesta change — se virar problema real, é ajuste de
acabamento (limitar a N itens, "ver mais"), não mudança de requisito.

**Dismiss por sessão pode parecer "quebrado"** pra quem espera que fechar
seja permanente (comportamento comum em outros apps). É decisão explícita
do dono do app — registrar a razão (reaparecer é intencional) ajuda quem
for dar suporte depois.
