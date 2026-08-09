# Implementation Plan: Quem pode ver em quem você votou

**Branch**: `021-visibilidade-do-voto` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/021-visibilidade-do-voto/spec.md`

## Summary

Trocar `votos_select_public ... using (true)` por uma política que devolve só o próprio
voto, corrigir a frase da Política de Privacidade que promete um círculo diferente, e
registrar a decisão para que `using (true)` não volte por inércia.

A feature é uma migration, três documentos e testes. **Nenhum widget muda, nenhum provider
muda, nenhum método de repositório muda** — porque o app já só lê o próprio voto
(`voting_round_repository.dart:78-86`). O trabalho de verdade está em provar que apertar a
leitura não quebrou a escrita nem a apuração, e em desarmar a armadilha que a própria
feature cria (ver Complexity Tracking).

Três incógnitas foram resolvidas por experimento contra o Postgres local, não por
raciocínio — inclusive uma que a spec listava como o risco principal e que **não se
confirmou**, e outra que **ninguém tinha visto**. Detalhes em [research.md](./research.md).

## Technical Context

**Language/Version**: Dart 3 / Flutter (canal estável do projeto); SQL (PostgreSQL 15, via
Supabase local)

**Primary Dependencies**: `supabase_flutter`, `flutter_riverpod`, `go_router`; `mocktail` e
`flutter_test` nos testes de unidade/widget; `test` puro nos testes de integração contra o
Postgres local

**Storage**: PostgreSQL gerenciado pelo Supabase. A feature toca **uma** política RLS da
tabela `public.votos`. Nenhuma coluna, nenhuma tabela, nenhum índice, nenhum dado alterado.

**Testing**: `flutter test test/unit test/widget` e `dart test test/integration` (exige
`supabase start`). A verificação central desta feature é de integração: RLS só se prova com
um banco de verdade e uma sessão de verdade.

**Target Platform**: Flutter Web (é o alvo publicado hoje) e móvel; o comportamento
verificado é do banco, portanto independe da plataforma.

**Project Type**: App móvel/web com backend gerenciado (Supabase). Sem servidor próprio.

**Performance Goals**: Sem meta nova. A política nova adiciona uma comparação de igualdade
por linha (`auth.uid() = usuario_id`) sobre uma tabela consultada por chave primária. Custo
irrelevante nesta escala.

**Constraints**: A restrição precisa valer no banco (FR-005) — nada que dependa da tela
conta. A apuração e a troca de voto não podem regredir (Princípio IV).

**Scale/Scope**: 1 migration, 3 documentos, ~4 arquivos de teste. Um distrito de 15+
igrejas; a tabela `votos` tem uma linha por pessoa por Rodada.

## Constitution Check

*GATE: avaliado antes da Phase 0 e reavaliado após a Phase 1.*

### I. Linguagem Ubíqua do Domínio (NON-NEGOTIABLE) — ✅ passa

Termos do glossário usados sem sinônimo: **Rodada de votação**, **Votar**, **Ação
candidata**, **Grupo**, **Visitante**, **Usuário**. Nomes de banco continuam em português
(`votos`, `votos_select_own`, `usuario_id`, `candidata_id`).

**Fronteira de idioma**: todo identificador Dart criado ou tocado por esta feature é
escrito em **inglês**, inclusive **dentro de arquivos de teste** — a única coisa que
permanece em português é o **nome do arquivo** de teste, seguindo a convenção que já
existe no repositório. As traduções fixadas, que já estão em uso e não mudam:
Rodada de votação→`VotingRound`, Voto→`Vote`, Ação candidata→`candidate`, Grupo→`Group`.
Nenhum identificador novo em português entra por esta feature.

### II. Privacidade e LGPD por Padrão (NON-NEGOTIABLE) — ✅ passa, e é o motivo da feature

A feature **só reduz exposição**. Nenhum dado novo, nenhum campo, nenhuma finalidade nova.

Declaração exigida pela seção "Requisitos de Domínio e Compliance":

| Pergunta | Resposta |
|---|---|
| Qual dado | O par (pessoa, candidata escolhida) já existente em `public.votos` |
| Finalidade | Apurar a Rodada de votação e mostrar à pessoa qual candidata ela escolheu |
| Quem pode ver — **hoje** | Qualquer pessoa, inclusive sem cadastro (`using (true)`) |
| Quem pode ver — **depois** | Só a própria pessoa. A apuração conta por fora da RLS |
| Consentimento adicional | Nenhum. A feature **corrige** o consentimento existente, que descrevia um círculo menor do que o real |

O ponto que torna isto uma correção e não uma melhoria: a Política afirma "o voto não é
anônimo **entre os participantes do Grupo**", e o banco entrega a internet inteira. Quem
aceitou os termos aceitou outra coisa. Divergência entre promessa e execução é violação de
constituição pela seção "Fluxo de Desenvolvimento" — e é essa violação **existente** que a
feature fecha.

### III. Desenvolvimento Guiado por Spec — ✅ passa

`/speckit-specify` → este `/speckit-plan`. `/speckit-clarify` foi pulado
deliberadamente: a única ambiguidade de regra (alcance "próprio voto" versus "participantes
do Grupo") tem padrão defensável e está registrada como Assumption na spec, com o texto
dizendo qual linha muda se a escolha for a outra. Se você quiser o outro alcance, rode
`/speckit-clarify` antes de `/speckit-implement` — muda uma expressão SQL e uma frase da
Política, não o plano.

### IV. Integridade das Regras de Domínio Testada (NON-NEGOTIABLE) — ⚠️ passa com exigência

A feature encosta em Rodada de votação. Três regras da lista do Princípio IV estão no raio:

| Regra | Como esta feature a ameaça | Como fica coberta |
|---|---|---|
| Revogabilidade de voto (só a última escolha conta) | Fechar a leitura poderia quebrar o `upsert` que troca o voto | Teste de integração que troca o voto **com a política nova aplicada** (FR-008) |
| Desempate por sorteio ao fechar a Rodada | Se a apuração passasse a enxergar menos votos, o empate mudaria | Coberto junto com a apuração (FR-011) |
| Descarte de candidatas perdedoras | Depende da vencedora apurada estar certa | Coberto pela apuração (FR-009) |

**A exigência**: a apuração precisa continuar contando **todos** os votos. Ela consegue
isso por ser `security definer` com dono `postgres`, o que faz a RLS não se aplicar —
verificado, não presumido (research.md, Decisão 2). Antes desta feature essa dependência
era inofensiva; depois dela, vira crítica. Isso está no Complexity Tracking e vira teste.

### V. Simplicidade e Papéis Mínimos — ✅ passa

Nenhum papel novo. A política nova não menciona Dono do Grupo, Líder/Diretor nem
Administrador do distrito — a regra é `auth.uid() = usuario_id`, a mais simples que atende
os requisitos. Nenhuma generalização especulativa: não há "ver votos do meu Grupo" nem
contagem por candidata, porque nada foi pedido e nenhuma tela consome.

**Resultado do gate**: aprovado. Uma exigência anotada no Complexity Tracking.

### Reavaliação pós-Phase 1

Sem mudança. O desenho final é uma política `for select` com uma comparação, uma migration
sem `alter table`, e nenhuma entidade nova — o desenho ficou **menor** que o gate inicial
previa, porque o experimento eliminou a necessidade de mexer no cliente Dart. Nenhuma
violação nova. ✅

## Project Structure

### Documentation (this feature)

```text
specs/021-visibilidade-do-voto/
├── plan.md              # Este arquivo
├── research.md          # Phase 0 — 5 decisões, 3 verificadas no Postgres local
├── data-model.md        # Phase 1 — nenhuma entidade nova; matriz de quem lê o quê
├── quickstart.md        # Phase 1 — como provar que funcionou
├── contracts/
│   └── schema.sql       # Phase 1 — a migration pretendida
├── checklists/
│   └── requirements.md  # do /speckit-specify
└── tasks.md             # do /speckit-tasks — NÃO criado aqui
```

### Source Code (repository root)

```text
supabase/migrations/
└── <timestamp>_votos_visibilidade.sql      # NOVO — única mudança de produção

