# Quickstart: Ação Sugerida

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`). Precisa de ao menos uma Categoria
de Grupo (feature 002) e um Administrador do distrito semeado (feature
005) pra testar cadastro/remoção.

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Sugestão automática na candidata** (US1, cenário 1): Grupo de
   Categoria X com Ações sugeridas cadastradas → propor candidata nesse
   Grupo mostra as sugestões de X.
2. **Categoria sem sugestão** (US1, cenário 2): Grupo de Categoria sem
   nenhuma Ação sugerida → nenhuma sugestão aparece, nome livre funciona.
3. **Nome livre sempre disponível** (US1/US2, cenário 3): digitar fora da
   lista de sugestões é aceito normalmente.
4. **Filtro na Ação avulsa** (US2, cenário 1): escolher Categoria X na
   tela de criar Ação avulsa mostra só as sugestões de X.
5. **Filtro não persiste** (US2, cenário 2): Ação avulsa criada depois de
   escolher um filtro não tem nenhuma Categoria salva.
6. **Sem escolher filtro** (US2, cenário 3): nenhuma Categoria escolhida →
   nenhuma sugestão, campo livre funciona.
7. **Administrador cadastra** (US3, cenário 1): nova Ação sugerida
   aparece nas sugestões da Categoria.
8. **Administrador remove** (US3, cenário 2): sugestão removida some da
   lista, sem afetar Ações já criadas.
9. **Não-Administrador recusado** (US3, cenário 3): tentar
   cadastrar/remover sem ser Administrador falha.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-003: não-admin não consegue cadastrar
insert into public.acoes_sugeridas (categoria_id, nome) values ('<categoria>', 'Ensaio');
-- como não-admin: deve falhar por RLS (0 rows affected / erro de policy)

-- FR-004: sugestões da candidata batem com a categoria do grupo
select s.nome from public.acoes_sugeridas s
join public.categorias_grupo c on c.id = s.categoria_id
where c.nome = (select categoria from public.grupos where id = '<grupo>');

-- FR-009: mesmo nome em categorias diferentes é permitido
insert into public.acoes_sugeridas (categoria_id, nome) values ('<categoria_a>', 'Retiro');
insert into public.acoes_sugeridas (categoria_id, nome) values ('<categoria_b>', 'Retiro');
-- ambos devem funcionar sem erro
```

## Resultado da validação (2026-07-24)

Todos os 9 cenários acima validados manualmente via `docker exec -i
supabase_db_iasd psql` antes do código Dart. Nenhum bug real encontrado
nesta feature (diferente de 006/007) — a autorização é uma `policy` RLS
simples, sem função `SECURITY DEFINER`, e não há `CHECK constraint`
condicional com risco de `NULL` (ver research.md).

Suíte automatizada completa: `flutter test` → **167/167 passando** (8
novos testes desta feature: 5 de integração — FR-004, FR-008, FR-003
(×2), FR-001/FR-002, FR-009 —, 1 unitário de `SuggestedAction`, 1 widget
— filtro de Categoria + chip preenche o campo de nome). `flutter
analyze` → sem apontamentos.
