-- Change mensagem-fixada — a ÚNICA exceção ao prazo de 30 dias do chat de Ação.
--
-- POR QUE ISTO EXISTE
-- Duas coisas se perdem no chat que `chat-de-grupo-e-acao` entrega. O que
-- importa afunda — "o ponto de encontro mudou" fica a quarenta mensagens de
-- distância de quem abre a tela na véspera. E a conversa de Ação some inteira
-- em 30 dias, levando junto a combinação que precisava sobreviver ao encontro.
--
-- O QUE ISTO CUSTA, e está escrito aqui porque é o item de peso desta change:
-- depois desta migration, "as mensagens da Ação são apagadas em 30 dias" é
-- FALSO sem ressalva. A promessa vira "30 dias, salvo o que estiver fixado,
-- com teto de 3 por chat" — e a Política de Privacidade precisa dizer isso, ou
-- o app promete uma coisa e o `where` do expurgo faz outra.
--
-- ROLLBACK NÃO É SEM PERDA. Reverter (drop das duas colunas, gatilho e expurgo
-- de volta ao que eram) faz o expurgo seguinte apagar toda mensagem fixada de
-- Ação já vencida — exatamente o que a fixação protegia.

-- ---------------------------------------------------------------------------
-- 1. As duas colunas
-- ---------------------------------------------------------------------------
-- Duas colunas em `mensagens`, e NÃO uma tabela `mensagens_fixadas`. A fixação
-- é atributo de uma mensagem, sempre 0 ou 1 por linha, e o expurgo precisa dela
-- no mesmo `where` — com tabela separada, o `delete` do expurgo viraria um
-- `not exists`.
--
-- `fixada_por` referencia `perfis(id)` como `removida_por`, e pelo mesmo
-- motivo: a anonimização de conta propaga sozinha.
alter table public.mensagens
  add column fixada_em  timestamptz,
  add column fixada_por uuid references public.perfis(id),
  -- As duas andam juntas, e o `check` diz isso de forma declarativa em vez de
  -- espalhar `:= null` pelo gatilho. Fixada sem quem fixou é registro pela
  -- metade; `fixada_por` sem `fixada_em` é uma fixação que não existe.
  add constraint mensagens_fixada_completa
    check ((fixada_em is null) = (fixada_por is null));

comment on column public.mensagens.fixada_em is
  'Instante da fixação. Não nulo é a EXCEÇÃO ao prazo de 30 dias: '
  '`expurgar_mensagens_de_acao()` não apaga linha fixada. Desfixar devolve a '
  'mensagem ao prazo imediatamente, sem carência nova — a vencida sai no '
  'expurgo seguinte. Change mensagem-fixada.';

comment on column public.mensagens.fixada_por is
  'Quem fixou. Fixar é da autoridade do espaço; DESFIXAR é dela ou do autor da '
  'mensagem — sem esse caminho, o prazo do que uma pessoa escreveu passaria a '
  'depender de outra indefinidamente. Zerada junto com `fixada_em` quando a '
  'mensagem vira lápide. Change mensagem-fixada.';

-- O `select` e o `update` de `authenticated` são grants de TABELA
-- (20260813200000:328), e grant de tabela alcança coluna acrescentada depois —
-- as duas novas já nascem legíveis e graváveis. O `insert` é que foi recortado
-- por coluna em 20260817120000, então mensagem NÃO nasce fixada pelo cliente:
-- fixar é `update`, sempre. Conferido em `information_schema.column_privileges`
-- pelo teste de privilégio, não presumido.

-- Índice parcial: as consultas de fixada são "as fixadas DESTE chat", nunca uma
-- varredura por `fixada_em`. Parcial porque a esmagadora maioria das linhas tem
-- a coluna nula, e o gatilho de teto conta por espaço a cada fixação.
create index mensagens_fixadas_do_grupo
  on public.mensagens (grupo_id, fixada_em desc)
  where fixada_em is not null;

create index mensagens_fixadas_da_acao
  on public.mensagens (acao_id, fixada_em desc)
  where fixada_em is not null;

