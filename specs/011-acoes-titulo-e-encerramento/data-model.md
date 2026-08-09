# Data Model: Ação — encerramento, contagem de confirmados e clareza do título

**Feature**: 011-acoes-titulo-e-encerramento | **Date**: 2026-08-09

**Nenhuma entidade nova. Nenhuma tabela nova. Nenhuma coluna nova.** Esta feature adiciona
dois conceitos *derivados* de dados que já existem, e aperta duas políticas de acesso.

---

## 1. `ActionTimeStatus` — estado no tempo (derivado)

Enum novo em `lib/features/action/domain/action.dart`. Não é persistido nem transportado: é
calculado a cada render a partir de `Action.dateTime` e do instante atual.

| Valor | Condição | Efeito na UI |
|---|---|---|
| `upcoming` | `agora < dateTime` | Comportamento de hoje, sem mudança |
| `happeningNow` | `dateTime <= agora <= dateTime + 4h` | Aparece na listagem com sinalização de "acontecendo agora"; confirmar e desistir continuam disponíveis (FR-002) |
| `ended` | `agora > dateTime + 4h` | Some da listagem (FR-003); detalhe abre por link com rótulo de encerrada e sem controles (FR-004, FR-005) |

**Transições**: só uma direção, só pela passagem do tempo —
`upcoming → happeningNow → ended`. Não há evento, nem ação de Usuário, nem gravação que
provoque a transição, e não existe volta.

**Constante**: `const defaultActionDuration = Duration(hours: 4);` — nomeada, não literal solto.
**Tem gêmea em SQL** (`interval '4 hours'` em `contracts/schema.sql`); cada uma carrega um
comentário apontando para a outra.

**Precedência com estados que já existem**:

| Situação | O que a tela mostra |
|---|---|
| Cancelada **e** encerrada | "Cancelada" (FR-008) |
| Candidata em votação **e** encerrada | Continua visível dentro da Rodada até a Rodada fechar; o encerramento só rege a listagem de Ações |

---

## 2. `ConfirmationCounts` — contagem agregada (derivada)

Estrutura de leitura, montada no cliente a partir de uma consulta agregada. Não existe no
banco.

| Campo | Tipo | Origem |
|---|---|---|
| `confirmed` | `int` | linhas de `confirmacoes_acao` com `status = 'confirmado'` para a Ação |
| `waiting` | `int` | linhas com `status = 'fila'` para a Ação |

**Consulta que a alimenta** — uma só, para a listagem inteira:

```
from('confirmacoes_acao').select('acao_id, status')
```

**Invariante de privacidade (Princípio II)**: `usuario_id` **não** entra na projeção. O
cliente obtém o número sem obter as pessoas. Essa é a diferença entre esta consulta e
`fetchAttendees`, que traz identidade e por isso passa pela RPC `perfil_publico`.

**Regras de exibição** derivadas dela:

| Estado | Texto |
|---|---|
| `confirmed == 0` | "Ninguém confirmou ainda" (FR-011 — nunca "0") |
| `confirmed == 1` | "1 confirmado" (FR-010, singular) |
| `confirmed > 1` | "N confirmados" |
| Com `limiteVagas` | "N de M vagas" (FR-012) |
| Lotada com `waiting > 0` | Indicação de lotada + tamanho da fila, separado da contagem (FR-013) |

`waiting` **nunca** é somado a `confirmed` (assumption da spec: somar faria uma Ação de 10
vagas parecer ter 15 participantes).

---

## 3. Numeração dos confirmados (apresentação pura)

Nada de modelo. `fetchAttendees` já devolve a lista **ordenada por `created_at`**
(`action_repository.dart:65`), que é exatamente a ordem de confirmação que FR-020 pede. A
numeração é o índice da lista renderizada + 1, calculado separadamente para confirmados e
para fila (FR-021), o que dá contiguidade de graça após qualquer desistência (FR-022).

---

## 4. Delta no banco

Nenhuma estrutura. Duas políticas de `confirmacoes_acao` ganham uma condição de tempo:

| Política | Hoje | Depois |
|---|---|---|
| `confirmacoes_acao_insert_self` | `with check (auth.uid() = usuario_id)` | idem **e** Ação não encerrada |
| `confirmacoes_acao_delete_self` | `using (auth.uid() = usuario_id)` | idem **e** Ação não encerrada |

O bloqueio do `delete` é o que cumpre FR-007: `confirmacoes_acao_promover_fila` é
`after delete`, então sem delete não há promoção.

`confirmacoes_acao_select_public` (`using (true)`) fica **intocada** — é ela que permite a
contagem ser visível a Visitante (FR-014).

Texto completo em [contracts/schema.sql](./contracts/schema.sql).

---

## 5. O que explicitamente NÃO muda

- `acoes`: nenhuma coluna, nenhum trigger.
- `confirmacoes_acao_decidir_status` (decide confirmado vs. fila na entrada) e
  `confirmacoes_acao_promover_fila` (promove ao liberar vaga): inalterados. A promoção
  continua automática **enquanto a Ação não encerra**.
- Apuração de Rodada de votação, desempate por sorteio, descarte de candidatas perdedoras,
  revogação de voto, composição de Dupla Missionária: inalterados. Os testes existentes que
  cobrem essas regras devem passar **sem edição** — se algum precisar mudar, é sinal de que
  esta feature vazou para além do escopo.
