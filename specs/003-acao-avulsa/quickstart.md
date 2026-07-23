# Quickstart: Ação Avulsa

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`).

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Criar Ação** (US1, cenários 1-2): criar Ação com/sem limite de vagas →
   já nasce confirmada, criador já aparece como confirmado.
2. **Bloqueio sem campos obrigatórios** (US1, cenário 3): tentar criar sem
   nome/data/local → sistema bloqueia.
3. **Confirmar/desistir** (US2, cenários 1-2): confirmar presença → aparece
   na lista; desistir → some, vaga libera.
4. **Confirmar idempotente** (US2, cenário 3): confirmar de novo já estando
   confirmado → não duplica, não dá erro.
5. **Visitante não confirma** (US2, cenário 4): sem Perfil, tentar
   confirmar → direciona pro cadastro.
6. **Fila de espera** (US3, cenários 1-3): Ação com 1 vaga, dois Usuários
   confirmam (o 2º cai na fila); o 1º desiste → o 2º é promovido
   automaticamente; alguém na fila desiste da fila → sai sem afetar os
   demais.
7. **Cancelar** (US4, cenários 1-3): criador cancela → Ação marcada
   cancelada, ninguém mais confirma; quem não criou não consegue cancelar.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-006/US3: fila promovida automaticamente
-- (criar acao com limite_vagas=1, confirmar dois usuarios, desistir o 1o)
delete from public.confirmacoes_acao where acao_id = '<acao>' and usuario_id = '<primeiro>';
select status from public.confirmacoes_acao where acao_id = '<acao>' and usuario_id = '<segundo>';
-- deve virar 'confirmado'

-- FR-009: sem confirmar em Ação cancelada
update public.acoes set cancelada_em = now() where id = '<acao>';
insert into public.confirmacoes_acao (acao_id, usuario_id) values ('<acao>', '<novo-usuario>');
-- deve levantar excecao "ação cancelada, não é possível confirmar presença"

-- SC-005: nunca mais confirmados que o limite
select count(*) from public.confirmacoes_acao where acao_id = '<acao>' and status = 'confirmado';
-- deve ser <= limite_vagas da acao
```

## Resultados da validação (2026-07-23)

Cenários 1-7 automatizados e verdes (89/89 testes, `flutter test`, contra
Postgres+Auth local via `supabase start`):

- US1: `test/integration/acoes_constraints_test.dart`,
  `test/integration/acao_criador_confirmado_test.dart`,
  `test/unit/acao_model_test.dart`
- US2: `test/integration/confirmar_idempotente_test.dart`,
  `test/integration/acoes_select_publico_test.dart`,
  `test/widget/lista_acoes_page_test.dart`,
  `test/widget/detalhe_acao_page_test.dart`
- US3: `test/integration/fila_de_espera_test.dart`,
  `test/integration/promover_fila_test.dart` (confirma ordem FIFO),
  `test/integration/sair_da_fila_test.dart`
- US4: `test/integration/apenas_criador_cancela_test.dart`,
  `test/integration/acao_cancelada_bloqueia_test.dart`

`flutter build macos --debug` confirma que o app compila e empacota com
as três features (001 + 002 + 003) juntas.

**Mesma lacuna conhecida das features anteriores**: SC-001/SC-002 (tempo de
criar Ação, tempo de refletir confirmar/desistir) não foram cronometrados
em dispositivo real — ambiente de build sem display disponível.

**Lacuna adicional (documentada, não testada)**: a trava de concorrência
(`SELECT ... FOR UPDATE` no trigger de status) é revisada por leitura e
seu comportamento sequencial é testado, mas uma corrida de verdade (dois
inserts simultâneos disputando a última vaga) exigiria orquestrar duas
conexões concorrentes — fora do escopo dos testes automatizados desta
sessão (ver research.md).
