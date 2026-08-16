## 1. Banco — funções de acesso

- [x] 1.1 `maior_de_idade()`: `stable`, `security definer`, `set search_path =
      public, pg_temp`, com `idade is not null and idade >= 18` explícito.
      Comentário na migration dizendo por que é `definer` e não `invoker`
      (ver design)
- [x] 1.2 `pode_ver_chat_grupo(uuid)`: participa do Grupo **e**
      `maior_de_idade()`. `stable`, `security invoker`
- [x] 1.3 `pode_ver_chat_acao(uuid)`: confirmação em qualquer status **ou**
      criador da Ação **ou** dono do Grupo dela — e `maior_de_idade()`. Reusar
      o predicado de `acoes_update_criador_ou_dono_grupo`
      (`20260724084300:228-239`), não reescrever
- [x] 1.3a As duas funções de acesso são `security invoker`, **não** `definer`
      — é o que faz o chat herdar sozinho a restrição de
      `acao-direcionada-a-grupo`. Comentário na migration explicando por que
      `maior_de_idade()` é definer e estas duas não são; sem ele, a próxima
      pessoa uniformiza as três e abre o chat de Ação restrita
- [x] 1.4 Testes de unidade SQL das três funções, isolados das policies: cada
      combinação de participação × idade × papel, com número real de casos
      anotado — `test/integration/chat_funcoes_de_acesso_test.dart`, **7 papéis
      × 3 idades = 21 credenciais × 3 funções = 63 casos**, mais 1 asserção de
      montagem (que os três `fila` não viraram um quarto `confirmado` em
      silêncio). 22 testes, todos verdes. As funções são chamadas direto
      (`select public.pode_ver_chat_grupo(@g)`), sem uma linha em `mensagens`:
      função e policy são duas barreiras, e `count(*)` em `mensagens` devolve o
      mesmo zero para as duas. Provado que discrimina por mutação — trocar o
      esperado de `na fila da Ação` para `false` deixa vermelho
      (`Expected: <false> Actual: <true>`)

## 2. Banco — tabela `mensagens`

- [x] 2.1 Tabela com o `check` de XOR entre `grupo_id` e `acao_id`, `texto`
      anulável com limite de 2000, `removida_em`/`removida_por`, `autor_id`
      não nulo
- [x] 2.2 Índices parciais `(grupo_id, created_at desc)` e `(acao_id,
      created_at desc)`
- [x] 2.3 Policies chamando **só** as funções de 1.2/1.3, nunca a condição
      inline: `select`, `insert` (com `auth.uid() = autor_id` e Grupo não
      arquivado), `update` restrito a autor + autoridade do espaço com
      `with check` gêmeo do `using`. **Nenhuma** policy de `delete`
- [x] 2.4 Gatilho `before update` que recusa qualquer alteração fora de
      `texto`, `removida_em`, `removida_por`, e recusa `texto` não nulo — sem
      ele, quem remove consegue reescrever e "mensagem não se edita" é letra
      morta
- [x] 2.5 `comment on table`/`on column` registrando as três lápides e que o
      texto removido não é guardado em lugar nenhum

## 3. Banco — moderação

- [x] 3.1 `denuncias_mensagem` no molde de `denuncias_imagem`
      (`20260810120000`), com `mensagem_id ... on delete set null` (não
      cascade) e `estado` incluindo `sem_mensagem`
- [x] 3.2 Policies: `insert` para quem lê aquele chat, com `with check`
      impedindo assinar por outro; `select` e `update` só para autoridade do
      espaço e Administrador do distrito, `with check` gêmeo do `using`
- [x] 3.3 Gatilho `after delete` em `mensagens` que marca denúncia pendente
      como `sem_mensagem`, preservando `motivo`

## 4. Banco — retenção e exclusão de conta

- [x] 4.1 `expurgar_mensagens_de_acao()`: apaga mensagem cuja Ação passou de
      `data_hora + interval '30 days'`. Consulta **antes** de sair cedo — ver
      `20260810170000:21-27`
- [x] 4.2 Agendamento `pg_cron` na migration, e registrar em
      `INFRA-PRODUCAO.md` que produção exige criá-lo à mão
- [x] 4.3 Segundo gatilho: o app chama o expurgo ao abrir um chat. Sem ele o
      prazo não se cumpre com o banco pausado (`20260810170000:9-14`)
- [x] 4.4 `excluir_conta` ganha `update mensagens set texto = null where
      autor_id = ...`, dentro da transação existente. Não criar caminho de
      falha parcial novo

## 5. Prova no banco (test/integration)

- [x] 5.1 Corte de idade: perfil com 17 anos lê 0 mensagens e tem `insert`
      recusado; perfil com 18 lê e escreve; Visitante (anônimo, sem Perfil)
      lê 0; Perfil anonimizado lê 0. Quatro credenciais
