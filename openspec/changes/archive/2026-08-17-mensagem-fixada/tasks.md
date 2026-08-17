## 1. Banco — colunas e gatilho

- [x] 1.1 **Reler o gatilho `before update` de `mensagens` que
      `chat-de-grupo-e-acao` deixou**, antes de escrever qualquer coisa. Esta
      change o edita; se ele mudou, a edição planejada não casa
- [x] 1.2 `alter table public.mensagens add column fixada_em timestamptz, add
      column fixada_por uuid references public.perfis(id)`
- [x] 1.3 Acrescentar `fixada_em` e `fixada_por` à lista de colunas que aquele
      gatilho permite alterar — e **nada mais** na lista
- [x] 1.4 Constante nomeada do teto (3) na migration, com comentário de que é
      escolha e não medição
- [x] 1.5 `comment on column` nas duas, dizendo que fixada não expira e que
      desfixar devolve a mensagem ao prazo

## 2. Banco — regras de fixar e desfixar

- [x] 2.1 No gatilho: transição nulo → não nulo exige autoridade do espaço
      (dono do Grupo, criador da Ação, dono do Grupo da Ação, Administrador do
      distrito). Reusar o mesmo predicado da remoção, não reescrever
- [x] 2.2 Transição não nulo → nulo aceita autoridade do espaço **ou** autor da
      mensagem
- [x] 2.3 Teto: na transição nulo → não nulo, `for update` na linha do Grupo ou
      da Ação **primeiro**, depois contar as fixadas do chat e recusar acima de
      3
- [x] 2.4 Fixar mensagem já fixada não altera `fixada_por` nem `fixada_em`
- [x] 2.5 Quando `texto` passa a nulo no mesmo `update`, zerar `fixada_em` e
      `fixada_por` na mesma linha — sem segundo gatilho, sem recursão

## 3. Banco — expurgo e exclusão de conta

- [x] 3.1 `expurgar_mensagens_de_acao()` ganha `and fixada_em is null`. Nada
      mais muda naquela função
- [x] 3.2 Confirmar que `excluir_conta` **não** precisa de linha nova: o
      `update ... set texto = null` existente já dispara o desfixe de 2.5.
      Provar por teste, não por leitura

## 4. Prova no banco (test/integration)

- [x] 4.1 Autoridade: dono do Grupo fixa; criador da Ação avulsa fixa;
      Administrador fixa; participante comum é recusado; participante comum
      fixando a própria mensagem é recusado; dono de outro Grupo é recusado.
      Seis casos
- [x] 4.2 Autor desfixa mensagem que outra pessoa fixou; autor sem autoridade
      tentando fixar de volta é recusado
- [x] 4.3 Teto: 3 fixadas passam, a 4ª é recusada; desfixar libera e a 4ª passa
- [x] 4.4 Concorrência: duas fixações simultâneas com uma vaga resultam em
      exatamente 1 fixada. Sem este teste a trava não está provada
- [x] 4.5 Expurgo: Ação de 31 dias com 1 fixada mantém a fixada e apaga o
      resto, com contagem antes e depois
- [x] 4.6 Desfixar depois do prazo: expurgo seguinte apaga, sem carência nova
- [x] 4.7 Remoção por moderação de mensagem fixada a desfixa e libera a vaga
- [x] 4.8 `excluir_conta` sobre autor de mensagem fixada: `texto` nulo e
      `fixada_em` nulo, na mesma transação
- [x] 4.9 Mensagem de Grupo fixada nunca é apagada por expurgo — Grupo não
      expira, mas confirmar que a condição nova não introduziu caminho
- [x] 4.10 Não participante e menor de 18 consultando as fixadas recebem 0
      linhas. A fixação não pode ter aberto porta que a leitura não abria
- [x] 4.11 `update` tentando alterar coluna fora da lista permitida continua
      recusado — o teste de `chat-de-grupo-e-acao` estendido com as duas novas

