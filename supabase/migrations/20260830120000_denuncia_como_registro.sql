-- Change denuncia-como-registro — a denúncia vira registro de verdade.
--
-- POR QUE ISTO EXISTE
-- Os Termos de Uso prometem: "o motivo que você escrever fica registrado
-- como a história do caso, inclusive depois de a mensagem deixar de
-- existir." Medido em 2026-08-17 (PENDENCIAS.md 2.24), como `authenticated`,
-- o dono de um Grupo REESCREVEU o `motivo` de uma denúncia alheia e TROCOU
-- `denunciante_id` para si mesmo — os dois ACEITOS. `denuncias_mensagem`
-- nasceu sem o equivalente de `mensagens_so_remove`.
--
-- Junto, duas dívidas vizinhas nunca decididas sobre a mesma tabela
-- (PENDENCIAS.md 2.23 e 2.14): nada impede a mesma pessoa de denunciar a
-- mesma mensagem mil vezes, e o `motivo` não tinha prazo nem saía com a
-- exclusão de conta — ao contrário do texto das mensagens, que já saía.
--
-- O QUE ISTO CUSTA, e precisa estar escrito: apagar o `motivo` de uma
-- denúncia JULGADA apaga o registro de por que uma mensagem foi removida. O
-- desfecho e o instante permanecem; o texto que os explicava, não. Mesma
-- escolha que a remoção de mensagem já faz.
--
-- MIGRATION ADITIVA, exceto pela recusa nova: `update` de `motivo`,
-- `denunciante_id`, `mensagem_id` ou `created_at` em `denuncias_mensagem`
-- passa a ser recusado. Medido (tarefa 0.3): nenhuma tela do app faz isso —
-- `ChatRepository.resolveReport` manda só `estado`/`resolvida_em`.

-- ---------------------------------------------------------------------------
-- 1. A denúncia registrada não se reescreve
-- ---------------------------------------------------------------------------
-- Molde: `mensagens_so_remove` (20260813200000). O que se copia é a FORMA —
-- comparar coluna a coluna com `is distinct from` e recusar com frase
-- própria — não o `security definer`: `mensagens_so_remove` precisa dele
-- para contar linha protegida por RLS; este gatilho só compara NEW com OLD,
-- não abre linha nenhuma, e privilégio que não é necessário não se pede.
create function public.denuncias_mensagem_so_resolve()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id is distinct from old.id then
    raise exception 'denúncia registrada não muda de identidade';
  end if;
  -- SÓ mensagem_id virar NULL é aceito — nunca apontar para OUTRA mensagem.
  -- A coluna tem `on delete set null` (20260813200000): quando a mensagem
  -- expurga, o Postgres executa exatamente este UPDATE por dentro, como o
  -- gatilho interno da própria FK — e ele passa por este gatilho `before
  -- update` igual a qualquer outro. Sem esta guarda, TODO expurgo de mensagem
  -- denunciada quebrava com "não aponta para outra mensagem", porque para
  -- este gatilho `mensagem_id: X -> null` é indistinguível de `mensagem_id:
  -- X -> Y`. Medido: `chat_expurgo_test.dart` (setUpAll) parava exatamente
  -- aqui antes deste ajuste.
  if new.mensagem_id is not null
     and new.mensagem_id is distinct from old.mensagem_id then
    raise exception 'denúncia registrada não aponta para outra mensagem';
  end if;
  if new.denunciante_id is distinct from old.denunciante_id then
    raise exception 'denúncia registrada não muda de quem denunciou';
  end if;
  -- SÓ o motivo vira NULL é aceito — nunca virar OUTRO texto. É a mesma
  -- forma de `mensagens_so_remove` com `texto` ("só pode ir a NULL"): o
  -- prazo (`expurgar_motivos_de_denuncia()`) e a exclusão de conta do
  -- denunciante zeram o motivo pela MESMA porta que uma reescrita tentaria
  -- usar, e os dois caminhos precisam continuar abertos.
  if new.motivo is not null and new.motivo is distinct from old.motivo then
    raise exception 'motivo de denúncia registrada não se reescreve';
  end if;
  if new.created_at is distinct from old.created_at then
    raise exception 'denúncia registrada não muda de quando foi feita';
  end if;
  return new;
