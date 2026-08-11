## Why

`/acoes` lista toda Ação (avulsa e de Grupo confirmada) misturada, agrupada só
por período (Sábado/Hoje/Semana/Outras). Uma Ação aberta a todo o distrito e
uma Ação de um Grupo de nicho pesam igual na tela — quem abre o app não bate o
olho primeiro no que alcança mais gente, nem no que é novo no Grupo/Ministério
de que participa.

## What Changes

Uma faixa de destaque (banner) no topo de `/acoes`, acima da lista por
período, com:
- Toda Ação avulsa — sempre, cor forte. É "distrital" para qualquer pessoa,
  incondicional.
- Ação de Grupo que o Usuário participa (qualquer Igreja, sem filtro por
  Igreja) — só enquanto for **nova**, cor mais neutra. "Nova" é um marcador de
  visto único e persistido por instalação (mesmo mecanismo de
  `hasUnseenNewsProvider`/Novidades): criada depois da última vez que a pessoa
  abriu `/acoes`.
- Ação de Grupo que o Usuário não participa **não** entra no banner — continua
  só na lista por período, como hoje.

Cada item do banner pode ser fechado (dismiss) individualmente. O fechamento é
só de sessão — em memória, não persiste: reaparece no próximo abrir do app se
ainda contar como novo pelo marcador.

## Capabilities

### New Capabilities
- `destaque-de-acoes`: quando uma Ação entra na faixa de destaque de `/acoes`,
  em qual cor, e quando some de lá.

## Impact

- `lib/features/action/presentation/action_list_page.dart` — nova faixa de
  banner acima da lista por período; card com variante de cor neutra.
- `lib/features/action/action_providers.dart` — provider agregado de "Grupos
  que eu participo" (evitar N+1 por card, mesmo padrão já usado para
  `confirmationCountsProvider`/capas); marcador de "última vez que vi
  `/acoes`", no padrão de `lib/features/news/data/news_repository.dart`
  (`readLastSeenDate`/`writeLastSeenDate`).
- Estado de dismiss por sessão: provider em memória (`StateProvider` ou
  equivalente), sem persistência em disco nem no banco.
- Nenhuma mudança de schema esperada: `participacoes_grupo` já existe e já
  serve pra derivar "meus Grupos".
