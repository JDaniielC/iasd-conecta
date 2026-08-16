-- Change fechar-superficie-anon, parte 1 de 2 — o `execute` das funções.
--
-- POR QUE ISTO EXISTE
-- `anon` é a role que o PostgREST usa em requisição SEM `Authorization`, e a
-- chave que a alcança vai dentro do JavaScript publicado. Seis funções
-- `security definer` estavam chamáveis por ela sem que ninguém tivesse
-- decidido isso. Medido em 2026-08-16 contra o banco local.
--
-- A ARMADILHA, e ela tem DUAS formas — a segunda é a que passa batida:
--
--   1. `grant execute ... to authenticated` ACRESCENTA um privilégio. Não
--      substitui o que já estava lá. Sem `revoke ... from public` antes, o
--      padrão do Postgres continua de pé. Foi o caso de `declarar_lideranca`,
--      `decidir_lideranca` e `fechar_rodada_se_devido`.
--
--   2. Função que nunca recebeu grant NENHUM também é chamável por todo mundo,
--      e não há linha de `grant` no diff para chamar atenção. Foi o caso de
--      `autor_de_mudanca`, `nome_valido` e `versao_texto_legal_vigente`.
--
-- O sinal genérico, para procurar em qualquer migration:
--   * `proacl` com uma entrada começando em `=` (nada antes do sinal) é o grant
--     a PUBLIC — forma 1;
--   * `proacl` NULO é o mesmo por omissão — forma 2, e é a mais fácil de não
--     ver, porque "sem ACL" soa como "sem privilégio" e é o oposto.
--
-- Consulta que acha as duas de uma vez, e que o teste de inventário desta
-- change roda a cada execução da suíte:
--   select proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
--   where n.nspname = 'public' and has_function_privilege('anon', p.oid, 'execute');
--
-- QUEM NÃO É TOCADO AQUI, e é decisão e não esquecimento:
--   `perfil_publico(uuid)`, `acao_encerrada(uuid)`, `acao_encerrada(timestamptz)`
--   e `limiar_crianca()` têm `anon=X` EXPLÍCITO no ACL. Alguém escreveu aquele
--   grant de propósito. Elas entram na lista de exceções do teste de
--   inventário, com o motivo ao lado — declaradas, não omitidas.
--
--   `unaccent*` pertence à extensão e ao `supabase_admin`. Mexer no ACL dela
--   quebra a extensão.

-- ---------------------------------------------------------------------------
-- 1. Forma 2 — nunca tiveram grant, herdaram PUBLIC
-- ---------------------------------------------------------------------------
-- Estas precisam do `grant` depois do `revoke`: sem ele, quem usa o app perde
-- a função junto com `anon`. É a diferença em relação ao bloco 2 abaixo.

-- `autor_de_mudanca()` devolve o Perfil da sessão. Para `anon`, `auth.uid()` é
-- nulo e ela já devolvia vazio — o risco aqui é zero, e ela está na lista pelo
-- mesmo motivo que as outras: o padrão concedeu, ninguém decidiu.
revoke execute on function public.autor_de_mudanca() from public;
grant execute on function public.autor_de_mudanca() to authenticated;

-- `nome_valido(text)` é a que dói, e o achado é de 2026-08-16.
--
-- Ela é `security definer` porque lê `palavras_bloqueadas`, que tem RLS e
-- NENHUMA policy: `anon` lendo a tabela direto leva `42501 permission denied`.
-- A lista está escondida de propósito.
--
-- Só que a função aceitava a pergunta. Como `anon`, sem sessão nenhuma:
--   nome_valido('idiota')      -> false
--   nome_valido('burro')       -> false
--   nome_valido('estupido')    -> false
--   nome_valido('Maria Silva') -> true
-- Quatro chamadas sobre uma lista de cinco palavras. A tabela recusar leitura
-- direta não protege nada enquanto a função responder a quem quer que pergunte:
-- sonda-se um termo por chamada e a lista sai inteira.
--
-- ELA CONTINUA `security definer`, e trocar para `invoker` seria o conserto
-- errado: sem privilégio para ler a lista, ela passaria a devolver "válido"
-- para tudo e a validação de nome sumiria EM SILÊNCIO — o modo de falha que
-- 20260806090000_nome_valido_security_definer.sql foi escrita para eliminar. O
-- defeito era quem podia perguntar, não a função.
revoke execute on function public.nome_valido(text) from public;
grant execute on function public.nome_valido(text) to authenticated;

-- `versao_texto_legal_vigente()` é `invoker` — a RLS de `versoes_texto_legal`
-- vale para ela. Está aqui pela forma 2 assim mesmo: o piso de privilégio é o
-- mesmo, e deixá-la de fora ensinaria que `invoker` dispensa a regra.
revoke execute on function public.versao_texto_legal_vigente() from public;
grant execute on function public.versao_texto_legal_vigente() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Forma 1 — grant sem revoke
-- ---------------------------------------------------------------------------
-- Sem `grant` depois: estas TRÊS já têm `authenticated=X` no ACL. Repetir o
-- grant não faria mal, e é justamente por isso que não se repete — a linha a
-- mais sugeriria que o `revoke` tirou de `authenticated`, e ele não tira.

revoke execute on function public.declarar_lideranca(uuid, integer) from public;
revoke execute on function public.decidir_lideranca(uuid, boolean) from public;

-- `fechar_rodada_se_devido` é a pior das seis e merece o parágrafo.
--
-- Ela ESCREVE — fecha Rodada de votação, apura os votos e grava a vencedora — e
-- o caminho de "fechar Rodada vencida" não confere `auth.uid()`; só o caminho
-- `p_forcar` confere. Qualquer pessoa com `curl` e a chave publicável fechava
-- Rodada vencida de qualquer Grupo, sem login.
--
-- O dano de dado é limitado: o segundo gatilho do app faria o mesmo assim que
-- alguém abrisse `/acoes`. Mas escrita destrutiva disparável por não
-- autenticado não é o que esta função dizia oferecer, e é o mesmo achado que o
-- `pentest-etico` mediu em `expurgar_mensagens_de_acao()` em 14/08.
revoke execute on function public.fechar_rodada_se_devido(uuid, boolean) from public;
