## 1. Levantamento

- [x] 1.1 Listar as tabelas de `public` com os três privilégios ainda
      concedidos a `anon`/`authenticated`, e anotar **o número** — é o antes
      (`information_schema.role_table_grants` via `docker exec supabase_db_iasd
      psql`): 14 tabelas × 2 papéis = 28 linhas, todas com
      `REFERENCES, TRIGGER, TRUNCATE`)
- [x] 1.2 Anotar a contagem atual das três suítes, para comparar depois
      (`flutter analyze`: 0 issues; `flutter test test/unit test/widget`: 273
      passando; `dart test test/integration`: 210 passando — todas verdes,
      depois de `supabase db reset` pra alinhar o Postgres local só com as
      migrations desta worktree, ver nota abaixo)

## 2. Migration

- [x] 2.1 `revoke truncate, references, trigger on all tables in schema public
      from anon, authenticated` — `supabase/migrations/20260811120000_revogar_truncate_de_anon_e_authenticated.sql`
- [x] 2.2 `alter default privileges in schema public revoke ...` para que tabela
      nova nasça fechada (`for role postgres`, porque é o papel que roda as
      migrations deste projeto — mesma descoberta de
      `20260805090000_service_role_default_privileges.sql`)
- [x] 2.3 Comentário registrando por que TRUNCATE importa aqui: ignora RLS e não
      dispara gatilho `after delete` — foi o que a feature 013 mediu.
      Aplicado via `supabase db reset`: 0 linhas remanescentes em
      `role_table_grants` para os três privilégios em `anon`/`authenticated`;
      `pg_default_acl FOR ROLE postgres` confirmado sem `D`/`x`/`t`

## 3. Prova

- [x] 3.1 Como `authenticated`, `truncate` em três tabelas de natureza diferente
      (uma com RLS de leitura pública, uma com gatilho, uma de junção) recusa
      — `test/integration/privilegios_publicos_truncate_test.dart`: `acoes`
      (RLS pública), `perfis` (gatilho), `participacoes_grupo` (junção),
      todas recusando com código `42501`
- [x] 3.2 Criar tabela de teste numa transação revertida e conferir que ela
      nasce **sem** os privilégios — mesmo arquivo, teste 4: `create table`
      dentro de `begin`/`rollback`, `information_schema.role_table_grants`
      vazio para `anon`/`authenticated` antes do `rollback`
- [x] 3.3 Rodar as três suítes e comparar com o número de 1.2 — igual, não
      "passou". `flutter analyze`: 0 issues (igual). `flutter test test/unit
      test/widget`: 273 passando (igual). `dart test test/integration`: 210
      → 214 passando — delta de +4 é exatamente os 4 testes novos de 3.1/3.2,
      nenhuma queda de teste pré-existente, nenhuma falha. Nenhum caminho
      legítimo dependia de REFERENCES/TRIGGER/TRUNCATE

## 4. Registro

- [x] 4.1 Fechar `PENDENCIAS.md` § 2.2 com a data e os números — feito,
      2026-08-11, com antes/depois de grants e das três suítes
