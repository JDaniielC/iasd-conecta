# Implementation Plan: Visibilidade das declarações de Líder/Diretor

**Branch**: `018-visibilidade-de-liderancas` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/018-visibilidade-de-liderancas/spec.md`

## Summary

Uma linha de SQL causou o problema e uma linha de SQL o resolve — o trabalho é provar que a
linha nova não quebra as três telas que dependiam da antiga.

`liderancas_select_public` é `using (true)`
(`supabase/migrations/20260724100000_leadership.sql:73-76`): qualquer pessoa sem cadastro lê a
tabela inteira via PostgREST, incluindo declarações **pendentes** e **rejeitadas**. A tela
esconde (`group_detail_page.dart:126-140` só renderiza confirmado), o banco não.

**A mudança**: substituir aquela política por uma com três disjuntos, um por leitor —
confirmada é pública, a própria pessoa vê a sua em qualquer estado, o Administrador do
distrito vê todas. Forma copiada de `igrejas_select_ativas_publico`
(`20260724092132_district_admin.sql:66-75`), que já faz exatamente isso em produção.

**O eixo técnico é: a prova não pode vir da tela.** SC-001 exige verificação por consulta
direta à API — porque a tela é o que esconde o problema, e um teste de widget que passa
reproduz a mesma ilusão que criou o vazamento. A prova vem de um teste de integração que faz
`set role anon` no Postgres, que é literalmente o que o PostgREST faz antes de aplicar RLS.

Escopo: **1 migration, 1 arquivo de teste novo, 1 linha no repositório Dart, 1 bloco em
`MAPA-DE-DADOS.md`**. Nenhuma coluna nova, nenhum backfill, nada apagado, nenhuma tela
redesenhada.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`. SQL (PostgreSQL 15 via Supabase).

**Primary Dependencies**: `flutter_riverpod ^3.3.2`, `supabase_flutter ^2.8.0`,
`postgres` (só em `test/integration`). **Nenhuma dependência nova.**

**Storage**: PostgreSQL via Supabase. Tabelas envolvidas: `liderancas` (política de select
substituída) e `administradores_distrito` (só lida, dentro da política). **Nenhuma coluna
nova, nenhuma função nova, nenhum trigger novo.**

**Testing**: `dart test test/integration` contra Supabase local — é onde a feature vive.
`flutter test test/unit test/widget` roda só como regressão. Gates de
`.github/workflows/ci.yml`: `flutter analyze`, `flutter test test/unit test/widget`,
`dart test test/integration`, `flutter build web`.

**Target Platform**: Flutter web (deploy atual) + Android/iOS. Irrelevante aqui — a regra é
do servidor, vale para qualquer cliente, inclusive o `curl` de quem não usa o app.

**Project Type**: app Flutter organizado por feature, com regra de domínio no banco (policies,
triggers, funções `security definer`) e espelho no cliente só para feedback imediato.

**Performance Goals**: a política acrescenta um `exists` numa tabela de unidades de linha
(`administradores_distrito`) por consulta a `liderancas`. Sem otimização especulativa —
sem índice novo, sem `(select auth.uid())`. Ver research.md D-002.

**Constraints**:
- A restrição tem que valer **no banco** (FR-004). Filtro no Dart é exatamente o que falhou.
- Não pode quebrar `public.excluir_minha_conta` (feature 009), que faz
  `delete from public.liderancas` (`20260806140000_exclusao_de_conta.sql:137`). Como é
  `security definer` e a tabela não tem `force row level security`, não é afetada — mas isso é
  **premissa a verificar**, não fé (research.md D-009, mesma armadilha da feature 011).
- Não pode alterar a regra de expiração anual (FR-009). A política não menciona `ano`.
- Não pode alterar quem declara nem quem confirma (feature 006).

**Scale/Scope**: 1 política, 3 consultas Dart existentes conferidas, 3 telas verificadas,
1 arquivo de teste novo com 6 casos. Base em `main`: 0 issues, 152 unit/widget,
127 integração → alvo **0 issues, 152 unit/widget, 133 integração**.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.* — **PASSA nos cinco,
sem exceção a justificar.**