- [x] 5.2 Chat de Grupo: participante lê e escreve; não participante lê 0;
      quem saiu do Grupo lê 0 inclusive das mensagens anteriores à saída
- [x] 5.3 Chat de Ação: confirmado lê; em fila lê e escreve; participante do
      Grupo sem confirmação lê 0 da Ação e continua lendo o Grupo; dono do
      Grupo sem confirmar lê e escreve; quem desconfirmou lê 0
- [x] 5.3a **Só se `acao-direcionada-a-grupo` já estiver aplicada** (conferir
      se `acoes.restrita_ao_grupo` existe antes de escrever este teste):
      Ação restrita ao Grupo — quem não participa do Grupo lê 0 mensagens
      daquele chat, mesmo tendo 18 anos ou mais. Prova que o `security
      invoker` de 1.3a está fazendo o trabalho. Se a coluna não existir ainda,
      registrar em `PENDENCIAS.md` que este teste é dívida daquela change
- [x] 5.4 Escrita: assinar por outro é recusado; texto vazio recusado; 2001
      caracteres recusado; 2000 aceito
- [x] 5.5 `update` de `texto` pelo autor é recusado; `update` que troca
      `grupo_id`, `acao_id`, `autor_id` ou `created_at` é recusado
- [x] 5.6 Grupo arquivado: `insert` recusado, `select` das antigas continua
      funcionando
- [x] 5.7 Remoção: dono do Grupo remove; criador da Ação avulsa remove;
      Administrador remove; autor remove a própria; participante comum é
      recusado; dono de **outro** Grupo é recusado. Seis casos
- [x] 5.8 Depois de remover, `texto` volta nulo para todos os papéis,
      inclusive Administrador do distrito. Remover de novo não sobrescreve
      `removida_por`
- [x] 5.9 Denúncia: participante denuncia; motivo vazio recusado; assinar por
      outro recusado; quem não lê o chat é recusado; participante comum lê 0
      denúncias, inclusive a que ele mesmo criou
- [x] 5.10 Expurgo: Ação de 31 dias atrás perde as mensagens; Ação de ontem
      mantém; mensagem de Grupo nunca some; Grupo arquivado mantém
- [x] 5.11 Denúncia pendente sobre mensagem expurgada vira `sem_mensagem`, com
      `motivo` preservado
- [x] 5.12 `excluir_conta`: mensagens do titular ficam com `texto` nulo e
      `removida_em` nulo (lápide de conta excluída, distinta da de moderação);
      mensagem de terceiro que cite o titular fica intacta

## 6. Prova do canal de tempo real

- [x] 6.1 `alter publication supabase_realtime add table public.mensagens`,
      com RLS ligado
- [x] 6.2 Teste: participante assina o canal, outro escreve, o evento chega
      dentro de uma janela determinada
- [x] 6.3 **Teste de não entrega** — o que prova a policy: não participante
      assina, alguém escreve, e o teste falha se **qualquer** evento chegar
      dentro da janela. Repetir com credencial de menor de 18. Sem estes dois,
      6.2 não prova nada sobre vazamento
- [x] 6.4 Anotar a janela usada e por quê. Janela curta demais faz o teste
      passar por não ter esperado

## 7. Dart — dados e tempo real

- [x] 7.1 `lib/features/chat/domain/message.dart`: as três lápides derivadas
      de `texto` + `removida_em`, sem coluna extra
- [x] 7.2 `lib/features/chat/data/chat_repository.dart`: consulta de histórico
      paginada, envio, remoção, denúncia
- [x] 7.3 Assinatura do canal por espaço, com dedução por `id` entre o que veio
      da consulta e o que veio do canal — sem ela a mensagem aparece duas vezes
- [x] 7.4 Estado de conexão exposto à tela: ao vivo / reconectando / sem tempo
      real. Ao reconectar, refazer a consulta para pegar o que passou na queda
- [x] 7.5 Chamada do expurgo ao abrir um chat (segundo gatilho da tarefa 4.3),
      sem bloquear a renderização

## 8. Dart — tela

- [x] 8.1 Aba de conversa em `group_detail_page.dart` e em
      `action_detail_page.dart`, só quando a pessoa pode ver o chat
- [x] 8.2 Quando não pode por idade, a tela **diz por quê** em vez de esconder
      sem explicação — ver design, Risks
- [x] 8.3 Campo de envio com contador de 2000 e recusa local antes do envio
- [x] 8.4 Renderização das três lápides com textos distintos
- [x] 8.5 Remover pede confirmação e avisa que é definitivo
- [x] 8.6 Denunciar: motivo obrigatório; tela de denúncias visível só a quem
      tem autoridade no espaço
- [x] 8.7 Grupo arquivado: histórico legível, campo de envio ausente

## 9. Prova no cliente (test/widget, test/unit)