-- ---------------------------------------------------------------------------
-- 2. O teto, como CONSTANTE NOMEADA
-- ---------------------------------------------------------------------------
-- TRÊS É ESCOLHA, NÃO MEDIÇÃO, e está escrito para ninguém confundir uma coisa
-- com a outra depois: três cabe numa faixa recolhida de tela de celular e força
-- escolher o que importa. Trocar é uma linha aqui e um número no Dart
-- (`ChatLimits.pinnedCeiling`), e o teste de integração falha se divergirem.
--
-- Função e não literal espalhado, mesmo padrão de `mensagem_teto_na_janela()`
-- (20260816160000:148): o gatilho lê daqui, e o teste que compara com o Dart lê
-- daqui também. Um número escrito em dois lugares é um número que vai divergir.
--
-- SEM GRANT — o cliente não lê este número do banco. Ele o conhece por
-- constante própria, conferida contra esta por teste.
create function public.mensagem_teto_de_fixadas()
returns integer language sql immutable as $$ select 3 $$;

revoke execute on function public.mensagem_teto_de_fixadas() from public;

comment on function public.mensagem_teto_de_fixadas() is
  'Quantas mensagens cabem fixadas no mesmo chat. Escolha, não medição — sem '
  'teto, fixar vira uma forma de desligar a retenção da conversa inteira. O '
  'Dart tem a cópia em lib/features/chat/domain/chat_limits.dart e um teste de '
  'integração falha se as duas divergirem.';

-- ---------------------------------------------------------------------------
-- 3. O gatilho `mensagens_so_remove`, agora com dois ofícios
-- ---------------------------------------------------------------------------
-- ESTE É O ÚNICO PONTO EM QUE ESTA CHANGE TOCA CÓDIGO DE `chat-de-grupo-e-acao`,
-- e a leitura do gatilho original (tarefa 1.1) corrigiu o plano que o design
-- trazia. O design falava em "acrescentar as duas colunas à lista de colunas
-- que o gatilho permite alterar". Não existe tal lista: o gatilho de
-- 20260813200000 tem uma lista de colunas IMUTÁVEIS mais a regra
--
--     if new.texto is not null then raise 'o único update permitido ... é a remoção'
--
-- que exige que TODO `update` esvazie o texto. Acrescentar coluna a uma lista
-- que não existe não faria fixar funcionar: fixar mantém o texto.
--
-- A alteração real é separar as duas operações que agora passam por aqui:
--
--   REMOÇÃO — mexe em `texto`/`removida_em`/`removida_por`. Continua valendo a
--             regra de antes, agora escrita como "texto só pode ir para nulo"
--             em vez de "texto tem que ser nulo": um `update` que não toca em
--             `texto` nenhum deixou de ser uma remoção malfeita.
--   FIXAÇÃO — mexe em `fixada_em`/`fixada_por`, e não toca no texto.
--
-- Uma trava de edição continua sendo uma só, e é esta. A alternativa recusada
-- era uma função `security definer` que fixasse por fora, sem mexer no gatilho:
-- contornar a própria trava para não editá-la deixa duas regras sobre a mesma
-- tabela, e a segunda é invisível para quem lê a primeira.
--
-- PASSOU A SER `security definer`, e o motivo escrito aqui é o segundo — o
-- primeiro estava ERRADO e a medição o desmentiu (convergência 2 desta change).
--
-- O que este comentário dizia até 2026-08-17: que o Administrador do distrito
-- modera sem ler o chat de Ação, contaria zero fixadas e passaria por cima do
-- teto. **É falso.** Medido como `authenticated` de verdade:
-- `pode_ver_chat_acao` = `t` para ele, `pode_moderar_espaco` = `t`, e a
-- contagem dele como invoker é 2 de 2. O braço de Administrador está em
-- `pode_ver_chat_acao` desde 20260813200000 — foi acrescentado lá justamente
-- porque a falta dele era um defeito, e este comentário nasceu repetindo a
-- versão antiga daquele arquivo. Hoje NINGUÉM modera sem ler: os quatro braços
-- de `pode_moderar_espaco` estão todos cobertos pelas duas funções de leitura.
--
-- O MOTIVO VERDADEIRO é o mesmo de `maior_de_idade()` e
-- `mensagens_ritmo_de_envio()`, e não depende de quem é quem hoje: como
-- `invoker`, a contagem do teto seria a que a RLS deixa quem fixa enxergar, e
-- passaria a depender de `mensagens_select_do_espaco` continuar tão larga
-- quanto é. Uma mudança futura que apertasse aquela policy faria a contagem
-- cair, o teto afrouxar, e nada disso apareceria — sem erro, sem log e sem
-- teste vermelho. O teto é uma promessa que está no texto legal desde a versão
-- 1.7; ele não pode ser função de uma policy de leitura.
--
-- Escrito assim porque o privilégio é real: `security definer` aqui bypassa a
-- RLS. Quem o lê precisa do motivo que se sustenta, não de um exemplo que
-- deixou de existir.
--
-- `auth.uid()` continua valendo dentro de `security definer`: ele lê o claim da
-- sessão, não o papel efetivo. Quem decide QUEM pode escrever na linha continua
-- sendo a policy `mensagens_update_autor_ou_autoridade`, avaliada contra a
-- sessão de verdade antes de o gatilho rodar.
create or replace function public.mensagens_so_remove()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_fixando    boolean;
  v_desfixando boolean;
  v_teto       integer;
  v_quantas    integer;