| Princípio | Situação | Evidência |
|---|---|---|
| **I. Linguagem Ubíqua** | PASSA. Nenhum termo novo. A política chama-se `liderancas_select_confirmada_propria_ou_admin` — **objeto de banco, logo em português**, como `liderancas`, `confirmado_em`, `rejeitado_em`. Nenhuma string de UI muda. Nenhum identificador Dart novo é criado em `lib/`; os identificadores novos do teste de integração são **em inglês** (`_rejectedUserId`, `_adminUserId`, `asVisitor`, `asUser`, `countVisibleDeclarations`), e só o **nome do arquivo** de teste fica em português (`visibilidade_liderancas_test.dart`) | contracts/schema.sql; tasks.md T005-T011 nomeiam cada identificador |
| **II. Privacidade e LGPD** | PASSA — **a feature é este princípio**. Nenhum dado novo é coletado, exibido ou retido. O delta é estritamente subtrativo: "esta pessoa tentou ser Líder e não foi confirmada" deixa de ser legível por quem não tem motivo. O limite do que continua público é literal do glossário: *"Identificação do Líder é pública na página do Ministério"* — a identificação do Líder, não a lista de quem tentou | `CONTEXT.md:149-150`; spec, seção "Declarações exigidas pela Constituição" |
| **III. Guiado por Spec** | PASSA. `spec.md` existe e é anterior a este plano. Nenhuma ambiguidade de regra de negócio sobrou para `/speckit-clarify`: os três leitores estão enumerados nos Acceptance Scenarios de US1, e a única afirmação factualmente errada da spec (edge case da conta excluída) foi corrigida contra o código sem mudar requisito nenhum | research.md D-008 |
| **IV. Regras de domínio testadas** | PASSA. Nenhuma das regras nomeadas do Princípio IV é tocada — nem fila de espera, nem desempate, nem revogação, nem descarte, nem Dupla Missionária (a spec já declara isso). A regra que **esta** feature cria (quem lê o quê) tem teste automatizado de integração antes de ser considerada pronta, e o teste consulta a API, não a tela | tasks.md T005-T011 |
| **V. Simplicidade e Papéis Mínimos** | PASSA. Nenhum papel novo: Visitante, Usuário, a própria pessoa e Administrador do distrito já existem. Nenhuma permissão nova — a política **remove** acesso. Uma política, três disjuntos, zero generalização especulativa (não há "nível de visibilidade" configurável, nem tabela de permissão) | contracts/schema.sql |

**Re-check pós-desenho (Fase 1)**: nada mudou. O desenho é uma policy e um `comment on table`;
não introduziu papel, termo, coluna nem dado pessoal.

## Project Structure

### Documentation (this feature)

```text
specs/018-visibilidade-de-liderancas/
├── plan.md              # Este arquivo
├── research.md          # D-001..D-009 — estados alcançáveis, desenho da policy,
│                        #   prova das 3 telas, expiração, interação com a 014,
│                        #   método de teste, e uma correção de fato na spec
├── contracts/
│   └── schema.sql       # O delta de banco, com o porquê escrito dentro
├── quickstart.md        # Como verificar as premissas, aplicar e reproduzir o vazamento
├── spec.md              # (já existia)
└── tasks.md             # Saída do /speckit-tasks
```

