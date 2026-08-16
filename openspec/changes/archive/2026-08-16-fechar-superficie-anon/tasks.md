## 1. Banco — o `execute` das funções

- [x] 1.1 Migration com `revoke execute ... from public` nas seis funções
      medidas, e `grant execute ... to authenticated` nas três que nunca
      tiveram grant nenhum (`autor_de_mudanca()`, `nome_valido(text)`,
      `versao_texto_legal_vigente()`). As três que já têm `authenticated` só
      levam o `revoke`
- [x] 1.2 **Não** tocar em `perfil_publico(uuid)`, `acao_encerrada(...)` (as
      duas sobrecargas) nem `limiar_crianca()`: têm `anon=X` explícito e são
      públicas por desenho. Nem em `unaccent*`, que é da extensão e pertence a
      `supabase_admin`
- [x] 1.3 Comentário na migration com o sinal genérico — `proacl` começando em
      `=` é grant a `PUBLIC`, e `proacl` **nulo** é o mesmo por omissão, que é
      o caso mais fácil de não ver. Três das seis eram esse caso
- [x] 1.4 Registrar na migration por que `nome_valido` continua `security
      definer`: como `invoker` ela passaria a devolver "válido" para tudo e a
      validação sumiria em silêncio. O defeito era quem podia perguntar, não a
      função

## 2. Banco — as policies de leitura

- [x] 2.1 As 13 policies de `select` que hoje endereçam `anon` passam a
      `to authenticated`, uma por vez, com o `using` **inalterado**. Lista
      medida em 2026-08-16: `acoes`, `acoes_sugeridas`,
      `administradores_distrito`, `categorias_grupo`, `confirmacoes_acao`,
      `fotos_capa`, `grupos`, `igrejas`, `liderancas`, `mudancas`,
      `participacoes_grupo`, `rodadas_votacao`, `versoes_texto_legal`
- [x] 2.2 Depois — e só depois — `revoke select ... from anon` nas mesmas 13.
      A ordem importa: fazer o `revoke` antes trocaria a resposta de "zero
      linhas" por `42501`, que revela que a tabela existe, e existe teste de
      oráculo nesta base cobrando o contrário
- [x] 2.3 `votos` tem `grant select` a `anon` e **nenhuma** policy que o
      alcance — a RLS já barra. Revogar o grant assim mesmo, e registrar que é
      defesa em profundidade, não conserto de vazamento
- [x] 2.4 Comentário na migration com a distinção Visitante × sem sessão e o
      apontamento para `superficie-sem-login`. É a frase que impede a reversão
      por quem ler "Ação é pública inclusive sem login" em `visibilidade-de-acao`

## 3. Prova no banco — inventário, não lista de consertos

- [x] 3.1 `test/integration/inventario_superficie_anon_test.dart`: enumera toda
      função de `public` com `prorettype <> 'trigger'::regtype` e falha se
      `has_function_privilege('anon', ...)` for verdadeiro para alguma fora da
      lista de exceções. Lista de exceções **no próprio arquivo**, cada linha
      com o motivo ao lado
- [x] 3.2 No mesmo arquivo: enumera toda policy de `select` de `public` e falha
      se alguma endereçar `anon` ou `PUBLIC` (`polroles = '{0}'::oid[]`) fora
      da lista de exceções
- [x] 3.3 Terceira asserção: nenhuma tabela de `public` com `grant select` a
      `anon` fora da lista. As três olham barreiras diferentes — privilégio de
      função, papel da policy, e grant de tabela — e fechar duas deixa a
      terceira aberta
- [x] 3.4 Provar que o inventário DISCRIMINA, por mutação: conceder de volta
      uma função à mão dentro de uma transação com rollback e conferir que o
      teste ficaria vermelho. Anotar o número de itens em cada uma das três
      listas de exceção — as três mutações movem **exatamente um contador
      cada**, medido em 2026-08-16 com rollback: `grant execute` na
      `nome_valido` leva funções de 8 para 9; `alter policy ... to anon` leva
      policies de 0 para 1; `grant select` leva grants de 0 para 1. Depois do
      rollback, 8/0/0 de novo. Listas de exceção: **8 funções, 0 policies, 0
      grants** — a superfície de LEITURA sem sessão foi a zero
- [x] 3.5 Teste do oráculo, com número real: como `anon`, `nome_valido` de uma
      palavra da lista é **recusada** (era `false`, medido em 2026-08-16 sobre
      uma lista de 5 palavras). Como `authenticated`, continua respondendo
