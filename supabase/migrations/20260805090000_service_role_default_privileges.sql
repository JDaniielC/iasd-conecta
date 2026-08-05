-- Achado ao construir scripts/bootstrap_admin.sh (2026-08-04): service_role
-- tem BYPASSRLS mas não ganha GRANT em tabela nenhuma por padrão neste
-- self-hosted. Causa raiz (pg_default_acl): o default configurado é "FOR
-- ROLE supabase_admin" (arwdDxtm pra todo mundo, correto) — mas as
-- migrations deste projeto rodam como `postgres`, e o default "FOR ROLE
-- postgres" só dá Dxtm (sem select/insert/update/delete) pra
-- anon/authenticated/service_role. anon/authenticated nunca sentiram
-- porque toda migration já dá grant explícito por tabela pra eles; só
-- service_role nunca tinha sido usado antes do bootstrap_admin.sh, então
-- nunca apareceu.
--
-- Diferente de anon/authenticated (que ficam com grant explícito e
-- escopado por tabela de propósito, seguindo RLS por política), service_role
-- por definição sempre deve ter acesso total — é o papel de bypass
-- confiável da plataforma. Por isso aqui é ALTER DEFAULT PRIVILEGES (pra
-- toda tabela futura ganhar automático) + backfill nas 13 tabelas
-- existentes, ao invés de grant tabela por tabela feito à mão de novo.

alter default privileges for role postgres in schema public
  grant select, insert, update, delete on tables to service_role;

do $$
declare
  t record;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format(
      'grant select, insert, update, delete on public.%I to service_role',
      t.tablename
    );
  end loop;
end;
$$;
