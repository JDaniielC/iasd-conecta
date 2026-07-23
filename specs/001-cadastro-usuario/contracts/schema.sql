-- Contrato de schema: Cadastro de Perfil e Upgrade para Conta (001)
-- Fonte de verdade que supabase/migrations/0001_perfis_igrejas.sql deve seguir.

create extension if not exists "unaccent";

create table public.igrejas (
  id uuid primary key default gen_random_uuid(),
  nome text not null unique,
  created_at timestamptz not null default now()
);

create table public.palavras_bloqueadas (
  palavra text primary key
);

create function public.nome_valido(nome text)
returns boolean
language sql
stable
as $$
  select not exists (
    select 1
    from public.palavras_bloqueadas b
    where unaccent(lower(nome)) like '%' || unaccent(lower(b.palavra)) || '%'
  );
$$;

create table public.perfis (
  id uuid primary key references auth.users(id) on delete cascade,
  nome text not null check (nome_valido(nome)),
  apelido text,
  igreja_id uuid references public.igrejas(id),
  telefone text,
  genero text not null check (genero in ('masculino', 'feminino')),
  idade integer not null check (idade >= 0),
  consentimento_lgpd_aceito_em timestamptz not null,
  created_at timestamptz not null default now(),
  constraint apelido_obrigatorio_menor check (idade >= 18 or apelido is not null)
);

create function public.perfil_publico(p_id uuid)
returns table (id uuid, nome_exibido text, igreja_id uuid)
language sql
stable
security definer
set search_path = public
as $$
  select p.id, coalesce(p.apelido, p.nome) as nome_exibido, p.igreja_id
  from public.perfis p
  where p.id = p_id;
$$;

grant execute on function public.perfil_publico(uuid) to anon, authenticated;

-- RLS restringe LINHAS, mas Postgres ainda exige GRANT de coluna/tabela antes
-- disso; sem isso, "authenticated" nem chega a avaliar a policy.
grant select on public.igrejas to anon, authenticated;
grant select, insert, update on public.perfis to authenticated;

alter table public.igrejas enable row level security;
alter table public.perfis enable row level security;

create policy igrejas_select_public
  on public.igrejas for select
  to anon, authenticated
  using (true);

create policy perfis_select_own
  on public.perfis for select
  to authenticated
  using (auth.uid() = id);

create policy perfis_insert_own
  on public.perfis for insert
  to authenticated
  with check (auth.uid() = id);

create policy perfis_update_own
  on public.perfis for update
  to authenticated
  using (auth.uid() = id);
