-- Contrato de schema: Ação Sugerida (008)
-- Fonte de verdade que a migration em supabase/migrations/ deve seguir.
-- Depende do schema das features 002 (categorias_grupo) e 005
-- (administradores_distrito) já aplicado.

create table public.acoes_sugeridas (
  id uuid primary key default gen_random_uuid(),
  categoria_id uuid not null references public.categorias_grupo(id),
  nome text not null check (length(trim(nome)) > 0)
);

grant select on public.acoes_sugeridas to anon, authenticated;
grant insert, delete on public.acoes_sugeridas to authenticated;

alter table public.acoes_sugeridas enable row level security;

create policy acoes_sugeridas_select_public
  on public.acoes_sugeridas for select
  to anon, authenticated
  using (true);

-- FR-001/FR-003: só Administrador do distrito cadastra.
create policy acoes_sugeridas_insert_admin
  on public.acoes_sugeridas for insert
  to authenticated
  with check (
    exists (select 1 from public.administradores_distrito where usuario_id = auth.uid())
  );

-- FR-002/FR-003: só Administrador do distrito remove.
create policy acoes_sugeridas_delete_admin
  on public.acoes_sugeridas for delete
  to authenticated
  using (
    exists (select 1 from public.administradores_distrito where usuario_id = auth.uid())
  );
