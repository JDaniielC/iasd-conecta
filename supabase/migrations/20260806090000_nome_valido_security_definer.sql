-- O projeto Supabase de produção sobe com "Enable automatic RLS" ligado: um
-- event trigger liga Row Level Security em toda tabela nova do schema public.
-- `palavras_bloqueadas` era a única tabela do projeto sem RLS de propósito,
-- porque `nome_valido()` roda como invoker e precisava do GRANT pra ler a
-- lista (ver BUG 1 em 20260724130000_fix_rls_security_bugs.sql).
--
-- A combinação falha em silêncio, que é o pior modo de falhar: numa base
-- nova, a tabela nasce com RLS e nenhuma policy. Postgres não levanta erro
-- nesse caso — só devolve zero linhas. `nome_valido()` passaria a enxergar
-- uma lista de palavras bloqueadas vazia e retornaria `true` pra qualquer
-- nome. A moderação sumiria sem nenhum erro no app e sem nenhum teste
-- vermelho (os testes semeiam perfis como superusuário, que bypassa RLS).
--
-- Correção em três partes, tornando o comportamento igual com ou sem o
-- event trigger:
--
-- 1. `nome_valido()` vira SECURITY DEFINER. Passa a rodar como o dono
--    (`postgres`, que tem BYPASSRLS) em vez de como quem chamou, então lê a
--    lista independentemente de RLS e de GRANT.
-- 2. `search_path` fixo. SECURITY DEFINER sem search_path pinado é escalação
--    de privilégio: quem chama poderia apontar `public` pra um schema seu e
--    fazer a função executar o código dele como dono. `extensions` está na
--    lista porque `unaccent` mora em `public` no self-hosted mas pode estar
--    em `extensions` dependendo de como a extensão foi criada.
-- 3. `palavras_bloqueadas` deixa de ser legível por anon/authenticated e
--    ganha RLS. O GRANT de 20260724130000 existia só pra alimentar esta
--    função; sem ele, a lista de palavras bloqueadas deixa de ser conteúdo
--    público — que é o que ela deveria ter sido desde o começo.

create or replace function public.nome_valido(nome text)
returns boolean
language sql
stable
security definer
set search_path = public, extensions, pg_temp
as $$
  select not exists (
    select 1
    from public.palavras_bloqueadas b
    where unaccent(lower(nome)) like '%' || unaccent(lower(b.palavra)) || '%'
  );
$$;

revoke select on public.palavras_bloqueadas from anon, authenticated;

alter table public.palavras_bloqueadas enable row level security;
