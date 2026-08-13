## 1. Banco — lista e função de casamento

- [ ] 1.1 `palavras_bloqueadas_mensagem` (palavra como chave primária), RLS
      ligada e **nenhuma** policy — nem para Administrador do distrito.
      Comentário na migration dizendo que a ausência é o mecanismo
- [ ] 1.2 `palavra_bloqueada_em(text)` devolvendo a palavra casada ou `null`:
      `stable`, `security definer`, `set search_path = public, extensions,
      pg_temp`, casando com `~ ('\y' || ... || '\y')` sobre `unaccent(lower())`
      dos dois lados
- [ ] 1.3 Testes SQL da função, isolados de gatilho: palavra inteira casa;
      mesma sequência dentro de palavra maior **não** casa; maiúscula, acento e
      ausência de acento casam; palavra colada em vírgula, ponto e fim de texto
      casa; lista vazia devolve `null` para tudo. Anotar a contagem de casos
- [ ] 1.4 Teste: a função continua enxergando a lista completa quando chamada
      por `authenticated`, que não tem acesso de leitura à tabela. É o cenário
      "filtro rodando sob papel sem acesso à lista" da spec — sem ele, o
      `security definer` não está provado

## 2. Banco — gatilho de filtro

- [ ] 2.1 Gatilho `before insert` em `mensagens` levantando exceção com a
      palavra na mensagem de erro e código próprio (`errcode` distinto do de
      intervalo e do de teto)
- [ ] 2.2 Mesmo gatilho em `denuncias_mensagem`, sobre `motivo`
- [ ] 2.3 Ambos entram **ao lado** do gatilho `before update` de
      `chat-de-grupo-e-acao`, sem alterá-lo
- [ ] 2.4 Teste: mensagem recusada não gera **nenhum** evento no canal de tempo
      real. Assinar antes, tentar escrever, esperar a mesma janela usada nos
      testes de Realtime daquela change e falhar se qualquer evento chegar

## 3. Banco — intervalo e teto

- [ ] 3.1 Índice `mensagens (autor_id, created_at desc)`
- [ ] 3.2 Constantes nomeadas na migration: 3 segundos de intervalo, 20
      mensagens por 5 minutos. Comentário registrando que são escolha, não
      medição
- [ ] 3.3 Gatilho `before insert` em `mensagens`: `perform 1 from perfis where
      id = auth.uid() for update` **primeiro**, depois `max(created_at)` e
      `count(*)` por autor e por chat. Exceção com código distinto por causa e
      com o tempo restante
- [ ] 3.4 Nada é gravado sobre a tentativa recusada. Confirmar que o gatilho
      não escreve em nenhuma tabela

## 4. Prova no banco (test/integration)

- [ ] 4.1 Mensagem com palavra da lista é recusada; sem palavra é aceita;
      recusa carrega a palavra
- [ ] 4.2 Duas palavras da lista na mesma mensagem: recusa, e a palavra
      devolvida é uma das duas
- [ ] 4.3 Palavra na lista de nomes e não na de conversa: recusada em `perfis`,
      aceita em `mensagens`. E o inverso. Prova que as duas listas são
      independentes
- [ ] 4.4 `select` na tabela da lista devolve 0 linhas como `authenticated` e
      como Administrador do distrito
- [ ] 4.5 Denúncia com palavra da lista no `motivo` é recusada
- [ ] 4.6 Intervalo: segunda mensagem antes de 3s recusada, a primeira
      permanece; depois de 3s aceita; mensagem em outro chat logo em seguida
      aceita
- [ ] 4.7 Teto: 20 mensagens respeitando o intervalo passam, a 21ª na janela é
      recusada; depois de a janela deslizar, volta a aceitar
- [ ] 4.8 Chamada direta à API sem passar pela tela é recusada igual
- [ ] 4.9 Concorrência: duas inserções simultâneas da mesma pessoa no mesmo
      chat resultam em exatamente 1 linha gravada. Sem este teste a trava não
      está provada
- [ ] 4.10 Códigos de erro: filtro, intervalo e teto devolvem três códigos
      distintos, verificados um a um

## 5. Dart — cliente

- [ ] 5.1 Constantes de intervalo e teto no Dart, num lugar só
- [ ] 5.2 Teste de integração que compara as constantes do Dart com as da
      migration e falha se divergirem
- [ ] 5.3 Repositório distingue as três causas pelo código do erro, nunca
      interpretando o texto da mensagem
- [ ] 5.4 Contagem regressiva e envio desabilitado até liberar, sem perder o
      texto digitado
- [ ] 5.5 Recusa por filtro mostra a palavra devolvida pelo servidor

## 6. Prova no cliente (test/widget, test/unit)

- [ ] 6.1 Widget: recusa por filtro mostra a palavra; recusa por intervalo
      mostra o tempo; recusa por teto mostra texto distinto do intervalo
- [ ] 6.2 Widget: em nenhuma das três recusas o texto digitado se perde
- [ ] 6.3 Widget: envio volta a habilitar sozinho quando o tempo passa
- [ ] 6.4 Julgar as três telas de recusa **na largura de celular**, não no
      desktop — contagem regressiva e nome da palavra competem com o campo de
      envio numa tela estreita

## 7. Legal e ledgers

- [ ] 7.1 Termos de Uso (`lib/features/legal/`): existe filtro de palavra e
      existe limite de ritmo. Regra que recusa conteúdo sem estar escrita é a
      pior versão disso. Rodar o agente `advogado-digital`
- [ ] 7.2 `REVISAO-JURIDICA.md`: recusar mensagem é decisão com efeito sobre o
      titular — registrar, com o limite assumido (falso negativo é o caso
      comum, ver design)
- [ ] 7.3 `PENDENCIAS.md`: a dívida "moderação só humana e reativa" de
      `chat-de-grupo-e-acao` fecha **parcialmente**; escrever o que continua
      aberto
- [ ] 7.4 `MAPA-DE-DADOS.md` **não** muda: confirmar que nenhuma coluna nova de
      pessoa foi criada, e registrar essa conferência

## 8. Fechamento

- [ ] 8.1 Gates com números reais: `flutter analyze` (0 issues), `flutter test
      test/unit test/widget` (contagem), `dart test test/integration` com
      `supabase start` (contagem), `flutter build web --release`
- [ ] 8.2 Rodar a skill `openspec-converge` e resolver o que ela achar
