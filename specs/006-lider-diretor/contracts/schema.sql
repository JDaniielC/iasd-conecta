-- Contrato de schema: Líder/Diretor de Ministério (006)
-- Fonte de verdade que a migration em supabase/migrations/ deve seguir.
-- Depende do schema das features 001 (perfis), 002 (grupos) e 005
-- (administradores_distrito) já aplicado.

create table public.liderancas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid not null references public.grupos(id),
  usuario_id uuid not null references public.perfis(id),
  ano integer not null,
  declarado_em timestamptz not null default now(),
  confirmado_por uuid references public.perfis(id),
  confirmado_em timestamptz,
  rejeitado_em timestamptz,
  unique (grupo_id, usuario_id, ano)
);

-- FR-001/FR-002/FR-003/FR-010: autodeclarar, exige Conta, idempotente,
-- redeclara após rejeição sem criar linha nova.
create function public.declarar_lideranca(p_grupo_id uuid, p_ano integer)
returns void
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_eh_anonimo boolean;
begin
  select is_anonymous into v_eh_anonimo from auth.users where id = v_uid;

  if v_eh_anonimo is distinct from false then
    raise exception 'usuário precisa ter Conta antes de se autodeclarar Líder/Diretor';
  end if;

  insert into public.liderancas (grupo_id, usuario_id, ano, declarado_em)
  values (p_grupo_id, v_uid, p_ano, now())
  on conflict (grupo_id, usuario_id, ano) do update
    set declarado_em = now(), rejeitado_em = null
    where public.liderancas.confirmado_em is null;
end;
$$;

-- FR-004/FR-005: só Administrador do distrito confirma ou rejeita.
create function public.decidir_lideranca(p_lideranca_id uuid, p_aprovar boolean)
returns void
language plpgsql
security definer
set search_path = public
as $$
begin
  if not exists (
    select 1 from public.administradores_distrito where usuario_id = auth.uid()
  ) then
    raise exception 'só um Administrador do distrito confirma ou rejeita uma declaração';
  end if;

  if p_aprovar then
    update public.liderancas
    set confirmado_em = now(), confirmado_por = auth.uid(), rejeitado_em = null
    where id = p_lideranca_id;
  else
    update public.liderancas
    set rejeitado_em = now(), confirmado_em = null, confirmado_por = null
    where id = p_lideranca_id;
  end if;
end;
$$;

grant select on public.liderancas to anon, authenticated;
grant execute on function public.declarar_lideranca(uuid, integer) to authenticated;
grant execute on function public.decidir_lideranca(uuid, boolean) to authenticated;

alter table public.liderancas enable row level security;

create policy liderancas_select_public
  on public.liderancas for select
  to anon, authenticated
  using (true);