## 5. Dart — dados

- [x] 5.1 Modelo ganha `fixadaEm`/`fixadaPor`; teto como constante num lugar só
- [x] 5.2 Teste de integração comparando o teto do Dart com o da migration
- [x] 5.3 Repositório: fixar, desfixar, e carregar as fixadas do chat —
      incluindo fixada antiga, fora da primeira página do histórico
- [x] 5.4 Decidir entre `union` na consulta de histórico e segunda consulta
      cacheada **medindo** as duas, não escolhendo antes (ver design)

## 6. Dart — tela

- [x] 6.1 Faixa de fixadas acima da conversa, **recolhida por padrão**,
      expandindo sob toque
- [x] 6.2 Sem fixada, nenhuma faixa ocupa espaço
- [x] 6.3 Ação de fixar/desfixar visível só a quem pode executá-la; desfixar
      aparece também para o autor
- [x] 6.4 Teto atingido: dizer que é preciso desfixar alguma, não devolver erro
      cru

## 7. Prova no cliente (test/widget, test/unit)

- [x] 7.1 Widget: 3 fixadas de 2000 caracteres cada, **na largura de celular** —
      a conversa continua visível e rolável sem interação extra. Julgar em
      celular, nunca no desktop
- [x] 7.2 Widget: chat sem fixada não mostra faixa
- [x] 7.3 Widget: participante comum não vê ação de fixar; autor vê desfixar na
      própria mensagem fixada
- [x] 7.4 Widget: lápide nunca aparece na faixa

## 8. Legal e ledgers — bloqueia o fechamento

- [x] 8.1 Política de Privacidade (`lib/features/legal/`): o prazo de 30 dias
      passa a ter exceção declarada, com o teto. Manter "30 dias" sem ressalva
      torna a política falsa. Rodar o agente `advogado-digital`
- [x] 8.2 `REVISAO-JURIDICA.md`: a exceção ao prazo, o teto, e o limite
      conhecido — quem é citado por outro não tem caminho para desfixar
- [x] 8.3 `MAPA-DE-DADOS.md`: as duas colunas novas com `arquivo:linha`
- [x] 8.4 Rodar o agente `promessa-vs-execucao` cruzando o prazo e a exceção
      declarados na Política contra o `where` real do expurgo
- [x] 8.5 `PENDENCIAS.md`: o que ficar aberto

## 9. Fechamento

- [x] 9.1 Gates com números reais: `flutter analyze` (0 issues), `flutter test
      test/unit test/widget` (contagem), `dart test test/integration` com
      `supabase start` (contagem), `flutter build web --release`
- [x] 9.2 Commit registra que o rollback **não** é sem perda: reverter apaga
      mensagem fixada de Ação já vencida no expurgo seguinte
- [x] 9.3 Rodar a skill `openspec-converge` e resolver o que ela achar

## Convergence 1

- [x] C1 **Fixar lápide devolve sucesso sobre nada.** Medido em 2026-08-17:
      como Dono, `update mensagens set fixada_em = now(), fixada_por = <eu>`
      sobre mensagem já removida devolveu **`UPDATE 1`**, e o estado final é
      `fixada_em` nulo — o bloco final do gatilho zera a fixação porque
      `texto is null`. `ChatRepository.pinMessage` confere `affected.isEmpty`,
      vê uma linha, e reporta que fixou. A tela não oferece "Fixar" em lápide,
      mas a API aceita, e neste projeto quem decide é o banco. Recusar no
      gatilho quando `new.texto is null` e o `update` PEDIU fixação —
      distinguindo do desfixe automático, que continua mudo de propósito. Ver
      `20260817160000`, bloco final de `mensagens_so_remove` — per Requirement
      "Lápide não fica fixada", (partial)
