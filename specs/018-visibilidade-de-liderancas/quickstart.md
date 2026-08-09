# Quickstart — provar o vazamento, fechar, e provar que fechou

**Feature**: 018-visibilidade-de-liderancas | **Date**: 2026-08-09

O roteiro é deliberadamente nesta ordem: **reproduzir o vazamento antes de consertar**. Se a
Parte 1 não retornar a declaração rejeitada, alguma coisa está errada no seu ambiente — e
consertar sem ver o problema é como validar por tela.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start            # sobe Postgres local com as migrations aplicadas
```

`psql` na porta 54322 a partir do host costuma dar conexão recusada mesmo com a porta
publicada. Todos os comandos abaixo rodam **dentro do container**, que é o que funcionou de
fato (mesmo achado da feature 011).

## Parte 0 — Verificar as três premissas ANTES de escrever a migration

`contracts/schema.sql` depende delas. Se qualquer uma cair, **parar** e revisar o contrato —
ver `research.md` D-009.

```bash
# 1. liderancas não pode estar com force row level security, senão
#    excluir_minha_conta (feature 009, security definer) passaria a ser filtrado
#    e a exclusão de conta deixaria de apagar a declaração.
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select relname||' | rls='||relrowsecurity||' | force='||relforcerowsecurity \
   from pg_class where relname in ('liderancas','administradores_distrito');"

# 2. anon/authenticated só podem ter SELECT em liderancas — escrita é só pelas
#    funções security definer.
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select grantee||' | '||privilege_type from information_schema.role_table_grants \
   where table_schema='public' and table_name='liderancas' \
     and grantee in ('anon','authenticated') order by 1;"

# 3. administradores_distrito continua legível por anon/authenticated — se apertar,
#    o 3º disjunto para de enxergar a linha do admin e a tela de pendências esvazia.
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select polname from pg_policy p join pg_class c on c.oid = p.polrelid \
   where c.relname = 'administradores_distrito';"
```

**Esperado**:

```
liderancas | rls=true | force=false
administradores_distrito | rls=true | force=false
anon | SELECT
authenticated | SELECT
administradores_distrito_select_public
```

**Se `force=t` em `liderancas`**: parar. Seguir mesmo assim troca um vazamento de privacidade
por um bug de exclusão de conta — que também é LGPD, e pior.

**Se aparecer `INSERT`/`UPDATE`/`DELETE` para `anon` ou `authenticated`**: parar. Significa
que alguém pode gravar direto na tabela, e o predicado `rejeitado_em is null` da política
passa a ser a única coisa entre um insert forjado e a página pública.

## Parte 1 — Reproduzir o vazamento (antes do fix)

Semear os três estados no mesmo Grupo e ler **como `anon`**, que é o role que o PostgREST usa
para um Visitante sem cadastro:

```bash
docker exec supabase_db_iasd psql -U postgres -d postgres <<'SQL'
begin;
insert into auth.users (id, aud, role, instance_id) values
  ('99000000-0000-0000-0000-000000000001','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
  ('99000000-0000-0000-0000-000000000002','authenticated','authenticated','00000000-0000-0000-0000-000000000000'),
  ('99000000-0000-0000-0000-000000000003','authenticated','authenticated','00000000-0000-0000-0000-000000000000');
insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) values
  ('99000000-0000-0000-0000-000000000001','Confirmada QS','feminino',30, now()),
  ('99000000-0000-0000-0000-000000000002','Pendente QS','feminino',30, now()),
  ('99000000-0000-0000-0000-000000000003','Rejeitada QS','feminino',30, now());
insert into public.grupos (id, nome, categoria, horario, local, dono_id) values
  ('99000000-0000-0000-0000-0000000000aa','Ministério QS','Ministério Jovem','sábados','Sede',
   '99000000-0000-0000-0000-000000000001');
insert into public.liderancas (grupo_id, usuario_id, ano, confirmado_em, confirmado_por) values
  ('99000000-0000-0000-0000-0000000000aa','99000000-0000-0000-0000-000000000001',
   extract(year from now())::int, now(), '99000000-0000-0000-0000-000000000001');
insert into public.liderancas (grupo_id, usuario_id, ano) values
  ('99000000-0000-0000-0000-0000000000aa','99000000-0000-0000-0000-000000000002',
   extract(year from now())::int);
insert into public.liderancas (grupo_id, usuario_id, ano, rejeitado_em) values
  ('99000000-0000-0000-0000-0000000000aa','99000000-0000-0000-0000-000000000003',
   extract(year from now())::int, now());