- [x] 9.1 Unidade: derivação das três lápides, seis casos (`texto` × `removida_em`)
- [x] 9.2 Unidade: dedução por `id` entre consulta e canal não duplica e não
      perde
- [x] 9.3 Widget: menor de 18 vê a explicação, não a aba vazia
- [x] 9.4 Widget: sem tempo real, o chat funciona e sinaliza; não fica em
      carregamento perpétuo
- [x] 9.5 Widget: Grupo arquivado mostra histórico sem campo de envio
- [x] 9.6 Widget: as três lápides renderizam sem `null` na tela

## 10. Legal e ledgers — bloqueia o fechamento

- [x] 10.1 `MAPA-DE-DADOS.md`: `mensagens` e `denuncias_mensagem` com
      `arquivo:linha`, **declarando que o conteúdo de `texto` é indeterminado**
      em vez de fingir que o descreve
- [x] 10.2 Política de Privacidade e Termos de Uso (`lib/features/legal/`):
      categoria de dado nova, prazo de 30 dias como promessa, corte de idade,
      responsabilidade de quem escreve, e o limite explícito de que mensagem de
      terceiro que cite a pessoa não é apagada pela exclusão de conta — só por
      denúncia. Rodar o agente `advogado-digital`, que lê o código antes
- [x] 10.3 `REVISAO-JURIDICA.md`: registrar as decisões com efeito legal —
      corte etário em 18, retenção de 30 dias, moderação humana reativa, texto
      removido não conservado
- [x] 10.4 `INFRA-PRODUCAO.md`: o `pg_cron` a agendar à mão em produção
- [x] 10.5 `SECURITY-AUDIT.md` / `PENDENCIAS.md`: o que ficar aberto, com o
      porquê
- [x] 10.6 Rodar o agente `promessa-vs-execucao` cruzando o prazo prometido na
      Política contra o expurgo real. É exatamente a classe de defeito que ele
      procura

## 11. Fechamento

- [x] 11.1 Gates com números reais anotados: `flutter analyze` (0 issues),
      `flutter test test/unit test/widget` (contagem), `dart test
      test/integration` com `supabase start` (contagem), `flutter build web
      --release` (sucesso)
- [x] 11.2 Rodar o agente `pentest-etico` sobre a superfície nova — REST do
      Supabase e canal de Realtime, com credencial de menor e de não
      participante
- [x] 11.3 Rodar a skill `openspec-converge` e resolver o que ela achar antes
      de arquivar — 5 passagens, 15 achados nas quatro primeiras e 4 na quinta,
      todos resolvidos. A quinta fechou a CLASSE em vez do caso: `chatProvider`
      virou `ChatNotifier` (uma composição da lista, não quatro) e a
      precedência deixou de ser ordem de chegada, virou a lápide absorvente.
      Gates depois: `flutter analyze` 0 issues, `flutter test test/unit
      test/widget` 422 passed, `dart test test/integration` 417 passed,
      `flutter build web --release` ok

- [x] 11.4 Escrever as Novidades da change em
      `lib/features/news/domain/news_item.dart` — 5 itens: a conversa existe, o
      corte de 18 anos e por quê, os 30 dias da conversa de Ação, a denúncia e
      a remoção, e o texto das mensagens saindo na exclusão de conta. Três
      deles são "sobre os dados dela", que é o gatilho do critério.
      Escritas junto as 5 Novidades das changes de 13/08 que fecharam sem
      escrever nenhuma (`acao-direcionada-a-grupo`, `convite-para-acao`,
      `notificacoes-in-app`, `log-de-mudancas-em-grupo-e-acao`,
      `destaque-de-acoes-distritais-e-de-grupo`), e registrado em
      `CRITERIO-DE-NOVIDADE.md` **quando** se escreve, para não repetir

## Convergence 1

- [x] **HIGH** — Fazer o corte de 18 anos alcançar `denuncias_mensagem`, hoje
      ele para em `mensagens` — per "Administrador menor de idade" (`contradicts`).
      Medido em 2026-08-14, transação com rollback, Administrador do distrito
      com 16 anos: `maior_de_idade()` = `false`, `pode_ver_chat_grupo` = `false`,
      `select` em `mensagens` = **0 linhas** (correto), e `select` em
      `denuncias_mensagem` = **2 linhas**, com o `motivo` legível
      (`'denuncia do GRUPO'`). Pior: o `update` de resolução afetou **1 linha** —
      ele arquiva denúncia. `pode_moderar_espaco`
      (`20260813200000_chat_de_grupo_e_acao.sql:238`) não chama
      `maior_de_idade()`, e as três policies de `denuncias_mensagem` (`:462`,
      `:475`, `:484`) dependem só dela. O `motivo` é texto livre escrito por uma
      pessoa sobre o que outra escreveu — a mesma categoria de dado que o corte
      etário existe para não entregar a menor de idade. A spec diz "a autoridade
      não levanta o corte de idade"; hoje levanta, para a tabela ao lado.
