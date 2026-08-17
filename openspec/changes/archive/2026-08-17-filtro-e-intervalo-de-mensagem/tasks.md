## 1. Banco — lista e função de casamento

- [x] 1.1 `palavras_bloqueadas_mensagem` (palavra como chave primária), RLS
      ligada e **nenhuma** policy — nem para Administrador do distrito.
      Comentário na migration dizendo que a ausência é o mecanismo
- [x] 1.2 `palavra_bloqueada_em(text)` devolvendo a palavra casada ou `null`:
      `stable`, `security definer`, `set search_path = public, extensions,
      pg_temp`, casando com `~ ('\y' || ... || '\y')` sobre `unaccent(lower())`
      dos dois lados
- [x] 1.3 Testes SQL da função, isolados de gatilho: palavra inteira casa;
      mesma sequência dentro de palavra maior **não** casa; maiúscula, acento e
      ausência de acento casam; palavra colada em vírgula, ponto e fim de texto
      casa; lista vazia devolve `null` para tudo. Anotar a contagem de casos
- [x] 1.4 Teste: a função continua enxergando a lista completa quando chamada
      por `authenticated`, que não tem acesso de leitura à tabela. É o cenário
      "filtro rodando sob papel sem acesso à lista" da spec — sem ele, o
      `security definer` não está provado

## 2. Banco — gatilho de filtro

- [x] 2.1 Gatilho `before insert` em `mensagens` levantando exceção com a
      palavra na mensagem de erro e código próprio (`errcode` distinto do de
      intervalo e do de teto)
- [x] 2.2 Mesmo gatilho em `denuncias_mensagem`, sobre `motivo`
- [x] 2.3 Ambos entram **ao lado** do gatilho `before update` de
      `chat-de-grupo-e-acao`, sem alterá-lo
- [x] 2.4 Teste: mensagem recusada não gera **nenhum** evento no canal de tempo
      real. Assinar antes, tentar escrever, esperar a mesma janela usada nos
      testes de Realtime daquela change e falhar se qualquer evento chegar

## 3. Banco — intervalo e teto

- [x] 3.1 Índice `mensagens (autor_id, created_at desc)`
- [x] 3.2 Constantes nomeadas na migration: 3 segundos de intervalo, 20
      mensagens por 5 minutos. Comentário registrando que são escolha, não
      medição
- [x] 3.3 Gatilho `before insert` em `mensagens`: `perform 1 from perfis where
      id = auth.uid() for update` **primeiro**, depois `max(created_at)` e
      `count(*)` por autor e por chat. Exceção com código distinto por causa e
      com o tempo restante
- [x] 3.4 Nada é gravado sobre a tentativa recusada. Confirmar que o gatilho
      não escreve em nenhuma tabela

## 4. Prova no banco (test/integration)

- [x] 4.1 Mensagem com palavra da lista é recusada; sem palavra é aceita;
      recusa carrega a palavra
- [x] 4.2 Duas palavras da lista na mesma mensagem: recusa, e a palavra
      devolvida é uma das duas
- [x] 4.3 Palavra na lista de nomes e não na de conversa: recusada em `perfis`,
      aceita em `mensagens`. E o inverso. Prova que as duas listas são
      independentes
- [x] 4.4 `select` na tabela da lista devolve 0 linhas como `authenticated` e
      como Administrador do distrito
- [x] 4.5 Denúncia com palavra da lista no `motivo` é recusada
- [x] 4.6 Intervalo: segunda mensagem antes de 3s recusada, a primeira
      permanece; depois de 3s aceita; mensagem em outro chat logo em seguida
      aceita
- [x] 4.7 Teto: 20 mensagens respeitando o intervalo passam, a 21ª na janela é
      recusada; depois de a janela deslizar, volta a aceitar
- [x] 4.8 Chamada direta à API sem passar pela tela é recusada igual
- [x] 4.9 Concorrência: duas inserções simultâneas da mesma pessoa no mesmo
      chat resultam em exatamente 1 linha gravada. Sem este teste a trava não
      está provada
- [x] 4.10 Códigos de erro: filtro, intervalo e teto devolvem três códigos
      distintos, verificados um a um

## 5. Dart — cliente

- [x] 5.1 Constantes de intervalo e teto no Dart, num lugar só
- [x] 5.2 Teste de integração que compara as constantes do Dart com as da
      migration e falha se divergirem
