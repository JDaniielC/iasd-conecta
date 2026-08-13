## 1. Dados

- [x] 1.1 Provider agregado "Grupos que eu participo" (`myGroupIdsProvider`
      ou equivalente): uma consulta em `participacoes_grupo` filtrada por
      `auth.uid()`, não uma por card
- [x] 1.2 `ActionsRepository` (ou o repositório existente de Ações) ganha
      `readLastSeenActionsDate`/`writeLastSeenActionsDate`, no padrão de
      `NewsRepository` — os três comportamentos do comentário de
      `hasUnseenNewsProvider` (lista vazia não grava, sem marcador grava a
      data mais recente na hora sem avisar, com marcador avisa só se houver
      item mais novo) se aplicam aqui também

## 2. Regra de quais Ações entram no destaque

- [x] 2.1 Função/provider que classifica cada `ActionWithChurch` em: destaque
      forte (avulsa), destaque neutro (Grupo que participo e criada depois do
      marcador), ou nenhum destaque — cobre as quatro combinações com Sábado
      (avulsa×sábado, avulsa×não, grupo-novo×sábado, grupo-novo×não)
- [x] 2.2 Atualizar o marcador de "última vez que vi `/acoes`" ao abrir a
      tela — mesmo ponto do ciclo de vida que `hasUnseenNewsProvider` usa
      para Novidades, não ao fechar

## 3. Faixa de destaque (UI)

- [x] 3.1 Faixa nova no topo de `ActionListPage`, acima do `ListView` por
      período, com os itens classificados como destaque em 2.1
- [x] 3.2 Variante de cor forte (avulsa) e neutra (Grupo-meu-novo) no card do
      destaque — reusar `_ActionCard` com um parâmetro de variante, ou um
      card dedicado da faixa; decidir olhando lado a lado com o destaque de
      Sábado existente (as três cores não podem se confundir na mesma tela)
- [x] 3.3 Botão de fechar (dismiss) em cada item da faixa

## 4. Dismiss por sessão

- [x] 4.1 `StateProvider<Set<String>>` (ids fechados), só em memória — sem
      gravar em disco nem enviar ao banco
- [x] 4.2 Item fechado sai da faixa nesta sessão; confirmar que reaparece
      depois de reiniciar o app (comportamento querido, não bug)

## 5. Prova

- [x] 5.1 Teste de widget: Ação avulsa sempre em destaque forte, com e sem
      Sábado
- [x] 5.2 Teste de widget: Ação de Grupo-que-participo aparece em destaque
      neutro só antes do marcador avançar; Ação de Grupo-que-não-participo
      nunca aparece em destaque
- [x] 5.3 Teste de widget: fechar um item o remove da faixa nesta sessão,
      sem afetar os demais
- [x] 5.4 Verificação manual: abrir com Perfil em vários Grupos, um Grupo,
      nenhum Grupo, e sem Perfil (Visitante) — confirmar que a faixa nunca
      quebra a tela quando vazia (sem Ação avulsa nem Ação de Grupo nova)

## Convergence 1

- [x] Decidir e escrever no spec **o que conta como "abrir `/acoes`"** para o
      marcador — a pergunta que nunca foi respondida e da qual as cinco tarefas
      seguintes dependem. Hoje o spec só diz "a última vez que o Usuário abriu
      `/acoes`" e o código responde "quando a tela é construída", sem olhar se
      alguma coisa chegou a ser mostrada. Opções a decidir: (a) avançar só
      quando a lista carregou COM sucesso; (b) avançar só quando a lista e a
      consulta de Grupos carregaram; (c) avançar só sobre as Ações que a pessoa
      teve chance de ver. Implementar antes de decidir produz cinco correções
      que se contradizem — per Requirement "Marcador de 'nova' é único e por
      instalação", (contradicts)
- [x] Não consumir a novidade quando a lista de Ações falhou ao carregar.
      Medido: com `actionsWithChurchProvider` lançando, a tela mostra "Não deu
      pra carregar as Ações agora." e o marcador avança do mesmo jeito —
      `writeCount=1`, de `2026-08-10` para `2026-08-12 12:00`. Uma falha de rede
      de um segundo apaga em silêncio a novidade de TODOS os Grupos, para
      sempre. `lastSeenActionsProvider`
      (`lib/features/action/action_providers.dart`) não conhece o estado da
      lista — per Scenario "Ação de Grupo deixa de ser nova", que condiciona o
      consumo à Ação já ter aparecido em destaque, (contradicts)
