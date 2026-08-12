-- PENDENCIAS.md § 2.2 — `anon` e `authenticated` herdam TRUNCATE, REFERENCES
-- e TRIGGER em toda tabela de `public`: default do fornecedor Supabase
-- (pg_default_acl "FOR ROLE postgres" já concede `Dxtm` pra esses dois papéis
-- em toda relação — ver a mesma investigação em
-- 20260805090000_service_role_default_privileges.sql), nunca concedido por
-- este projeto.
--
-- TRUNCATE importa mais que os outros dois porque ignora RLS por completo
-- (não é "select/insert/update/delete filtrado pela policy que não se aplica"
-- — é outro caminho de execução no Postgres, que nem consulta pg_policy) E
-- não dispara gatilho `after delete`. As duas garantias sobre as quais este
-- projeto constrói privacidade e limpeza de arquivo (bucket do Storage
-- limpo por gatilho enfileirando trabalho, feature 013) dependem de DELETE
-- passar pela policy e pelo gatilho — TRUNCATE pula as duas.
--
-- Não é vulnerabilidade viva hoje: `anon` é `rolcanlogin = f`, só alcançável
-- via PostgREST, que mapeia verbo HTTP para SELECT/INSERT/UPDATE/DELETE e
-- nunca emite TRUNCATE. É higiene de menor privilégio numa porta que hoje
-- ninguém alcança — mas a feature 013 mediu a consequência concreta que essa
-- porta teria em `fotos_capa`: uma única instrução apagaria todas as linhas
-- sem enfileirar limpeza, e todos os arquivos do bucket virariam órfãos de
-- uma vez. `fotos_capa` e `denuncias_imagem` já saíram do default nas
-- migrations da feature 013; esta migration fecha as outras 14 tabelas.
--
-- REFERENCES e TRIGGER entram junto porque vieram juntos no mesmo default,
-- não porque têm o mesmo efeito dramático — nenhum caminho do app precisa
-- que anon/authenticated criem FK ou gatilho.
--
-- Dois revokes, não um: o primeiro fecha as tabelas que já existem; sem o
-- segundo, a próxima `create table` em `public` (rodando como `postgres`,
-- como toda migration deste projeto) herdaria o default de novo e a porta
-- reabriria em silêncio, sem que quem escreveu a migration seguinte
-- precisasse lembrar de revogar.

revoke truncate, references, trigger
  on all tables in schema public
  from anon, authenticated;

alter default privileges for role postgres in schema public
  revoke truncate, references, trigger
  on tables
  from anon, authenticated;