end;
$$;

-- O NOME IMPORTA (tarefa 1.3): gatilhos `before` da mesma tabela disparam em
-- ordem ALFABÉTICA, e já existe `denuncias_mensagem_filtro_de_palavra_no_update`
-- (20260817140000), que só roda `when (new.motivo is distinct from
-- old.motivo)`. "f" vem antes de "s", então o filtro de palavra roda
-- PRIMEIRO neste `update`.
--
-- DECISÃO: deixar nesta ordem, e não forçar um nome que ordene diferente.
-- Depois desta migration, TODO `update` que mude `motivo` para um texto
-- diferente é rejeitado por este gatilho de qualquer forma — o filtro de
-- palavra, ao rodar antes, só decide qual FRASE a pessoa lê no caso raro de
-- alguém tentar reescrever o motivo justamente com uma palavra bloqueada:
-- "palavra não aceita" em vez de "motivo não se reescreve". As duas são
-- recusa correta sobre a MESMA tentativa ilegítima; nenhum cenário da spec
-- depende de qual mensagem aparece nesse cruzamento raro, e nomear o gatilho
-- só para ganhar a ordem alfabética trocaria um nome que descreve o que a
-- função faz por um que descreve quando ela roda.
create trigger denuncias_mensagem_so_resolve_trigger
  before update on public.denuncias_mensagem
  for each row
  execute function public.denuncias_mensagem_so_resolve();

comment on trigger denuncias_mensagem_so_resolve_trigger on public.denuncias_mensagem is
  'Os Termos de Uso prometem: "o motivo que você escrever fica registrado '
  'como a história do caso". Até esta migration a promessa era só do texto — '
  '`authenticated` tinha update liberado em id, mensagem_id, denunciante_id, '
  'motivo e created_at, e reescrever o motivo ou trocar o denunciante era '
  'ACEITO (PENDENCIAS.md 2.24, medido em 2026-08-17). Este gatilho é quem '
  'cumpre a promessa: só o desfecho (estado, resolvida_em) muda depois do '
  'registro, e motivo só pode ir a NULL — nunca virar outro texto. Change '
  'denuncia-como-registro.';

-- ---------------------------------------------------------------------------
-- 2. Uma denúncia PENDENTE por (mensagem, denunciante)
-- ---------------------------------------------------------------------------
-- PARCIAL é o ponto (PENDENCIAS.md 2.23): fora de `pendente`, repetir é
-- legítimo — fato novo depois de um julgamento é outro caso, e a spec diz
-- isso. Um `check` com subconsulta não serve — `check` não enxerga outra
-- linha —, e um gatilho que só contasse abriria a mesma corrida que este
-- índice fecha de graça.
create unique index denuncias_mensagem_pendente_unica
  on public.denuncias_mensagem (mensagem_id, denunciante_id)
  where estado = 'pendente';

comment on index denuncias_mensagem_pendente_unica is
  'Uma denúncia PENDENTE por (mensagem_id, denunciante_id) — não uma para '
  'sempre: fora de pendente, repetir é legítimo (spec moderacao-de-mensagem, '
  '"Denunciar de novo depois do desfecho"). PARCIAL é o ponto: sem o where, '
  'a mesma pessoa não poderia denunciar de novo depois do desfecho. '
  'mensagem_id nulo (denúncia órfã, pós-expurgo) NÃO colide com nulo em '
  'índice único no Postgres — consequência aceita: depois do expurgo a '
  'mesma pessoa poderia abrir outra pendente órfã, mas não há tela que '
  'denuncie mensagem que já não existe, então o caminho não é alcançável '
  'pelo app. Escrito para quem for endurecer isso não descobrir sozinho. '
  'Change denuncia-como-registro.';