- [x] **HIGH** — Fazer a lista de denúncias do Grupo incluir as dos chats das
      Ações daquele Grupo — per "Dono do Grupo vê as denúncias do Grupo dele"
      (`partial`). A spec diz, com todas as letras, "vê as do chat do Grupo dele
      **e as dos chats das Ações daquele Grupo**". A RLS já permite — medido:
      a dona enxergou as 2 denúncias, incluindo a do chat da Ação. Quem não
      permite é a consulta do app: `ChatRepository.fetchReports`
      (`lib/features/chat/data/chat_repository.dart`) filtra
      `eq('mensagens.grupo_id', id)`, e denúncia de chat de Ação tem
      `mensagens.grupo_id` nulo — some da tela. O Dono do Grupo abre
      `/grupos/:id/denuncias` e vê menos do que o banco lhe daria, sem nada
      indicar que falta algo.
- [x] **MEDIUM** — Escrever o teste de integração do cenário "Ação cancelada" —
      per "Ação cancelada" (`missing`). O comportamento está CERTO e foi medido:
      depois de `cancelada_em = now()`, quem confirmou continua com
      `pode_ver_chat_acao` = `true`, lê 1 mensagem e **escreve** (insert aceito).
      É exatamente o que a spec pede — "cancelar é justamente quando mais se
      precisa avisar". Não há um teste sequer segurando isso, e `pode_ver_chat_acao`
      é `security invoker`: qualquer aperto futuro na policy de `acoes` para Ação
      cancelada apaga o chat dela em silêncio, que é a classe de falha que o
      `security invoker` foi escolhido para produzir de propósito no caso da Ação
      restrita.
- [x] **MEDIUM** — Escrever o teste do cenário "Administrador menor de idade" —
      per o mesmo cenário (`missing`). Nenhum arquivo cruza as duas condições:
      `chat_corte_de_idade_test` não cria Administrador, e `chat_moderacao_test`
      só usa Administrador de 30 anos. Foi essa lacuna que deixou o achado HIGH
      acima passar por 380 testes verdes.
- [x] **MEDIUM** — Escrever o teste do caminho de RECONEXÃO — per "Conexão cai e
      volta" (`missing`). `mergeMessages` está provado em unidade
      (`test/unit/chat_deducao_test.dart`, 5 casos) e a entrega no canal está
      provada em integração, mas **nada exercita a transição**
      `reconnecting → subscribed` que dispara `loadHistory` em
      `lib/features/chat/chat_providers.dart`. A spec pede as duas metades —
      "mostra as mensagens que chegaram durante a queda" **e** "nenhuma mensagem
      aparece duplicada" — e é a emenda entre consulta e canal que produz as duas.
- [x] **MEDIUM** — Escrever o teste de widget do cenário "Menor de idade abre um
      Grupo em que participa" — per o mesmo cenário (`missing`).
      `conversa_page_test.dart` prova a explicação DENTRO da conversa; ninguém
      prova a segunda metade do cenário, que é sobre `group_detail_page`: "não
      existe aba de conversa na tela" **e** "o resto da tela funciona igual,
      inclusive a seção de mudanças". A entrada é condicional a
      `canSeeChatProvider`, e uma regressão nela some com o botão para todo mundo
      — ou o mostra para menor de idade — sem nada ficar vermelho.
- [x] **LOW** — Registrar na spec de `moderacao-de-mensagem` a decisão sobre o
      autor da mensagem denunciada resolver a própria denúncia (`contradicts`).
      As duas requirements discordam entre si: "A autoridade de remover segue quem
      manda no espaço" inclui "em qualquer chat: o autor da própria mensagem",
      e "A denúncia tem desfecho registrado" diz "só quem tem autoridade de
      remoção naquele espaço PODE resolvê-la" — lidas juntas, o denunciado
      arquiva o caso contra si. O código já decidiu o contrário, de propósito e
      com teste (`pode_moderar_espaco` sem o autor; `chat_denuncia_test.dart`), e
      foi um defeito real corrigido durante esta change. Falta a frase na spec,
      senão a próxima leitura "conserta" o código de volta.

## Convergence 2

