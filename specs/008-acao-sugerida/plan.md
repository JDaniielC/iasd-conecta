# Implementation Plan: Ação Sugerida

**Branch**: `008-acao-sugerida` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/008-acao-sugerida/spec.md`

## Summary

Ação sugerida é uma tabela nova, `acoes_sugeridas` (id, categoria_id
`references categorias_grupo(id)`, nome) — cadastro simples, sem edição
(só insert/delete), mesmo padrão de `igrejas`/`categorias_grupo`
(features 001/002). Só o Administrador do distrito escreve (RLS
insert/delete); leitura é pública, igual às demais listas de referência.
Ao propor Ação candidata, a Categoria já vem do Grupo pai
(`grupos.categoria`, texto), então a busca de sugestões faz `join` com
`categorias_grupo` por igualdade de nome. Ao criar Ação avulsa, a tela
deixa escolher uma Categoria (mesmo seletor já usado em Criar Grupo) só
pra filtrar a consulta — nada é persistido na Ação avulsa em si (FR-006),
então nenhuma coluna nova em `acoes`.

**Nota de convenção**: `lib/features/acao_sugerida/` nova, em inglês —
mesmo padrão de `leadership/`/`district_admin/` (features 005/006).

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001-007

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — uma tabela nova
(`acoes_sugeridas`); nenhuma coluna nova em tabela existente

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres local via `docker exec psql` antes do código Dart, depois testes
de integração (`package:postgres`), unit e widget com
`flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: sugestões aparecem em <1s ao propor candidata
(SC-001)

**Constraints**: `grupos.categoria` é texto livre (sem FK pra
`categorias_grupo`, ver feature 002) — o `join` pra achar sugestões de
uma candidata é por igualdade de texto (`categorias_grupo.nome =
grupos.categoria`), não por id; se o texto não bater com nenhuma
Categoria cadastrada, nenhuma sugestão aparece (Edge Case já assumido na
spec, mesmo comportamento de Categoria sem sugestões).

**Scale/Scope**: lista pequena (dezenas de itens, baseada em
`CATEGORIAS-DE-ACAO.md`), sem paginação necessária

**Visual**: reusa o tema 7me já existente; tela de gerenciar Ações
sugeridas segue o mesmo layout de `ManageChurchesPage` (feature 005)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Banco usa o termo do glossário em português (`acoes_sugeridas`); pasta e código Dart novos em inglês (`SuggestedAction`) | PASS |
| II. Privacidade e LGPD | Nenhum dado pessoal envolvido — é uma lista de referência de nomes de Ação, sem vínculo a Usuário | PASS |
| III. Spec-Driven | spec.md concluído antes deste plano; clarify não teve pergunta — spec já resolveu as ambiguidades como Assumptions | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: só Administrador cadastra/remove (FR-003), sugestões da candidata batem com a Categoria do Grupo (FR-004), Categoria de filtro da Ação avulsa não persiste (FR-006), Categoria sem sugestão não quebra o fluxo (FR-008) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Nenhum papel novo; reusa o papel Administrador do distrito já existente; sem edição de Ação sugerida (só cadastrar/remover), consistente com o padrão já usado em `igrejas`/`categorias_grupo` | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/008-acao-sugerida/
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
    └── acao_sugerida/                       # feature nova, em inglês
        ├── data/
        │   └── suggested_action_repository.dart
        ├── domain/
        │   └── suggested_action.dart
        ├── suggested_action_providers.dart
        └── presentation/
            └── manage_suggested_actions_page.dart

# telas tocadas (adicionam o seletor de sugestão, sem pasta nova):
#   lib/features/acao/presentation/criar_acao_page.dart
#   lib/features/acao/presentation/criar_candidata_page.dart

supabase/
└── migrations/
    └── <timestamp>_acao_sugerida.sql   # tabela + policies

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: pasta nova `lib/features/acao_sugerida/` (inglês);
`criar_acao_page.dart`/`criar_candidata_page.dart` só ganham um campo de
sugestão a mais, sem virar parte da pasta nova.

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