lib/features/legal/presentation/
└── privacy_policy_page.dart                # EDITADO — a frase dos votos (FR-012)

test/integration/
└── votos_visibilidade_test.dart            # NOVO — o teste que importa (FR-001..FR-009)

MAPA-DE-DADOS.md                            # EDITADO — FR-013
CONTEXT.md                                  # EDITADO — registro da decisão (FR-014)
```

**Structure Decision**: o app segue `lib/features/<feature>/{data,domain,presentation}` com
banco em `supabase/migrations/` e testes em `test/{unit,widget,integration}`. Esta feature
não cria pasta nenhuma. Ela é quase inteiramente **banco e documento** — a única mudança em
`lib/` é uma string de texto legal.

**O que esta feature deliberadamente NÃO toca**: `voting_round_repository.dart`,
`voting_round_detail_page.dart` e os providers de votação. Eles já fazem a coisa certa. A
tentação de "aproveitar e ajustar" ali é o caminho para quebrar revogabilidade de voto sem
necessidade.

## Complexity Tracking

> Preenchido porque o gate do Princípio IV saiu com exigência.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| A feature cria um modo de falha silenciosa que hoje não existe: se `fechar_rodada_se_devido` deixar de ser `security definer`, a apuração passa a contar **só os votos de quem chamou** e elege a candidata de quem fechou a Rodada. Medido: com 2 votos numa candidata e 1 noutra, a apuração como invoker chamada pela minoria elegeu a candidata de 1 voto (research.md, Decisão 3). | Não é evitável. É consequência inerente de apertar a RLS: enquanto `using (true)` valia, invoker e definer contavam igual, e o `security definer` era decorativo. Fechar a leitura é o requisito (FR-001..FR-005); armar essa dependência é o preço. | **Alternativa 1 — deixar `using (true)`**: rejeitada, é o problema. **Alternativa 2 — apurar no cliente**: rejeitada, exigiria devolver todos os votos ao cliente, ou seja, o vazamento de volta. **Alternativa 3 — confiar que ninguém vai mexer**: rejeitada, é exatamente como `using (true)` sobreviveu. Mitigação adotada: teste de integração que falha se a apuração parar de ver todos os votos (FR-009), mais comentário na migration explicando a dependência **no lugar onde ela seria quebrada**. |
