# Implementation Plan: Rodada de Votação

**Branch**: `004-rodada-votacao` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/004-rodada-votacao/spec.md`

## Summary

Participante de um Grupo abre uma Rodada de votação (prazo) e propõe Ações
candidatas — reaproveitando integralmente a tabela `acoes` e o mecanismo de
`confirmacoes_acao` da feature 003, apenas com `grupo_id`/`rodada_id`
preenchidos e uma coluna nova `confirmada = false` enquanto está em
votação. Qualquer participante do Grupo vota (upsert por Rodada+Usuário,
trocar de voto é idempotente e sempre conta só a última escolha). Fechamento
por prazo é preguiçoso: uma função `fechar_rodada_se_devido()` roda no
início de toda operação relevante (votar, propor, buscar detalhes da
Rodada) e só faz algo se o prazo já passou (ou se foi forçada pelo Dono do
Grupo). Ao fechar, apura a mais votada (sorteio via `ORDER BY random()`
entre empatadas), marca essa candidata `confirmada = true` (vira Ação de
Grupo de verdade, reusando todas as telas/regras de Ação já existentes) e
apaga as demais candidatas daquela Rodada (cascade already limpa
`confirmacoes_acao` e `votos` associados).

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001/002/003

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — duas tabelas novas (`rodadas_votacao`,
`votos`) e três colunas novas em `acoes` (`grupo_id`, `rodada_id`,
`confirmada`)

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres/Auth local, unit e widget com `flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: abrir Rodada + propor candidata em <2min (SC-001);
trocar voto reflete em <2s (SC-002)

**Constraints**: apuração de empate (FR-012) e a garantia de exatamente uma
vencedora quando há candidatas (SC-003) DEVEM ser estruturais (função de
banco), não client-side — mesmo padrão de invariante das features
anteriores. Fechamento preguiçoso (Assumption/Clarification): nenhum job
agendado, `fechar_rodada_se_devido()` é chamada explicitamente pelo
repositório antes de ler/escrever numa Rodada.

**Scale/Scope**: mesma escala das features anteriores

**Visual**: reusa o tema 7me já existente — sem mudança de estética

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Tabelas/colunas usam os termos do glossário (`rodadas_votacao`, `votos`, `candidata_id`, `vencedora_id`, `confirmada`) — nenhum sinônimo da lista `_Avoid_` | PASS |
| II. Privacidade e LGPD | Participantes/votantes exibidos via `perfil_publico()`, nunca `select` direto em `perfis` — reusa o invariante já validado | PASS |
| III. Spec-Driven | spec.md + clarify concluídos antes deste plano | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: só participante do Grupo abre/propõe/vota (FR-004/FR-007), voto revogável só última conta (FR-006), fechamento preguiçoso (FR-008), só Dono encerra antes do prazo (FR-009/FR-010), apuração + sorteio de empate (FR-011/FR-012), vencedora vira confirmada preservando presenças (FR-013/FR-015), perdedoras descartadas (FR-014), sem vencedora se zero candidatas (FR-018), só quem propôs a vencedora ou Dono cancela (FR-016) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Nenhum papel novo — Ação candidata reusa a entidade Ação; "quem abriu a Rodada"/"quem propôs" são só atributos, não papéis novos do glossário | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/004-rodada-votacao/
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
│   └── acao/                                # reusa a feature 003, estende
│       ├── data/
│       │   ├── acao_repository.dart          # ganha métodos cientes de grupo_id/rodada_id
│       │   └── rodada_repository.dart        # abrir/fechar Rodada, votar
│       ├── domain/
│       │   ├── acao.dart                     # ganha grupoId/rodadaId/confirmada
│       │   └── rodada.dart                   # modelo Rodada/Voto
│       └── presentation/
│           ├── lista_rodadas_page.dart        # Rodadas de um Grupo
│           ├── detalhe_rodada_page.dart       # candidatas + votar + encerrar
│           └── criar_candidata_page.dart      # propor Ação candidata

supabase/
└── migrations/
    └── <timestamp>_rodada_votacao.sql         # colunas novas em acoes + tabelas + função de fechamento

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: estende a feature `acao/` já existente (mesma
pasta, não uma feature nova isolada) — Ação candidata É uma Ação, não uma
entidade paralela. `rodada.dart`/`rodada_repository.dart` entram como
arquivos novos dentro de `lib/features/acao/`.

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
