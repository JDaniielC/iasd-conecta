-- Change filtro-e-intervalo-de-mensagem — as duas portas que a moderação
-- reativa de `chat-de-grupo-e-acao` deixou abertas.
--
-- POR QUE ISTO EXISTE
-- Naquela change a moderação é HUMANA e REATIVA: a mensagem ofensiva fica no ar
-- até alguém denunciar e o dono do Grupo abrir o app. Duas consequências que
-- nada barrava:
--
--   1. Nada barra a palavra na ENTRADA. `nome_valido()` existe, mas casa por
--      TRECHO (`like '%' || palavra || '%'`,
--      20260806090000_nome_valido_security_definer.sql:38-41) sobre uma lista
--      calibrada para nome de cadastro. Em texto corrido, trecho produz falso
--      positivo — a palavra proibida dentro de outra palavra legítima — e a
--      lista de nomes não é a lista de conversa.
--   2. Nada limita o RITMO. Uma pessoa enche o chat de um Grupo em segundos, e
--      a remoção é uma a uma.
--
-- A recusa acontece na ESCRITA, nunca na exibição. O canal de tempo real
-- entrega a linha assim que ela existe: uma mensagem gravada e escondida depois
-- já foi lida por quem estava com o chat aberto.
--
-- MIGRATION PURAMENTE ADITIVA. A lista nasce VAZIA, e com lista vazia toda
-- mensagem passa — o comportamento é idêntico ao de antes desta change, então
-- ela pode subir antes de a lista ser definida sem janela em que o chat quebre.

-- ---------------------------------------------------------------------------
-- 1. A lista da conversa, SEPARADA da lista de nomes
-- ---------------------------------------------------------------------------
-- Tabela própria e não uma coluna `escopo` em `palavras_bloqueadas`: além de
-- alterar tabela que hoje sustenta um `check` de `perfis`, a REGRA DE CASAMENTO
-- é diferente entre os dois usos — trecho para nome, palavra inteira para
-- conversa. Duas regras sobre uma tabela é onde a próxima pessoa erra qual das
-- duas está aplicando.
create table public.palavras_bloqueadas_mensagem (
  palavra text primary key,

  -- METACARACTERE É BUG DE DISPONIBILIDADE, não de estilo. A palavra entra
  -- dentro de uma expressão regular (ver `palavra_bloqueada_em`); um `(` solto
  -- na lista faz o Postgres levantar erro de sintaxe de regex em TODA inserção
  -- de mensagem do app, não só na que contivesse a palavra. A constraint
  -- transforma isso em recusa na hora de editar a lista, que é onde há alguém
  -- olhando.
  constraint palavras_bloqueadas_mensagem_sem_metacaractere
    check (palavra ~ '^[[:alpha:] -]+$'),

  -- Uma letra só casaria a inicial de qualquer frase que a tivesse isolada.
  constraint palavras_bloqueadas_mensagem_tamanho
    check (length(btrim(palavra)) >= 2)
);

comment on table public.palavras_bloqueadas_mensagem is
  'Lista de palavras que o distrito não aceita em CONVERSA. Separada de '
  'palavras_bloqueadas (que valida nome de Perfil) porque a regra de casamento '
  'é outra: aqui é palavra inteira, lá é trecho. O padrão aceitável num nome de '
  'cadastro é mais estrito que numa conversa entre adultos, e misturar as duas '
  'listas obriga a escolher um dos dois errados. Change '
  'filtro-e-intervalo-de-mensagem.';

-- RLS LIGADA E NENHUMA POLICY, e a AUSÊNCIA é o mecanismo — nem para
-- Administrador do distrito. Some-se a isso a ausência de `grant select`: são
-- duas barreiras, e é de propósito. Sem o grant, `anon`/`authenticated` levam
-- `42501 permission denied`; se algum dia alguém conceder o grant achando que
-- resolve um bug, a RLS sem policy segura e a leitura devolve zero linhas.
--
-- Uma lista legível é o roteiro de como contorná-la.
--
-- A lista se administra FORA do app, como a de nomes: não há tela de
-- administração, e isso é decisão, não pendência.
alter table public.palavras_bloqueadas_mensagem enable row level security;

