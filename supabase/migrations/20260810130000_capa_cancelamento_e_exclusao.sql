-- Feature 013 — US4: a imagem some junto com o que ela ilustra.
--
-- =====================================================================
-- POR QUE ESTA FUNÇÃO É REESCRITA INTEIRA, E DE ONDE VEIO O TEXTO
-- =====================================================================
-- `create or replace` substitui o corpo inteiro. Reescrever a partir de uma
-- migration antiga é como a feature 014 REVERTEU um conserto de segurança sem
-- ninguém notar — o texto abaixo foi extraído do banco com
-- `pg_get_functiondef('public.excluir_minha_conta'::regproc)` depois de
-- aplicar TODAS as migrations, e só então recebeu o bloco novo. É o estado
-- vivo da função, não a memória de um arquivo.
--
-- O que mudou em relação ao estado anterior: UM delete a mais, marcado com
-- "Feature 013, FR-024". Nada mais foi tocado — nem a herança, nem o bypass do
-- gatilho de autorização do responsável, nem a anonimização.

CREATE OR REPLACE FUNCTION public.excluir_minha_conta()
 RETURNS void
 LANGUAGE plpgsql
 SECURITY DEFINER
 SET search_path TO 'public', 'pg_temp'
AS $function$
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
$function$
;


-- =====================================================================
-- Cancelamento de Ação — ato explícito, porque não há cascade que dispare
-- =====================================================================
--
-- FR-022. Cancelar uma Ação é `update acoes set cancelada_em = now()`: a linha
-- da Ação **não some**, então nenhum cascade toca a capa. Sem este gatilho, a
-- imagem de uma Ação cancelada ficaria pública para sempre, e ninguém
-- perceberia — a Ação some das listas, a imagem não.
--
-- O gatilho fica em `acoes`, e não na tela, para valer também quando o
-- cancelamento vier de outro caminho: o Administrador cancelando Ação alheia,
-- o arquivamento de Grupo (feature 014), ou qualquer coisa futura.
--
-- **Ação ENCERRADA por tempo mantém a capa**, e a diferença é deliberada:
-- encerrada é histórico — aconteceu, tem presenças registradas, e a capa faz
-- parte do registro (FR-023). Cancelada é o contrário: não aconteceu.

create function public.acoes_remover_capa_ao_cancelar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  delete from public.fotos_capa where acao_id = new.id;
  return new;
end;
$$;

create trigger acoes_remover_capa_ao_cancelar
  after update of cancelada_em on public.acoes
  for each row
  when (old.cancelada_em is null and new.cancelada_em is not null)
  execute function public.acoes_remover_capa_ao_cancelar();
