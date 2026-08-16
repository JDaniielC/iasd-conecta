## 1. Os dois papéis, num lugar só

- [x] 1.1 `createTestVisitor(conn, id)` em `db_test_helper.dart`: `auth.users`
      com `is_anonymous = true` e **nenhuma** linha em `perfis`. Comentário
      dizendo em que difere de `createTestProfileWithoutAccount` — aquele é
      Perfil sem Conta, tem `perfis`, e é outra pessoa
- [x] 1.2 `asVisitor(conn, uid, action)` em `acao_restrita_helper.dart` passa a
      ser `asUser` com um `uid` sem `perfis`. Comentário registrando que ela
      **mudou de significado** nesta change, e por quê: `signInAnonymously` no
      arranque faz todo Visitante chegar como `authenticated`
- [x] 1.3 `asAnon(conn, action)` novo, com o corpo da `asVisitor` antiga
      (`set role anon`). Comentário dizendo que é a superfície sem
      `Authorization`, não uma categoria de pessoa
- [x] 1.4 Conferir os identificadores em inglês contra o glossário do
      `CONTEXT.md` — `Visitante` é `Visitor`, e `anon` é nome de papel do
      Postgres, não termo de domínio

## 2. Varredura — um arquivo por vez, com a suíte inteira ao fim de cada um

Para cada ponto, responder por escrito no comentário do teste: *provava o que a
pessoa sem cadastro vê, ou o que uma requisição sem credencial alcança?*
Substituição mecânica é o modo de errar aqui.

- [x] 2.1 `visibilidade_liderancas_test.dart` — 7 pontos, o maior. Apagar a
      cópia local de `asVisitor` e usar a compartilhada
- [x] 2.2 `votos_visibilidade_test.dart` — 4 pontos. Apagar a cópia local
      `_asVisitor`
- [x] 2.3 `acoes_select_publico_test.dart` e `grupos_select_publico_test.dart`
      — 3 pontos cada. Os nomes dizem "papel anon (Visitante)"; o requisito
      (FR-005, FR-006, FR-010) é sobre quem não tem cadastro
- [x] 2.4 `mudancas_rls_test.dart` — 3 pontos
- [x] 2.5 `acao_restrita_invisivel_test.dart` e
      `acao_restrita_presencas_test.dart` — 2 pontos cada
- [x] 2.6 `chat_corte_de_idade_test.dart` — 2 pontos, e é o caso que precisa
      dos DOIS papéis: o Visitante não vê a conversa por não ter Perfil, e sem
      sessão não alcança as funções do chat. Hoje é uma afirmação só —
      **virou dois testes irmãos**: "Visitante sem cadastro não passa no corte,
      e lê 0" (`maior_de_idade()` = false, 0 mensagens, resposta é lista vazia)
      e "sem sessão nenhuma — nem chama, nem lê" (`ServerException` nas duas)
- [x] 2.7 `church_archive_visibility_test.dart` e `notificacao_anon_test.dart`
      — 2 pontos cada. O segundo é `asAnon` pelo nome do arquivo, e vale
      conferir se não quer os dois
- [x] 2.8 Um ponto cada: `acao_restrita_rodada_test.dart`,
      `acao_restrita_saida_do_grupo_test.dart`,
      `arquivar_grupo_lideranca_test.dart`,
      `chat_privilegio_funcao_test.dart`,
      `contatos_para_convite_isolamento_test.dart`,
      `convite_leitura_restrita_test.dart`, `foto_capa_orfao_test.dart`,
      `leadership_public_current_test.dart`
- [x] 2.9 Conferir que a contagem fecha: `grep -c` por `asVisitor(` e `asAnon(`
      soma 39, e nenhuma cópia local de helper sobrou — **33 `asVisitor` e 9
      `asAnon`** contando definições, delegações e o arquivo novo de contraste.
      Nenhum `set role anon` fora do helper (os 4 que o `grep` acha são
      comentário). As duas cópias locais viraram delegação de uma linha ao
      helper compartilhado, em vez de sumirem: elas preservam a assinatura curta
      dos 11 pontos daqueles arquivos, e não são uma segunda definição

## 3. O que a varredura achar

- [x] 3.1 Listar os testes que ficaram vermelhos ao passar a exercer a policy
      de verdade, com o número medido de cada um. Vermelho aqui é requisito
      que nunca teve prova, não acidente — **nenhum ficou vermelho**. Três
      deixaram de passar pelo motivo errado e continuam verdes pelo certo:
      `FR-011: Visitante não consegue confirmar presença` e
      `Visitante não consegue inserir grupo` paravam na falta de `grant` e
      agora exercem a FK contra `perfis`; `FR-007: Igreja arquivada` passa a
      exercer a policy. Um vermelho apareceu ao ESCREVER o teste de contraste,
      não na varredura — ver 4.1
