# Implementation Plan: Dupla Missionária

**Branch**: `007-dupla-missionaria` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/007-dupla-missionaria/spec.md`

## Summary

Dupla Missionária não é uma tabela nova — é a mesma `acoes` (avulsa ou
candidata) já existente das features 003/004, com duas colunas novas:
`eh_dupla_missionaria boolean not null default false` e `genero_visitado
text nullable` (CHECK igual ao de `perfis.genero`: 'masculino'/'feminino').
Toda a validação de composição por gênero e o limite fixo de 2 vagas vivem
em triggers `BEFORE INSERT`/`BEFORE UPDATE` em `acoes` e
`confirmacoes_acao`, no mesmo estilo já usado (`checar_dono_participa`,
`confirmacoes_acao_decidir_status`). A promoção da fila de espera reusa e
estende `promover_fila_acao` (função `SECURITY DEFINER` da feature 003) pra
pular, em ordem de chegada, qualquer candidato da fila que formaria
composição inválida com quem ainda está confirmado.

**Nota de convenção**: este plano só *adiciona* duas colunas/campos à
`Acao`/`NovaAcao` já existentes (`lib/features/acao/domain/acao.dart`),
que permanecem majoritariamente em português — não é uma tradução
completa da classe. Full-rewrite pra inglês ficaria fora de escopo desta
feature (ela toca só a adição de composição por gênero, não é dona
conceitual de `Acao` do jeito que a feature 005 era de `Igreja`/`Church`);
segue o mesmo padrão já usado pelas features 004/005 ao adicionar
`grupoId`/`rodadaId`/`confirmada` sem traduzir a classe inteira. Os dois
campos novos, porém, já nascem com nome em inglês
(`isMissionaryPair`/`visitedGender`) no modelo Dart, mapeando pras colunas
`eh_dupla_missionaria`/`genero_visitado` em português no banco — mesmo
padrão de fronteira de idioma das features 005/006.

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001-006

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — duas colunas novas em `acoes`
(`eh_dupla_missionaria`, `genero_visitado`); nenhuma tabela nova; dois
triggers estendidos (`confirmacoes_acao_decidir_status`,
`promover_fila_acao`) e um `CHECK constraint` novo em `acoes`

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres local via `docker exec psql` antes do código Dart, depois testes
de integração (`package:postgres`), unit e widget com
`flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: criar Dupla Missionária em <1min (SC-001);
confirmação (aceita ou recusada) reflete imediatamente na tela, sem espera
perceptível

**Constraints**: a validação de composição depende do gênero de quem
confirma, hoje só disponível em `perfis.genero` (RLS restringe select
direto a linhas próprias) — a checagem vive dentro do trigger (roda como
dono da tabela, mesmo padrão de `promover_fila_acao`), nunca no client.

**Scale/Scope**: mesma escala das features anteriores; Dupla Missionária é
sempre exatamente 2 vagas, fila de espera potencialmente maior mas sem
limite superior novo

**Visual**: reusa o tema 7me já existente; tela de criar Ação/candidata
ganha um toggle "Dupla Missionária" + seletor de gênero do visitado,
condicional

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Banco usa os termos do glossário em português (`eh_dupla_missionaria`, `genero_visitado`); campos novos no modelo Dart em inglês (`isMissionaryPair`, `visitedGender`), sem traduzir a classe `Acao` inteira (ver Summary) | PASS |
| II. Privacidade e LGPD | Nenhum dado pessoal novo coletado — `genero_visitado` é sobre a pessoa que será visitada (não é um Usuário cadastrado), e o gênero de quem confirma já é dado existente do Perfil, só lido pelo trigger, nunca exposto a outro Usuário | PASS |
| III. Spec-Driven | spec.md concluído antes deste plano; clarify não teve pergunta formal — a única ambiguidade material (estratégia de promoção da fila pulando inválidos) já veio resolvida pelo usuário como Assumption na própria spec | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: 2 vagas fixas não configuráveis (FR-003), composição válida aceita em toda combinação (FR-004/SC-003), composição inválida recusada nas duas direções (FR-005/SC-002), regra checada no momento da confirmação (FR-006), primeira confirmação sempre aceita (FR-007), fila de espera reusada quando lotada (FR-008), promoção da fila pulando inválido (FR-009) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Nenhum papel novo; Dupla Missionária reusa 100% a estrutura de Ação/confirmação já existente, sem tabela nem função paralela | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/007-dupla-missionaria/
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
└── features/
    └── acao/
        ├── domain/
        │   └── acao.dart                 # + isMissionaryPair, visitedGender
        ├── data/
        │   └── acao_repository.dart      # + criar com esses campos
        └── presentation/
            ├── criar_acao_page.dart      # + toggle Dupla Missionária
            └── criar_candidata_page.dart # + toggle Dupla Missionária

supabase/
└── migrations/
    └── <timestamp>_dupla_missionaria.sql  # colunas + CHECK + triggers estendidos

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: nenhuma pasta nova — a feature estende
`lib/features/acao/` já existente (mesmo padrão de 004, que estendeu
`acao.dart`/`acao_repository.dart` pra Rodada de votação sem criar pasta
própria).

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
