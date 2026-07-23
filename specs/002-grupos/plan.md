# Implementation Plan: Grupos

**Branch**: `002-grupos` | **Date**: 2026-07-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/002-grupos/spec.md`

## Summary

Usuário (Perfil ou Conta, tanto faz) cria um Grupo com nome, Categoria,
horário recorrente, local e detalhes; a Igreja do Grupo é herdada do criador
(pode ser nula). Criador vira Dono do Grupo automaticamente. Qualquer pessoa
— Visitante incluído — lê a lista de Grupos e detalhes livremente (RLS
`SELECT` público, igual ao padrão já usado pra `igrejas` na feature 001).
Participar/sair é auto-serviço de quem já tem Perfil. Dono edita o Grupo,
remove participante, e transfere a posse — com duas invariantes garantidas
no banco, não só na UI: (1) só dá pra transferir pra quem já participa, (2)
Dono não sai sem transferir antes. Sem exclusão de Grupo nesta feature (ver
Clarifications da spec).

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto da
feature 001, sem novo setup de toolchain

**Primary Dependencies**: as mesmas da feature 001 (`supabase_flutter`,
`flutter_riverpod`, `go_router`); nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — duas tabelas novas (`grupos`,
`participacoes_grupo`) e uma tabela de referência (`categorias_grupo`)

**Testing**: mesmo padrão da feature 001 — testes de contrato direto no
Postgres/Auth local (`package:postgres`, `package:supabase`), unit e widget
com `flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único da feature 001)

**Performance Goals**: criar Grupo em <2min (SC-001); Participar/sair
reflete na lista de participantes em <2s (SC-003)

**Constraints**: invariantes de posse do Grupo (transferir só pra quem
participa; Dono não sai sem transferir) DEVEM ser garantidas no banco, não
só no client — mesmo padrão de "regra de negócio vira constraint/trigger"
usado em `apelido_obrigatorio_menor` na feature 001

**Scale/Scope**: mesma escala da feature 001 (comunidade de um distrito);
Grupos por Usuário sem limite (ver Assumptions da spec)

**Visual**: reusa o tema 7me já existente em `lib/core/theme/app_theme.dart`
— sem mudança de estética, só novas telas no mesmo estilo

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Tabelas/colunas usam os termos do glossário (`grupos`, `participacoes_grupo`, `dono_id`, `categoria`) — nenhum sinônimo da lista `_Avoid_` (evita "membro", "time", "comunidade" como nome de coluna/tabela) | PASS |
| II. Privacidade e LGPD | Lista de participantes exibida via `perfil_publico()`, nunca `select` direto em `perfis` — reusa o invariante já validado na feature 001 | PASS |
| III. Spec-Driven | spec.md + clarify concluídos antes deste plano | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: dono automático (FR-003), só-Dono edita/remove/transfere (FR-009/010/011), transferir só pra participante e Dono não sai sem transferir (FR-011/012), Participar idempotente (FR-013) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Dono do Grupo já é papel do glossário (por-Grupo, não global) — nenhum papel novo introduzido | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/002-grupos/
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
│   └── grupo/
│       ├── data/
│       │   └── grupo_repository.dart      # CRUD de grupos + participacoes_grupo
│       ├── domain/
│       │   ├── grupo.dart                  # modelo Grupo
│       │   └── categoria_grupo.dart        # modelo Categoria de Grupo
│       └── presentation/
│           ├── lista_grupos_page.dart      # descoberta (Visitante + Usuário)
│           ├── detalhe_grupo_page.dart     # detalhes + participar/sair
│           ├── criar_grupo_page.dart       # US1
│           └── editar_grupo_page.dart      # US3 (Dono)

supabase/
└── migrations/
    └── <timestamp>_grupos.sql              # tabelas + RLS + triggers de invariante

test/
├── unit/                                   # Grupo/CategoriaGrupo, regras de domínio
├── widget/                                 # telas de grupo
└── integration/                            # contratos contra Postgres local
```

**Structure Decision**: mesma estrutura de feature (`lib/features/<nome>/data|domain|presentation`)
já estabelecida em `perfil/` na feature 001 — reaplicada para `grupo/`, sem
mudança de convenção.

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