- [x] **HIGH** — Fechar o caminho de falha parcial de "remover mensagem
      denunciada": hoje são DUAS escritas sem reparo, e a denúncia fica presa —
      per "A denúncia tem desfecho registrado" (`partial`).
      `_ReportCard._removeMessage`
      (`lib/features/chat/presentation/message_reports_page.dart`) chama
      `removeMessage()` e, **depois**, `_resolve(messageRemoved)`. Não é
      transação. Medido em 2026-08-14, executando só o passo 1 como a Dona do
      Grupo e parando: `msg_tem_texto=false`, `msg_removida=true`,
      `denuncia_estado=pendente`, `denuncia_resolvida_em=NULO`,
      `algum_gatilho_conserta=NAO`. Nada no banco repara — o gatilho
      `denuncias_sem_mensagem` é `before delete`, e remover é `update`.
      A consequência é pior que o estado sujo: o botão só aparece sob
      `isPending && report.messageId != null && !report.messageRemoved`, e com a
      mensagem já removida essa condição é falsa. **A denúncia fica `pendente`
      para sempre, sem nenhum botão que a resolva** — viola "toda denúncia DEVE
      terminar em um de dois estados". O conserto provável é uma função no banco
      que faça as duas escritas numa transação, no molde de
      `expurgar_mensagens_de_acao`; a alternativa barata é o card oferecer
      "concluir a decisão" quando encontrar esse estado.
- [x] **HIGH** — Fazer o bloco de denúncias órfãs aparecer quando o espaço não
      tem denúncia nenhuma — per "A denúncia sobrevive à expiração da conversa"
      (`partial`). `_ReportList.build`
      (`lib/features/chat/presentation/message_reports_page.dart`) faz
      `if (reports.isEmpty) return 'Nenhuma mensagem denunciada aqui.'` **antes**
      de montar o `ListView` que contém `_OrphanReports()`. Ou seja: o
      Administrador do distrito só enxerga denúncia órfã se aquele espaço tiver,
      por acaso, outra denúncia viva. E o caso comum é justamente o contrário —
      a denúncia vira órfã porque as mensagens da Ação foram expurgadas, e um
      espaço expurgado tende a não ter denúncia viva nenhuma. O bloco foi
      acrescentado na auditoria de promessa contra execução exatamente para essa
      linha deixar de ser ramo morto, e continua morto na situação que mais
      importa.
- [x] **MEDIUM** — Registrar a decisão "toda escrita deste app confere quantas
      linhas afetou", e aplicá-la a `resolveReport` — per "A denúncia tem
      desfecho registrado" (`partial`). Esta é a TERCEIRA vez que o mesmo
      defeito aparece nesta change: (1) `pode_ver_chat_acao` sem o braço de
      Administrador, em que a remoção afetava zero linha e a tela dizia que deu
      certo; (2) `ChatRepository.removeMessage` sem `.select()`, mesmo sintoma;
      (3) agora `ChatRepository.resolveReport`
      (`lib/features/chat/data/chat_repository.dart`), que faz `update ... eq` e
      não olha o resultado — recusa de RLS devolve zero linha, não exceção, então
      `_resolve` cai no caminho de sucesso, invalida a lista e o card volta
      `pendente` sem uma palavra. Parar de consertar caso a caso: a causa é que
      **no Postgres a recusa de RLS num `update` é ausência, não erro**, e isso
      precisa estar escrito — em `CLAUDE.md` ou na spec — como regra do
      repositório, com `removeMessage` de exemplo. Sem a regra escrita, a quarta
      ocorrência é questão de tempo.
- [x] **LOW** — Parar de trazer `denunciante_id` no payload das denúncias órfãs
      — per "A denúncia é visível só para quem pode resolvê-la" (`partial`).
      `ChatRepository.fetchOrphanReports` usa `.select()` sem lista de colunas,
      então a linha inteira viaja, incluindo `denunciante_id`. `MessageReport`
      não expõe o campo e a tela não o mostra, mas a spec diz "NÃO DEVE
      mostrá-la aos demais participantes, **nem revelar a eles quem
      denunciou**", e o dado sai do banco assim mesmo. `denuncias_do_espaco` já
      faz o certo — devolve colunas nomeadas, sem o denunciante. Alinhar as
      duas.

## Convergence 3

**Padrão, e a decisão que falta.** Os dois HIGH abaixo não são defeitos
independentes: a lista da conversa tem **uma única fonte de renderização, o
canal de tempo real**, e nenhum caminho que releia sob demanda. `_send` não
atualiza nada, a paginação não tem chamador, e uma falha de histórico deixa a
lista vazia sem repetição. O `chatProvider` emite em cinco pontos — carga
inicial, ausência de sessão, erro de carga, evento do canal, e a transição para
`subscribed` — e **nenhum deles é uma ação da pessoa**. Antes de consertar os
dois separadamente, decidir e escrever no design quem manda na lista: o canal é
otimização sobre uma consulta que a tela sabe refazer, ou é a fonte? Enquanto
isso não estiver escrito, cada caminho novo que não passe pelo canal vira o
próximo achado.

