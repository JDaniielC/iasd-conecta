# Implementation Plan: Administrador do Distrito

**Branch**: `005-administrador-distrito` | **Date**: 2026-07-24 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/005-administrador-distrito/spec.md`

## Summary

Administrador do distrito é uma linha em `administradores_distrito`
(usuário + quem promoveu), nunca autoconcedida — só quem já está na tabela
insere outra linha, e só pra um Usuário com Conta (checado via
`auth.users.is_anonymous`). `igrejas` ganha `arquivada_em`: arquivar é só um
`UPDATE`, nunca `DELETE` — preserva todo vínculo histórico. A policy de
`SELECT` de `igrejas` passa a esconder arquivadas de quem não é
administrador. A policy de `UPDATE` de `acoes` (já estendida na feature 004
pra incluir o Dono do Grupo) ganha mais uma condição: administrador do
distrito também cancela qualquer Ação.

**Nota de convenção**: esta é a primeira feature com código Dart em inglês
(constituição v1.1.0). Como parte do trabalho aqui, o modelo `Igreja`
(tocado diretamente por esta feature, que adiciona arquivamento) é traduzido
pra `Church` — arquivo, classe, e os métodos de repositório/provider que o
buscam. Os demais modelos existentes (`Perfil`, `Grupo`, `Acao`) não são
tocados por esta feature e permanecem em português por ora, conforme o
próprio Princípio I prevê (tradução gradual, por arquivo).

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001-004

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — uma tabela nova
(`administradores_distrito`), uma coluna nova em `igrejas`
(`arquivada_em`), e duas policies existentes (`igrejas` select, `acoes`
update) substituídas

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres/Auth local, unit e widget com `flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: promover Administrador em <1min (SC-001); Igreja
arquivada some da lista em <2s (SC-003)

**Constraints**: "usuário promovido precisa ter Conta" (FR-002) só é
verificável olhando `auth.users.is_anonymous`, que não é exposto via REST —
a checagem vive dentro do trigger de `administradores_distrito` (roda no
banco, tem acesso direto ao schema `auth`), não no client.

**Scale/Scope**: mesma escala das features anteriores; poucos
Administradores esperados (não uma hierarquia grande)

**Visual**: reusa o tema 7me já existente — sem mudança de estética

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Banco usa os termos do glossário em português (`administradores_distrito`, `arquivada_em`); código Dart novo em inglês (`Church`, `DistrictAdmin`), conforme a fronteira de idioma emendada na v1.1.0 | PASS |
| II. Privacidade e LGPD | Nenhum dado pessoal novo coletado; `administradores_distrito` guarda só IDs (mesmo padrão de transparência de `participacoes_grupo`) | PASS |
| III. Spec-Driven | spec.md concluído antes deste plano (clarify não teve pergunta — ambiguidades já resolvidas como Assumptions) | PASS |
| IV. Regras Testadas | tasks.md DEVE incluir testes automatizados pra: só admin promove (FR-003), promovido precisa ter Conta (FR-002), arquivar Igreja não apaga vínculo histórico (FR-005), Igreja arquivada some da lista pra não-admin mas continua visível pra admin (FR-007/FR-008), admin cancela qualquer Ação (FR-009) | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Administrador do distrito já é papel do glossário — nenhum papel novo introduzido; promoção reusa o padrão de `GRANT`/trigger já estabelecido, sem mecanismo de revogação especulativo (fora de escopo, Assumption da spec) | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/005-administrador-distrito/
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
│   ├── perfil/
│   │   └── domain/
│   │       └── church.dart              # renomeado de igreja.dart (tradução)
│   └── district_admin/                  # feature nova, em inglês
│       ├── data/
│       │   └── district_admin_repository.dart
│       ├── domain/
│       │   └── district_admin.dart
│       └── presentation/
│           ├── promote_admin_page.dart
│           └── manage_churches_page.dart

supabase/
└── migrations/
    └── <timestamp>_district_admin.sql    # tabela + coluna + policies substituídas

test/
├── unit/
├── widget/
└── integration/
```

**Structure Decision**: nova pasta `lib/features/district_admin/` (inglês,
primeira feature sob a nova convenção); `igreja.dart` renomeado in-place
pra `church.dart` dentro de `perfil/domain/` (mantém a localização, já que
Church continua conceitualmente parte do cadastro de Perfil).

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