begin
  if new.id is distinct from old.id
     or new.grupo_id is distinct from old.grupo_id
     or new.acao_id is distinct from old.acao_id
     or new.autor_id is distinct from old.autor_id
     or new.created_at is distinct from old.created_at then
    raise exception 'mensagem enviada não se edita';
  end if;

  -- `is distinct from` e não `is not null`: o que o gatilho recusa é REESCREVER
  -- o texto. Mantê-lo como está — o que toda fixação faz — não é edição, e
  -- esvaziá-lo continua sendo o único caminho permitido.
  if new.texto is distinct from old.texto and new.texto is not null then
    raise exception 'o único update permitido em mensagem é a remoção';
  end if;

  -- A quarta combinação — texto preenchido COM `removida_em` — o banco nunca
  -- produziu, e `message.dart` conta com isso para derivar as três lápides sem
  -- coluna de estado. Antes desta change, a regra acima bastava para impedi-la.
  -- Agora que um `update` pode não tocar em `texto`, ela precisa ser dita.
  if (new.removida_em is distinct from old.removida_em
      or new.removida_por is distinct from old.removida_por)
     and new.texto is not null then
    raise exception 'remoção sem esvaziar o texto não é remoção';
  end if;

  -- Remoção acontece UMA vez. Um segundo `update` — outro moderador clicando
  -- depois, ou o mesmo duas vezes — não reescreve quem removeu nem quando: o
  -- registro é do ato, e o ato foi um só. Sem isto, quem chegasse por último
  -- levaria o crédito (ou a culpa) de uma decisão que não tomou.
  if old.removida_em is not null then
    new.removida_em := old.removida_em;
    new.removida_por := old.removida_por;
  end if;

  v_fixando    := old.fixada_em is null     and new.fixada_em is not null;
  v_desfixando := old.fixada_em is not null and new.fixada_em is null;

  -- FIXAR LÁPIDE É RECUSADO, e não aceito sobre nada. Achado na convergência 1
  -- desta change: sem esta guarda, o bloco final zerava a fixação porque
  -- `texto is null`, o `update` devolvia UMA LINHA AFETADA, e
  -- `ChatRepository.pinMessage` — que confere `affected.isEmpty` — reportava
  -- sucesso sobre nada. É a mesma família de defeito que "recusa de RLS é
  -- ausência, não erro", pelo avesso: aceitação declarada sobre um efeito que
  -- não aconteceu.
  --
  -- A guarda é sobre o PEDIDO, não sobre o efeito: quem manda `fixada_em` numa
  -- lápide pediu para fixar e merece a recusa. O desfixe automático do bloco
  -- final continua mudo — lá o gatilho age por conta própria, e quem remove
  -- não pediu para desfixar.
  --
  -- `PT403` e NÃO `PT409`: o cliente lê a causa do código, e `PT409` é o teto.
  -- Mandá-lo aqui faria a tela dizer "este chat já tem 3 fixadas, desfixe uma"
  -- sobre uma mensagem que não tem texto — recusa correta com explicação
  -- falsa, que é pior do que a frase genérica. `PT403` não é decodificado por
  -- `SendRefusal`, então a tela cai em "Você não pode fixar esta mensagem".
  if v_fixando and new.texto is null then
    raise exception 'mensagem sem texto não se fixa'
      using errcode = 'PT403';
  end if;

  -- Fixar mensagem JÁ FIXADA não muda nada, mesma escolha da remoção e pelo
  -- mesmo motivo: quem fixou foi quem fixou primeiro. Sem isto, um segundo
  -- toque reescreveria `fixada_por` e a ordem da faixa.
  if old.fixada_em is not null and new.fixada_em is not null then
    new.fixada_em := old.fixada_em;
    new.fixada_por := old.fixada_por;
  end if;

  -- FIXAR é da autoridade do espaço, e só dela: fixar decide o que todo mundo
  -- vê primeiro, e tira a mensagem do prazo de expiração. `pode_moderar_espaco`
  -- e não `pode_moderar_mensagem` — a segunda tem o braço do autor, que aqui
  -- não entra. Predicado reusado, não reescrito.
  if v_fixando then
    if not public.pode_moderar_espaco(new.grupo_id, new.acao_id) then
      raise exception 'só quem tem autoridade neste espaço pode fixar mensagem'
        using errcode = 'PT403';
    end if;

    -- A TRAVA É O PONTO, e sem ela o teto é decoração: duas fixações
    -- simultâneas leem a mesma contagem e passam as duas.
    --
    -- Trava no ESPAÇO e não no Perfil, ao contrário de
    -- `mensagens_ritmo_de_envio` (20260816160000) — lá o recurso disputado é o
    -- ritmo de UMA pessoa; aqui é o teto DO CHAT, e duas pessoas com autoridade
    -- fixando ao mesmo tempo é exatamente o par que precisa serializar.
    --
    -- A trava vem ANTES da contagem. Depois dela seria contar sobre um estado
    -- que a outra transação ainda pode mudar.
    if new.grupo_id is not null then
      perform 1 from public.grupos where id = new.grupo_id for update;
    else
      perform 1 from public.acoes where id = new.acao_id for update;
    end if;

    -- A própria linha não entra na conta: neste braço ela ainda está com
    -- `fixada_em` nulo na tabela — o gatilho é `before`.
    select count(*) into v_quantas
    from public.mensagens m
    where m.fixada_em is not null
      and ((new.grupo_id is not null and m.grupo_id = new.grupo_id)
        or (new.acao_id  is not null and m.acao_id  = new.acao_id));

    v_teto := public.mensagem_teto_de_fixadas();
    if v_quantas >= v_teto then
      -- `hint` com o teto, para a tela dizer "desfixe uma das 3" sem
      -- interpretar texto de mensagem de erro. Mesma disciplina dos três
      -- códigos de 20260816160000.
      raise exception
        'este chat já tem % mensagens fixadas, o máximo', v_quantas
        using errcode = 'PT409', hint = v_teto::text;
    end if;

    -- QUEM FIXA É QUEM ESTÁ FIXANDO — recusar, não carimbar por cima. Mesmo
    -- raciocínio que 20260817120000 usou para NÃO reescrever `created_at` em
    -- gatilho: reescrever em silêncio um valor que alguém mandou é pior do que
    -- recusar, porque quem mandou não fica sabendo que foi ignorado. Sem esta
    -- linha, quem tem autoridade atribuiria a fixação a outra pessoa.
    if new.fixada_por is distinct from auth.uid() then
      raise exception 'a fixação se registra em nome de quem fixa'
        using errcode = 'PT403';
    end if;

    -- E QUANDO É AGORA. Achado na convergência 2: `fixada_por` era conferido
    -- contra `auth.uid()` e `fixada_em` não era conferido contra nada —
    -- medido, `'2020-01-01'` e `'2099-12-31'` foram os DOIS aceitos. Duas
    -- consequências, e a segunda é a que pesa: a faixa ordena por `fixada_em
    -- desc`, então uma data futura prende a mensagem no alto para sempre; e a
    -- Política de Privacidade 1.7 passou a declarar que o app guarda "quem
    -- fixou e quando", o que torna este campo uma afirmação ao titular.
    --
    -- Recusa e não carimbo, pelo mesmo motivo da linha acima.
    --
    -- A TOLERÂNCIA É DE RELÓGIO, e é escolha, não medição. O cliente manda
    -- `DateTime.now().toUtc()`, e o relógio do aparelho não é o do servidor;
    -- cinco minutos é folga para desencontro comum sem deixar espaço para
    -- escolher posição na faixa. Ela mora só aqui — o Dart não precisa dela,
    -- porque o valor que ele manda já é o relógio dele.
    --
    -- Restauração de dump não passa por aqui: ela é `insert`, e este gatilho é
    -- `before update`. Semeadura de cenário com data antiga também não — o
    -- `insert` não alcança estas colunas (o grant de 20260817120000 recorta
    -- `insert` em quatro colunas, e nenhuma é de fixação).
    if new.fixada_em < now() - interval '5 minutes'
       or new.fixada_em > now() + interval '5 minutes' then
      raise exception 'a fixação se registra na hora em que acontece'
        using errcode = 'PT403';
    end if;
  end if;

  -- DESFIXAR é da autoridade do espaço OU do autor da mensagem, e o braço do
  -- autor é o que devolve a ele o controle do prazo do que escreveu. Sem ele, o
  -- prazo de uma mensagem passaria a depender de outra pessoa indefinidamente,
  -- e o direito de eliminação dela dependeria de pedir.
  --
  -- Escrito no gatilho e não em segunda policy: duas policies sobre o mesmo
  -- `update` se combinam por `or`, e a mais larga venceria as duas.
  --
  -- `pode_moderar_mensagem` é exatamente "autor OU autoridade do espaço".
  if v_desfixando then
    -- `coalesce`, e não o predicado cru: `pode_moderar_mensagem` compara
    -- `auth.uid() = autor_id`, e sem sessão isso é NULO, não `false`. Um
    -- `if not null then` NÃO dispara — a recusa passaria batido justamente
    -- para quem chegasse sem identidade. `pode_moderar_espaco` não tem esse
    -- buraco (começa com `maior_de_idade() and`), mas depender disso é
    -- depender do corpo de outra função.
    if not coalesce(
             public.pode_moderar_mensagem(
               old.autor_id, new.grupo_id, new.acao_id),
             false) then
      raise exception 'só a autoridade do espaço ou o autor podem desfixar'
        using errcode = 'PT403';
    end if;
  end if;

  -- LÁPIDE NÃO FICA FIXADA. Quando o texto vai a nulo — moderação ou
  -- `excluir_conta` —, a fixação cai na MESMA linha e na mesma transação. Uma
  -- marca de mensagem removida no topo do chat ocupa vaga do teto e não informa
  -- nada, e a linha volta a contar prazo como qualquer outra.
  --
  -- POR ÚLTIMO e sem checagem de autoridade, de propósito: quem desfixa aqui é
  -- o gatilho, não quem mandou o `update`. Um moderador que remove mensagem
  -- fixada de outra pessoa não está pedindo para desfixar, e não deveria
  -- precisar de permissão para um efeito que ele não escolheu.
  --
  -- Alternativa recusada: um segundo gatilho `after update`. Precisaria de um
  -- `update` na mesma tabela que acabou de disparar o gatilho — recursão a
  -- desarmar, para fazer numa segunda passada o que a primeira já podia fazer.
  --
  -- Consequência para `excluir_conta`: o `update ... set texto = null` que ela
  -- já faz desfixa junto, sem uma linha nova naquela função. A transação única
  -- continua única.
  if new.texto is null then
    new.fixada_em := null;
    new.fixada_por := null;
  end if;

  return new;