- [x] 5.3 Repositório distingue as três causas pelo código do erro, nunca
      interpretando o texto da mensagem
- [x] 5.4 Contagem regressiva e envio desabilitado até liberar, sem perder o
      texto digitado
- [x] 5.5 Recusa por filtro mostra a palavra devolvida pelo servidor

## 6. Prova no cliente (test/widget, test/unit)

- [x] 6.1 Widget: recusa por filtro mostra a palavra; recusa por intervalo
      mostra o tempo; recusa por teto mostra texto distinto do intervalo
- [x] 6.2 Widget: em nenhuma das três recusas o texto digitado se perde
- [x] 6.3 Widget: envio volta a habilitar sozinho quando o tempo passa
- [x] 6.4 Julgar as três telas de recusa **na largura de celular**, não no
      desktop — contagem regressiva e nome da palavra competem com o campo de
      envio numa tela estreita

## 7. Legal e ledgers

- [x] 7.1 Termos de Uso (`lib/features/legal/`): existe filtro de palavra e
      existe limite de ritmo. Regra que recusa conteúdo sem estar escrita é a
      pior versão disso. Rodar o agente `advogado-digital`
- [x] 7.2 `REVISAO-JURIDICA.md`: recusar mensagem é decisão com efeito sobre o
      titular — registrar, com o limite assumido (falso negativo é o caso
      comum, ver design)
- [x] 7.3 `PENDENCIAS.md`: a dívida "moderação só humana e reativa" de
      `chat-de-grupo-e-acao` fecha **parcialmente**; escrever o que continua
      aberto
- [x] 7.4 `MAPA-DE-DADOS.md` **não** muda: confirmar que nenhuma coluna nova de
      pessoa foi criada, e registrar essa conferência

## 8. Fechamento

- [x] 8.1 Gates com números reais: `flutter analyze` (0 issues), `flutter test
      test/unit test/widget` (contagem), `dart test test/integration` com
      `supabase start` (contagem), `flutter build web --release`
- [x] 8.2 Rodar a skill `openspec-converge` e resolver o que ela achar
      — duas passagens: 5 achados na 1, 3 na 2, todos fechados

## Convergence 1

- [x] **CRITICAL** Fechar o bypass do limite de ritmo por `created_at` forjado —
      per `intervalo-entre-mensagens` → "O limite vale no banco, não na tela" e
      o cenário "Chamada direta à API", (`contradicts`).
      **Medido em 2026-08-16**, pela API real (PostgREST, sessão `authenticated`
      de verdade): **30 mensagens inseridas em segundos, ZERO recusas**, bastando
      mandar `"created_at": "2020-01-01T00:00:00Z"` no corpo do `insert`. O
      gatilho `mensagens_ritmo_de_envio` conta `max(created_at)` e `count(*)`
      das linhas **existentes** dentro da janela; linha gravada com data antiga
      nasce fora da janela, então nem o intervalo nem o teto voltam a ver nada.
      Causa: `authenticated` tem `insert` em **todas as 8 colunas** de
      `mensagens` — `created_at`, `id` e `removida_por` inclusive (medido em
      `information_schema.column_privileges`). O `grant` é de
      `chat-de-grupo-e-acao` e nunca teve recorte.
      Conserto, e o precedente é desta base: `revoke insert on public.mensagens
      from authenticated` seguido de `grant insert (grupo_id, acao_id, autor_id,
      texto)`, no molde de `20260811160000_grant_update_perfis_por_coluna.sql` —
      grant de coluna restringe a lista do `insert`, e policy com `with check`
      não restringiria. **O app não precisa mudar**: `ChatRepository.send`
      (`chat_repository.dart:162-167`) já manda exatamente essas quatro colunas.
      Vale carimbar `new.created_at := now()` no gatilho também, como cinto e
      suspensório — mas o grant é o conserto, porque ele também fecha
      `removida_por` forjado no insert.
      O teste tem de rodar pela API (`limites_de_chat_test.dart`), não pela
      conexão direta: como `postgres` o grant não se aplica e o caso passaria
      verde sobre o defeito.