- [x] Distinguir "não participo de nenhum Grupo" de "não consegui descobrir de
      quais Grupos participo". Medido: com `myGroupIdsProvider` lançando, o
      destaque de Grupo fica em 0, a tela não avisa nada (aviso na tela = 0) e o
      marcador avança (`writeCount=1`) — a novidade é consumida sem nunca ter
      sido mostrada. Causa: `.value ?? const <String>{}` em
      `lib/features/action/presentation/action_list_page.dart` lê erro como
      conjunto vazio — per Requirement "Ação de Grupo entra no destaque só para
      quem participa e só enquanto nova", (contradicts)
- [x] Resolver o conflito entre o filtro de Igreja da tela e o "qualquer Igreja"
      do requisito. Medido com três Ações (avulsa da Central, avulsa da Boa
      Vista, e Ação nova de um Grupo meu sediado na Boa Vista): sem filtro
      `forte=2 neutro=1`; filtrando "Central" `forte=1 neutro=0` — a novidade do
      meu próprio Grupo some, e o marcador avança assim mesmo, então ela não
      volta. O requisito diz "qualquer Igreja — participação não filtra por
      Igreja" e a proposal repete "sem filtro por Igreja"; a faixa é montada a
      partir da lista já filtrada. Decidir qual das duas frases vale e escrever
      no spec — per Requirement "Ação de Grupo entra no destaque só para quem
      participa e só enquanto nova", (contradicts)
- [x] Separar a falha de ler o marcador da falha de gravá-lo. Medido: com a
      gravação lançando, o destaque de Grupo vai a 0 e nenhuma exceção aparece
      na tela, embora o marcador esteja preservado (`2026-08-10`) e a leitura
      tenha funcionado — ler e gravar vivem no mesmo `Future` em
      `lastSeenActionsProvider`, então a falha da gravação descarta a leitura
      boa. Efeito: enquanto o armazenamento do aparelho estiver com problema, o
      destaque de Grupo nunca funciona, calado — per Requirement "Marcador de
      'nova' é único e por instalação", (partial)
- [x] Cobrir a falha de leitura do marcador com o mesmo tratamento. Medido: com
      a leitura lançando, destaque de Grupo = 0, `writeCount=0`, nenhuma exceção
      visível na tela — per Requirement "Marcador de 'nova' é único e por
      instalação", (partial)
- [x] Fixar em teste o cenário "Item fechado reaparece na próxima abertura do
      app". Medido agora e funciona (`1 → 0 → 1`, recriando o `ProviderScope`,
      que é o equivalente a reiniciar o app), mas nenhum teste do repositório
      cobre, e a task 4.2 pedia justamente confirmar isso — per Scenario "Item
      fechado reaparece na próxima abertura do app", (missing)

## Convergence 2

- [x] Provar em teste de integração, como `authenticated`, que
      `GroupRepository.fetchMyGroupIds` devolve só os Grupos de quem chamou.
      Medido em 2026-08-13 contra o banco local, no papel real do app: um
      `select grupo_id,usuario_id from participacoes_grupo` SEM o filtro
      devolve 2 linhas, de 2 usuários diferentes — a RLS dessa tabela não
      restringe às próprias linhas (é ela que permite `fetchMemberIds` listar
      os membros de um Grupo alheio). O `.eq('usuario_id', uid)` no cliente é
      a única linha de defesa da regra. E nada o exercita: os dois testes que
      envolvem Grupos em `test/widget/destaque_acoes_test.dart` sobrepõem
      `myGroupIdsProvider`, então tirar aquele `.eq` numa refatoração faria a
      tarja "Novo no seu Grupo" aparecer para Ação de Grupo alheio com os 309
      testes verdes — per Requirement "Ação de Grupo entra no destaque só para
      quem participa e só enquanto nova", (missing)
- [x] Cobrir `ActionsSeenRepository` com teste — hoje ele não tem nenhum.
      Medido em 2026-08-13 e correto: grava na chave `acoes_ultima_vista`, um
      instante local de 12:00 vira `2026-08-12T15:00:00.000Z`, volta como
      `DateTime` UTC do mesmo instante, e a comparação que a regra faz acerta
      nos dois sentidos (Ação criada 1 min depois é nova, 1 min antes não é).
      Nada disso está preso: trocar a chave, tirar o `.toUtc()` ou mudar o
      formato não quebra nenhum dos 309 testes, e o sintoma seria toda Ação de
      Grupo deixando de ser nova de uma vez (ou nunca deixando) — per
      Requirement "Marcador de 'nova' é único e por instalação", (missing)
