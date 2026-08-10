-- Feature 014 — arquivar Grupo.
--
-- POR QUE ARQUIVAR E NÃO APAGAR
-- Apagar Grupo é impossível hoje, e não por esquecimento: `rodadas_votacao.grupo_id`,
-- `acoes.grupo_id` e `liderancas.grupo_id` são chaves estrangeiras sem `on delete`.
-- O banco recusa o `delete`. Arquivar é o que o domínio de fato pede — o Grupo sai de
-- circulação sem deixar de ter existido, como `acoes.cancelada_em` e
-- `perfis.anonimizado_em` já fazem.
--
-- DESVIO DO CONTRATO, declarado
-- A seção 4 de specs/014-arquivar-grupo/contracts/schema.sql previa reescrever as
-- políticas de insert de `rodadas_votacao` e `votos` acrescentando a checagem de
-- participação junto com a de arquivado. Reli as definições antes de escrever, como a
-- T016 manda, e a premissa não se sustenta: essas políticas **não** checam participação.
--   participacoes_grupo_insert_self  -> with check (auth.uid() = usuario_id)
--   rodadas_votacao_insert_participante -> with check (auth.uid() = aberta_por)
--   votos_insert_self                -> with check (auth.uid() = usuario_id)
-- Quem exige participação são os TRIGGERS (`rodadas_votacao_checar_participante`,
-- `acoes_candidata_checar_regras`, `votos_checar_regras`), que já resolvem o Grupo.
-- Então a checagem de arquivado entra lá, ao lado da regra irmã, em vez de virar uma
-- segunda cópia da regra de participação dentro de uma policy. Uma regra, um lugar.
-- Só `participacoes_grupo` recebe a checagem na policy, porque não tem trigger.

-- =====================================================================
-- 1. O estado
-- =====================================================================

alter table public.grupos
  add column arquivado_em timestamptz,
  add column arquivado_por uuid references public.perfis(id);

comment on column public.grupos.arquivado_em is
  'Nulo = Grupo ativo. Espelha acoes.cancelada_em e perfis.anonimizado_em — o app já '
  'tem um padrão para "saiu de circulação sem deixar de ter existido". Feature 014.';

comment on column public.grupos.arquivado_por is
  'Quem arquivou. Visível SÓ ao Administrador do distrito (FR-019), que precisa disso '
  'para decidir se desarquiva.';

-- Índice parcial: a listagem sempre filtra por ativo, e arquivado é a minoria.
create index grupos_ativos on public.grupos (id) where arquivado_em is null;

-- =====================================================================
-- 2. Arquivar
-- =====================================================================