-- ---------------------------------------------------------------------------
-- 2. `palavra_bloqueada_em(text)` — devolve a palavra, não um booleano
-- ---------------------------------------------------------------------------
-- Devolver a palavra é o que permite a recusa ser CORRIGÍVEL. Não vaza a lista:
-- só sai palavra que já estava no texto enviado — quem a leu acabou de
-- digitá-la. Recusa sem nome é recusa que a pessoa não sabe corrigir, e ela
-- reenvia até desistir.
--
-- `\y` é a fronteira de palavra do Postgres, e `~` (regex) em vez de `like` é
-- exatamente a diferença que separa esta lista da de nomes. Custo assumido:
-- regex não usa índice. A lista é de dezenas de palavras num distrito, e a
-- alternativa (`to_tsvector`) traria dicionário e stemming, que decidem
-- sozinhos coisas que esta lista precisa decidir explicitamente.
--
-- `security definer` com `search_path` fixo pelo motivo já escrito em
-- 20260806090000: como `invoker`, a função leria a tabela sob RLS, enxergaria
-- ZERO LINHAS — que o Postgres não trata como erro — e passaria a aceitar tudo.
-- A moderação sumiria sem nenhum erro no app e sem nenhum teste vermelho.
-- `extensions` na lista porque `unaccent` pode morar em `public` ou em
-- `extensions` conforme a extensão foi criada.
create function public.palavra_bloqueada_em(p_texto text)
returns text
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select b.palavra
  from public.palavras_bloqueadas_mensagem b
  where unaccent(lower(p_texto)) ~ ('\y' || unaccent(lower(b.palavra)) || '\y')
  limit 1;
$$;

comment on function public.palavra_bloqueada_em(text) is
  'A palavra da lista de conversa que aparece no texto, ou null quando ele está '
  'limpo. Casa por PALAVRA INTEIRA, ignorando maiúsculas e acentos. Change '
  'filtro-e-intervalo-de-mensagem.';

-- SEM GRANT NENHUM, e isto é o oposto do que se fez com `nome_valido`.
--
-- `nome_valido` precisa ser chamável pelo `check` de `perfis`, que roda no
-- contexto de quem insere — por isso ela tem `grant execute to authenticated`,
-- e a consequência aceita lá é que uma sessão pode adivinhar a lista de nomes
-- uma palavra por vez. Aqui não há essa obrigação: quem chama esta função é
-- gatilho `security definer`, que roda como o dono e não precisa de privilégio
-- de ninguém. Deixar a função inalcançável fecha o ataque de dicionário que a
-- outra lista ainda tem em aberto.
--
-- `revoke ... from public` e NÃO simples ausência de grant: função nova no
-- Postgres nasce chamável por PUBLIC, com `proacl` NULO. É a forma 2 da
-- armadilha descrita em 20260816120000_revogar_execute_de_public.sql — a que
-- não deixa linha de `grant` no diff para chamar atenção.
revoke execute on function public.palavra_bloqueada_em(text) from public;

-- ---------------------------------------------------------------------------
-- 3. Os números do ritmo, como CONSTANTE NOMEADA
-- ---------------------------------------------------------------------------
-- ESCOLHA, NÃO MEDIÇÃO — e está escrito aqui para ninguém confundir uma coisa
-- com a outra depois. Três segundos não atrapalha conversa real e transforma
-- "encher o chat" em trabalho manual longo; 20 em 5 minutos é acima do ritmo de
-- qualquer conversa de combinação observável neste app. Trocar é uma linha aqui
-- e um número no Dart, e o teste de integração falha se os dois divergirem.
--
-- Funções e não literais espalhados: o gatilho lê daqui, e o teste que compara
-- com as constantes do Dart lê daqui também. Um número escrito em dois lugares
-- é um número que vai divergir.
--
-- SEM GRANT — o cliente NÃO lê estes números do banco. Ele os conhece por
-- constante própria, conferida contra estas por teste. Uma consulta a mais em
-- toda abertura de chat para ler dois inteiros que mudam quase nunca é custo
-- que não se paga.
create function public.mensagem_intervalo_minimo()
returns interval language sql immutable as $$ select interval '3 seconds' $$;

create function public.mensagem_janela_do_teto()
returns interval language sql immutable as $$ select interval '5 minutes' $$;

create function public.mensagem_teto_na_janela()
returns integer language sql immutable as $$ select 20 $$;