- [x] C2 **A volta do canal não refaz a consulta das fixadas.**
      `ChatNotifier._reloadRecent` (`lib/features/chat/chat_providers.dart`)
      chama só `fetchHistory`, então uma fixada ANTIGA — fora da primeira
      página, que é o caso que motivou `fetchPinned` existir — fixada ou
      desfixada durante a queda do canal não entra nem sai da faixa até a
      pessoa fechar e reabrir a tela. É o mesmo buraco que a reconsulta na
      reconexão foi escrita para fechar em `chat-de-grupo-e-acao`, agora meio
      fechado. Acrescentar `fetchPinned` ao `_reloadRecent`, e um teste de
      widget com o canal caindo e voltando — per Requirement "A faixa de
      fixadas não engole a conversa", (partial)
- [x] C3 **O teto no chat de AÇÃO não tem teste.** Os três casos de teto
      (`chat_fixada_test.dart` § 4.3) e o de concorrência (§ 4.4) usam Grupo,
      então o braço `perform 1 from public.acoes ... for update` do gatilho
      nunca roda na suíte. Medido à mão em 2026-08-17: 3 fixadas passam e a 4ª
      dá `PT409` — funciona, e continua sem prova. Princípio IV é inegociável.
      Acrescentar o caso de teto em Ação avulsa a `chat_fixada_test.dart` —
      per Requirement "Há teto de mensagens fixadas por chat", (missing)

## Convergence 2

- [x] C4 **A justificativa escrita do `security definer` é falsa, e ela é o que
      sustenta um privilégio.** `20260817160000_mensagem_fixada.sql`, bloco 3,
      afirma: *"o Administrador do distrito MODERA sem LER o chat de Ação
      (`pode_ver_chat_acao`) ... Ele contaria zero fixadas e passaria por cima
      do teto"*. **Medido em 2026-08-17, como `authenticated` de verdade:**
      `pode_ver_chat_acao` = `t`, `pode_moderar_espaco` = `t`, e a contagem
      dele como invoker é **2 de 2** — o braço de Administrador existe em
      `pode_ver_chat_acao` desde `20260813200000`, acrescentado justamente
      porque a falta dele era um defeito. Ninguém no app modera sem ler: os
      quatro braços de `pode_moderar_espaco` estão todos cobertos pelas duas
      funções de leitura. O argumento defensável — como `invoker`, uma policy
      futura mais apertada derrubaria a contagem para zero e o teto sumiria
      sem erro, que é o mesmo de `maior_de_idade()` e
      `mensagens_ritmo_de_envio` — é OUTRO, e não é o que está escrito.
      Reescrever o comentário para o motivo verdadeiro, ou tirar o
      `security definer` se o motivo verdadeiro não bastar. Um privilégio que
      bypassa RLS justificado por premissa que a medição desmente é o que a
      próxima pessoa vai ler e acreditar — per Requirement "Há teto de
      mensagens fixadas por chat", (contradicts)
- [x] C6 **A segunda metade do cenário de teto não é provada em lugar nenhum.**
      A spec diz: *"THEN a operação é recusada AND **a tela diz que é preciso
      desfixar alguma antes**"*. A recusa está provada (`chat_fixada_test.dart`
      § 4.3, `chat_fixada_api_test.dart`). A FRASE não: nenhum teste de widget
      toca "Fixar", e `test/unit/recusa_de_envio_test.dart` só alcança
      `pinnedCeiling` pelo laço de `sendRefusalMessage` que exige `isNotEmpty`
      e ausência de `'null'` — não que a frase mande desfixar. É a recusa muda
      que esta feature existe para não ter, e ela passaria despercebida se
      alguém trocasse o texto. Acrescentar: caso de unidade afirmando que a
      frase de `pinnedCeiling` diz desfixar e nomeia o teto; e caso de widget
      que toca "Fixar" com o teto cheio e lê a frase na tela — per Scenario
      "Teto atingido", (missing)
