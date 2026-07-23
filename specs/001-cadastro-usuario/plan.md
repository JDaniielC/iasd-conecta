# Implementation Plan: Cadastro de Perfil e Upgrade para Conta

**Branch**: `001-cadastro-usuario` | **Date**: 2026-07-23 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/001-cadastro-usuario/spec.md`

## Summary

Toda pessoa pode virar Usuário criando um Perfil (nome, gênero, idade, Igreja
opcional, telefone opcional, consentimento LGPD) sem precisar de e-mail nem
senha. Tecnicamente isso usa Supabase Anonymous Sign-in: o app entra numa
sessão anônima na primeira abertura e o Perfil é uma linha em `public.perfis`
com `id = auth.uid()`. Upgrade opcional para Conta vincula credencial (e-mail
ou telefone) à mesma sessão anônima via `updateUser`, preservando o mesmo
`auth.uid()` — sem migração de dados. Idade nunca é exposta a outros (RLS
restringe SELECT da tabela base ao dono; qualquer exibição pública passa por
uma função `SECURITY DEFINER` que só devolve nome/Apelido). Apelido obrigatório
para menor de idade é uma constraint de banco, não só validação de app.

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable channel)

**Primary Dependencies**: Flutter, `supabase_flutter` (Auth + Postgres client),
`flutter_riverpod` (estado/DI), `go_router` (navegação declarativa)

**Storage**: Supabase Postgres com Row Level Security; Supabase Auth
(Anonymous Sign-in + upgrade via `updateUser`)

**Testing**: `flutter_test` (unit/widget), `integration_test` (fluxo
end-to-end no app), `mocktail` (dublês do client Supabase), testes SQL simples
para constraints/RLS no schema

**Target Platform**: iOS 13+ e Android 8+ (app móvel), mesma cobertura de
plataforma do 7me

**Project Type**: mobile-app (projeto Flutter único; Supabase é BaaS, sem
backend próprio a manter)

**Performance Goals**: cadastro de Perfil concluído em <2min (SC-001);
Usuário reconhecido ao reabrir o app em <5s (SC-004)

**Constraints**: LGPD non-negotiable (Princípio II); idade nunca deve
transitar pra fora do dono nem em payload de API, não só escondida na UI;
app requer conexão de rede (offline-first fica fora de escopo desta feature)

**Scale/Scope**: comunidade de um distrito (15+ igrejas), escala de centenas a
poucos milhares de Usuários — sem necessidade de engenharia de escala pesada

**Visual**: estética 7me — azul marinho + branco, minimalista, tipografia
limpa e legível, wordmark leve (estilo script) na tela de abertura, cartões
com bastante espaço em branco, sem ruído visual (sem gradientes pesados,
ícones decorativos ou densidade de informação alta)

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Gate | Status |
|---|---|---|
| I. Linguagem Ubíqua | Tabelas/colunas/rotas usam os termos do glossário (`perfis`, `apelido`, `igreja_id`, Conta) — nenhum sinônimo da lista `_Avoid_` | PASS |
| II. Privacidade e LGPD | Idade protegida por RLS na tabela base (não só ocultada na UI); consentimento LGPD com timestamp obrigatório na constraint; Apelido obrigatório pra menor é constraint de banco | PASS |
| III. Spec-Driven | spec.md + clarify concluídos antes deste plano | PASS |
| IV. Regras Testadas | tasks.md (fase seguinte) DEVE incluir testes automatizados pra: Apelido substitui nome, idade nunca exposta, Perfil persiste entre sessões, upgrade pra Conta preserva o mesmo id | Pendente em tasks.md |
| V. Simplicidade e Papéis Mínimos | Perfil/Conta são dois estados de autenticação do mesmo papel "Usuário", não um papel novo — nenhuma hierarquia adicional introduzida | PASS |

Nenhuma violação a justificar em Complexity Tracking.

## Project Structure

### Documentation (this feature)

```text
specs/001-cadastro-usuario/
├── plan.md              # This file
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
│   ├── schema.sql
│   └── auth-flow.md
└── tasks.md              # Phase 2 output (/speckit-tasks)
```

### Source Code (repository root)

```text
lib/
├── main.dart
├── app.dart                        # MaterialApp + go_router + tema 7me
├── core/
│   ├── theme/                      # cores, tipografia, espaçamento (estética 7me)
│   └── supabase_client.dart        # inicialização do cliente Supabase
├── features/
│   └── perfil/
│       ├── data/                   # repositório: chama Supabase (perfis, igrejas)
│       ├── domain/                 # modelos (Perfil, Igreja) e regras (ex: exige Apelido)
│       └── presentation/
│           ├── cadastro_perfil_page.dart
│           ├── upgrade_conta_page.dart
│           └── widgets/

supabase/
├── migrations/
│   └── 0001_perfis_igrejas.sql     # schema, RLS, constraints, função pública
└── seed.sql                        # lista inicial de igrejas do distrito (dev/test)

test/
├── unit/                           # regras de domínio (Apelido obrigatório, etc.)
└── widget/                         # telas de cadastro/upgrade

integration_test/
└── cadastro_perfil_flow_test.dart  # fluxo ponta a ponta
```

**Structure Decision**: projeto Flutter único (Option 1 simplificado, sem
`backend/` — Supabase cobre esse papel via schema + RLS versionados em
`supabase/migrations/`, que fazem parte do controle de versão do app).

## Complexity Tracking

*Nenhuma violação do Constitution Check a justificar.*
