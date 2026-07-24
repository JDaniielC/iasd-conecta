# Quickstart: Administrador do Distrito

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`).

## Semear o primeiro Administrador do distrito (fora do fluxo do app)

Depois de criar um Perfil normalmente e fazer upgrade pra Conta (feature
001), rode direto no Postgres local (ou como `service_role`):

```sql
-- Trigger dispara pra qualquer papel (RLS bypass de service_role/superusuário
-- não pula trigger) — por isso precisa desabilitar/reabilitar em volta do
-- insert. Descoberto durante a validação empírica desta feature.
alter table public.administradores_distrito
  disable trigger administradores_distrito_checar_regras_trigger;

insert into public.administradores_distrito (usuario_id, promovido_por)
values ('<id-do-perfil-com-conta>', '<id-do-perfil-com-conta>');

alter table public.administradores_distrito
  enable trigger administradores_distrito_checar_regras_trigger;
```

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Promover Administrador** (US1, cenário 1): Administrador semeado
   promove um Usuário com Conta → esse Usuário vira Administrador.
2. **Recusa sem Conta** (US1, cenário 2): tentar promover um Usuário só
   com Perfil → recusado.
3. **Recusa por não-admin** (US1, cenário 3): Usuário comum tenta promover
   → recusado.
4. **Adicionar Igreja** (US2, cenário 1): Administrador adiciona uma
   Igreja nova → aparece na lista pra todo mundo.
5. **Arquivar Igreja** (US2, cenário 2): Administrador arquiva uma Igreja
   → some da lista de opções, mas vínculos antigos continuam intactos.
6. **Recusa por não-admin** (US2, cenário 3): Usuário comum tenta
   adicionar/arquivar → recusado.
7. **Visibilidade de arquivadas** (US2, cenário 4): só Administrador vê
   arquivadas na lista.
8. **Cancelar qualquer Ação** (US3): Administrador cancela uma Ação que
   não criou e cujo Grupo não administra.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-002: promover usuario sem Conta falha
insert into public.administradores_distrito (usuario_id, promovido_por)
values ('<id-perfil-sem-conta>', '<id-admin>');
-- deve levantar excecao "usuário precisa ter Conta..."

-- FR-007/FR-008: arquivada some pra nao-admin, continua visivel pra admin
update public.igrejas set arquivada_em = now() where id = '<igreja>';
select count(*) from public.igrejas where id = '<igreja>'; -- como anon: 0
select count(*) from public.igrejas where id = '<igreja>'; -- como admin: 1

-- FR-009: admin cancela qualquer Acao
update public.acoes set cancelada_em = now() where id = '<qualquer-acao>';
-- como admin: funciona mesmo sem ser criador nem dono do grupo
```

## Resultados da validação (2026-07-24)

Cenários 1-8 automatizados e verdes (122/122 testes, `flutter test`, contra
Postgres+Auth local via `supabase start`):

- US1: `test/integration/district_admin_promote_authorization_test.dart`,
  `test/integration/district_admin_requires_account_test.dart`,
  `test/unit/district_admin_model_test.dart`
- US2: `test/integration/church_manage_authorization_test.dart`,
  `test/integration/church_archive_visibility_test.dart`,
  `test/widget/manage_churches_page_test.dart`
- US3: `test/integration/district_admin_cancel_any_action_test.dart`

`flutter build macos --debug` confirma que o app compila e empacota com
as cinco features (001-005) juntas.

**Achado de metodologia de teste**: `RESET ROLE` não limpa o GUC
`request.jwt.claims` sozinho — uma sessão psql que fez `set role
authenticated; set request.jwt.claims ...` e depois só `reset role` ainda
enxerga o claim antigo em consultas seguintes. Toda checagem manual/teste
que simula papel `anon` depois de uma checagem autenticada agora também dá
`reset request.jwt.claims` explicitamente (ver
`church_archive_visibility_test.dart`).

**Mesma lacuna conhecida das features anteriores**: SC-001/SC-003 (tempo
de promover, tempo de refletir arquivamento) não foram cronometrados em
dispositivo real — ambiente de build sem display disponível.
