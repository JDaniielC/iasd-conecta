# Data Model: Ação Avulsa

## `public.acoes`

| Coluna | Tipo | Regra |
|---|---|---|
| `id` | `uuid` | PK, default `gen_random_uuid()` |
| `nome` | `text` | `NOT NULL`, `CHECK (length(trim(nome)) > 0)` |
| `data_hora` | `timestamptz` | `NOT NULL` |
| `local` | `text` | `NOT NULL` |
| `detalhes` | `text` | nullable |
| `limite_vagas` | `integer` | nullable, `CHECK (limite_vagas is null or limite_vagas > 0)` — nulo = ilimitada |
| `criador_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id)` |
| `cancelada_em` | `timestamptz` | nullable — presente = Ação cancelada |
| `created_at` | `timestamptz` | default `now()` |

## `public.confirmacoes_acao`

| Coluna | Tipo | Regra |
|---|---|---|
| `acao_id` | `uuid` | `NOT NULL`, `REFERENCES acoes(id) ON DELETE CASCADE` |
| `usuario_id` | `uuid` | `NOT NULL`, `REFERENCES perfis(id) ON DELETE CASCADE` |
| `status` | `text` | `NOT NULL`, `CHECK (status IN ('confirmado', 'fila'))` — preenchido por trigger, nunca pelo client |
| `created_at` | `timestamptz` | default `now()` — também define a ordem de chegada da fila |

**PK composta**: `(acao_id, usuario_id)` — mesma pessoa não confirma duas
vezes na mesma Ação (garante FR-012 no nível de schema).

**Invariantes estruturais**:
- `acoes_criador_vira_confirmado` (`AFTER INSERT ON acoes`): insere a
  confirmação do criador automaticamente (FR-013).
- `confirmacoes_acao_decidir_status` (`BEFORE INSERT ON
  confirmacoes_acao`): trava a linha de `acoes` (`FOR UPDATE`), recusa se
  `cancelada_em` não for nulo (FR-009), e define `status` como
  `'confirmado'` ou `'fila'` conforme `limite_vagas` e a contagem atual de
  confirmados (FR-005/FR-006/FR-007).
- `confirmacoes_acao_promover_fila` (`AFTER DELETE ON confirmacoes_acao`,
  `SECURITY DEFINER`): se a linha apagada tinha `status = 'confirmado'`,
  promove o `fila` mais antigo daquela Ação pra `confirmado` (FR-006).

## RLS (Row Level Security)

Ambas as tabelas com `ENABLE ROW LEVEL SECURITY`.

**`acoes`**:
- `select_public`: `FOR SELECT USING (true)` — FR-010.
- `insert_criador`: `FOR INSERT WITH CHECK (auth.uid() = criador_id)` —
  FR-001.
- `update_criador`: `FOR UPDATE USING (auth.uid() = criador_id)` — só quem
  criou cancela (FR-008); `criador_id` nunca muda nesta feature (sem
  transferência, diferente de Grupo), então não precisa de `WITH CHECK
  (true)` separado.
- Sem policy de `DELETE` (cancelar é soft, não apaga a linha).

**`confirmacoes_acao`**:
- `select_public`: `FOR SELECT USING (true)` — FR-010.
- `insert_self`: `FOR INSERT WITH CHECK (auth.uid() = usuario_id)` — FR-003,
  sempre auto-serviço.
- `delete_self`: `FOR DELETE USING (auth.uid() = usuario_id)` — FR-004,
  sempre auto-serviço; diferente de Grupo, não existe "criador remove
  confirmado" nesta feature.
- Sem policy de `UPDATE` — a única escrita em `status` depois do insert é
  via trigger `SECURITY DEFINER`, nunca via client direto.
