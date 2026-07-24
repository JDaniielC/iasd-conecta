# Quickstart: Dupla Missionária

## Pré-requisitos

Mesmos das features anteriores — `supabase start` com a migration desta
feature aplicada (`supabase db reset`).

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Criar Dupla Missionária avulsa** (US1, cenário 1): criar Ação com
   `eh_dupla_missionaria = true` e `genero_visitado` informado → nasce com
   `limite_vagas = 2`.
2. **Criar Dupla Missionária de Grupo** (US1, cenário 2): mesma regra
   dentro de uma Ação candidata.
3. **Limite não configurável** (US1, cenário 3): tentar `limite_vagas`
   diferente de 2 numa Dupla Missionária → `CHECK constraint` recusa.
4. **Primeira confirmação sempre aceita** (US2, cenário 1): confirmar
   presença sem ninguém confirmado ainda → aceita, qualquer gênero.
5. **2 homens visitando homem** (US2, cenário 2): aceita.
6. **2 homens visitando mulher** (US2, cenário 3): recusada.
7. **2 mulheres visitando homem** (US2, cenário 4): recusada.
8. **1 homem + 1 mulher** (US2, cenário 5): aceita, qualquer visitado.
9. **Fila de espera por capacidade**: com as 2 vagas válidas preenchidas,
   uma 3ª tentativa (qualquer gênero) entra na fila, não é recusada por
   gênero.
10. **Promoção pulando inválido**: uma pessoa confirmada desiste; o
    sistema promove o primeiro da fila que formar composição válida com
    quem ainda está confirmado, pulando os inválidos.

## Verificações estruturais (via SQL, banco local)

```sql
-- FR-003: limite diferente de 2 falha
insert into public.acoes (nome, data_hora, local, criador_id, limite_vagas,
  eh_dupla_missionaria, genero_visitado)
values ('Visita', now(), 'Casa', '<uid>', 3, true, 'masculino');
-- deve violar acoes_dupla_missionaria_check

-- FR-005/FR-006: 2 homens visitando mulher falha na segunda confirmação
-- (primeira confirmação de um homem já aceita via criador_vira_confirmado)
insert into public.confirmacoes_acao (acao_id, usuario_id) values ('<acao>', '<homem2>');
-- deve levantar "composição inválida para Dupla Missionária"

-- FR-008/FR-009: fila promovida pulando inválido
delete from public.confirmacoes_acao where acao_id = '<acao>' and usuario_id = '<confirmado>';
select status from public.confirmacoes_acao where acao_id = '<acao>';
-- o próximo válido da fila deve virar 'confirmado', inválidos continuam 'fila'
```

## Resultado da validação (2026-07-24)

Todos os 10 cenários acima validados manualmente via `docker exec -i
supabase_db_iasd psql` antes do código Dart, com `set role authenticated;
set request.jwt.claims to '...'` simulando cada sessão.

**Bug real encontrado e corrigido durante a validação**:
`confirmacoes_acao_decidir_status()` precisava de `SECURITY DEFINER` — sem
isso, a RLS de `perfis` (só permite ler a própria linha) bloqueava
silenciosamente a leitura do gênero de quem já estava confirmado,
deixando 2 homens visitando mulher passar sem erro. Corrigido antes de
qualquer código Dart ser escrito.

**Segundo bug encontrado pelo próprio teste automatizado**: o `CHECK
constraint` usando `limite_vagas = 2` sozinho permitia `limite_vagas NULL`
passar despercebido (comparação com `NULL` em SQL retorna `NULL`, não
`FALSE`, e `CHECK` só rejeita em `FALSE`). Corrigido com `limite_vagas is
not null and limite_vagas = 2` explícito.

Suíte automatizada completa: `flutter test` → **159/159 passando** (19
novos testes desta feature: 13 de integração — FR-002, FR-003 (×2),
FR-004 (×4: mesmo gênero ×2, gênero misto ×2), FR-005/FR-006 (×2), FR-007,
Edge Case fila por capacidade, FR-009 promoção pulando inválido —, 6
unitários de `NovaAcao`/`Acao` com `isMissionaryPair`/`visitedGender`).
`flutter analyze` → sem apontamentos.