-- A recusa do índice cru seria "23505 duplicate key value violates unique
-- constraint" — o cliente não tem como distinguir isso de qualquer outra
-- violação de unicidade do banco. Este gatilho `before insert` cobre o MESMO
-- caso ANTES do índice, com um código de erro da família `PT` (como as três
-- de `filtro-e-intervalo-de-mensagem`), e é `security definer` porque a
-- checagem PRECISA enxergar a denúncia pendente já existente mesmo quando
-- quem denuncia não tem `select` liberado por RLS na tabela — que é o caso
-- comum, já que `denuncias_mensagem_select_autoridade` não alcança quem
-- denunciou.
--
-- O índice continua sendo a garantia ATÔMICA: entre duas inserções
-- concorrentes do mesmo par, é ele — não este gatilho — quem impede as duas
-- de passarem juntas. Este gatilho cobre o caminho comum com mensagem
-- legível; a corrida rara ainda cai no índice, como `23505` cru.
create function public.denuncias_mensagem_unica_pendente()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if new.estado = 'pendente' and exists (
    select 1 from public.denuncias_mensagem
    where mensagem_id = new.mensagem_id
      and denunciante_id = new.denunciante_id
      and estado = 'pendente'
  ) then
    raise exception
      'você já tem uma denúncia pendente sobre esta mensagem'
      using errcode = 'PT423';
  end if;
  return new;
end;
$$;

create trigger denuncias_mensagem_unica_pendente_trigger
  before insert on public.denuncias_mensagem
  for each row
  execute function public.denuncias_mensagem_unica_pendente();

comment on trigger denuncias_mensagem_unica_pendente_trigger on public.denuncias_mensagem is
  'PT423: a mesma pessoa já tem denúncia PENDENTE sobre a mesma mensagem. '
  'Não é limite de ritmo — essa recusa continua não existindo de propósito '
  '(PENDENCIAS.md 2.23) — é impedir repetir a MESMA denúncia sem limitar '
  'quantas mensagens diferentes a pessoa denuncia. O índice '
  'denuncias_mensagem_pendente_unica é quem garante isso de fato; este '
  'gatilho só troca "23505 duplicate key" cru por um código que a tela sabe '
  'ler. Change denuncia-como-registro.';

-- ---------------------------------------------------------------------------
-- 3. O motivo tem prazo, contado do DESFECHO — e sai com a conta de quem
--    denunciou
-- ---------------------------------------------------------------------------
-- 0.1: decidido com o dono do app em 2026-08-30. Trinta dias — o mesmo
-- número que a Política já usa para a mensagem de Ação — para a titular não
-- aprender um segundo prazo. Constante nomeada, no molde de
-- `mensagem_teto_de_fixadas()` (20260817160000).
create function public.denuncia_prazo_do_motivo()
returns interval language sql immutable as $$ select interval '30 days' $$;

revoke execute on function public.denuncia_prazo_do_motivo() from public;

comment on function public.denuncia_prazo_do_motivo() is
  'Prazo do motivo de denúncia, contado do DESFECHO (resolvida_em) — nunca '
  'da criação. Pendente não expira: é a mesma razão de mensagem_id ter '
  '`on delete set null` em vez de cascade — contar da criação apagaria o '
  'motivo de uma denúncia que ninguém julgou, exatamente o resultado que '
  'aquela decisão evitou. Escolha do dono do app (2026-08-30): o mesmo '
  'número que a Política já usa para a mensagem de Ação. Change '
  'denuncia-como-registro.';

-- `motivo` precisa poder ir a NULL para o prazo e a exclusão de conta
-- funcionarem. O `check (length(btrim(motivo, ...)) > 0)` já TOLERA NULL —
-- no Postgres um check que avalia para NULL passa —, então nenhuma outra
-- mudança nele é necessária. O gatilho da seção 1 é quem impede motivo NULO
-- de nascer assim: o `insert` continua exigindo motivo não vazio pelo mesmo
-- `check` de sempre.
alter table public.denuncias_mensagem alter column motivo drop not null;

