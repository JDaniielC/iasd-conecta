-- Feature 004: rodada-votacao
-- Ver specs/004-rodada-votacao/contracts/schema.sql (fonte de verdade) e data-model.md.

create table public.rodadas_votacao (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references public.grupos(id),
  aberta_por uuid not null references public.perfis(id),
  prazo timestamptz not null,
  fechada_em timestamptz,
  created_at timestamptz not null default now()
);

alter table public.acoes
  add column grupo_id uuid references public.grupos(id),
  add column rodada_id uuid references public.rodadas_votacao(id),
  add column confirmada boolean not null default true;

alter table public.rodadas_votacao
  add column vencedora_id uuid references public.acoes(id);

create table public.votos (
  rodada_id uuid not null references public.rodadas_votacao(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  candidata_id uuid not null references public.acoes(id) on delete cascade,
  updated_at timestamptz not null default now(),
  primary key (rodada_id, usuario_id)
);

-- FR-004: só participante do Grupo abre Rodada.
create function public.rodadas_votacao_checar_participante()
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
  return new;
end;
$$;

create trigger rodadas_votacao_checar_participante_trigger
  before insert on public.rodadas_votacao
  for each row
  execute function public.rodadas_votacao_checar_participante();

-- FR-003/FR-004: só participante do Grupo propõe candidata; grupo_id é
-- sempre derivado da Rodada, nunca confiado do client; recusa se a Rodada
-- já fechou.
create function public.acoes_candidata_checar_regras()
returns trigger
language plpgsql
as $$
declare
  v_fechada timestamptz;
  v_grupo_id uuid;
begin
  if new.rodada_id is null then
    return new;
  end if;

  select fechada_em, grupo_id into v_fechada, v_grupo_id
  from public.rodadas_votacao where id = new.rodada_id;

  if v_fechada is not null then
    raise exception 'rodada já fechada, não é possível propor candidata';
  end if;

  if not exists (
    select 1 from public.participacoes_grupo
    where grupo_id = v_grupo_id and usuario_id = auth.uid()
  ) then
    raise exception 'só participantes do grupo propõem candidata';
  end if;

  new.grupo_id := v_grupo_id;
  new.confirmada := false;

  return new;
end;
$$;

create trigger acoes_candidata_checar_regras_trigger
  before insert on public.acoes
  for each row
  execute function public.acoes_candidata_checar_regras();

-- FR-005/FR-007: só participante do Grupo vota, só em candidata válida de
-- Rodada aberta.
create function public.votos_checar_regras()
returns trigger
language plpgsql
as $$
declare
  v_fechada timestamptz;
  v_grupo_id uuid;
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

  if not exists (
    select 1 from public.acoes
    where id = new.candidata_id and rodada_id = new.rodada_id and confirmada = false
  ) then
    raise exception 'candidata inválida para esta rodada';
  end if;

  return new;
end;
$$;

create trigger votos_checar_regras_trigger
  before insert or update on public.votos
  for each row
  execute function public.votos_checar_regras();

-- FR-008/FR-009/FR-010/FR-011/FR-012/FR-013/FR-014/FR-018: fechamento
-- preguiçoso + apuração. SECURITY DEFINER porque mexe em Ações/votos de
-- outras pessoas.
create function public.fechar_rodada_se_devido(
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
    update public.acoes set confirmada = true where id = v_vencedora;
    delete from public.acoes
    where rodada_id = p_rodada_id and confirmada = false and id <> v_vencedora;
  end if;

  update public.rodadas_votacao
  set fechada_em = now(), vencedora_id = v_vencedora
  where id = p_rodada_id;
end;
$$;

grant select on public.rodadas_votacao to anon, authenticated;
grant insert on public.rodadas_votacao to authenticated;
grant select on public.votos to anon, authenticated;
grant insert, update on public.votos to authenticated;
grant execute on function public.fechar_rodada_se_devido(uuid, boolean) to authenticated;

alter table public.rodadas_votacao enable row level security;
alter table public.votos enable row level security;

create policy rodadas_votacao_select_public
  on public.rodadas_votacao for select
  to anon, authenticated
  using (true);

create policy rodadas_votacao_insert_participante
  on public.rodadas_votacao for insert
  to authenticated
  with check (auth.uid() = aberta_por);

create policy votos_select_public
  on public.votos for select
  to anon, authenticated
  using (true);

create policy votos_insert_self
  on public.votos for insert
  to authenticated
  with check (auth.uid() = usuario_id);

create policy votos_update_self
  on public.votos for update
  to authenticated
  using (auth.uid() = usuario_id)
  with check (auth.uid() = usuario_id);

-- FR-016: substitui a policy de update da feature 003 — agora quem propôs
-- a Ação OU o Dono do Grupo (quando for Ação de Grupo) pode atualizar
-- (cancelar).
drop policy if exists acoes_update_criador on public.acoes;

create policy acoes_update_criador_ou_dono_grupo
  on public.acoes for update
  to authenticated
  using (
    auth.uid() = criador_id
    or (
      grupo_id is not null
      and exists (
        select 1 from public.grupos g
        where g.id = acoes.grupo_id and g.dono_id = auth.uid()
      )
    )
  );
