-- Contrato de banco da feature 014 — Arquivar Grupo.
--
-- Este arquivo é o CONTRATO, não a migration. A migration vai em
-- supabase/migrations/<timestamp>_arquivar_grupo.sql.
--
-- POR QUE FUNÇÃO E NÃO UPDATE NO CLIENTE  (ler antes de "simplificar" isto)
-- Três políticas fecham a porta do cliente:
--   grupos_update_dono   (20260723220703_grupos.sql:115) — só o Dono altera o Grupo,
--                         então o Administrador do distrito não arquiva Grupo alheio.
--   acoes_update_criador (20260723230639_acoes.sql:131)  — só quem criou altera a Ação,
--                         então o Dono não cancela Ação que outra pessoa criou no Grupo dele.
--   RLS de rodadas_votacao — idem para encerrar Rodada de terceiro.
-- Fazer no cliente exigiria afrouxar as três em caráter permanente, para servir a uma
-- operação que cada pessoa faz uma vez na vida.
--
-- E atomicidade: arquivar faz quatro coisas. Em quatro chamadas do cliente, uma falha no
-- meio deixa Ações canceladas dentro de um Grupo que continua ativo — estado pior do que
-- não ter arquivado. Função é transação.
--
-- Mesmo padrão de public.excluir_minha_conta (feature 009).

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

revoke all on function public.desarquivar_grupo(uuid) from public;
grant execute on function public.desarquivar_grupo(uuid) to authenticated;

-- =====================================================================
-- 4. Grupo arquivado não aceita mais nada
-- =====================================================================
--
-- FR-011/FR-012. As telas escondem os botões; estas políticas é que executam.
-- Sem elas, uma chamada direta à API contornaria a regra inteira.

drop policy if exists participacoes_grupo_insert_self on public.participacoes_grupo;
create policy participacoes_grupo_insert_self
  on public.participacoes_grupo for insert
  to authenticated
  with check (
    auth.uid() = usuario_id
    and exists (select 1 from public.grupos g
                where g.id = grupo_id and g.arquivado_em is null)
  );

drop policy if exists rodadas_votacao_insert_participante on public.rodadas_votacao;
create policy rodadas_votacao_insert_participante
  on public.rodadas_votacao for insert
  to authenticated
  with check (
    exists (select 1 from public.participacoes_grupo p
            where p.grupo_id = rodadas_votacao.grupo_id and p.usuario_id = auth.uid())
    and exists (select 1 from public.grupos g
                where g.id = rodadas_votacao.grupo_id and g.arquivado_em is null)
  );

-- Voto e Ação candidata: a checagem entra nos triggers/políticas que já existem
-- para eles (acoes_candidata_checar_regras e a política de insert de votos),
-- somando `and grupo não arquivado`. Os nomes exatos saem na migration, depois
-- de reler as definições atuais — este contrato registra a REGRA, não o texto.

-- =====================================================================
-- 5. O que NÃO é tocado, de propósito
-- =====================================================================
--
-- participacoes_grupo: as linhas ficam. "Suspensa" é ausência de permissão, não
--   ausência de linha — é isso que faz o desarquivamento devolver todo mundo sem
--   guardar uma segunda lista que um dia divergiria (FR-017, FR-021).
--
-- liderancas: fica. É o registro de quem foi responsável perante a igreja. O que
--   muda é a EXIBIÇÃO (FR-016) — e é aí que mora o risco 4 do plano: se a consulta
--   que mostra o Líder/Diretor não filtrar Grupo arquivado, a identificação pública
--   continua no ar para Visitante, em silêncio.
--
-- confirmacoes_acao: nenhuma presença é apagada (FR-015).
--
-- fechar_rodada_se_devido, confirmacoes_acao_promover_fila,
-- confirmacoes_acao_decidir_status, acao_encerrada: inalteradas.
