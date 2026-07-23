# Quickstart: Grupos

## Pré-requisitos

Mesmos da feature 001 — `supabase start` rodando com a migration desta
feature aplicada (`supabase db reset` depois de adicionar a migration em
`supabase/migrations/`).

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Criar Grupo** (US1, cenário 1): com um Perfil ativo, criar Grupo com
   nome/Categoria/horário/local preenchidos → Grupo aparece na lista com
   esse Perfil como Dono.
2. **Bloqueio sem nome/Categoria** (US1, cenário 2): tentar criar sem nome
   ou sem Categoria → sistema bloqueia.
3. **Visitante vê Grupos livremente** (US2, cenário 1): sem nenhum Perfil,
   abrir lista de Grupos e detalhes → tudo visível.
4. **Visitante não participa** (US2, cenário 2): Visitante tenta Participar
   → direcionado ao cadastro de Perfil.
5. **Participar/sair** (US2, cenários 3-4): Usuário participa → aparece na
   lista de participantes; sai → some da lista; participa de novo → funciona.
6. **Dono edita** (US3, cenário 1): editar nome/horário/local/detalhes →
   mudança visível pra todo mundo.
7. **Dono remove participante** (US3, cenário 2): remover alguém → some da
   lista de participantes.
8. **Transferir posse** (US3, cenário 3): transferir pra outro participante
   → esse vira o novo Dono, o antigo vira participante comum.
9. **Não-Dono não administra** (US3, cenário 4): tentar editar/remover/
   transferir sem ser Dono → recusado.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-011: só dá pra transferir pra quem já participa
update public.grupos set dono_id = '<id-de-quem-nao-participa>' where id = '<grupo>';
-- deve levantar excecao "novo dono precisa participar do grupo..."

-- FR-012: Dono nao sai sem transferir antes
delete from public.participacoes_grupo where grupo_id = '<grupo>' and usuario_id = '<dono-atual>';
-- deve levantar excecao "transfira a posse do grupo antes de sair"

-- FR-013: participar e idempotente
insert into public.participacoes_grupo (grupo_id, usuario_id) values ('<grupo>', '<usuario-ja-participante>')
  on conflict (grupo_id, usuario_id) do nothing;
-- nao deve gerar erro nem duplicar linha
```

## Resultados da validação (2026-07-23)

Cenários 1-9 automatizados e verdes (61/61 testes, `flutter test`, contra
Postgres+Auth local via `supabase start`):

- US1: `test/integration/grupos_constraints_test.dart`,
  `test/integration/grupo_dono_participante_test.dart`,
  `test/unit/grupo_model_test.dart`
- US2: `test/integration/grupos_select_publico_test.dart`,
  `test/integration/participar_idempotente_test.dart`,
  `test/widget/lista_grupos_page_test.dart`,
  `test/widget/detalhe_grupo_page_test.dart`
- US3: `test/integration/transferir_posse_test.dart`,
  `test/integration/dono_nao_sai_sem_transferir_test.dart`,
  `test/integration/apenas_dono_administra_test.dart`,
  `test/widget/editar_grupo_page_test.dart`
- Correção do router (feature 001): `test/widget/router_visitante_test.dart`
  confirma que Visitante sem Perfil cai direto na lista de Grupos.

`flutter build macos --debug` confirma que o app compila e empacota com as
duas features (001 + 002) juntas.

**Mesma lacuna conhecida da feature 001**: SC-001/SC-003 (tempo de criar
Grupo, tempo de refletir Participar/sair) não foram cronometrados em
dispositivo real — ambiente de build sem display disponível.