comment on column public.denuncias_mensagem.motivo is
  'O que quem denunciou escreveu — a história do caso (Termos de Uso). Vira '
  'NULL depois do prazo (denuncia_prazo_do_motivo(), contado do desfecho) ou '
  'da exclusão de conta de quem denunciou: o desfecho e o instante '
  'permanecem, o texto que os explicava, não. NUNCA nasce nulo — o `insert` '
  'continua exigindo motivo não vazio — e denuncias_mensagem_so_resolve_trigger '
  'recusa qualquer update que troque um motivo por OUTRO texto; só a '
  'transição para NULL é aceita. Change denuncia-como-registro.';

-- Molde: `expurgar_mensagens_de_acao()` (20260813200000). `security
-- definer` porque a faxina precisa alcançar toda denúncia julgada,
-- independente de quem a lê pela RLS.
create function public.expurgar_motivos_de_denuncia()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagados integer;
begin
  update public.denuncias_mensagem
  set motivo = null
  where resolvida_em is not null
    and motivo is not null
    and now() > resolvida_em + public.denuncia_prazo_do_motivo();
  get diagnostics v_apagados = row_count;
  return v_apagados;
end;
$$;

comment on function public.expurgar_motivos_de_denuncia() is
  'Apaga o motivo de denúncia COM DESFECHO (resolvida_em não nulo) passada '
  'do prazo. Pendente nunca expira. O prazo é promessa na Política de '
  'Privacidade, então tem DOIS gatilhos, no molde de '
  'expurgar_mensagens_de_acao(): este job de pg_cron e uma chamada do app ao '
  'abrir a tela de denúncias (ChatRepository). Só o cron não cumpre — no '
  'plano gratuito o projeto pausa por inatividade e o cron para junto. '
  'Change denuncia-como-registro.';

revoke execute on function public.expurgar_motivos_de_denuncia() from public;
grant execute on function public.expurgar_motivos_de_denuncia() to authenticated;

select cron.schedule(
  'expurgar-motivos-de-denuncia',
  '47 3 * * *',
  $$select public.expurgar_motivos_de_denuncia()$$
);

-- Uma linha em `excluir_minha_conta`, na mesma transação: esvazia o motivo
-- de quem é `denunciante_id`. `denunciante_id` NÃO é anulado — ele aponta
-- para `perfis`, e a anonimização do Perfil já tira o nome; anular a coluna
-- transformaria a denúncia em órfã e QUEBRARIA o índice único parcial da
-- seção 2 (mensagem_id nulo não colide com nulo, denunciante_id nulo
-- também não colidiria, e duas pendentes órfãs do mesmo Perfil anonimizado
-- deixariam de ser distinguíveis pelo índice).
--
-- `create or replace`, corpo extraído do banco com
-- `pg_get_functiondef('public.excluir_minha_conta'::regproc)` depois de
-- aplicar todas as migrations anteriores (a versão vigente é a de
-- `20260810130000_capa_cancelamento_e_exclusao.sql`, não a de
-- `20260810000000` — ela é anterior na ordem alfabética do `grep`, mas foi
-- SUBSTITUÍDA por uma migration posterior que este arquivo quase pulou por
-- procurar `create or replace` em minúsculas só). Mesma lição da
-- `20260810130000`: reescrever a partir de uma migration velha é como perder
-- um `delete` que ninguém notou. Um bloco novo, marcado abaixo — nada mais
-- foi tocado.
create or replace function public.excluir_minha_conta()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_herdeiro uuid;
  v_tem_heranca boolean;