- [x] Provar o cenário "Mensagens do chat foram expurgadas" — per
      `intervalo-entre-mensagens` → "Nenhum dado novo é guardado para contar o
      ritmo", (`missing`).
      O cenário está escrito na spec e **nenhum teste o exercita** (`grep`
      por `expurg` em `ritmo_de_mensagem_test.dart` e `limites_de_chat_test.dart`
      devolve zero). É a consequência aceita do desenho: com o teto atingido num
      chat de Ação, rodar `expurgar_mensagens_de_acao()` tem de fazer o envio
      voltar a ser aceito, porque não há mais o que contar. Sem o teste, a
      afirmação da spec é só uma frase.

- [x] Exercitar o filtro de palavra num chat de **Ação** — per
      `filtro-de-palavra-em-mensagem` → "Mensagem com palavra bloqueada é
      recusada na escrita", (`missing`).
      `filtro_palavra_mensagem_test.dart` só usa Grupo. O gatilho é indiferente
      ao espaço (lê `new.texto`), então o risco é baixo — mas o ritmo, que tem a
      mesma cara, foi medido nos dois e o filtro não. Um caso, no arquivo que já
      existe.

- [x] Limpar a faixa de palavra bloqueada quando a pessoa edita o texto — per
      `filtro-de-palavra-em-mensagem` → "Quem escreveu fica sabendo qual palavra
      barrou", (`partial`).
      `chat_page.dart`: a recusa por `blockedWord` não tem `retryAfter`, então
      não há relógio para apagá-la — `_refusal` fica na tela até um envio dar
      certo ou a pessoa sair. A faixa diz "a palavra X não é aceita, troque essa
      parte", e continua dizendo isso depois de a pessoa ter trocado. Conserto:
      um listener no `_controller` que chama `_clearRefusal()` quando
      `_refusal.kind == blockedWord` e o texto mudou.

