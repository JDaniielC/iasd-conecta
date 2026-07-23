-- Feature 002: grupos
-- Ver specs/002-grupos/contracts/schema.sql (fonte de verdade) e data-model.md.

create table public.categorias_grupo (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique
);

create table public.grupos (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(trim(nome)) > 0),
  categoria text not null,
  horario text not null,
  local text not null,
  detalhes text,
  igreja_id uuid references public.igrejas(id),
  dono_id uuid not null references public.perfis(id),
  created_at timestamptz not null default now()
);

create table public.participacoes_grupo (
  grupo_id uuid not null references public.grupos(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (grupo_id, usuario_id)
);

-- FR-003: criador vira automaticamente participante do próprio grupo.
create function public.criar_participacao_do_dono()
returns trigger
language plpgsql
as $$
begin
  insert into public.participacoes_grupo (grupo_id, usuario_id)
  values (new.id, new.dono_id)
  on conflict (grupo_id, usuario_id) do nothing;
  return new;
end;
$$;

create trigger grupos_dono_vira_participante
  after insert on public.grupos
  for each row
  execute function public.criar_participacao_do_dono();

-- FR-011: só dá pra transferir a posse pra quem já participa do grupo.
create function public.checar_dono_participa()
returns trigger
language plpgsql
as $$
begin
  if new.dono_id is distinct from old.dono_id then
    if not exists (
      select 1 from public.participacoes_grupo
      where grupo_id = new.id and usuario_id = new.dono_id
    ) then
      raise exception 'novo dono precisa participar do grupo antes de receber a posse';
    end if;
  end if;
  return new;
end;
$$;

create trigger grupos_dono_deve_participar
  before update on public.grupos
  for each row
  execute function public.checar_dono_participa();

-- FR-012: Dono não sai do próprio grupo sem transferir a posse antes.
create function public.checar_dono_nao_sai_sem_transferir()
returns trigger
language plpgsql
as $$
begin
  if exists (
    select 1 from public.grupos
    where id = old.grupo_id and dono_id = old.usuario_id
  ) then
    raise exception 'transfira a posse do grupo antes de sair';
  end if;
  return old;
end;
$$;

create trigger participacoes_grupo_dono_nao_sai_sem_transferir
  before delete on public.participacoes_grupo
  for each row
  execute function public.checar_dono_nao_sai_sem_transferir();

grant select on public.categorias_grupo to anon, authenticated;
grant select on public.grupos to anon, authenticated;
grant insert, update on public.grupos to authenticated;
grant select on public.participacoes_grupo to anon, authenticated;
grant insert, delete on public.participacoes_grupo to authenticated;

alter table public.categorias_grupo enable row level security;
alter table public.grupos enable row level security;
alter table public.participacoes_grupo enable row level security;

create policy categorias_grupo_select_public
  on public.categorias_grupo for select
  to anon, authenticated
  using (true);

create policy grupos_select_public
  on public.grupos for select
  to anon, authenticated
  using (true);

create policy grupos_insert_dono
  on public.grupos for insert
  to authenticated
  with check (auth.uid() = dono_id);

create policy grupos_update_dono
  on public.grupos for update
  to authenticated
  using (auth.uid() = dono_id)
  with check (true);

create policy participacoes_grupo_select_public
  on public.participacoes_grupo for select
  to anon, authenticated
  using (true);

create policy participacoes_grupo_insert_self
  on public.participacoes_grupo for insert
  to authenticated
  with check (auth.uid() = usuario_id);

create policy participacoes_grupo_delete_self_or_dono
  on public.participacoes_grupo for delete
  to authenticated
  using (
    auth.uid() = usuario_id
    or exists (
      select 1 from public.grupos g
      where g.id = grupo_id and g.dono_id = auth.uid()
    )
  );
