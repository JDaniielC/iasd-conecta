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
- [ ] 5.4 Verificação manual: abrir com Perfil em vários Grupos, um Grupo,
      nenhum Grupo, e sem Perfil (Visitante) — confirmar que a faixa nunca
      quebra a tela quando vazia (sem Ação avulsa nem Ação de Grupo nova)
