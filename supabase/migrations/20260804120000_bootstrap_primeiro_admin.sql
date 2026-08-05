-- Permite a primeira linha de administradores_distrito nascer sem exigir
-- admin pré-existente (bootstrap). Ver docs/plans/2026-08-04-bootstrap-admin-design.md.
-- A exceção só vale pra chamada sem auth.uid() (service_role do
-- scripts/bootstrap_admin.sh, ou psql direto) — NÃO pra qualquer papel só
-- por a tabela estar vazia. Achado testando o teste FR-003 já existente
-- (district_admin_promote_authorization_test.dart): uma primeira versão
-- ingênua (bypass por "tabela vazia", sem checar auth.uid()) deixava
-- QUALQUER usuário autenticado virar o primeiro Administrador se
-- corresse antes de alguém rodar o bootstrap — escalação de privilégio.
-- Da segunda linha em diante, ou pra qualquer chamada autenticada, regra
-- original: só admin promove admin.
create or replace function public.administradores_distrito_checar_regras()
returns trigger
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_eh_anonimo boolean;
begin
  if auth.uid() is null and not exists (select 1 from public.administradores_distrito) then
    return new;
  end if;

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

-- Privilégio de service_role nas tabelas (administradores_distrito, perfis,
-- igrejas, palavras_bloqueadas) resolvido de forma geral em
-- 20260805090000_service_role_default_privileges.sql, não aqui.
