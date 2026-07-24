-- Correção de 3 bugs críticos de RLS/autorização encontrados em auditoria
-- de segurança ponta a ponta (2026-07-24). Ver SECURITY-AUDIT.md na raiz
-- do repo para evidência de reprodução de cada um.

-- BUG 1 (feature 001): nome_valido() lê palavras_bloqueadas como
-- invoker (sem SECURITY DEFINER), mas a tabela nunca recebeu GRANT pra
-- anon/authenticated — todo cadastro real falhava com "permission
-- denied for table palavras_bloqueadas". Só não foi pego antes porque
-- os testes semeiam perfis direto como superusuário (bypassa GRANT).
grant select on public.palavras_bloqueadas to anon, authenticated;

-- BUG 2 (feature 004): acoes_candidata_checar_regras() só valida
-- participação/rodada quando rodada_id não é nulo — um INSERT direto
-- com grupo_id preenchido e rodada_id nulo pulava toda a validação, e
-- `confirmada` nasce `true` por default. Qualquer authenticated
-- conseguia forjar uma Ação de Grupo "confirmada" sem nunca ter
-- participado do Grupo nem passado por votação. Fix: grupo_id só é
-- permitido junto de rodada_id — Ação de Grupo sempre nasce candidata.
create or replace function public.acoes_candidata_checar_regras()
returns trigger
language plpgsql
as $$
declare
  v_fechada timestamptz;
  v_grupo_id uuid;
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

  new.grupo_id := v_grupo_id;
  new.confirmada := false;
  return new;
end;
$$;

-- BUG 3 (feature 003/004/005): as policies de UPDATE de acoes nunca
-- tiveram WITH CHECK explícito — Postgres reusa USING (que só checa
-- identidade de quem pode mexer na linha), então qualquer criador
-- conseguia `update acoes set confirmada = true` na própria candidata
-- via PostgREST, virando "vencedora" sem nenhum voto, bypassando
-- fechar_rodada_se_devido inteiro. Fix: trigger BEFORE UPDATE protege
-- confirmada/grupo_id/rodada_id/criador_id contra alteração direta;
-- fechar_rodada_se_devido (único caminho legítimo que muda confirmada)
-- sinaliza bypass via GUC de transação antes do UPDATE interno.
create function public.acoes_protege_campos_internos()
returns trigger
language plpgsql
as $$
begin
  if current_setting('app.bypass_acoes_protecao', true) = 'true' then
    return new;
  end if;

  if new.confirmada is distinct from old.confirmada
     or new.grupo_id is distinct from old.grupo_id
     or new.rodada_id is distinct from old.rodada_id
     or new.criador_id is distinct from old.criador_id then
    raise exception 'não é permitido alterar confirmada/grupo_id/rodada_id/criador_id diretamente';
  end if;

  return new;
end;
$$;

create trigger acoes_protege_campos_internos_trigger
  before update on public.acoes
  for each row
  execute function public.acoes_protege_campos_internos();

create or replace function public.fechar_rodada_se_devido(
  p_rodada_id uuid,
  p_forcar boolean default false
)
returns void
language plpgsql
security definer
set search_path = public
as $$
declare
  v_prazo timestamptz;
  v_fechada timestamptz;
  v_grupo_id uuid;
  v_vencedora uuid;
begin
  select prazo, fechada_em, grupo_id into v_prazo, v_fechada, v_grupo_id
  from public.rodadas_votacao
  where id = p_rodada_id
  for update;

  if v_fechada is not null then
    return;
  end if;

  if p_forcar then
    if not exists (
      select 1 from public.grupos where id = v_grupo_id and dono_id = auth.uid()
    ) then
      raise exception 'só o Dono do Grupo encerra a Rodada antes do prazo';
    end if;
  elsif now() < v_prazo then
    return;
  end if;

  select a.id into v_vencedora
  from public.acoes a
  left join public.votos v on v.candidata_id = a.id and v.rodada_id = p_rodada_id
  where a.rodada_id = p_rodada_id and a.confirmada = false
  group by a.id
  order by count(v.usuario_id) desc, random()
  limit 1;

  if v_vencedora is not null then
    perform set_config('app.bypass_acoes_protecao', 'true', true);
    update public.acoes set confirmada = true where id = v_vencedora;
    perform set_config('app.bypass_acoes_protecao', 'false', true);
    delete from public.acoes
    where rodada_id = p_rodada_id and confirmada = false and id <> v_vencedora;
  end if;

  update public.rodadas_votacao
  set fechada_em = now(), vencedora_id = v_vencedora
  where id = p_rodada_id;
end;
$$;