- [x] 3.6 Teste de não regressão para quem TEM sessão: um Visitante
      (`authenticated`) continua lendo `grupos`, `acoes`, `fotos_capa`,
      `igrejas` e `categorias_grupo`, e continua enxergando os participantes de
      um Grupo. Sem este contraste, fechar tudo passaria no teste acima

## 4. Prova na tela — o caminho degradado

- [x] 4.1 Rodar o app com o `signInAnonymously` falhando de propósito e
      confirmar que a Home aparece, **na largura de celular**. É a única
      situação real em que o app é `anon`, e ela nunca foi exercitada — está na
      seção de verificação manual do `PENDENCIAS.md` — **a Home aparece**,
      completa: os dois cartões de explicação, "Ver Grupos/Ministérios",
      "Ver Ações", "Novidades" e os dois links legais. Ela ainda se degrada
      sozinha, e para melhor: sem sessão o botão "Criar Perfil" some, restando
      só o que não precisa de banco.
      **A largura de celular NÃO foi verificada** — `resize_window` reporta
      sucesso e `window.innerWidth` continua 1379. É limitação do controle de
      janela, não do app, e fica como verificação manual devida no
      `PENDENCIAS.md`
- [x] 4.2 No mesmo estado, tocar uma ação que precisa do banco e confirmar que
      aparece explicação, não tela vazia nem erro de servidor — `/grupos` com
      **1 Grupo semeado no banco** mostra **"Não deu pra carregar os Grupos
      agora."**. É o ramo `error:`, e é o certo: explicação, não a lista vazia
      que afirmaria falsamente que o distrito não tem Grupo nenhum.
      Ressalva medida: leva **~15 s** até a mensagem, com indicador de carga
      antes. Não é carregamento perpétuo, e é lento
- [x] 4.3 Registrar o resultado das duas com o que foi visto, não com "passou".
      Se a Home não aparecer, a change para aqui e o design volta à mesa — a
      Home apareceu, a change segue.
      **A primeira montagem deste teste estava errada e vale mais que o
      resultado.** Buildei com chave publicável INVÁLIDA para forçar a falha do
      login, e com isso toda requisição morria na autenticação, antes de chegar
      em `anon` — cenário que não existe. A tela mostrava "Nenhum Grupo ainda."
      com 1 Grupo no banco, e eu quase registrei isso como achado da change.
      O cenário real é chave VÁLIDA com login anônimo recusado: refeito
      desligando `enable_anonymous_sign_ins` no `config.toml`, medido no HTTP —
      `signInAnonymously` devolve **422** e `GET /rest/v1/grupos` como `anon`
      devolve **401** com `42501 permission denied for table grupos`.
      Terceira armadilha: a sessão sobrevive no `localStorage` entre builds. Na
      primeira tentativa com chave válida o Grupo apareceu, porque havia
      `sb-127-auth-token` guardado. Só depois de `localStorage.clear()` o
      arranque foi frio de verdade

## 5. Correção de ledger

- [x] 5.1 `PENDENCIAS.md` § 2.1: **fechar**, com a medição de 2026-08-16 —
      `authenticated` tem `update` só em `apelido`,
      `consentimento_lgpd_igreja_aceito_em`, `igreja_id`, `nome`, `telefone`, e
      `has_table_privilege(...,'update')` na tabela é `false`. Foi a change
      `endurecer-grant-update-perfis`, de 12/08, e o ledger não foi atualizado
      — **eu estava errado, e o registro fica**. O ledger JÁ dizia
      "FECHADO em 2026-08-11", no CORPO da entrada. Minha varredura de itens
      abertos olhou só o CABEÇALHO, onde 12 de 24 entradas carregam a marca e a
      2.1 não carregava. O defeito real era de formato, não de conteúdo: a
      marca subiu para o cabeçalho, como nas outras. A medição continua válida
      e confirma o que o corpo já afirmava
- [x] 5.2 `PENDENCIAS.md` § 2.18 e § 2.8: fechar as duas apontando para esta
      change, com os números
- [x] 5.3 `PENDENCIAS.md` § 2.19: **continua aberta**, e escrever por que não
      entrou aqui — é configuração do servidor de Realtime, não `revoke` nem
      policy, e exige outra forma de prova
- [x] 5.4 `SECURITY-AUDIT.md`: o oráculo de `nome_valido` é achado novo, de
      16/08, e não estava em ledger nenhum. Registrar com as quatro sondagens
      medidas e com a lição — a tabela recusar leitura direta não protege a
      lista enquanto a função aceitar a pergunta