revoke execute on function public.mensagem_intervalo_minimo() from public;
revoke execute on function public.mensagem_janela_do_teto() from public;
revoke execute on function public.mensagem_teto_na_janela() from public;

comment on function public.mensagem_intervalo_minimo() is
  'Intervalo mínimo entre duas mensagens da mesma pessoa no mesmo chat. Escolha, '
  'não medição. O Dart tem a cópia em lib/features/chat/domain/chat_limits.dart '
  'e um teste de integração falha se as duas divergirem.';

-- O índice que a filtragem POR AUTOR pede. Os de `chat-de-grupo-e-acao` são
-- `(grupo_id, created_at desc)` e `(acao_id, created_at desc)`: servem para
-- desenhar a conversa, não para contar o que UMA pessoa escreveu nela.
create index mensagens_por_autor on public.mensagens (autor_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 4. Os três códigos de erro
-- ---------------------------------------------------------------------------
-- TRÊS CÓDIGOS DISTINTOS, para o cliente diferenciar as causas SEM interpretar
-- texto de mensagem de erro. Texto se traduz, se reescreve e se quebra em
-- silêncio; código não.
--
--   PT422  palavra bloqueada        (o conteúdo é o problema)
--   PT425  cedo demais              (intervalo mínimo — HTTP 425 Too Early)
--   PT429  mensagens demais         (teto na janela — HTTP 429)
--
-- O prefixo `PT` não é enfeite: o PostgREST lê os três últimos dígitos de um
-- SQLSTATE `PTxxx` e devolve AQUELE código HTTP. Um SQLSTATE inventado fora
-- dessa família (`IA001` e afins) chega ao cliente com o código certo no corpo,
-- mas como HTTP 500 — e recusa esperada que sobe como erro de servidor
-- envenena log e alarme de produção.
--
-- O `hint` carrega o dado que a tela precisa, também sem interpretar texto:
-- a PALAVRA no caso do filtro, os SEGUNDOS que faltam nos dois de ritmo.

-- ---------------------------------------------------------------------------
-- 5. Gatilho de filtro, em `mensagens` e em `denuncias_mensagem`
-- ---------------------------------------------------------------------------
-- Gatilho e não `check constraint`, mesmo sendo o `check` mais declarativo: a
-- mensagem de erro de um `check` violado não carrega QUAL palavra casou — só o
-- nome da constraint —, e a recusa sem nome é justamente o desenho que esta
-- change recusou.
--
-- `security definer` para poder chamar `palavra_bloqueada_em` sem que ela
-- precise de grant a papel nenhum. Ver o bloco 2.
create function public.mensagens_filtro_de_palavra()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_palavra text;
begin
  v_palavra := public.palavra_bloqueada_em(new.texto);
  if v_palavra is not null then
    raise exception
      'a mensagem tem uma palavra que este distrito não aceita: %', v_palavra
      using errcode = 'PT422', hint = v_palavra;
  end if;
  return new;
end;
$$;

-- ENTRA AO LADO de `mensagens_so_remove_trigger`, que é `before update` e
-- continua intocado. Este é `before insert`: são momentos diferentes e regras
-- diferentes.
--
-- O NOME importa. Gatilhos `before` de uma mesma tabela disparam em ordem
-- ALFABÉTICA, e `f` vem antes de `r`: o filtro roda antes do ritmo. É a ordem
-- certa — quando a mensagem tem palavra bloqueada E chegou cedo demais, a
-- recusa que a pessoa consegue agir é a da palavra. E como o filtro aborta
-- antes, o ritmo nem chega a tomar a trava.
create trigger mensagens_filtro_de_palavra_trigger
  before insert on public.mensagens
  for each row
  execute function public.mensagens_filtro_de_palavra();

-- O MESMO filtro no `motivo` da denúncia. Sem ele, o campo de denúncia vira a
-- via aberta que o chat deixou de ser — e ele é lido por quem modera.
create function public.denuncias_mensagem_filtro_de_palavra()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_palavra text;
begin
  v_palavra := public.palavra_bloqueada_em(new.motivo);
  if v_palavra is not null then
    raise exception
      'o motivo tem uma palavra que este distrito não aceita: %', v_palavra
      using errcode = 'PT422', hint = v_palavra;
  end if;
  return new;
end;
$$;

create trigger denuncias_mensagem_filtro_de_palavra_trigger
  before insert on public.denuncias_mensagem
  for each row
  execute function public.denuncias_mensagem_filtro_de_palavra();

-- ---------------------------------------------------------------------------
-- 6. Gatilho de ritmo — intervalo e teto, SOB TRAVA
-- ---------------------------------------------------------------------------
-- A TRAVA É O PONTO, e sem ela o resto é decoração: duas escritas simultâneas
-- da mesma pessoa leem o mesmo `max(created_at)` e passam as duas. É o mesmo
-- recurso que `confirmacoes_acao_decidir_status` usa para o limite de vagas
-- (20260723230639:35), pelo mesmo motivo.
--
-- Trava na linha de `perfis` DO AUTOR, e não na do Grupo ou da Ação: travar o
-- espaço serializaria o chat inteiro por causa do limite de uma pessoa. Travando
-- o Perfil, só as escritas daquela pessoa se serializam — que é exatamente o
-- conjunto que o limite mede. Duas pessoas conversando nunca esperam uma pela
-- outra.
--
-- `new.autor_id` e não `auth.uid()`: para toda escrita que passa pela API os
-- dois são o mesmo valor — `mensagens_insert_autor` recusa assinar por outro —,
-- mas a semeadura de cenário em teste roda como superusuário, onde `auth.uid()`
-- é nulo e a trava viraria silenciosamente um `perform` sobre zero linhas. A
-- linha que precisa ser travada é a do autor da mensagem, e é ela que está
-- escrita aqui.
--
-- `security definer`: a contagem tem que ser a REAL, não a que a RLS deixa o
-- autor ver. Como `invoker`, uma policy futura mais apertada faria a contagem
-- cair para zero e o limite sumir — sem erro e sem teste vermelho, o modo de
-- falha que este projeto já pagou uma vez.
--
-- NADA É GRAVADO sobre a tentativa recusada. Sem tabela de tentativa, sem
-- contador, sem log: a contagem sai do `created_at` das mensagens que existem.
-- Um contador de tentativa é dado de COMPORTAMENTO — quando esta pessoa tentou
-- falar e quantas vezes —, e o projeto já recusou por escrito criar dado desse
-- tipo por conveniência (lib/features/news/data/news_repository.dart:7-16).
--
-- Consequência aceita: quando as mensagens de uma Ação expiram, o limite
-- daquele chat zera. Chat expirado não é chat que se possa encher.
create function public.mensagens_ritmo_de_envio()
returns trigger
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_intervalo interval := public.mensagem_intervalo_minimo();
  v_janela    interval := public.mensagem_janela_do_teto();
  v_teto      integer  := public.mensagem_teto_na_janela();
  v_ultima    timestamptz;
  v_primeira  timestamptz;
  v_quantas   integer;
  v_faltam    integer;
begin
  perform 1 from public.perfis where id = new.autor_id for update;

  -- Uma varredura só, restrita à janela: fora dela nada interessa nem para o
  -- intervalo (3s cabe em 5min) nem para o teto.
  select max(m.created_at), min(m.created_at), count(*)
    into v_ultima, v_primeira, v_quantas
  from public.mensagens m
  where m.autor_id = new.autor_id
    and m.created_at > now() - v_janela
    and ((new.grupo_id is not null and m.grupo_id = new.grupo_id)
      or (new.acao_id  is not null and m.acao_id  = new.acao_id));

  if v_ultima is not null and v_ultima > now() - v_intervalo then
    -- `ceil`: faltando 0,2 s, dizer "0 segundos" e recusar de novo é pior do
    -- que arredondar para cima e a pessoa esperar um instante a mais.
    v_faltam := ceil(extract(epoch from (v_ultima + v_intervalo - now())));
    raise exception 'espere % segundo(s) para enviar outra mensagem', v_faltam
      using errcode = 'PT425', hint = v_faltam::text;
  end if;

  if v_quantas >= v_teto then
    -- O teto libera quando a MAIS ANTIGA da janela sai dela.
    v_faltam := ceil(extract(epoch from (v_primeira + v_janela - now())));
    raise exception
      'você já enviou % mensagens nesta conversa nos últimos minutos', v_quantas
      using errcode = 'PT429', hint = v_faltam::text;
  end if;

  return new;
end;
$$;

create trigger mensagens_ritmo_de_envio_trigger
  before insert on public.mensagens
  for each row
  execute function public.mensagens_ritmo_de_envio();