- [x] **Decidir** (não consertar): a denúncia não tem limite de ritmo —
      per `intervalo-entre-mensagens`, escopo, (`unrequested`).
      O chat ganhou teto e intervalo; `denuncias_mensagem` ganhou só o filtro de
      palavra. É coerente com o design ("denunciar não é conversar, e um limite
      aqui protegeria quem está sendo denunciado"), e está escrito assim em
      `chat_repository.dart`. Mas o `motivo` é texto livre lido por quem modera,
      e nada impede mil denúncias em um minuto. Não é defeito desta change —
      é uma decisão que ninguém tomou por escrito. Registrar em `PENDENCIAS.md`
      ou decidir aqui.

## Convergence 2

- [x] **CRITICAL** Traduzir três identificadores Dart em português — per
      Constituição, Princípio I "Linguagem Ubíqua do Domínio"
      (NON-NEGOTIABLE), (`contradicts`).
      Medido em 2026-08-17, varrendo os sítios de declaração dos arquivos que
      esta change tocou:
      `test/integration/filtro_palavra_mensagem_test.dart:164` `leituraDireta`,
      `test/integration/limites_de_chat_test.dart:209` `erro` e
      `:240` `aceitas`.
      A regra vale para código de TESTE tanto quanto para produção — só o *nome
      do arquivo* de teste é exceção declarada (`CLAUDE.md`, "Idioma do
      código"). Traduções, do glossário: `leituraDireta` → `directRead`,
      `erro` → `error`, `aceitas` → `accepted`. Falha em silêncio: código em
      português roda igual, passa no `flutter analyze` e passa nos testes.

- [x] Não relatar falha de envio para mensagem que já foi gravada — per
      `intervalo-entre-mensagens` → "A recusa por ritmo diz quanto falta
      esperar", (`partial`).
      **A causa raiz é de `chat-de-grupo-e-acao`; foi esta change que a tornou
      visível.** `ChatRepository.send` faz duas idas ao servidor: o `insert`, e
      depois `_withAuthorNames`, que resolve o nome do autor por
      `perfil_publico`. O `insert` commita sozinho — medido em 2026-08-17, a
      contagem do Grupo foi de 1 para 2 antes de qualquer passo seguinte. E
      `_withAuthorNames` (`chat_repository.dart:70-93`) **não tem `catch`**:
      qualquer falha ali sobe, `ChatNotifier.send` propaga, e `_send` cai no
      ramo genérico — "Não deu pra enviar agora. Tente de novo."
      A mensagem foi. A pessoa tenta de novo, e agora leva **PT425 "espere 3
      segundos"** (medido) sobre uma mensagem que já está no chat. Antes do
      limite de ritmo o reenvio duplicava em silêncio; agora produz uma recusa
      que ninguém entende.
      Conserto, e a decisão já foi tomada nesta mesma classe vinte linhas
      abaixo: `withAuthorName` (singular) tem `try/catch` com o comentário
      "Sem o nome a mensagem ainda é legível; sem a mensagem, não". Aplicar o
      mesmo a `_withAuthorNames` — nome não resolvido vira `Message` sem
      `authorName`, e o envio é sucesso porque foi sucesso.
      NÃO MEDIDO: a falha do `perfil_publico` em si. Tentei induzi-la revogando
      `execute` de `authenticated` e não induziu — aquela função tem `anon=X`
      explícito (exceção declarada em `inventario_superficie_anon_test.dart`),
      então continua chamável. As duas pontas estão medidas; o meio está lido.

- [x] Fechar o beco da recusa de ritmo sem `hint` — per
      `intervalo-entre-mensagens` → "a tela DEVE impedir o reenvio até lá",
      (`partial`).
      `chat_page.dart`, `_applyRefusal`: com `retryAfter` nulo — `hint` ausente
      ou ilegível, o caso que `SendRefusal._seconds` trata de propósito — não há
      relógio, então `_remaining` fica nulo e a faixa **nunca some**. Editar o
      texto também não a apaga: `_onTextChanged` só limpa `blockedWord`. Fica
      "Espere um instante para enviar outra mensagem" na tela até um envio dar
      certo ou a pessoa sair.
      Deixar o envio ABERTO nesse caso está certo (a tela não sabe até quando),
      e é só a faixa que precisa expirar. `recusa_de_envio_test.dart` já cobre
      `retryAfter` nulo na FRASE; falta cobrir no estado da tela.

## Convergence 3

- [x] Aplicar o filtro de palavra também no `update` do `motivo` — per
      `filtro-de-palavra-em-mensagem` → "O motivo de uma denúncia passa pelo
      mesmo filtro", (`partial`).
      Medido em 2026-08-17, como `authenticated`, pelo caminho de verdade: o
      dono do Grupo reescreveu o `motivo` de uma denúncia limpa para
      `"seu zumaxo"` — palavra da lista — e o banco **ACEITOU**.
      `denuncias_mensagem_filtro_de_palavra_trigger` é `before INSERT` e mais
      nada (`pg_trigger`, um único gatilho na tabela), e `authenticated` tem
      `update` em `motivo` (`information_schema.column_privileges`), liberado
      pela policy `denuncias_mensagem_update_autoridade`.
      O contraste é o que torna isto nítido: a mesma tentativa em
      `mensagens.texto` foi **recusada**, porque `mensagens_so_remove` guarda
      as colunas uma a uma. A tabela irmã nunca ganhou o equivalente.
      Conserto: o gatilho passa a `before insert or update`.
      **ARMADILHA, e ela é o motivo de esta tarefa carregar mais que o defeito:**
      precisa de `when (new.motivo is distinct from old.motivo)`. Sem isso,
      `resolveReport` — que só toca `estado` e `resolvida_em` — reavaliaria um
      `motivo` antigo, e uma denúncia gravada ANTES de a palavra entrar na lista
      passaria a ser impossível de resolver. A moderação travaria justamente nos
      casos mais velhos.

- [x] **Registrar em `PENDENCIAS.md`** (não consertar aqui): quem modera pode
      reescrever a denúncia dos outros — fora do escopo desta change,
      (`unrequested`).
      Medido no mesmo ensaio: o dono do Grupo trocou `denunciante_id` da
      denúncia para si mesmo, e o banco **ACEITOU**. `authenticated` tem
      `update` em `id`, `mensagem_id`, `created_at`, `denunciante_id` e
      `motivo`, e não há gatilho recortando coluna.
      Contradiz o que a própria migration de `chat-de-grupo-e-acao` afirma —
      "o `motivo` escrito por quem denunciou é o que fica como registro do
      caso" — e o que os Termos dizem sobre a denúncia ser vista só por quem a
      resolve. A causa raiz é daquela change, não desta: o `grant update` sem
      recorte e a ausência de um `denuncias_mensagem_so_resolve` no molde de
      `mensagens_so_remove`.
      Esta change conserta só a metade que é dela (o filtro no `update`). O
      recorte de coluna é comportamento novo sobre requirement de outra
      capability, e comportamento novo nasce em spec.
