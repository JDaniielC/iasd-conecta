# Implementation Plan: Ação Avulsa

**Branch**: `003-acao-avulsa` | **Date**: 2026-07-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/003-acao-avulsa/spec.md`

## Summary

Usuário com Perfil cria uma Ação avulsa (nome, data/hora, local, detalhes,
limite de vagas opcional) já confirmada, sem votação; o criador vira
confirmado automaticamente (mesmo padrão trigger de Grupo/Dono). Qualquer
pessoa — Visitante incluído — vê a Ação e a lista de confirmados
livremente. Confirmar presença é auto-serviço e idempotente; se a Ação
estiver lotada, a confirmação vira fila de espera; ao alguém desistir, o
próximo da fila é promovido automaticamente — tudo garantido por trigger no
banco, não só no client (mesmo padrão de invariante estrutural da feature
002). Só quem criou cancela a Ação.

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001/002

**Primary Dependencies**: as mesmas já usadas (`supabase_flutter`,
`flutter_riverpod`, `go_router`); nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — duas tabelas novas (`acoes`,
`confirmacoes_acao`)

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres/Auth local, unit e widget com `flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: criar Ação em <2min (SC-001); confirmar/desistir
reflete em <2s (SC-002)

**Constraints**: capacidade de vagas (FR-005/FR-006/FR-007, SC-005) DEVE ser
garantida no banco sob concorrência — o trigger que decide
confirmado-vs-fila trava a linha de `acoes` (`SELECT ... FOR UPDATE`) antes
de contar confirmados, serializando confirmações concorrentes pra mesma
Ação e evitando estourar o limite de vagas por corrida

**Scale/Scope**: mesma escala das features anteriores

**Visual**: reusa o tema 7me já existente — sem mudança de estética

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Tabelas/colunas usam os termos do glossário (`acoes`, `confirmacoes_acao`, `criador_id`, `cancelada_em`) — nenhum sinônimo da lista `_Avoid_` (evita "evento", "atividade" como nome de tabela) | PASS |
| II. Privacidade e LGPD | Lista de confirmados exibida via `perfil_publico()`, nunca `select` direto em `perfis` — reusa o invariante já validado nas features 001/002 | PASS |
| III. Spec-Driven | spec.md + clarify concluídos antes deste plano | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: criador confirmado automático (FR-013), fila de espera quando lotado (FR-005), promoção automática ao desistir (FR-006), vagas ilimitadas sem limite (FR-007), só-criador cancela (FR-008), sem confirmar em Ação cancelada (FR-009), confirmar idempotente (FR-012) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Nenhum papel novo — "quem criou a Ação" é só um atributo (`criador_id`), não um papel do glossário | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/003-acao-avulsa/
├── plan.md
├── research.md
├── data-model.md
├── quickstart.md
├── contracts/
│   └── schema.sql
└── tasks.md
```

### Source Code (repository root)

```text
lib/
├── features/
│   └── acao/
│       ├── data/
│       │   └── acao_repository.dart        # CRUD de acoes + confirmacoes_acao
│       ├── domain/
│       │   └── acao.dart                    # modelo NovaAcao/Acao
│       └── presentation/
│           ├── lista_acoes_page.dart        # descoberta (Visitante + Usuário)
│           ├── detalhe_acao_page.dart       # detalhes + confirmar/desistir
│           └── criar_acao_page.dart         # US1

supabase/
└── migrations/
    └── <timestamp>_acoes.sql                # tabelas + RLS + triggers de invariante

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: mesma estrutura de feature (`lib/features/<nome>/data|domain|presentation`)
já estabelecida em `perfil/` e `grupo/` — reaplicada para `acao/`.

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