- [x] 3.2 Para cada um, classificar pelo design (§ "O que fazer com um vermelho
      que aparecer"): teste errado (conserta aqui, com a medição no
      comentário), policy errada (registra em `PENDENCIAS.md`, conserto é
      change própria), ou nenhum dos dois (a change para) — **vazio por
      construção**: a varredura não produziu vermelho nenhum (ver 3.1). Os
      vermelhos desta change vieram todos das convergências, não da varredura,
      e nenhum era defeito de policy: dois eram teste medindo a barreira errada
      (convergência 1), um era o helper novo herdando identidade (convergência
      3), e um era colisão de uid que eu mesmo introduzi (convergência 4).
      Nenhum caiu no desfecho 2 do design
- [x] 3.3 **Nenhuma migration e nenhuma linha de `lib/` nesta change.**
      Conferir o diff final e registrar a conferência — `git diff main -- lib/
      supabase/` volta vazio

## 4. Prova de que a separação vale

- [x] 4.1 Teste novo, ou asserção nova num existente, provando os dois papéis
      lado a lado no MESMO cenário: o Visitante lê os Grupos, e sem sessão a
      resposta é diferente. Sem esse contraste, alguém volta a fundir os dois
      e nada fica vermelho — `visitante_nao_e_anon_test.dart`, 3 casos.
      **O contraste sobre `grupos` NÃO existe hoje** e a asserção falhou ao ser
      escrita: `anon` lê `grupos` exatamente como o Visitante, porque a policy
      ainda o endereça. Escrevê-la seria escrever o resultado da change
      seguinte neste arquivo. O contraste usa `notificacoes`, onde os dois já
      diferem — Visitante alcança e a policy devolve 0; sem sessão a barreira é
      o `grant`, uma camada antes. Provado carregador por mutação: trocar o
      `asVisitor` por `asAnon` deixa vermelho
- [x] 4.2 Provar que `is_anonymous = true` importa: uma regra que lê a coluna
      (`declarar_lideranca`) recusa o Visitante de teste. Se passar, o helper
      está criando um Usuário que o app não produz
- [x] 4.3 Anotar a contagem final de `asVisitor` e de `asAnon` na suíte — 33 e 9

## 5. Fechamento

- [x] 5.1 Gates com números reais: `flutter analyze` 0 issues; `flutter test
      test/unit test/widget` 424 passed; `dart test test/integration` 421
      passed (eram 417 — o teste do chat virou dois e o de contraste tem três);
      `flutter build web --release` ok
- [x] 5.2 Rodar `dart test test/integration` mais de uma vez e conferir que a
      contagem não oscila — passar a exercer a policy expõe a arquivos que
      antes paravam cedo, e a capability cobra determinismo em paralelo — três
      execuções, 418/418 antes do teste de contraste e 421 depois, sem
      oscilação
- [x] 5.3 Rodar a skill `openspec-converge` e resolver o que ela achar — 1
      passada, 3 achados, todos resolvidos. O HIGH virou medição: das 48 cópias
      locais de `asUser`, **16 não devolvem `request.jwt.claims`** e 32
      devolvem. A requirement não foi estreitada — o risco é real e já está
      documentado dentro de uma das 32; ela passou a declarar o débito com a
      contagem, e proíbe a 49ª. Registrado em `PENDENCIAS.md` § 2.20
- [ ] 5.4 Retomar `change/fechar-superficie-anon`, que está parada com as duas
      migrations escritas e verificadas

## Convergence 1

- [x] **HIGH** — Reconciliar a requirement "Cada papel de teste tem uma
      definição só" com a suíte, que tem **48 cópias locais de `asUser`** além
      da compartilhada — per essa requirement (`contradicts`). Medido em
      2026-08-16: `grep` por `Future<void> asUser(` e `Future<void> _asUser(`
      em `test/integration/` acha 48 arquivos, cada um com a sua. A requirement
      que esta change escreve diz "as formas de assumir um papel no banco DEVEM
      viver num lugar só", e o `proposal.md` desta change exclui varrer o resto
      da suíte nos Non-Goals. Escrita e escopo discordam, e arquivar assim
      deixa uma requirement falsa no dia em que entra em `specs/`. Duas saídas:
      estreitar a requirement aos papéis que esta change define — Visitante e
      sem-sessão, que são os que a confusão atingiu — ou mantê-la ampla e
      registrar a dívida das 48 em `PENDENCIAS.md`, com a contagem. A primeira
      é mais honesta: `asUser` nunca foi ambíguo, e uniformizá-lo é limpeza,
      não conserto de premissa.