begin
  if v_uid is null then
    raise exception 'é preciso estar autenticado para excluir a própria conta';
  end if;

  if not exists (select 1 from public.perfis where id = v_uid) then
    raise exception 'não há Perfil para excluir';
  end if;

  -- Herdeiro: Administrador do distrito mais antigo entre os que ficam. O
  -- desempate por usuario_id existe só pra a eleição ser determinística quando
  -- dois Administradores nascem no mesmo instante (bootstrap).
  select usuario_id into v_herdeiro
  from public.administradores_distrito
  where usuario_id <> v_uid
  order by created_at, usuario_id
  limit 1;

  v_tem_heranca :=
    exists (select 1 from public.grupos where dono_id = v_uid)
    or exists (
      select 1 from public.rodadas_votacao
      where aberta_por = v_uid and fechada_em is null
    );

  if v_herdeiro is null then
    -- Recusa mesmo sem nada a herdar: sem Administrador nenhum, o distrito
    -- fica sem quem cadastre Igreja e sem quem promova outro Administrador, e
    -- administradores_distrito_checar_regras exige um admin pré-existente pra
    -- promover — só a migration de bootstrap sairia desse buraco.
    if exists (select 1 from public.administradores_distrito where usuario_id = v_uid) then
      raise exception 'você é o único Administrador do distrito; promova outro Administrador antes de excluir sua conta';
    end if;
    if v_tem_heranca then
      raise exception 'não há Administrador do distrito para receber seus Grupos e Rodadas de votação abertas';
    end if;
  end if;

  -- Transferência: participação primeiro, senão grupos_dono_deve_participar
  -- (BEFORE UPDATE) recusa o update. grupos_dono_vira_participante só cobre
  -- INSERT, então não adianta esperar que ela apareça sozinha.
  if v_tem_heranca then
    insert into public.participacoes_grupo (grupo_id, usuario_id)
    select g.id, v_herdeiro
    from public.grupos g
    where g.dono_id = v_uid
    on conflict do nothing;

    update public.grupos set dono_id = v_herdeiro where dono_id = v_uid;

    update public.rodadas_votacao set aberta_por = v_herdeiro
    where aberta_por = v_uid and fechada_em is null;
  end if;

  -- Vínculos vivos: somem. Vínculos históricos (acoes.criador_id, rodadas
  -- fechadas, liderancas.confirmado_por, confirmações de Ações passadas)
  -- continuam apontando pro Perfil anonimizado, de propósito.
  delete from public.votos v
  using public.rodadas_votacao r
  where v.usuario_id = v_uid and v.rodada_id = r.id and r.fechada_em is null;

  delete from public.confirmacoes_acao c
  using public.acoes a
  where c.usuario_id = v_uid and c.acao_id = a.id and a.data_hora > now();

  delete from public.participacoes_grupo where usuario_id = v_uid;
  delete from public.liderancas where usuario_id = v_uid;
  delete from public.administradores_distrito where usuario_id = v_uid;

  -- Feature 013, FR-024. Capa de Ação AVULSA enviada por quem sai.
  --
  -- Só avulsa (`a.grupo_id is null`), de propósito: capa de Ação de Grupo
  -- ilustra uma atividade do Grupo, que continua existindo com outro Dono.
  -- Apagar a capa do Grupo herdado seria estragar o Grupo de terceiros porque
  -- uma pessoa saiu — é a mesma lógica que faz o Grupo ser herdado em vez de
  -- apagado (FR-025).
  --
  -- Isto apaga só a LINHA. O gatilho fotos_capa_enfileirar_remocao põe o
  -- arquivo na fila, e a chamada de rede acontece fora desta transação — é
  -- exatamente o que impede uma falha de rede de abortar a exclusão de conta e
  -- transformar o direito do art. 18, VI da LGPD em refém do armazenamento.
  --
  -- Nota que parece bug e não é: esta função NÃO apaga as Ações de quem sai.
  -- Ela anonimiza o Perfil e deixa acoes.criador_id apontando para ele
  -- (histórico, feature 009). A Ação continua existindo, sem capa, com criador
  -- 'Membro removido'. É a regra.
  delete from public.fotos_capa f
  using public.acoes a
  where f.acao_id = a.id
    and a.grupo_id is null
    and f.enviada_por = v_uid;

  -- NOVO NESTA CHANGE: o motivo que este Perfil escreveu ao denunciar sai
  -- com a conta, como o texto das mensagens dele já saía
  -- (mensagens_perdem_texto_ao_anonimizar, 20260813200000). A denúncia em si
  -- continua existindo, com o desfecho que tiver — só o texto que ele
  -- escreveu deixa de existir. `denuncias_mensagem_so_resolve_trigger`
  -- permite exatamente esta transição (motivo -> NULL).
  update public.denuncias_mensagem
  set motivo = null
  where denunciante_id = v_uid and motivo is not null;

  -- 'Membro removido' passa em nome_valido(); apelido nulo faz
  -- perfil_publico() (coalesce(apelido, nome)) exibir exatamente isso.
  -- O bypass existe porque o gatilho da seção 4 bloquearia este update mesmo
  -- rodando como dono: gatilho não é RLS, e SECURITY DEFINER não pula gatilho.
  -- Mesmo formato que fechar_rodada_se_devido usa com app.bypass_acoes_protecao.
  perform set_config('app.bypass_autorizacao_responsavel', 'true', true);
  update public.perfis set
    nome = 'Membro removido',
    apelido = null,
    telefone = null,
    igreja_id = null,
    genero = null,
    idade = null,
    -- Feature 015. Estas duas são dado pessoal de TERCEIRO: a pessoa não tem
    -- conta, não tem tela e não tem como pedir exclusão. Se ficassem aqui, o
    -- app teria excluído a conta da criança e guardado o nome e o telefone da
    -- mãe — exatamente a promessa que a tela de exclusão faz e não cumpriria.
    responsavel_nome = null,
    responsavel_contato = null,
    autorizacao_responsavel_em = null,
    autorizacao_responsavel_versao = null,
    anonimizado_em = now()
  where id = v_uid;
  perform set_config('app.bypass_autorizacao_responsavel', 'false', true);

  -- Encerra o login. O JWT já emitido continua válido até expirar, então o
  -- cliente precisa chamar signOut() logo após esta função retornar.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.excluir_minha_conta() from public;
