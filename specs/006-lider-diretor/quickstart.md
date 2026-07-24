# Quickstart: Líder/Diretor de Ministério

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`). Precisa de ao menos um
Administrador do distrito semeado (ver quickstart da feature 005).

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Autodeclarar** (US1, cenário 1): Usuário com Conta chama
   `declarar_lideranca` → declaração pendente criada.
2. **Recusa sem Conta** (US1, cenário 2): Usuário só com Perfil tenta →
   recusado.
3. **Duplicata é não-operação** (US1, cenário 3): chamar de novo pro mesmo
   Grupo/ano → sem erro, sem duplicar.
4. **Admin confirma** (US2, cenário 1): `decidir_lideranca(id, true)` →
   vira confirmada.
5. **Admin rejeita** (US2, cenário 2): `decidir_lideranca(id, false)` →
   não confirmada.
6. **Recusa por não-admin** (US2, cenários 3-4): Dono do Grupo ou Usuário
   comum tenta decidir → recusado.
7. **Identificação pública** (US3): qualquer pessoa vê o Líder confirmado
   do ano corrente na página do Grupo, sem Perfil.
8. **Codireção** (US3, cenário 2): dois Líderes confirmados do mesmo Grupo
   aparecem os dois.
9. **Expiração preguiçosa** (US4): confirmação de ano anterior não conta
   como atual; redeclarar pro ano corrente funciona normalmente.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-002: sem Conta falha
select public.declarar_lideranca('<grupo>', 2026); -- como usuario so-perfil
-- deve levantar excecao "usuário precisa ter Conta..."

-- FR-003: duplicata e nao-operacao
select public.declarar_lideranca('<grupo>', 2026); -- de novo, mesma pessoa
select count(*) from public.liderancas where grupo_id = '<grupo>'; -- ainda 1

-- FR-004/FR-005: so admin decide
select public.decidir_lideranca('<lideranca>', true); -- como nao-admin
-- deve levantar excecao "só um Administrador do distrito..."

-- FR-006/FR-008: so confirmada do ano corrente conta como atual
select * from public.liderancas
where grupo_id = '<grupo>' and confirmado_em is not null and rejeitado_em is null
  and ano = extract(year from now())::int;
```

## Resultado da validação (2026-07-24)

Todos os 9 cenários acima validados manualmente via `docker exec -i
supabase_db_iasd psql` antes de qualquer código Dart, com `set role
authenticated; set request.jwt.claims to '...'` simulando cada sessão —
inclusive o caso de codireção (dois `usuario_id` confirmados no mesmo
`grupo_id`/ano) e o de expiração preguiçosa (linha de ano anterior não
contada, redeclaração no ano corrente cria linha nova).

Suíte automatizada completa: `flutter test` → **140/140 passando** (18 novos
testes desta feature: 10 de integração — FR-002, FR-003, FR-004,
FR-005 (×2), FR-006/FR-008 (×2), FR-009, FR-010 —, 6 unitários de
`LeadershipDeclaration.status`/`isCurrentFor`, 2 de widget de
`DetalheGrupoPage` — codireção e ausência de seção sem Líder confirmado).
`flutter analyze` → sem apontamentos.