- [x] **MEDIUM** — Renomear os dois testes que se chamam "sessão anônima" e
      rodam `asAnon` — per "Teste da superfície sem credencial", cláusula "e o
      nome do teste diz isso" (`partial`).
      `convite_leitura_restrita_test.dart:84` ("sessão anônima não lê convite
      nenhum") e `contatos_para_convite_isolamento_test.dart:60` ("sessão
      anônima nem alcança a listagem"). **"Sessão anônima" é exatamente o que
      `signInAnonymously` produz** — é o Visitante, que tem sessão. Os corpos
      já foram corrigidos para `asAnon`, mas os nomes guardam a ambiguidade que
      a change existe para matar, e é pelo nome que a próxima pessoa escolhe o
      helper.
- [x] **MEDIUM** — Acrescentar a asserção de Visitante nesses mesmos dois
      arquivos — per "Recusa que acontece antes da regra" (`partial`). Medido
      em 2026-08-16: o Visitante **alcança** `convites_acao` e a policy devolve
      **0 linhas**; `contatos_para_convite` devolve **0 linhas** para ele. Sob
      `asAnon` os dois param no `grant`, que é a barreira anterior — o cenário
      diz que um teste assim "não serve como prova daquela regra". Hoje a regra
      "quem não tem cadastro não vê convite" não tem prova nenhuma: só o
      privilégio tem. Os dois arquivos ficam com um teste por barreira, como
      `chat_corte_de_idade_test` já ficou.

## Convergence 2

- [x] **LOW** — Tirar o uid do Visitante de `_allUids` nos cinco arquivos onde
      ele entrou, e limpá-lo explicitamente — per "Cada papel de teste tem uma
      definição só", a divergência invisível que ela descreve (`partial`).
      Medido em 2026-08-16: o uid fica **dentro de `_allUids` em 5 arquivos**
      (`acao_restrita_invisivel`, `acao_restrita_presencas`,
      `acao_restrita_rodada`, `acao_restrita_saida_do_grupo`,
      `chat_corte_de_idade`) e **fora em 12**. Hoje é inofensivo — nesses cinco
      `_allUids` só alimenta o laço de `cleanUpTestUser`. A armadilha é o nome:
      em `mudancas_rls_test` uma lista chamada `_allUids` **cria Perfil** para
      cada uid, e foi por isso que ali o Visitante ficou de fora com comentário.
      Mesmo identificador, dois contratos, e a diferença é invisível — quem
      acrescentar um laço de criação num daqueles cinco dá Perfil ao Visitante,
      e a partir daí `asVisitor` prova um Usuário cadastrado com o nome errado.
      É a inconsistência que esta própria change introduziu, e o conserto são
      cinco edições de duas linhas.

## Convergence 3

- [x] **HIGH** — Fazer `asAnon` limpar `request.jwt.claims` ANTES de entrar —
      per "A suíte exercita o papel que o app usa" (`contradicts`), e é o
      cenário "Uma cópia esquece de desfazer o que fez" acontecendo dentro da
      definição compartilhada que esta change escreveu.
      Medido em 2026-08-16: deixando claims para trás como as 16 cópias locais
      deixam, e entrando em `asAnon`, `auth.uid()` devolveu
      `fd000000-0000-0000-0000-000000000001` em vez de `null`. O teste que diz
      provar "sem sessão" roda como `anon` **com a identidade de outra
      pessoa**, e toda policy que usa `auth.uid()` responde como se ela
      estivesse ali — o "não" que o teste observa pode ser o "não" dado a
      outrem, ou pior, um "sim".
      A proteção existia e eu a apaguei: `church_archive_visibility_test` fazia
      `reset role; reset request.jwt.claims;` antes do `set role anon`, com o
      comentário explicando (`:27-29`, "achado durante a validação manual desta
      feature"). Ao converter o arquivo para `asVisitor`, as duas linhas saíram
      e ninguém as reescreveu no helper.
      Consertar em `asAnon`, não nos chamadores — é o motivo de a definição ser
      uma só. E teste de regressão que reproduza a sujeira de propósito:
      `set` claims, `reset role` sozinho, entrar em `asAnon`, exigir
      `auth.uid()` nulo. Sem ele o conserto volta a sumir na próxima limpeza.

## Convergence 4

- [x] **MEDIUM** — Trocar o uid de `visitante_nao_e_anon_test.dart`, que colide
      com outro arquivo — per a requirement de determinismo em paralelo de
      `suite-de-integracao` (`contradicts`). Medido em 2026-08-16: 283 uids
      declarados na suíte e **18 colisões entre arquivos**.
      `f7000000-0000-0000-0000-000000000001` está em
      `visitante_nao_e_anon_test.dart:_uidOwner` **e** em
      `notificacao_acao_cancelada_test.dart:_uidDona`. O arquivo é desta change,
      e a suíte roda os arquivos em paralelo contra o mesmo banco: o
      `cleanUpTestUser` de um apaga o Perfil que o outro está usando no meio do
      teste. Não está mordendo hoje — os inserts são `on conflict do nothing` e
      as limpezas moram no `tearDownAll` —, e é exatamente o modo de falha que
      a capability existe para proibir.
- [x] **LOW** — Registrar em `PENDENCIAS.md` as outras **17 colisões de uid**,
      todas anteriores a esta change, com os pares medidos — per a mesma
      requirement (`partial`). Não são desta change e varrê-las é escopo
      próprio: cada par precisa de alguém decidindo qual dos dois arquivos
      muda. Ficam registradas com a contagem e a data, e com a consulta que as
      encontra, para a varredura não ter de redescobri-las.
