## 1. Banco — o `execute` das funções

- [ ] 1.1 Migration com `revoke execute ... from public` nas seis funções
      medidas, e `grant execute ... to authenticated` nas três que nunca
      tiveram grant nenhum (`autor_de_mudanca()`, `nome_valido(text)`,
      `versao_texto_legal_vigente()`). As três que já têm `authenticated` só
      levam o `revoke`
- [ ] 1.2 **Não** tocar em `perfil_publico(uuid)`, `acao_encerrada(...)` (as
      duas sobrecargas) nem `limiar_crianca()`: têm `anon=X` explícito e são
      públicas por desenho. Nem em `unaccent*`, que é da extensão e pertence a
      `supabase_admin`
- [ ] 1.3 Comentário na migration com o sinal genérico — `proacl` começando em
      `=` é grant a `PUBLIC`, e `proacl` **nulo** é o mesmo por omissão, que é
      o caso mais fácil de não ver. Três das seis eram esse caso
- [ ] 1.4 Registrar na migration por que `nome_valido` continua `security
      definer`: como `invoker` ela passaria a devolver "válido" para tudo e a
      validação sumiria em silêncio. O defeito era quem podia perguntar, não a
      função

## 2. Banco — as policies de leitura

- [ ] 2.1 As 13 policies de `select` que hoje endereçam `anon` passam a
      `to authenticated`, uma por vez, com o `using` **inalterado**. Lista
      medida em 2026-08-16: `acoes`, `acoes_sugeridas`,
      `administradores_distrito`, `categorias_grupo`, `confirmacoes_acao`,
      `fotos_capa`, `grupos`, `igrejas`, `liderancas`, `mudancas`,
      `participacoes_grupo`, `rodadas_votacao`, `versoes_texto_legal`
- [ ] 2.2 Depois — e só depois — `revoke select ... from anon` nas mesmas 13.
      A ordem importa: fazer o `revoke` antes trocaria a resposta de "zero
      linhas" por `42501`, que revela que a tabela existe, e existe teste de
      oráculo nesta base cobrando o contrário
- [ ] 2.3 `votos` tem `grant select` a `anon` e **nenhuma** policy que o
      alcance — a RLS já barra. Revogar o grant assim mesmo, e registrar que é
      defesa em profundidade, não conserto de vazamento
- [ ] 2.4 Comentário na migration com a distinção Visitante × sem sessão e o
      apontamento para `superficie-sem-login`. É a frase que impede a reversão
      por quem ler "Ação é pública inclusive sem login" em `visibilidade-de-acao`

## 3. Prova no banco — inventário, não lista de consertos

- [ ] 3.1 `test/integration/inventario_superficie_anon_test.dart`: enumera toda
      função de `public` com `prorettype <> 'trigger'::regtype` e falha se
      `has_function_privilege('anon', ...)` for verdadeiro para alguma fora da
      lista de exceções. Lista de exceções **no próprio arquivo**, cada linha
      com o motivo ao lado
- [ ] 3.2 No mesmo arquivo: enumera toda policy de `select` de `public` e falha
      se alguma endereçar `anon` ou `PUBLIC` (`polroles = '{0}'::oid[]`) fora
      da lista de exceções
- [ ] 3.3 Terceira asserção: nenhuma tabela de `public` com `grant select` a
      `anon` fora da lista. As três olham barreiras diferentes — privilégio de
      função, papel da policy, e grant de tabela — e fechar duas deixa a
      terceira aberta
- [ ] 3.4 Provar que o inventário DISCRIMINA, por mutação: conceder de volta
      uma função à mão dentro de uma transação com rollback e conferir que o
      teste ficaria vermelho. Anotar o número de itens em cada uma das três
      listas de exceção
- [ ] 3.5 Teste do oráculo, com número real: como `anon`, `nome_valido` de uma
      palavra da lista é **recusada** (era `false`, medido em 2026-08-16 sobre
      uma lista de 5 palavras). Como `authenticated`, continua respondendo
- [ ] 3.6 Teste de não regressão para quem TEM sessão: um Visitante
      (`authenticated`) continua lendo `grupos`, `acoes`, `fotos_capa`,
      `igrejas` e `categorias_grupo`, e continua enxergando os participantes de
      um Grupo. Sem este contraste, fechar tudo passaria no teste acima

## 4. Prova na tela — o caminho degradado

- [ ] 4.1 Rodar o app com o `signInAnonymously` falhando de propósito e
      confirmar que a Home aparece, **na largura de celular**. É a única
      situação real em que o app é `anon`, e ela nunca foi exercitada — está na
      seção de verificação manual do `PENDENCIAS.md`
- [ ] 4.2 No mesmo estado, tocar uma ação que precisa do banco e confirmar que
      aparece explicação, não tela vazia nem erro de servidor
- [ ] 4.3 Registrar o resultado das duas com o que foi visto, não com "passou".
      Se a Home não aparecer, a change para aqui e o design volta à mesa

## 5. Correção de ledger

- [ ] 5.1 `PENDENCIAS.md` § 2.1: **fechar**, com a medição de 2026-08-16 —
      `authenticated` tem `update` só em `apelido`,
      `consentimento_lgpd_igreja_aceito_em`, `igreja_id`, `nome`, `telefone`, e
      `has_table_privilege(...,'update')` na tabela é `false`. Foi a change
      `endurecer-grant-update-perfis`, de 12/08, e o ledger não foi atualizado
- [ ] 5.2 `PENDENCIAS.md` § 2.18 e § 2.8: fechar as duas apontando para esta
      change, com os números
- [ ] 5.3 `PENDENCIAS.md` § 2.19: **continua aberta**, e escrever por que não
      entrou aqui — é configuração do servidor de Realtime, não `revoke` nem
      policy, e exige outra forma de prova
- [ ] 5.4 `SECURITY-AUDIT.md`: o oráculo de `nome_valido` é achado novo, de
      16/08, e não estava em ledger nenhum. Registrar com as quatro sondagens
      medidas e com a lição — a tabela recusar leitura direta não protege a
      lista enquanto a função aceitar a pergunta
- [ ] 5.5 Conferir que `MAPA-DE-DADOS.md` **não** muda: nenhuma coluna nova,
      nenhum dado novo. Registrar a conferência

## 6. Fechamento

- [ ] 6.1 Conferir os identificadores Dart em inglês no arquivo de teste novo,
      contra o glossário do `CONTEXT.md`. A regra falha em silêncio: código em
      português roda igual e passa no `flutter analyze`
- [ ] 6.2 Gates com números reais: `flutter analyze` (0 issues), `flutter test
      test/unit test/widget` (contagem), `dart test test/integration` com
      `supabase start` (contagem), `flutter build web --release`
- [ ] 6.3 Rodar o agente `pentest-etico` sobre a superfície fechada, com a
      chave publicável e sem `Authorization` — é a forma que achou o precedente
      em 14/08
- [ ] 6.4 Rodar a skill `openspec-converge` e resolver o que ela achar antes de
      arquivar