commit;

set role anon;
select p.nome,
       case when l.confirmado_em is not null then 'confirmada'
            when l.rejeitado_em  is not null then 'REJEITADA'
            else 'PENDENTE' end as estado
from public.liderancas l join public.perfis p on p.id = l.usuario_id
where l.grupo_id = '99000000-0000-0000-0000-0000000000aa' order by 2;
reset role;
SQL
```

**Esperado ANTES do fix — 3 linhas.** É o vazamento:

```
 Confirmada QS | confirmada
 Pendente QS   | PENDENTE
 Rejeitada QS  | REJEITADA
```

O `join` com `perfis` acima roda como `postgres`; num ataque real o nome sairia da RPC
`perfil_publico`, que é pública. O ponto é o `usuario_id` + estado, e esse a policy entrega.

## Parte 2 — Aplicar a mudança

```bash
# criar supabase/migrations/<timestamp>_liderancas_visibilidade.sql com o conteúdo
# de specs/018-visibilidade-de-liderancas/contracts/schema.sql
supabase db reset          # reaplica tudo do zero, do jeito que o CI faz
```

Conferir que a política velha morreu e a nova nasceu:

```bash
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select polname from pg_policy p join pg_class c on c.oid = p.polrelid \
   where c.relname = 'liderancas';"
```

**Esperado**: `liderancas_select_confirmada_propria_ou_admin`, e **nenhuma** linha
`liderancas_select_public`.

## Parte 3 — Provar que fechou (os quatro leitores)

Repetir o seed da Parte 1 (o `db reset` apagou tudo), promover um admin, e ler com cada role.
`set role anon` e `set role authenticated` + `request.jwt.claims` são exatamente o que o
PostgREST faz — não é aproximação.

```bash
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc "
  set role anon;
  select 'anon => '||count(*) from public.liderancas
  where grupo_id = '99000000-0000-0000-0000-0000000000aa';"
```

| Leitor | Como | Esperado |
|---|---|---|
| Visitante | `set role anon` | **1** (só a confirmada) |
| Usuário comum que não é o autor | `set role authenticated` + `sub` de um quarto usuário | **1** |
| A pessoa que se declarou e foi rejeitada | `sub` = `...0003` | **2** (a confirmada pública + a própria rejeitada) |
| Administrador do distrito | `sub` de um usuário em `administradores_distrito` | **3** |

Sempre com **os dois** resets ao final de cada bloco:

```sql
reset role;
reset request.jwt.claims;
```

`reset role` **não** limpa GUC customizado. Sem `reset request.jwt.claims`, o `set role anon`
seguinte ainda enxerga o `sub` anterior e o resultado mente — armadilha documentada em
`test/integration/church_archive_visibility_test.dart:18-22`.

Limpeza:

```bash
docker exec supabase_db_iasd psql -U postgres -d postgres -c \
  "delete from public.liderancas where grupo_id = '99000000-0000-0000-0000-0000000000aa';
   delete from public.grupos where id = '99000000-0000-0000-0000-0000000000aa';
   delete from public.perfis where nome like '% QS';
   delete from auth.users where id::text like '99000000%';"
```

## Parte 4 — Gates

```bash
flutter analyze                              # esperado: 0 issues
flutter test test/unit test/widget           # esperado: 152 (inalterado)
dart test test/integration                   # esperado: 133 (127 + 6 novos)
flutter build web                            # esperado: build sem erro
```

O número de integração é a evidência da feature. `133` sem os 6 casos novos significa que o
arquivo de teste não rodou.

## Parte 5 — Conferência manual das três telas (regressão, não prova)

Isto **não** vale como verificação de SC-001 — é só para pegar quebra visível. A prova é a
Parte 3.

```bash
flutter run -d chrome
```

1. Sem fazer nada (Visitante): abrir um Grupo com Líder confirmado → a seção "Líder/Diretor"
   aparece com o nome.
2. Como o Usuário que se declarou e foi rejeitado: abrir o Grupo → a tela de declaração mostra
   o estado da própria declaração.
3. Como Administrador do distrito: abrir `/leadership/pending` → as pendentes do distrito
   continuam listadas.
4. Como Usuário comum (não admin, sem declaração): abrir `/leadership/pending` na barra de
   endereço → "Nenhuma declaração pendente.", sem erro e sem tela vermelha. Esse é o
   comportamento **novo e desejado**.