- [x] **HIGH** — Fazer a mensagem enviada aparecer para quem a enviou mesmo com
      o canal caído — per "Conexão indisponível" e "Participante escreve"
      (`partial`). `_ChatPageState._send`
      (`lib/features/chat/presentation/chat_page.dart`) faz `_controller.clear()`
      no sucesso do `insert` e **não** acrescenta a mensagem localmente nem
      invalida o provider. As cinco emissões de `chatProvider`
      (`lib/features/chat/chat_providers.dart`) são carga inicial, sessão
      ausente, erro de carga, callback do canal e transição para `subscribed`.
      Com `connection` em `reconnecting`, nenhuma dispara: a pessoa digita,
      aperta enviar, **o texto some do campo e não aparece em lugar nenhum**, e
      não há erro — o `insert` deu certo. A spec exige que sem tempo real "o
      chat continua utilizável pela consulta comum", e escrever sem ver o que se
      escreveu é o oposto disso. Note que a faixa de aviso já está na tela, o
      que torna o efeito pior: a tela diz que está reconectando e ainda assim
      engole a mensagem sem explicar a relação.
- [x] **HIGH** — Dar caminho para as mensagens além das 50 mais recentes — per
      "Envio em Grupo arquivado", cláusula "as mensagens antigas continuam
      legíveis" (`partial`). Medido em 2026-08-14 com 60 mensagens num Grupo:
      `total_no_banco=60`, `a_consulta_do_app_traz=50`,
      `mais_antiga_alcancavel=NAO`. `ChatRepository.fetchHistory` tem o
      parâmetro `before` e **nenhum chamador o usa** (`grep 'before:'` em
      `lib/features/chat/` não devolve nada), então `pageSize = 50` é um teto
      absoluto, não uma página. Chat de Grupo **não expira** por decisão desta
      change: a 51ª mensagem empurra a 1ª para fora do alcance permanentemente,
      e num Grupo ativo isso acontece em semanas. É a única categoria de dado do
      app que fica inalcançável sem nada tê-la apagado.
- [x] **LOW** — Fazer o bloco das denúncias órfãs sobreviver a uma falha da
      consulta do espaço — per "A denúncia sobrevive à expiração da conversa"
      (`partial`). `_OrphanReports` está dentro do ramo `data:` de
      `messageReportsProvider`
      (`lib/features/chat/presentation/message_reports_page.dart`); se essa
      consulta cair no `error:`, as órfãs somem junto, embora venham de outro
      provider que pode estar perfeitamente bem. Terceira variação do mesmo
      bloco ficar inalcançável — as duas anteriores foram consertadas nas
      convergências anteriores.

## Convergence 4

- [x] **HIGH** — Inverter a precedência das sobreposições locais da conversa: o
      servidor tem de vencer o que a tela guardou — per "Mensagem removida na
      conversa" e "Administrador consulta o texto removido" (`contradicts`).
      `chat_page.dart` monta a lista como
      `mergeMessages([..._older, ...state.messages], _justSent)`, e
      `mergeMessages` foi escrita com a regra "quem chega DEPOIS vence" — regra
      medida, o teste `chat_deducao_test.dart` "quem chega depois vence — a
      remoção não é desfeita pelo histórico" passa exatamente por causa dela.
      Consequência: `_justSent` vence sempre. A pessoa envia uma mensagem, ela
      ou um moderador a remove, a remoção chega pelo canal como `update` — e a
      cópia local, com o texto, continua desenhada na tela de quem escreveu.
      **O texto removido volta para alguém**, que é o que a spec de moderação
      proíbe em letra ("NÃO DEVE devolver o texto removido a ninguém").
      `_older` tem a mesma falha por outro caminho: ele é a página anterior,
      `state.messages` não contém aquelas linhas, então uma remoção lá nunca
      alcança a cópia carregada.
      O conserto é a ordem dos argumentos —
      `mergeMessages([..._older, ..._justSent], state.messages)` —, e as duas
      sobreposições continuam funcionando: `state.messages` não contém a
      mensagem recém-enviada, então ela sobrevive até o servidor falar dela, e
      aí o servidor vence. **Falta escrever no design a regra que estava
      implícita**: sobreposição local existe para o que o servidor ainda não
      disse, e é descartada assim que ele diz.
- [x] **MEDIUM** — Provar a segunda metade do cenário "Alguém sai do Grupo" —
      per esse cenário (`missing`). O teste
      `chat_acesso_grupo_test.dart` prova só a primeira metade, do ponto de
      vista de quem saiu ("deixa de ler, inclusive o anterior à saída"). A
      cláusula **"AND as mensagens que ela escreveu continuam visíveis para quem
      ficou"** não tem asserção nenhuma — nada no arquivo olha pela sessão de
      quem permaneceu. O comportamento está certo, medido em 2026-08-14 com
      rollback: depois da saída, `quem_ficou_ainda_le=1` e
      `texto_intacto='escrita por quem saiu'`. É a metade que protege contra o
      conserto errado — alguém apertando a policy para resolver a primeira
      metade apagaria a conversa de quem ficou, e nada ficaria vermelho.

## Convergence 5

