-- Feature 005: administrador-distrito
-- Ver specs/005-administrador-distrito/contracts/schema.sql (fonte de verdade) e data-model.md.

create table public.administradores_distrito (
  usuario_id uuid primary key references public.perfis(id),
  promovido_por uuid not null references public.perfis(id),
  created_at timestamptz not null default now()
);

alter table public.igrejas
  add column arquivada_em timestamptz;

-- FR-001/FR-002/FR-003: só Administrador promove, e só quem tem Conta.
-- SECURITY DEFINER porque precisa ler auth.users.is_anonymous — schema
-- auth não é acessível ao papel authenticated (ver research.md).
create function public.administradores_distrito_checar_regras()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_eh_anonimo boolean;
begin
  if not exists (
    select 1 from public.administradores_distrito where usuario_id = auth.uid()
  ) then
    raise exception 'só um Administrador do distrito promove outro';
  end if;

  select is_anonymous into v_eh_anonimo from auth.users where id = new.usuario_id;

  if v_eh_anonimo is distinct from false then
    raise exception 'usuário precisa ter Conta antes de ser promovido a Administrador do distrito';
  end if;

  return new;
end;
$$;

create trigger administradores_distrito_checar_regras_trigger
  before insert on public.administradores_distrito
  for each row
  execute function public.administradores_distrito_checar_regras();

grant select on public.administradores_distrito to anon, authenticated;
grant insert on public.administradores_distrito to authenticated;
grant insert, update on public.igrejas to authenticated;

alter table public.administradores_distrito enable row level security;

create policy administradores_distrito_select_public
  on public.administradores_distrito for select
  to anon, authenticated
  using (true);

create policy administradores_distrito_insert_promovido_por_self
  on public.administradores_distrito for insert
  to authenticated
  with check (auth.uid() = promovido_por);

-- FR-007/FR-008: substitui a policy de select da feature 001 — Igreja
-- arquivada some da lista pra quem não é Administrador.
drop policy if exists igrejas_select_public on public.igrejas;

create policy igrejas_select_ativas_publico
  on public.igrejas for select
  to anon, authenticated
  using (
    arquivada_em is null
    or exists (
      select 1 from public.administradores_distrito where usuario_id = auth.uid()
    )
  );

-- FR-004/FR-006: só Administrador adiciona/arquiva Igreja.
create policy igrejas_insert_admin
  on public.igrejas for insert
  to authenticated
  with check (
    exists (select 1 from public.administradores_distrito where usuario_id = auth.uid())
  );

create policy igrejas_update_admin
  on public.igrejas for update
  to authenticated
  using (
    exists (select 1 from public.administradores_distrito where usuario_id = auth.uid())
  );

-- FR-009: substitui a policy de update de acoes da feature 004 — soma
-- Administrador do distrito a quem já podia cancelar.
drop policy if exists acoes_update_criador_ou_dono_grupo on public.acoes;

create policy acoes_update_criador_dono_grupo_ou_admin
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
    or exists (
      select 1 from public.administradores_distrito where usuario_id = auth.uid()
    )
  );