- [x] 5.5 Conferir que `MAPA-DE-DADOS.md` **não** muda: nenhuma coluna nova,
      nenhum dado novo. Registrar a conferência — conferido: as duas migrations
      têm **0** ocorrências de `create table` e de `alter table ... add column`.
      Só `revoke`, `grant` e `alter policy ... to`. A change muda quem alcança o
      que já está gravado, não o que se grava

## 6. Fechamento

- [x] 6.1 Conferir os identificadores Dart em inglês no arquivo de teste novo,
      contra o glossário do `CONTEXT.md`. A regra falha em silêncio: código em
      português roda igual e passa no `flutter analyze` — **e falhou**. Os dois
      arquivos novos tinham `abertas`, `naoDeclaradas`, `sobrando`, `erro`,
      `contar`, `tabela`, `coluna`, `linhas`, `igrejas`, `categorias`,
      `palavras`, `termo`, `chamada`. Traduzidos para `reachable`,
      `undeclared`, `staleExceptions`, `error`, `countRows`, `table`, `column`,
      `churches`, `categories`, `words`, `word`, `call`.
      Junto foi `visitante_nao_e_anon_test.dart`, da change anterior, que
      passou pela conferência equivalente dela e tinha `dentro`, `depois`,
      `doVisitante`, `semSessao` — agora `insideAnon`, `afterwards`,
      `fromVisitor`, `withoutSession`. A conferência de lá não pegou; esta
      pegou porque foi feita listando os identificadores, não lendo o arquivo
- [x] 6.2 Gates com números reais: `flutter analyze` **0 issues**; `flutter
      test test/unit test/widget` **424 passed**; `dart test test/integration`
      **444 passed** (eram 424 — 4 do inventário, 15 da superfície e 1 do
      contraste de `grupos`); `flutter build web --release` ok
- [x] 6.3 Rodar o agente `pentest-etico` sobre a superfície fechada, com a
      chave publicável e sem `Authorization` — é a forma que achou o precedente
      em 14/08 — **feito direto, sem o subagente**: as instruções desta sessão
      proíbem invocar subagente sem o usuário pedir, e o valor da tarefa é o
      teste, não quem o roda. Medido em 2026-08-16 com `curl`, chave publicável,
      sem `Authorization`:
      **20/20 tabelas** devolvem `401` com `42501` — inclusive as seis que a
      migration fechou e as que já eram fechadas (`mensagens`, `perfis`,
      `palavras_bloqueadas`, `convites_acao`, `notificacoes`).
      **RPC**: `nome_valido`, `fechar_rodada_se_devido`, `declarar_lideranca`,
      `decidir_lideranca`, `pode_ver_chat_grupo`, `autor_de_mudanca`,
      `versao_texto_legal_vigente`, `expurgar_mensagens_de_acao` e
      `maior_de_idade` -> `401`. `perfil_publico` -> `200 []` e
      `limiar_crianca` -> `200 13`, as duas intencionais.
      **Escrita** em `grupos` e `mensagens` -> `401`. **Embed lateral**
      (`grupos?select=*,participacoes_grupo(*)`) -> `401`.
      Armadilha da própria medição, registrada: a primeira rodada mandou corpo
      vazio nas RPCs com argumento e recebeu `404 PGRST202` — o PostgREST não
      acha a assinatura, e `404` NÃO é prova de fechamento. Refeito com os
      argumentos certos, e aí vieram os `401`.
      **Achado**: `anon` INSERE em `denuncias_imagem` — `23503` de FK, ou seja
      passou pelo grant e pela policy. É intencional (FR-015, denúncia de foto
      sem cadastro, `denuncias_imagem_insert_qualquer` com `with check
      (denunciante_id is null or ...)`), e é **uma só** em toda a base. Mas o
      inventário desta change não a enxerga: ele só olha `select`. Ver a
      convergência
- [x] 6.4 Rodar a skill `openspec-converge` e resolver o que ela achar antes de
      arquivar — 1 passada, 2 achados, ambos resolvidos. O inventário ganhou a
      QUARTA barreira (escrita), com `denuncias_imagem` na lista de exceções e
      o motivo da FR-015; e o ramo `error:` da lista de Grupos ganhou teste,
      porque a verificação de 4.2 foi execução única à mão. Os dois provados
      carregadores por mutação

## Convergence 1