- [x] C5 **`fixada_em` é escrito pelo cliente e conferido por ninguém.**
      Medido: como Dono, `update ... set fixada_em = '2020-01-01'` e
      `'2099-12-31'` foram **os dois ACEITOS**, e a faixa ordena por
      `fixada_em desc` — quem modera fixa a própria mensagem no alto para
      sempre com uma data futura. `fixada_por` é conferido contra `auth.uid()`;
      `fixada_em` não é conferido contra nada. Pesa mais desde a versão 1.7 do
      texto legal, que passou a declarar *"Guardamos quem fixou e quando"*.
      É a mesma família do `created_at` forjado que `20260817120000` existe
      para fechar, e o precedente de lá manda **recusar, não carimbar por
      cima**. Ressalva para a próxima passagem não reabrir isto como novidade:
      `removida_em` tem exatamente a mesma forma desde
      `chat-de-grupo-e-acao` e foi aceita assim — a diferença é que
      `fixada_em` ordena elemento de tela e virou declaração legal. Decidir
      entre recusar fora de uma janela de tolerância em torno de `now()` ou
      recortar o grant de `update` por coluna — per Requirement "Fixar
      registra quem e quando", (partial)

## Convergence 3

- [x] C7 **CRITICAL — o vocabulário desta change nunca entrou no glossário.**
      Constituição, Princípio I (NON-NEGOTIABLE): *"Um termo novo ou renomeado
      só entra em código depois de atualizado em `CONTEXT.md`"*.
      `grep -in "fixa" CONTEXT.md` devolve **zero** ocorrências do conceito, e
      o termo já está em identificador Dart (`pinnedAt`, `pinnedBy`,
      `isPinned`, `fetchPinned`, `pinMessage`, `unpinMessage`,
      `pinnedCeiling`), em schema (`fixada_em`, `fixada_por`,
      `mensagem_teto_de_fixadas`), em texto de tela ("Fixar", "Desfixar",
      "3 de 3 mensagens fixadas") e no texto legal 1.7. As changes vizinhas
      registraram as delas — `blockedWord`, `windowCeiling` e `retryAfter`
      estão na tabela. É exatamente a armadilha que o CLAUDE.md nomeia: sem a
      entrada, a próxima pessoa inventa `highlight` ou `sticky`, e duas
      traduções para a mesma coisa é pior do que o português. Acrescentar à
      tabela de `CONTEXT.md`: Fixar mensagem / Desfixar mensagem / Mensagem
      fixada / Teto de fixadas / quando foi fixada / quem fixou / Faixa de
      fixadas — per Constituição Princípio I, (missing)
- [x] C8 **Desfixar mensagem ANTIGA injeta ela na conversa de quem não
      paginou, e corrompe o cursor de "carregar o que veio antes".** MEDIDO:
      `mergeMessages` com uma página de 3 mensagens recentes mais uma linha de
      três meses atrás vinda do canal devolve
      `[antiga, recente0, recente1, recente2]` — o id desconhecido ENTRA. E
      `chat_providers.dart:405` usa `_compose().messages.firstOrNull` como
      cursor `before` do `loadOlder`, então a página seguinte passa a ser
      pedida a partir de três meses atrás e todo o histórico intermediário
      fica fora de alcance; `:417` ainda desliga o botão de vez quando aquela
      página volta vazia (`_hasMoreOlder = page.isNotEmpty`). O filtro do canal
      (`:215`) é só por espaço, sem recorte de tempo, e esta change tornou o
      caso rotineiro — `fetchPinned` existe justamente para alcançar fixada
      fora da primeira página. Conserto: no callback do canal, evento `update`
      de id que `_server` não conhece deve alimentar só `_pinned`
      (`_rememberPinned`), nunca `_server`; `insert` continua entrando como
      hoje. Com teste de widget que entrega o `update` de linha antiga e
      confere que a conversa não ganhou mensagem nova e que o cursor não
      andou — per Requirement "A faixa de fixadas não engole a conversa"
      ("sem impedir o acesso a ela"), (partial)
