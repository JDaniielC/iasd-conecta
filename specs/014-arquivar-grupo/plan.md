# Implementation Plan: Arquivar Grupo

**Branch**: `014-arquivar-grupo` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/014-arquivar-grupo/spec.md`

## Summary

Um Grupo ganha um estado — ativo ou arquivado. Arquivar tira o Grupo das listas, encerra as
Rodadas de votação abertas **sem apurar**, cancela as Ações de Grupo futuras, e mostra ao Dono,
antes de confirmar, exatamente quanto disso vai acontecer. Desarquivar devolve o Grupo e os
participantes, mas **não** ressuscita o que foi cancelado.

O eixo técnico foi decidido pelo levantamento, não por preferência: **arquivar é uma RPC
`security definer`**. As políticas de acesso atuais impedem qualquer outro desenho — o Dono do
Grupo não pode alterar Ação que não criou, e o Administrador do distrito não pode alterar
Grupo que não é dele. Fazer no cliente exigiria afrouxar as duas, o que é um modelo de
permissão pior do que uma função que faz uma coisa só.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: `supabase_flutter ^2.8.0`, `flutter_riverpod ^3.3.2`,
`go_router ^17.3.0`. Nenhuma nova.

**Storage**: PostgreSQL via Supabase. **Duas colunas novas** em `grupos`
(`arquivado_em`, `arquivado_por`) e **duas funções novas** (`arquivar_grupo`,
`desarquivar_grupo`). Nenhuma tabela nova.

**Testing**: `flutter_test` + `mocktail` (unit/widget), `dart test test/integration` contra
Postgres local. Gates de `.github/workflows/ci.yml`.

**Target Platform**: Flutter web (deploy atual) + Android/iOS.

**Project Type**: app Flutter por feature, com regra de domínio no banco.

**Performance Goals**: irrelevante. Arquivar é raro e mexe em dezenas de linhas, não milhares.

**Constraints**:
- **Atomicidade**: arquivar faz quatro coisas (marca o Grupo, cancela Ações, encerra Rodadas,
  descarta candidatas). Ou tudo, ou nada — estado parcial deixaria Ações canceladas num Grupo
  que continua ativo.
- Desistir da confirmação altera **0 registros** (FR-006, SC-002).
- Nenhuma presença confirmada é apagada (FR-015, SC-006).
- Nenhuma Rodada é apurada por causa de um arquivamento (FR-007, SC-005).

**Scale/Scope**: 2 colunas, 2 funções de banco, ~4 telas tocadas, 1 tela nova (lista de
arquivados), ~6 arquivos de teste.

## O levantamento que decidiu o desenho

Três fatos do banco atual, cada um fechando uma porta:

| Fato | Onde | O que impede |
|---|---|---|
| `grupos_update_dono`: update só com `auth.uid() = dono_id` | `20260723220703_grupos.sql:115` | O **Administrador do distrito não consegue arquivar** Grupo alheio por update direto |
| `acoes_update_criador`: update só com `auth.uid() = criador_id` | `20260723230639_acoes.sql:131` | O **Dono não consegue cancelar** Ação do Grupo que outra pessoa criou |
| `fechar_rodada_se_devido` **apura**: escolhe vencedora, promove, descarta perdedoras | `20260724084300_rodada_votacao.sql:134,178` | Não serve para arquivar — arquivar precisa fechar **sem** vencedora |

Conclusão: uma RPC `security definer`, no mesmo padrão de `excluir_minha_conta` (feature 009),
que valida quem pode e faz as quatro coisas numa transação. Afrouxar as políticas para o
cliente fazer o trabalho seria dar ao Dono poder de escrita sobre Ação alheia — muito mais
superfície do que uma função com um propósito.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|---|---|---|
| **I. Linguagem Ubíqua** | ⚠️ PASS condicionado | Dois termos **novos** — **Arquivar o Grupo** e **Grupo arquivado** — entram em `CONTEXT.md` **antes** do código (FR-023), primeira tarefa da feature. Identificadores Dart em inglês: `archiveGroup`, `unarchiveGroup`, `isArchived`, `archivedAt`, `archivedBy`, `ArchivePreview`. Banco em português: `arquivado_em`, `arquivado_por`, `arquivar_grupo`, `desarquivar_grupo`. **Inclui código de teste** — a 011 errou nisso e o padrão já está anotado no topo da spec |
| **II. Privacidade e LGPD** | ✅ PASS | Nenhum dado pessoal novo. `arquivado_por` é vínculo entre um Perfil e um Grupo que já existem, visível **só ao Administrador do distrito** (FR-019). A feature **reduz** exposição: Ministério arquivado deixa de exibir publicamente a identificação do Líder/Diretor (FR-016) |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita e validada. `/speckit-clarify` **pulado**; as três decisões de escopo foram tomadas com o usuário antes da escrita. **Uma decisão foi tomada sem consulta** e está marcada na spec: Rodada aberta encerra sem apurar (ver risco 3) |
| **IV. Integridade das Regras de Domínio Testada** | ⚠️ PASS — **é a feature com maior alcance sobre o Princípio IV até aqui** | Toca **quatro das cinco** regras centrais: fila de espera (ninguém é promovido nas Ações canceladas), desempate por sorteio (**não acontece** — Rodada encerra sem apurar), descarte de candidatas (descarte **total**, sem vencedora), revogação de Participar (participações ficam, não são apagadas). Cada uma exige teste de integração próprio, e os testes existentes de apuração **devem passar sem edição** |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel novo. Nenhuma dependência nova. Duas colunas e duas funções — o mínimo que o levantamento permite |

**Complexity Tracking**: nenhuma violação a justificar.

## Project Structure

### Documentation (this feature)

```text
specs/014-arquivar-grupo/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 6 decisões
├── data-model.md        # Fase 1 — o estado, a prévia, quem pode o quê
├── contracts/
│   └── schema.sql       # Fase 1 — colunas, funções, políticas
├── quickstart.md        # Fase 1 — validação
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks — NÃO criado aqui)
```

### Source Code (repository root)

```text
lib/features/group/
├── domain/group.dart                      # ALTERADO: + archivedAt/archivedBy, isArchived
├── domain/archive_preview.dart            # NOVO: os 4 números da confirmação
├── data/group_repository.dart             # ALTERADO: + archiveGroup, unarchiveGroup,
│                                          #   fetchArchivePreview, fetchArchivedGroups
├── group_providers.dart                   # ALTERADO: + archivedGroupsProvider,
│                                          #   archivePreviewProvider
└── presentation/
    ├── group_detail_page.dart             # ALTERADO: opção de arquivar (Dono e Admin)
    ├── group_list_page.dart               # ALTERADO: esconde arquivados
    ├── archive_group_sheet.dart           # NOVO: a confirmação com os 4 números
    └── archived_groups_page.dart          # NOVO: pendências do Administrador

