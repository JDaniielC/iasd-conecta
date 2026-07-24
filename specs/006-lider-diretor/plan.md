# Implementation Plan: Líder/Diretor de Ministério

**Branch**: `006-lider-diretor` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/006-lider-diretor/spec.md`

## Summary

`liderancas(grupo_id, usuario_id, ano, ...)` guarda uma declaração por
Grupo+Usuário+ano. Toda escrita passa por duas funções `SECURITY DEFINER`
— `declarar_lideranca` (autodeclarar, exige Conta, idempotente/reseta após
rejeição) e `decidir_lideranca` (só Administrador do distrito confirma ou
rejeita) — não há `GRANT INSERT/UPDATE` direto pra `authenticated` na
tabela; toda escrita é mediada pelas funções, que já embutem as regras de
autorização e o upsert condicional (não sobrescreve uma declaração já
confirmada). Leitura é pública (`SELECT` liberado) — tanto pra Visitante
ver o Líder confirmado do ano corrente quanto pro Administrador ver a
lista de pendentes. "Ministério" e "Líder/Diretor" não geram tabela
própria — são consultas sobre `liderancas` (existência de confirmação do
ano corrente) e `grupos`.

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001-005

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — uma tabela nova (`liderancas`),
duas funções `SECURITY DEFINER` (`declarar_lideranca`, `decidir_lideranca`)

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres/Auth local, unit e widget com `flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: autodeclarar em <1min (SC-001); confirmação reflete
na identificação pública em <2s (SC-003)

**Constraints**: expiração anual (FR-008) é preguiçosa — comparação de
`ano` no momento da consulta, sem job agendado (mesmo padrão da Rodada de
votação, feature 004); "precisa ter Conta" (FR-002) checado via
`auth.users.is_anonymous` dentro da função `SECURITY DEFINER` (mesmo
padrão da feature 005, `auth` não é acessível a `authenticated`
diretamente).

**Scale/Scope**: mesma escala das features anteriores

**Visual**: reusa o tema 7me já existente — sem mudança de estética

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Banco em português (`liderancas`, `declarar_lideranca`, `decidir_lideranca`); código Dart novo em inglês (`lib/features/leadership/`, `LeadershipDeclaration`) | PASS |
| II. Privacidade e LGPD | Nenhum dado pessoal novo; leitura pública de `liderancas` não expõe idade nem nenhum campo sensível (só ids + timestamps + ano) | PASS |
| III. Spec-Driven | spec.md + clarify concluídos antes deste plano (clarify sem pergunta formal — edge case documentado direto na spec) | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: exige Conta (FR-002), duplicata é não-operação (FR-003), só admin decide (FR-004/FR-005), identificação pública só do ano corrente (FR-006/FR-008), codireção (FR-007), redeclarar após expirar ou rejeitar (FR-009/FR-010) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Líder/Diretor e Ministério não são papéis/entidades novos no sentido de tabela própria — são estados derivados de `liderancas`+`grupos`; nenhuma hierarquia nova | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/006-lider-diretor/
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
│   ├── grupo/
│   │   └── presentation/
│   │       └── detalhe_grupo_page.dart   # ganha seção "Líder/Diretor" (US3)
│   └── leadership/                        # feature nova, em inglês
│       ├── data/
│       │   └── leadership_repository.dart
│       ├── domain/
│       │   └── leadership_declaration.dart
│       └── presentation/
│           ├── declare_leadership_page.dart
│           └── pending_declarations_page.dart

supabase/
└── migrations/
    └── <timestamp>_leadership.sql

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: nova pasta `lib/features/leadership/` (inglês);
`DetalheGrupoPage` (feature 002, português) ganha uma seção nova pra
exibir os Líderes confirmados — é o único ponto de toque num arquivo
existente fora da pasta nova.

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