end;
$$;

-- O gatilho não é recriado: `create or replace function` troca o corpo, e
-- `mensagens_so_remove_trigger` continua apontando para a mesma função.

-- ---------------------------------------------------------------------------
-- 4. O expurgo ganha UMA condição
-- ---------------------------------------------------------------------------
-- `and m.fixada_em is null`, e nada mais muda: o agendamento do `pg_cron`, o
-- segundo gatilho no app (`ChatRepository.fetchHistory`) e a contagem devolvida
-- continuam como estavam.
--
-- Daqui cai fora, sem precisar de código, o comportamento que a spec exige:
-- mensagem desfixada DEPOIS do prazo é apagada no expurgo seguinte, sem
-- carência nova. O `where` olha o estado de agora, não a história dele.
create or replace function public.expurgar_mensagens_de_acao()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.mensagens m
  using public.acoes a
  where m.acao_id = a.id
    and now() > a.data_hora + interval '30 days'
    and m.fixada_em is null;
  get diagnostics v_apagadas = row_count;
  return v_apagadas;
end;
$$;

comment on function public.expurgar_mensagens_de_acao() is
  'Apaga as mensagens de Ação passados 30 dias da data do encontro, EXCETO as '
  'fixadas (change mensagem-fixada). A exceção está declarada na Política de '
  'Privacidade — mantê-la só aqui torna a Política falsa.';