**Sem `data-model.md`, de propósito.** Nenhuma entidade nova, nenhum campo novo, nenhuma
transição de estado nova — a spec diz isso na letra ("Nenhuma entidade nova... O que muda é
**quem consegue lê-la**"). O único conteúdo que um `data-model.md` teria — a tabela de estados
alcançáveis e a matriz leitor × visibilidade — está em `research.md` D-001 e D-002, ao lado do
raciocínio que a produziu, em vez de num arquivo que repetiria o schema existente.

### Source Code (repository root)

```text
supabase/migrations/
└── <timestamp>_liderancas_visibilidade.sql   # NOVO — cópia de contracts/schema.sql

lib/features/leadership/
├── data/leadership_repository.dart           # 1 linha: alinha fetchCurrentLeaders ao
│                                             #   predicado da política (T012)
├── leadership_providers.dart                 # INTOCADO
├── domain/leadership_declaration.dart        # INTOCADO
└── presentation/                             # INTOCADO (as 2 páginas)

lib/features/group/presentation/
└── group_detail_page.dart                    # INTOCADO — a seção do Líder continua igual

test/integration/
└── visibilidade_liderancas_test.dart         # NOVO — 6 casos, consulta como anon/
                                              #   authenticated/autor/admin

MAPA-DE-DADOS.md                              # linhas 60-62 e 68-73: o fato deixa de ser
                                              #   vigente e vira a regra que existe
```

**Structure Decision**: layout existente do repositório, feature `leadership` já isolada em
`lib/features/leadership/`. **Nenhum arquivo Dart novo** — a feature é de banco, e criar
camada em Dart para uma regra de servidor seria exatamente o erro que ela conserta. O único
toque em `lib/` (T012) existe para o predicado do cliente não divergir do predicado da
política, não para implementar a regra.

## A política, e a prova de que as três telas sobrevivem

O desenho completo e o porquê de cada conjunção estão em `contracts/schema.sql` e em
`research.md` D-001/D-002. O resumo executável:

```sql
using (
  (confirmado_em is not null and rejeitado_em is null)   -- 1) confirmada é pública
  or usuario_id = auth.uid()                             -- 2) a própria, em qualquer estado
  or exists (select 1 from public.administradores_distrito
             where usuario_id = auth.uid())              -- 3) quem decide vê todas
)
```

| Tela | Consulta (`leadership_repository.dart`) | Leitor | Disjunto | Resultado |
|---|---|---|---|---|
| Página do Ministério (`group_detail_page.dart:137`) | `fetchCurrentLeaders`, linhas 31-37 | `anon` e qualquer Usuário | **1** | Líder confirmado continua visível — FR-006 |
| Minha declaração (`declare_leadership_page.dart:51`) | `fetchMyDeclaration`, linhas 45-51 | a própria pessoa | **2** | vê pendente / rejeitada / confirmada — FR-008 |
| Pendências do Administrador (`pending_declarations_page.dart:37`) | `fetchPendingDeclarations`, linhas 59-64 | Administrador do distrito | **3** | vê todas as pendentes do distrito — FR-007 |

Com role `anon`, `auth.uid()` é `null` — os disjuntos 2 e 3 nunca disparam. `fetchMyDeclaration`
usa `.maybeSingle()`, mas filtra pela chave única `(grupo_id, usuario_id, ano)`, e a política só
**remove** linha, nunca adiciona: continua no máximo uma.

## Riscos

1. **`force row level security` em `liderancas`.** Se estivesse ligado, `excluir_minha_conta`
   (feature 009, `security definer`) passaria a ser filtrado pela política e a exclusão de
   conta deixaria de apagar a declaração — bug de LGPD criado por uma feature de privacidade.
   É a mesma armadilha que a 011 documentou. **Mitigação**: T001 verifica antes de aplicar,
   com comando em `quickstart.md`. Se estiver ligado, parar e revisar o contrato.

2. **Predicado duplicado que diverge em silêncio.** `confirmado_em is not null and
   rejeitado_em is null` existe na política e (depois de T012) em `fetchCurrentLeaders`. Se
   divergirem, a linha some da tela **sem erro nenhum** — a RLS remove antes de o Dart ver.
   **Mitigação**: T012 alinha os dois, e o comentário do contrato manda mudar juntos.
   Duplicação declarada, no estilo da 011.

3. **A rota `/leadership/pending` não é gateada por `isDistrictAdminProvider`**
   (`lib/app.dart:150-152`). Hoje, quem digita a URL vê as pendências do distrito inteiro.
   Depois desta feature, vê no máximo a própria, ou a tela vazia. **Não é regressão — é a
   segunda coisa que a feature conserta de graça**, e sem `catch` novo, porque a consulta não
   falha, só retorna menos linha. Gatear a rota é melhoria de UX que esta spec não pediu;
   fica registrada aqui, não vira tarefa.

4. **Feature 014 (arquivar Grupo) mexe no mesmo `fetchCurrentLeaders`.** Nenhuma escreve na
   mudança da outra (a 018 mexe na RLS, a 014 na consulta), e a 014 ainda não tem migration.
   Merge textual, não conflito de regra. **Residual declarado**: depois das duas, uma
   declaração confirmada de Grupo arquivado continua legível por `anon` via API — decisão da
   014 (`specs/014-arquivar-grupo/data-model.md:82,105`), que a 018 não reverte. Anotado no
   cabeçalho da migration para quem auditar depois não achar que é descuido desta.

5. **A prova vir da tela.** É o risco que a spec nomeia. **Mitigação**: nenhum teste de
   widget novo. A verificação de SC-001 é `set role anon` + consulta, e T006/T010 exigem
   número real de linhas, não "passou".

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

Sem violações. Nada a justificar.
