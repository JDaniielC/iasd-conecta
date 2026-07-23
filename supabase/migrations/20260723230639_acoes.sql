-- Feature 003: acao-avulsa
-- Ver specs/003-acao-avulsa/contracts/schema.sql (fonte de verdade) e data-model.md.

create table public.acoes (
  id uuid primary key default gen_random_uuid(),
  nome text not null check (length(trim(nome)) > 0),
  data_hora timestamptz not null,
  local text not null,
  detalhes text,
  limite_vagas integer check (limite_vagas is null or limite_vagas > 0),
  criador_id uuid not null references public.perfis(id),
  cancelada_em timestamptz,
  created_at timestamptz not null default now()
);

create table public.confirmacoes_acao (
  acao_id uuid not null references public.acoes(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  status text not null check (status in ('confirmado', 'fila')),
  created_at timestamptz not null default now(),
  primary key (acao_id, usuario_id)
);

-- FR-005/FR-006/FR-007/FR-009: status decidido no banco, sob trava de
-- concorrência (ver research.md).
create function public.confirmacoes_acao_decidir_status()
returns trigger
language plpgsql
as $$
declare
  v_cancelada timestamptz;
  v_limite integer;
  v_confirmados integer;
begin
  perform 1 from public.acoes where id = new.acao_id for update;

  select cancelada_em, limite_vagas into v_cancelada, v_limite
  from public.acoes where id = new.acao_id;

  if v_cancelada is not null then
    raise exception 'ação cancelada, não é possível confirmar presença';
  end if;

  if v_limite is null then
    new.status := 'confirmado';
  else
    select count(*) into v_confirmados
    from public.confirmacoes_acao
    where acao_id = new.acao_id and status = 'confirmado';

    if v_confirmados < v_limite then
      new.status := 'confirmado';
    else
      new.status := 'fila';
    end if;
  end if;

  return new;
end;
$$;

create trigger confirmacoes_acao_decidir_status
  before insert on public.confirmacoes_acao
  for each row
  execute function public.confirmacoes_acao_decidir_status();

-- FR-013: criador vira confirmado automático (mesmo padrão de Grupo/Dono).
create function public.criar_confirmacao_do_criador()
returns trigger
language plpgsql
as $$
begin
  insert into public.confirmacoes_acao (acao_id, usuario_id)
  values (new.id, new.criador_id)
  on conflict (acao_id, usuario_id) do nothing;
  return new;
end;
$$;

create trigger acoes_criador_vira_confirmado
  after insert on public.acoes
  for each row
  execute function public.criar_confirmacao_do_criador();

-- FR-006: promove o mais antigo da fila quando uma vaga confirmada se
-- libera. SECURITY DEFINER porque mexe na linha de outro Usuário.
create function public.promover_fila_acao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
begin
  if old.status = 'confirmado' then
    update public.confirmacoes_acao
    set status = 'confirmado'
    where ctid = (
      select ctid from public.confirmacoes_acao
      where acao_id = old.acao_id and status = 'fila'
      order by created_at
      limit 1
    );
  end if;
  return old;
end;
$$;

create trigger confirmacoes_acao_promover_fila
  after delete on public.confirmacoes_acao
  for each row
  execute function public.promover_fila_acao();

grant select on public.acoes to anon, authenticated;
grant insert, update on public.acoes to authenticated;
grant select on public.confirmacoes_acao to anon, authenticated;
grant insert, delete on public.confirmacoes_acao to authenticated;

alter table public.acoes enable row level security;
alter table public.confirmacoes_acao enable row level security;

create policy acoes_select_public
  on public.acoes for select
  to anon, authenticated
  using (true);

create policy acoes_insert_criador
  on public.acoes for insert
  to authenticated
  with check (auth.uid() = criador_id);

create policy acoes_update_criador
  on public.acoes for update
  to authenticated
  using (auth.uid() = criador_id);

create policy confirmacoes_acao_select_public
  on public.confirmacoes_acao for select
  to anon, authenticated
  using (true);

create policy confirmacoes_acao_insert_self
  on public.confirmacoes_acao for insert
  to authenticated
  with check (auth.uid() = usuario_id);

create policy confirmacoes_acao_delete_self
  on public.confirmacoes_acao for delete
  to authenticated
  using (auth.uid() = usuario_id);