grant execute on function public.excluir_minha_conta() to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A versão do texto legal
-- ---------------------------------------------------------------------------
-- Gêmea da constante `LegalMetadata.version`. Não dá para derivar uma da
-- outra: o texto legal está compilado no binário, e a versão é metadado dele.
-- `test/integration/versao_texto_legal_registro_test.dart` falha se
-- divergirem.
--
-- Sobe para 1.9 porque a Política deixa de prometer que o motivo "não expira
-- com o tempo" e passa a descrever o prazo de 30 dias e a saída na exclusão
-- de conta — mudança MAIS RESTRITIVA sobre dado que já existia, mesmo caso da
-- 1.7. Consentimento colhido sob 1.7 não cobre isso: quem se cadastrou antes
-- desta linha aceitou uma promessa de guarda eterna que deixou de ser
-- verdadeira.
--
-- 1.9 e não 1.8: a change `alcance-do-titular-sobre-texto-proprio`, mesclada
-- em `main` antes desta, já ocupou 1.8 (`20260830110000_versao_texto_legal_1_8.sql`).
-- As duas branches nasceram do mesmo commit antes de qualquer uma mesclar, e
-- cada uma calculou "o próximo número livre" de forma independente. Renumerado
-- ao mesclar main nesta branch.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.9', timestamptz '2026-08-30 00:00:00-03')
on conflict (versao) do nothing;

-- ---------------------------------------------------------------------------
-- Rollback
-- ---------------------------------------------------------------------------
-- `drop trigger`/`drop function` dos dois gatilhos da seção 1 e 2, `drop
-- index` do índice único, `drop function` de `expurgar_motivos_de_denuncia`
-- e `denuncia_prazo_do_motivo`, `cron.unschedule('expurgar-motivos-de-denuncia')`,
-- `alter table ... alter column motivo set not null` (só depois de tratar
-- linha já nula), e devolver `excluir_minha_conta` à versão anterior.
--
-- A REVERSÃO NÃO DEVOLVE MOTIVO JÁ APAGADO PELO PRAZO OU PELA EXCLUSÃO DE
-- CONTA. O texto que o expurgo ou a exclusão de conta já apagaram continua
-- apagado — reverter a migration futura, não o passado.