lib/features/action/presentation/action_list_page.dart   # ALTERADO? ver risco 5
lib/app.dart                                             # ALTERADO: rota dos arquivados

supabase/migrations/
└── <timestamp>_arquivar_grupo.sql         # NOVO

CONTEXT.md                                 # ALTERADO: 2 termos novos — PRIMEIRO

test/
├── unit/group_archive_test.dart                       # NOVO
├── widget/archive_group_sheet_test.dart               # NOVO
├── widget/lista_grupos_page_test.dart                 # ALTERADO: arquivado não aparece
└── integration/
    ├── arquivar_grupo_efeitos_test.dart               # NOVO — Princípio IV
    └── arquivar_grupo_permissao_test.dart             # NOVO
```

**Structure Decision**: tudo dentro de `lib/features/group/`, que já existe. Arquivar é uma
operação sobre Grupo, não um conceito novo que mereça módulo próprio — diferente da Foto de
capa (013), que serve a Grupo **e** a Ação.

## Riscos e decisões que precisam de olho

1. **Atomicidade não é opcional.** Arquivar marca o Grupo, cancela N Ações, encerra M Rodadas
   e descarta as candidatas delas. Feito em quatro chamadas do cliente, uma falha no meio
   deixa Ações canceladas num Grupo ativo — pior do que não ter arquivado. Uma função de banco
   é uma transação; é isso que garante o "ou tudo, ou nada" que FR-007 e FR-006 pedem.

2. **Não reusar `fechar_rodada_se_devido`.** Ela apura: escolhe vencedora, promove a Ação e
   descarta as perdedoras. Chamá-la ao arquivar criaria uma Ação confirmada dentro de um Grupo
   que acabou de sair do ar. O encerramento do arquivamento é outro caminho, escrito
   explicitamente: `fechada_em = now()`, `vencedora_id` nulo, **todas** as candidatas
   descartadas.

3. **A decisão sem consulta.** Encerrar a Rodada sem apurar foi decidido por mim, não pelo
   usuário — está marcado em Assumptions da spec como o ponto mais discutível. É o primeiro
   item a revisitar se algo soar errado depois.

4. **Ministério arquivado que continua mostrando o Líder.** `liderancas` não é tocada pelo
   arquivamento, de propósito (é histórico). Se a consulta que exibe o Líder/Diretor não
   filtrar Grupo arquivado, FR-016 quebra **em silêncio** — a identificação pública continua no
   ar, visível a Visitante. É o bug mais provável desta feature, e o que menos aparece em
   teste de unidade.

5. **Onde mais o Grupo arquivado pode vazar.** A listagem é o caso óbvio (FR-010). Mas o Grupo
   também aparece na resolução de Igreja da lista de Ações
   (`action_providers.dart`, que lê `grupos.igreja_id`) e nas telas de Rodada. Cada consumidor
   precisa ser conferido — a spec só cita a listagem, e cobrir só ela deixaria buracos.

6. **Desarquivar não ressuscita nada**, e essa é a consequência mais dura da feature. Um Grupo
   arquivado por engano na véspera de uma Ação com 12 presenças destrói aquele encontro de
   forma irreversível. FR-003 e FR-022 existem só para que ninguém descubra isso depois.

7. **Ninguém é notificado.** Quem participava e quem tinha presença confirmada descobre ao
   abrir o app. Está em Assumptions; não é falha de implementação, é ausência de canal.

## Ordem entre as features abertas

**`012 ✅ → 010 ✅ → 011 ✅ → 013 → 014 (esta)`**

As três primeiras estão mergeadas em `main`. Esta feature é a última da fila.

| Feature | Relação com a 014 |
|---|---|
| 011 (mergeada) | O conceito de Ação encerrada já existe. Ação de Grupo **passada** não é tocada pelo arquivamento — só a futura é cancelada |
| 013 (antes desta) | **Grupo arquivado mantém a capa**, porque o Grupo não é apagado. E o FR-021 da 013 ("quando um Grupo é apagado, sua capa deixa de existir") **continua descrevendo um evento que não acontece** — esta feature arquiva, não apaga |
| 010 (mergeada) | Sem interação |

**Conflito de arquivo com a 013**: as duas alteram `group_detail_page.dart` e
`group_list_page.dart`. A 013 entra antes; esta lê o arquivo já modificado.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões — por que RPC e não cliente, como o
estado é guardado, como a Rodada encerra sem apurar, de onde vêm os quatro números da
confirmação, o que acontece com as participações, e onde o Grupo arquivado precisa sumir.

Nenhum `NEEDS CLARIFICATION` restante.

## Fase 1 — Design

Concluída:

- [data-model.md](./data-model.md) — o estado, a prévia, a tabela de quem-pode-o-quê e o que
  explicitamente não muda.
- [contracts/schema.sql](./contracts/schema.sql) — as duas colunas, as duas funções e as
  políticas, com o motivo de cada escolha escrito no próprio arquivo.
- [quickstart.md](./quickstart.md) — validação, com foco em provar que **nada** foi apurado,
  apagado ou promovido.

**Constitution Check pós-design**: reavaliado, sem mudança. O design **reforçou** o Princípio
IV — as quatro regras tocadas ganharam teste de integração próprio — e manteve o II, porque
nada de pessoal se move. Princípios I e III seguem com a condição e a ressalva já registradas.