**O padrão, e ele não é mais uma decisão faltando — é a decisão aplicada num
lugar só.** A convergência 4 escreveu a regra no design, com todas as letras:
*"sobreposição local existe para o que o servidor ainda não disse, e é
descartada assim que ele diz. Onde os dois falam da mesma linha, vence o
servidor — sempre."* Ela foi implementada em **um** ponto: a ordem dos
argumentos do `mergeMessages` do `build` de `chat_page.dart`. Os três achados
abaixo são os OUTROS pontos onde a mesma lista se compõe, e nos três a cópia
local vence o servidor. Dois deles devolvem à tela o texto de uma mensagem
removida, que é exatamente o que a regra foi escrita para impedir.

Antes de consertar os três separadamente: a regra precisa de um lugar só onde
seja aplicada, não de três consertos que a repetem. Hoje há quatro composições
da lista — `build`, `loadHistory`, o callback do canal e as duas sobreposições
do widget — e cada uma decide por conta própria quem vence. Enquanto isso for
assim, a quinta composição é o próximo achado, e a regra escrita no design
continuará verdadeira no papel e falsa em três caminhos.

- [x] **HIGH** — Fazer a remoção feita pela própria pessoa aparecer na tela dela
      sem depender do canal — per "Mensagem removida na conversa" e "Remover
      apaga o conteúdo e conserta a denúncia" (`partial`).
      `_MessageActions._remove` (`lib/features/chat/presentation/chat_page.dart`)
      chama `removeMessage()` e, no sucesso, **não faz nada**: não invalida o
      `chatProvider`, não mexe em `_justSent`, não guarda a remoção em lugar
      nenhum. O único caminho que redesenha é o evento do canal. Medido em
      2026-08-16, com `connection` em `reconnecting`:
      `chamou_o_banco=1`, `texto_ainda_na_tela=true`, `lapide_na_tela=false` —
      a mensagem saiu do banco e o texto continua desenhado para quem acabou de
      mandar tirá-lo, sem erro e sem lápide. É o gêmeo exato do defeito de
      `_send` que a convergência 3 consertou, e a decisão do design já cobre os
      dois pela mesma frase: *"toda ação da pessoa que muda esse conjunto
      atualiza a tela sem depender de o canal estar de pé"*. Remover é ação da
      pessoa e muda o conjunto.
- [x] **HIGH** — Fazer a reconexão aceitar o que o servidor diz sobre as linhas
      que a tela já tinha — per "Conexão cai e volta" e "Administrador consulta
      o texto removido" (`contradicts`). `loadHistory`
      (`lib/features/chat/chat_providers.dart`) faz
      `messages = mergeMessages(history, messages)`, passando a consulta como
      argumento ANTIGO. Para a carga INICIAL isso está certo, e o comentário
      explica bem por quê: o evento que o canal entregou enquanto a consulta
      viajava é mais novo que ela. Na RECONEXÃO a relação se inverte —
      `messages` é o que o canal entregou ANTES da queda, e a consulta é a mais
      nova das duas. Medido em 2026-08-16, dublando o canal e derrubando-o de
      propósito: mensagem removida durante a queda, `consultas=2`, e depois de
      voltar `texto_na_tela='o texto que a moderação tirou'`,
      `removida_em=null`, `lapide=MessageTombstone.visible`. A consulta trouxe
      a linha removida e a cópia velha ganhou. O `loadHistory` da reconexão
      existe justamente para trazer o que passou na queda, e é o único caso em
      que ele descarta o que trouxe. O conserto não é inverter a ordem no
      método — isso quebraria a carga inicial, cujo raciocínio continua válido:
      as duas chamadas precisam de precedências diferentes, e a diferença tem
      de ficar escrita. `test/unit/chat_reconexao_test.dart` passa porque
      compara só `id`s, nunca conteúdo — foi por aí que isto entrou.
- [x] **MEDIUM** — Fazer o expurgo alcançar as páginas antigas e a sobreposição
      local — per "Ação passou de 30 dias" (`partial`). O callback de `delete`
      em `chat_providers.dart` faz
      `messages = messages.where((m) => m.id != goneId)`, e `messages` é só a
      lista do provider. As páginas carregadas por "Carregar o que veio antes"
      moram em `_older`, no estado do widget, e `_justSent` também — nenhuma
      das duas é filtrada, e `mergeMessages` não tem como descartar uma linha
      que o servidor deixou de mencionar. Medido em 2026-08-16, chat de Ação
      com uma página anterior carregada: depois do expurgo,
      `antiga_na_tela=true` e `recente_na_tela=false` — some da tela só o que o
      provider conhecia, e a mensagem expurgada continua legível. O comentário
      do próprio callback diz "Some do banco, tem de sumir daqui"; para
      `_older` ele não some. É o caso em que a Política de Privacidade promete
      que a mensagem "deixa de existir" depois de 30 dias.