- [x] **MEDIUM** — Escrever o teste do ramo `error:` da lista de Grupos — per
      "O app continua abrindo quando a sessão anônima falha", cenário "A pessoa
      tenta uma ação que precisa do banco nesse estado" (`missing`).
      Medido em 2026-08-16: `grep 'Não deu pra carregar os Grupos'` acha **1
      ocorrência em `lib/`** (`group_list_page.dart:171`) e **0 em `test/`**. O
      cenário foi verificado uma vez, à mão, com o app rodando e o login
      anônimo recusado — e é justamente o caminho que esta change transformou:
      antes, `anon` lia `grupos` e a tela mostrava a lista; agora recebe `401` e
      cai no `error:`. Sem teste, quem trocar aquele ramo por
      `const SizedBox.shrink()` faz a tela voltar a mentir por omissão, e
      nenhum gate acusa.
      A outra metade do requirement — "a tela inicial aparece" — essa tem prova:
      `supabase_bootstrap_test.dart` cobre os três caminhos de `ensureSession`,
      incluindo "não propaga falha do sign-in anônimo".
- [x] **MEDIUM** — Decidir se o inventário cobre ESCRITA, e alinhar a Purpose —
      per a Purpose de `superficie-sem-login`, "o que uma requisição sem sessão
      nenhuma **alcança** do banco" (`partial`).
      As quatro requirements falam de LEITURA — "não entrega dado de pessoa",
      "para cada tabela que PODE ler". O inventário
      (`inventario_superficie_anon_test.dart`) segue isso: as três asserções
      olham privilégio de função, papel de policy de `select`, e `grant select`.
      Escrita não é olhada por ninguém.
      Medido em 2026-08-16, com `curl` sem `Authorization`: `anon` **INSERE** em
      `denuncias_imagem` — resposta `23503`, violação de chave estrangeira, o
      que só acontece depois de passar pelo `grant` e pela policy. É a única em
      toda a base (1 grant de escrita, 1 policy:
      `denuncias_imagem_insert_qualquer`, com `with check (denunciante_id is
      null or denunciante_id = auth.uid())`), e é **intencional** — FR-015,
      denúncia de foto sem cadastro, porque exigir cadastro para denunciar foto
      de menor protegeria o problema.
      Não há vazamento hoje. O que há é uma trava que não tranca a porta que a
      Purpose diz cobrir: uma policy de `insert` para `anon` acrescentada
      amanhã passa por todos os gates. Duas saídas — acrescentar a quarta
      asserção ao inventário, com `denuncias_imagem` na lista de exceções e o
      motivo da FR-015 ao lado; ou estreitar a Purpose para dizer LEITURA, e
      registrar a escrita como fora de escopo. A primeira é mais barata e
      fecha a classe.

## Convergence 2

- [x] **MEDIUM** — Provar que o `revoke` não levou junto quem precisa — per
      "Função nova não nasce chamável por papel público" (`partial`).
      As três funções que ganharam `grant execute ... to authenticated`
      (`autor_de_mudanca`, `nome_valido`, `versao_texto_legal_vigente`) só têm
      teste do lado da RECUSA. Medido em 2026-08-16:
      `grep autor_de_mudanca test/integration/` acha **1 arquivo**,
      `superficie_sem_sessao_test.dart`, e lá ela aparece apenas no caso que
      exige `ServerException` sem sessão.
      O modo de falha é o teste passar pelo motivo errado: se o `grant` tivesse
      sido esquecido em uma delas, ela estaria fechada para TODO MUNDO, o teste
      de recusa continuaria verde, e o app quebraria em produção sem nenhum
      gate acusar. Medido que hoje funcionam — `autor_de_mudanca` devolve o uid
      da sessão, `nome_valido('Maria Silva')` devolve `true`,
      `versao_texto_legal_vigente()` devolve `1.5` —, e é isso que precisa
      virar asserção.
      O par já existe na base como modelo: `chat_privilegio_funcao_test.dart`
      tem "authenticated continua podendo chamar todas", com o comentário
      dizendo exatamente isto — "o `revoke from public` não pode ter levado
      junto quem precisa".
- [x] **LOW** — Dar à lista de escrita a mesma checagem de exceção obsoleta que
      a de funções tem — per a mesma requirement, cláusula da lista de exceções
      (`partial`). `_functionsOpenOnPurpose` é conferida nos dois sentidos: o
      que está aberto fora da lista reprova, e **exceção declarada para função
      que já não está aberta também reprova** (`staleExceptions`), porque ela
      autorizaria dormente a próxima função de mesmo nome.
      `_writesOpenOnPurpose` só tem o primeiro sentido — medido: **0**
      ocorrências de `_writesOpenOnPurpose.keys` no arquivo. Se
      `denuncias_imagem` deixar de aceitar escrita sem sessão, a exceção fica
      lá e passa a ser permissão esquecida.