create function public.arquivar_grupo(p_grupo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_uid uuid := auth.uid();
  v_dono uuid;
  v_arquivado timestamptz;
begin
  select dono_id, arquivado_em into v_dono, v_arquivado
  from public.grupos where id = p_grupo_id;

  if v_dono is null then
    raise exception 'Grupo não encontrado.';
  end if;

  -- FR-009: já arquivado não arquiva de novo.
  if v_arquivado is not null then
    raise exception 'Este Grupo já está arquivado.';
  end if;

  -- FR-001/FR-002: Dono do Grupo ou Administrador do distrito. Mais ninguém.
  if v_uid is distinct from v_dono
     and not exists (select 1 from public.administradores_distrito d
                     where d.usuario_id = v_uid) then
    raise exception 'Só o Dono do Grupo ou o Administrador do distrito arquiva.';
  end if;

  -- (a) o Grupo sai do ar
  update public.grupos
  set arquivado_em = now(), arquivado_por = v_uid
  where id = p_grupo_id;

  -- (b) Ações de Grupo FUTURAS são canceladas. Ação passada NÃO é tocada —
  --     histórico é histórico (FR-014). As presenças ficam: a Ação aparece
  --     cancelada, com quem havia confirmado (FR-015).
  update public.acoes
  set cancelada_em = now()
  where grupo_id = p_grupo_id
    and confirmada = true
    and cancelada_em is null
    and data_hora > now();

  -- (c) Rodadas abertas encerram SEM APURAR.
  --
  --     NÃO usar public.fechar_rodada_se_devido aqui. Ela APURA: escolhe a mais
  --     votada, resolve empate por sorteio e promove a vencedora a Ação
  --     confirmada. Chamá-la produziria um encontro marcado por um Grupo que
  --     acabou de sair do ar. Ver research.md D-003.
  update public.rodadas_votacao
  set fechada_em = now(), vencedora_id = null
  where grupo_id = p_grupo_id and fechada_em is null;

  -- (d) descarte TOTAL das candidatas dessas Rodadas — sem vencedora.
  delete from public.acoes a
  using public.rodadas_votacao r
  where a.rodada_id = r.id
    and r.grupo_id = p_grupo_id
    and a.confirmada = false;
end;
$$;

comment on function public.arquivar_grupo(uuid) is
  'Tira o Grupo de circulação sem apagá-lo (apagar é impossível: FKs sem on delete). '
  'Cancela Ações futuras, encerra Rodadas SEM apurar e descarta as candidatas. '
  'Participações e declarações de liderança NÃO são apagadas. Feature 014.';

revoke all on function public.arquivar_grupo(uuid) from public;
grant execute on function public.arquivar_grupo(uuid) to authenticated;

-- =====================================================================
-- 3. Desarquivar — só o Administrador do distrito (FR-018)
-- =====================================================================
--
-- Não ressuscita nada: as Ações canceladas continuam canceladas e as Rodadas
-- encerradas continuam encerradas (FR-022). As participações voltam sozinhas
-- porque nunca foram apagadas (FR-017/FR-021, research D-005).

create function public.desarquivar_grupo(p_grupo_id uuid)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  if not exists (select 1 from public.administradores_distrito d
                 where d.usuario_id = auth.uid()) then
    raise exception 'Só o Administrador do distrito desarquiva.';
  end if;

  update public.grupos
  set arquivado_em = null, arquivado_por = null
  where id = p_grupo_id and arquivado_em is not null;
end;
$$;

comment on function public.desarquivar_grupo(uuid) is
  'Devolve o Grupo e, de graça, os participantes — as linhas de participacoes_grupo '
  'nunca foram apagadas. NÃO ressuscita Ação cancelada nem Rodada encerrada. '
  'Feature 014.';

revoke all on function public.desarquivar_grupo(uuid) from public;
grant execute on function public.desarquivar_grupo(uuid) to authenticated;

-- =====================================================================
-- 4. Grupo arquivado não aceita mais nada (FR-011, FR-012)
-- =====================================================================
--
-- As telas escondem os botões; isto aqui é o que executa. Sem isto, uma chamada
-- direta à API contorna a regra inteira — é a mesma diferença entre esconder e
-- proteger que as features 018 e 021 trataram.

-- 4a. Participar do Grupo: não há trigger, então a regra entra na policy.
drop policy if exists participacoes_grupo_insert_self on public.participacoes_grupo;
create policy participacoes_grupo_insert_self
  on public.participacoes_grupo for insert
  to authenticated
  with check (
    auth.uid() = usuario_id
    and exists (select 1 from public.grupos g
                where g.id = grupo_id and g.arquivado_em is null)
  );

-- 4b. Abrir Rodada de votação: o trigger já resolve o Grupo e já exige
--     participação. A checagem de arquivado entra ao lado, não numa policy
--     separada — senão a regra "sobre este Grupo" ficaria dividida em dois
--     lugares que podem divergir.
create or replace function public.rodadas_votacao_checar_participante()
returns trigger
language plpgsql
as $$
begin
  if not exists (
    select 1 from public.participacoes_grupo
    where grupo_id = new.grupo_id and usuario_id = auth.uid()
  ) then
    raise exception 'só participantes do grupo abrem rodada de votação';
  end if;

  -- Feature 014.
  if exists (
    select 1 from public.grupos g
    where g.id = new.grupo_id and g.arquivado_em is not null
  ) then
    raise exception 'este Grupo está arquivado e não aceita Rodada de votação';
  end if;

  return new;
end;
$$;

-- 4c. Propor Ação candidata.
--
-- ATENÇÃO A QUEM FOR MEXER AQUI: esta função foi redefinida por
-- 20260724130000_fix_rls_security_bugs.sql, e é ESSA versão que está sendo
-- estendida — não a original de 20260724084300. Duas coisas vêm de lá e não
-- podem sumir:
--   * `grupo_id` preenchido com `rodada_id` nulo é RECUSADO. Sem isso dá para
--     forjar Ação de Grupo confirmada sem nunca ter participado do Grupo.
--   * a participação é checada por `new.criador_id`, não por `auth.uid()`.
-- Eu escrevi este bloco a partir da versão original por engano, e
-- test/integration/security_acao_grupo_sem_rodada_test.dart pegou. Se você
-- estiver aqui por causa dele, é isto.
create or replace function public.acoes_candidata_checar_regras()
returns trigger
language plpgsql
as $$
declare
  v_fechada timestamptz;
  v_grupo_id uuid;
  v_arquivado timestamptz;
begin
  if new.rodada_id is null then
    if new.grupo_id is not null then
      raise exception 'Ação de Grupo só pode ser criada como candidata de uma Rodada de votação';
    end if;
    return new;
  end if;

  select fechada_em, grupo_id into v_fechada, v_grupo_id
  from public.rodadas_votacao where id = new.rodada_id;

  if v_fechada is not null then
    raise exception 'rodada já fechada, não é possível propor candidata';
  end if;

  if not exists (
    select 1 from public.participacoes_grupo
    where grupo_id = v_grupo_id and usuario_id = new.criador_id
  ) then
    raise exception 'só participante do Grupo propõe Ação candidata';
  end if;

  -- Feature 014. Na prática arquivar já fecha as Rodadas, então este ramo é
  -- defesa em profundidade: ele é o que segura se uma Rodada aberta escapar
  -- por qualquer caminho futuro.
  select arquivado_em into v_arquivado
  from public.grupos where id = v_grupo_id;
  if v_arquivado is not null then
    raise exception 'este Grupo está arquivado e não aceita Ação candidata';
  end if;

  new.grupo_id := v_grupo_id;
  new.confirmada := false;
  return new;
end;
$$;

-- 4d. Votar.
create or replace function public.votos_checar_regras()
returns trigger
language plpgsql
as $$
declare
  v_fechada timestamptz;
  v_grupo_id uuid;
  v_arquivado timestamptz;
begin
  select fechada_em, grupo_id into v_fechada, v_grupo_id
  from public.rodadas_votacao where id = new.rodada_id;

  if v_fechada is not null then
    raise exception 'rodada já fechada, não é possível votar';
  end if;

  if not exists (
    select 1 from public.participacoes_grupo
    where grupo_id = v_grupo_id and usuario_id = auth.uid()
  ) then
    raise exception 'só participantes do grupo votam';
  end if;

  -- Feature 014. Mesma defesa em profundidade do 4c.
  select arquivado_em into v_arquivado
  from public.grupos where id = v_grupo_id;
  if v_arquivado is not null then
    raise exception 'este Grupo está arquivado e não aceita voto';
  end if;

  if not exists (
    select 1 from public.acoes
    where id = new.candidata_id and rodada_id = new.rodada_id and confirmada = false
  ) then
    raise exception 'candidata inválida para esta rodada';
  end if;

  return new;
end;
$$;

-- =====================================================================
-- 5. O que NÃO é tocado, de propósito
-- =====================================================================
--
-- participacoes_grupo: as linhas ficam. "Suspensa" é ausência de permissão, não
--   ausência de linha — é isso que faz o desarquivamento devolver todo mundo sem
--   guardar uma segunda lista que um dia divergiria (FR-017, FR-021).
--
-- liderancas: fica. É o registro de quem foi responsável perante a igreja. O que
--   muda é a EXIBIÇÃO (FR-016), e isso é feito no cliente — ver
--   leadership_repository.dart. É a única parte desta feature que falha em
--   silêncio se alguém a remover: nada no banco impede um Ministério arquivado
--   de continuar exibindo publicamente quem é o responsável.
--
-- confirmacoes_acao: nenhuma presença é apagada (FR-015).
--
-- fechar_rodada_se_devido, confirmacoes_acao_promover_fila,
-- confirmacoes_acao_decidir_status, acao_encerrada: inalteradas.