- [x] **LOW** — Escrever o teste da metade de TELA do limite de 2000 caracteres
      — per "Mensagem longa demais" (`missing`). A cláusula tem duas metades e
      só uma tem prova: `chat_escrita_test.dart` cobre "a operação é recusada"
      no banco (`'2000 caracteres passa, 2001 não'`); "a tela diz o limite
      antes do envio" não tem asserção nenhuma — `grep` por `2000`, `maxLength`
      ou `contador` nos testes de conversa não devolve nada. O contador de
      `_Composer` só aparece a partir de 1801 caracteres e o botão fecha em
      2001, e as duas condições são números escritos à mão em
      `chat_page.dart`, longe do `check` do banco que elas espelham. Uma
      regressão em qualquer das duas transforma a recusa educada num erro de
      servidor depois de a pessoa ter escrito o texto inteiro.

## Convergence 6

**Passada sobre o código NOVO.** A convergência 5 reescreveu o dono da lista, e
esta olha o que a reescrita trouxe. Os dois achados são da mesma família de
sempre — quem fala pela lista —, e agora por um ângulo que não existia antes: a
costura ficou boa, mas há dois caminhos que **não passam por ela**. Um é uma
lacuna dentro do próprio `ChatNotifier`; o outro é uma tela que ainda escreve
por fora dele.

- [x] **MEDIUM** — Fazer `ChatNotifier.remove` encontrar a linha em `_pending`,
      não só em `_server` — per "Mensagem removida na conversa" e "Remover apaga
      o conteúdo e conserta a denúncia, não a conversa" (`partial`).
      `remove` (`lib/features/chat/chat_providers.dart`) procura a versão atual
      com `_server.where(...).firstOrNull` e, quando não acha, sintetiza a
      lápide com `authorId: ''` e `createdAt: DateTime.now()`. `_pending` não é
      consultado — e é exatamente onde mora a mensagem que a pessoa acabou de
      escrever e cujo eco o canal ainda não trouxe, que é o caminho que a
      própria convergência 5 criou. Medido em 2026-08-16, canal caído, enviar e
      remover em seguida: `autor=""`, `nome=null`, `created=2026-08-16` numa
      conversa de 14/08. Na tela, a lápide **muda de lugar** — vai para o fim da
      conversa, dois dias à frente — e aparece assinada por "Alguém". A spec diz
      "as mensagens seguintes continuam na mesma ordem", e a marca existe para
      dizer que houve algo **ali**. A metade que importa funciona (o texto some);
      o que quebra é a posição e o nome.
- [x] **MEDIUM** — Fazer a remoção feita na tela de DENÚNCIAS alcançar a
      conversa aberta atrás dela — per "Mensagem removida na conversa"
      (`partial`). `_ReportCard._removeMessage`
      (`lib/features/chat/presentation/message_reports_page.dart`) chama
      `ChatRepository.removeMessage` direto e invalida só
      `messageReportsProvider`. A tela de denúncias é aberta por `context.push`
      a partir da conversa, então o `chatProvider` daquele espaço continua vivo
      atrás — e não fica sabendo. Medido em 2026-08-16, com o canal caído:
      `texto_ainda_na_conversa=true`, `lapide=false`. Quem modera volta para a
      conversa e lê o texto que acabou de mandar tirar. É a mesma frase de
      decisão do design, cruzando de tela: "toda ação da pessoa que muda esse
      conjunto atualiza a tela sem depender de o canal estar de pé". O conserto
      barato é `ref.invalidate(chatProvider(space))` ali — invalidar provider
      sem ouvinte é no-op, então a tela de denúncias aberta por link direto não
      paga canal nenhum.

## Convergence 7

**A passada que não achou defeito.** Um único item, e ele é de REGISTRO: um
limite conhecido que precisa estar escrito antes de arquivar, senão a próxima
pessoa a ler `_reloadRecent` vai achar que é esquecimento e "consertar" com N
idas ao servidor por reconexão.

- [x] **LOW** — Escrever no design o alcance da reconexão: ela refaz **a
      página mais recente**, não as páginas anteriores já carregadas — per
      "Conexão cai e volta" (`partial`, limite aceito). Medido em 2026-08-16:
      com uma página anterior carregada, derrubar o canal e voltar dá
      `consultas_recentes=2` — a reconsulta acontece — e
      `texto_antigo_na_tela=true`. Uma remoção ocorrida DURANTE a queda sobre
      uma linha das páginas antigas não é aprendida: ela não vem na resposta de
      `fetchHistory` sem `before`, e o canal não repete o que perdeu. O texto
      fica na tela daquela pessoa até ela sair da conversa. Não é conserto que
      valha: refazer todas as páginas carregadas é uma ida ao servidor por
      página em cada reconexão, e reconexão em rede de celular é frequente. O
      que falta é a frase, ao lado da regra da lápide absorvente, dizendo que o
      alcance da reconexão é a página recente e por quê.