- [x] Decidir se o comportamento "falha ao gravar o marcador não derruba o
      destaque já lido" entra na spec. Está implementado (leitura e gravação
      são dois providers desde a Convergence 1) e tem teste, mas nenhum
      requisito o pede — quem ler a spec não sabe que é obrigatório, e uma
      refatoração que volte a juntar os dois passaria pela spec sem conflito.
      Levantado para consciência, não é defeito — (unrequested)

## Convergence 3

- [x] Invalidar `myGroupIdsProvider` ao Participar e ao Sair de um Grupo.
      Medido em 2026-08-13: participando de um Grupo e voltando para `/acoes`
      na mesma sessão do app, a faixa segue sem a novidade — `neutro=0` e a
      consulta de Grupos não foi refeita (`consultas=1`, o mesmo de antes de
      participar). Só reiniciando o app: `neutro=1`, `consultas=2`. Causa:
      `myGroupIdsProvider` (`lib/features/group/group_providers.dart`) não é
      `autoDispose`, então cacheia pela vida do app, e `_join`
      (`lib/features/group/presentation/group_detail_page.dart:28`) invalida
      só `membersProvider(groupId)`; `_leave` tem o espelho do problema, e
      continuaria mostrando novidade de Grupo do qual a pessoa saiu.
      O dano não é só o atraso: o marcador avança nessa visita, porque a lista
      e os Grupos "carregaram com sucesso" — só que respondendo a pergunta de
      antes. Medido no encadeamento completo (abro /acoes sem participar,
      participo, volto, reinicio): marcador `12:00` -> `12:10` e, mesmo depois
      do reinício, `neutro=0`. A novidade do Grupo em que a pessoa acabou de
      entrar é consumida sem nunca ter sido mostrada, e não volta.
      É a mesma classe da Convergence 1 por outra porta — lá era erro, aqui é
      dado velho — e a decisão registrada na spec continua valendo: a correção
      é invalidar o cache, não mexer na regra — per Requirement "Ação de Grupo
      entra no destaque só para quem participa e só enquanto nova", (partial)

## Convergence 4

- [x] ~~Corrigir a frase de `design.md:42-44`~~ — **avaliada e dispensada pelo
      dono do app em 2026-08-13.** O risco descrito abaixo foi superestimado:
      `design.md` vira registro histórico ao ser arquivado, `proposal.md` não
      afirma nada sobre RLS, e o main spec — o documento vivo — nunca conteve a
      afirmação. A verdade já está nos dois lugares que alguém lê ao mexer no
      código: o comentário em `lib/features/group/data/group_repository.dart:158`
      ("a RLS de `participacoes_grupo` NÃO restringe o select às próprias
      linhas"), encostado na linha que ele protege, e o teste de integração da
      Convergence 2, que fica vermelho se o filtro sumir. Reclassificada de
      MEDIUM para LOW. O texto original do achado segue abaixo, para quem fizer
      arqueologia:
- [x] Corrigir a frase de `design.md:42-44` que atribui à RLS uma proteção que
      ela não tem. O texto diz "Sem Perfil/Conta, a consulta não roda (RLS:
      `auth.uid()` nulo) — resultado vazio". Medido em 2026-08-13: como `anon`,
      `GET /rest/v1/participacoes_grupo?select=grupo_id,usuario_id` devolve
      HTTP 200 com as linhas de TODOS os usuários. A RLS dessa tabela é aberta
      de propósito — é ela que permite `fetchMemberIds` listar os membros de um
      Grupo alheio. Quem garante o resultado vazio sem Conta é o
      `if (uid == null) return const <String>{}` de
      `GroupRepository.fetchMyGroupIds`, e a Convergence 2 já mediu que o
      filtro no cliente é a única defesa também no caso `authenticated`.
      O código está certo e testado; o perigo é o documento: quem ler o design
      e acreditar que a RLS protege pode tirar o guard do cliente numa
      refatoração, achando que há uma segunda linha de defesa que não existe —
      per Requirement "Ação de Grupo entra no destaque só para quem participa e
      só enquanto nova", (contradicts)
