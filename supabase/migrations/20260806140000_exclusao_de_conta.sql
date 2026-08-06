-- Feature 009: exclusão de conta com anonimização do Perfil e herança de posse.
-- Ver specs/009-exclusao-de-conta/contracts/schema.sql (fonte de verdade),
-- spec.md (o quê e por quê) e research.md (alternativas descartadas).
--
-- O problema: apagar o auth.users de quem é Dono de Grupo, criador de Ação,
-- abriu Rodada, é Administrador do distrito ou tem declaração de Líder/Diretor
-- falha por violação de chave estrangeira — 8 colunas referenciam perfis(id)
-- com ON DELETE NO ACTION. Na prática, o direito de exclusão do art. 18, VI da
-- LGPD não é cumprível hoje para esses usuários, e a Política de Privacidade
-- admite isso.
--
-- A saída não é cascatear (destruiria Grupo de terceiros) nem bloquear até a
-- pessoa transferir tudo na mão (condicionar um direito do titular a uma
-- tarefa dele é obstáculo ao art. 18). É anonimizar o Perfil — o art. 16
-- dispensa a exclusão quando o dado está anonimizado — e transferir para o
-- Administrador do distrito mais antigo apenas o que exige alguém capaz de
-- agir: posse de Grupo e Rodada de votação ainda aberta.

-- ---------------------------------------------------------------------------
-- 1. O Perfil precisa sobreviver ao fim do login
-- ---------------------------------------------------------------------------
-- perfis.id referencia auth.users(id) com ON DELETE CASCADE. Enquanto essa FK
-- existir, apagar o login apaga a linha de perfis — e a linha anonimizada é
-- justamente a âncora do histórico de terceiros. Nenhuma variação de ON DELETE
-- resolve: SET NULL é impossível (a coluna é PK) e NO ACTION bloquearia a
-- exclusão do próprio login.
--
-- Consequência aceita: perfis deixa de ter garantia referencial contra
-- auth.users, e passa a existir legitimamente linha de perfis sem auth.users
-- correspondente — que é exatamente o estado "anonimizado". A única escrita em
-- perfis.id continua sendo o cadastro, que grava auth.uid().

alter table public.perfis drop constraint perfis_id_fkey;

-- ---------------------------------------------------------------------------
-- 2. Anonimização de verdade exige gênero e idade nulos
-- ---------------------------------------------------------------------------
-- Num distrito pequeno, gênero + idade + quais Grupos a pessoa participava
-- reidentifica. Como o art. 16 só dispensa a exclusão quando o dado está
-- anonimizado, deixar esses dois campos tornaria frágil a base para conservar
-- a linha. Os check constraints existentes toleram nulo: no Postgres um CHECK
-- que resulta em NULL passa, então apelido_obrigatorio_menor
-- (idade >= 18 or apelido is not null) não bloqueia idade nula.

alter table public.perfis alter column genero drop not null;
alter table public.perfis alter column idade drop not null;
alter table public.perfis add column anonimizado_em timestamptz;
