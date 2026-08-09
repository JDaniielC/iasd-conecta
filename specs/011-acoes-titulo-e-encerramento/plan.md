# Implementation Plan: Ação — encerramento, contagem de confirmados e clareza do título

**Branch**: `011-acoes-titulo-e-encerramento` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/011-acoes-titulo-e-encerramento/spec.md`

## Summary

Quatro mudanças na Ação, três de apresentação e uma com dente no banco:

1. **Encerramento por tempo** (P1) — uma Ação passa a ser *a acontecer*, *acontecendo agora*
   ou *encerrada*, derivado de `data_hora + 4h`. Encerrada some da listagem, continua
   acessível por link, e não aceita mais confirmar/desistir. Como FR-007 promete que ninguém
   é promovido da fila depois do encerramento, esconder o botão não basta: a regra é
   reforçada no banco, via política de acesso, com teste de integração.
2. **Contagem de confirmados na listagem** (P2) — uma consulta agregada extra, sem trazer
   quem é quem.
3. **Nome da Ação** (P3) — texto de apoio no formulário e recusa quando o nome digitado é
   igual ao nome/Apelido de quem está criando.
4. **Numeração dos confirmados** (P4) — `1.`, `2.`, `3.` no detalhe.

O eixo técnico é: **estado derivado, não gravado**. Nada de coluna nova, nada de job. O
encerramento é uma função pura sobre `data_hora`, testável em `test/unit/`, avaliada em
tempo de render — com um relógio injetável para o teste não depender de `DateTime.now()`.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: `flutter_riverpod ^3.3.2`, `go_router ^17.3.0`,
`supabase_flutter ^2.8.0`, `intl ^0.20.2`. Nenhuma dependência nova.

**Storage**: PostgreSQL via Supabase. Tabelas envolvidas: `acoes`, `confirmacoes_acao`.
**Nenhuma coluna nova** — só uma migration que aperta duas políticas de acesso existentes.

**Testing**: `flutter_test` + `mocktail` (unit/widget) e `dart test test/integration` contra
Supabase local. Gates de `.github/workflows/ci.yml`: `flutter analyze`,
`flutter test test/unit test/widget`, `dart test test/integration`, `flutter build web`.

**Target Platform**: Flutter web (deploy atual) + Android/iOS.

**Project Type**: mobile/web app Flutter organizado por feature, com regra de domínio no
banco (triggers e políticas) e espelho client-side só para feedback imediato.

**Performance Goals**: a listagem de Ações não pode virar N+1 — a contagem de confirmados de
todas as Ações sai de **uma** consulta agregada, não de uma por Ação.

**Constraints**:
- A contagem NÃO PODE trazer identidade de ninguém (Princípio II) — a consulta lê
  `acao_id, status`, nunca `usuario_id`.
- O limiar de 4 horas fica em **dois lugares** (Dart e SQL). Duplicação declarada e testada
  nos dois lados; ver Riscos.
- O bloqueio de desistência em Ação encerrada não pode quebrar a exclusão de conta da
  feature 009, que apaga `confirmacoes_acao` do Usuário. Ver Riscos, item 1.

**Scale/Scope**: 4 telas tocadas, 1 modelo de domínio, 1 repositório, 1 migration,
~5 arquivos de teste. Distrito de 15+ igrejas — centenas de confirmações, não milhões.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|-----------|----------|-------------------------------|
| **I. Linguagem Ubíqua** | ✅ PASS | Termos de UI e de spec usam o glossário exato (Ação, Ação candidata, Rodada de votação, Participar, Apelido, Dupla Missionária, fila de espera). Identificadores em inglês: `ActionTimeStatus`, `clockProvider`, `ConfirmationCounts`, seguindo o mapa de tradução que a feature **012 já estabeleceu em `CONTEXT.md`** antes desta. Como a 012 vem primeiro (ver "Ordem entre as features abertas"), o módulo já se chama `lib/features/action/` e seus tipos já estão em inglês — **não há desvio a declarar** |
| **II. Privacidade e LGPD** | ✅ PASS | Nenhum dado pessoal novo. A contagem é agregada e a consulta que a alimenta **não seleciona `usuario_id`** — o número existe sem que o cliente saiba quem é quem, o que é mais forte do que o mínimo exigido. A lista nominal de confirmados continua vindo só pela RPC `perfil_publico`, que já aplica a regra de Apelido para menor de idade. Nenhuma nova exposição a Visitante além de um número. |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita e validada. `/speckit-clarify` **pulado**; as três ambiguidades de regra (limiar de encerramento, destino da Ação encerrada, escopo de correção de título) foram decididas com o usuário antes da escrita da spec e estão registradas em Assumptions e no checklist. |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS — é o coração desta feature | A **fila de espera** é regra central e esta feature muda o comportamento dela na borda (FR-007: sem promoção após o encerramento). Por isso o bloqueio é feito no banco, não só na UI, e ganha teste em `test/integration/`. As demais regras — desempate por sorteio, revogação de voto, descarte de candidatas, composição de Dupla Missionária — não mudam, e os testes existentes que as cobrem devem continuar verdes sem edição. |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel novo. Nenhuma coluna, job agendado ou `Timer` de UI. Estado derivado por função pura. A contagem sai de uma consulta agregada em vez de uma view nova — a view entra só se a consulta agregada doer, o que num distrito desse tamanho não acontece. |

### Complexity Tracking

**Nenhuma violação a justificar.**

Registro histórico, porque a decisão mudou durante o planejamento: este plano nasceu com um
desvio declarado do Princípio I — manter identificadores em português em `acao.dart` porque
renomeá-los no meio de uma mudança de comportamento produziria um diff irrevisável. A pendência
correspondente virou a feature **012 (identificadores em inglês)**, e a ordem foi então
invertida para colocar a 012 **antes** desta. Com isso o desvio deixou de existir em vez de ser
justificado — que é o desfecho melhor.

## Project Structure

### Documentation (this feature)

```text
specs/011-acoes-titulo-e-encerramento/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — decisões e alternativas descartadas
├── data-model.md        # Fase 1 — estado derivado e agregado (nenhuma entidade nova)
├── contracts/
│   └── schema.sql       # Fase 1 — delta de migration (políticas de acesso)
├── quickstart.md        # Fase 1 — roteiro de validação
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks — NÃO criado aqui)
```

### Source Code (repository root)

> Caminhos pós-rename da feature 012, que vem antes desta.

```text
lib/
├── core/
│   └── providers.dart                          # ALTERADO: + clockProvider (relógio injetável)
└── features/action/
    ├── domain/action.dart                      # ALTERADO: + ActionTimeStatus + função pura
    │                                           #   de encerramento; + modelo da contagem
    ├── data/action_repository.dart              # ALTERADO: + consulta agregada da contagem
    ├── action_providers.dart                   # ALTERADO: + provider da contagem
    └── presentation/
        ├── action_list_page.dart               # ALTERADO: filtra encerradas + contagem no card
        ├── action_detail_page.dart             # ALTERADO: rótulo de encerrada, esconde ações,
        │                                       #   numera confirmados e fila
        ├── create_action_page.dart             # ALTERADO: texto de apoio + validação do nome
        └── create_candidate_page.dart          # ALTERADO: mesmo texto de apoio e validação

supabase/migrations/
└── <timestamp>_acao_encerrada_bloqueia_presenca.sql   # NOVO

test/
├── unit/
│   ├── acao_encerramento_test.dart             # NOVO: fronteiras da função pura
│   └── acao_nome_criador_test.dart             # NOVO: normalização e igualdade do nome
├── widget/
│   ├── lista_acoes_page_test.dart              # ALTERADO: encerrada some, contagem aparece
│   ├── detalhe_acao_page_test.dart             # ALTERADO: encerrada esconde botões, numeração
│   └── criar_acao_page_nome_test.dart          # NOVO: recusa do nome do próprio criador
└── integration/
    └── acao_encerrada_nao_promove_fila_test.dart   # NOVO: Princípio IV
```

**Structure Decision**: mantida a organização por feature. Tudo cabe no módulo
`lib/features/action/` já existente — nenhuma pasta nova. O único arquivo fora do módulo é
`core/providers.dart`, que ganha o relógio injetável porque ele é infraestrutura
compartilhada, não regra de Ação.

## Riscos e decisões que precisam de olho

1. ~~**O bloqueio de desistência pode quebrar a exclusão de conta (feature 009)**~~ —
   **RESOLVIDO na implementação, e o risco era menor do que este plano supunha.**

   O medo original: se o bloqueio de FR-007 fosse um `trigger before delete` genérico, quem
   tivesse confirmação numa Ação encerrada não conseguiria mais apagar a conta — bug de LGPD
   criado por uma feature de UX. A decisão foi usar **política de acesso (RLS)** em vez de
   trigger, porque `excluir_minha_conta` é `security definer` e não passa por RLS.

   As duas premissas foram medidas contra o banco antes da migration (T001):
   `excluir_minha_conta` tem `prosecdef = true`, e nem `confirmacoes_acao` nem `acoes` têm
   `force row level security`. Confirmadas.

   E ao escrever o teste apareceu uma **segunda razão, independente**, que ninguém tinha
   notado: `excluir_minha_conta` só apaga confirmação de Ação **futura**
   (`a.data_hora > now()`) — confirmação de Ação passada é mantida de propósito, como
   histórico da feature 009. Ou seja, a política nunca atravessa o caminho da exclusão: Ação
   futura não está encerrada, Ação encerrada não é tocada.

   O teste `acao_encerrada_nao_promove_fila_test.dart` caso (c) trava as duas metades mesmo
   assim — a razão de algo estar certo pode mudar sem aviso.
2. **O limiar de 4 horas fica duplicado em Dart e em SQL**. Não há como derivar um do outro
   sem uma ida ao servidor a cada render. Mitigação: constante nomeada nos dois lados, cada
   uma com comentário apontando para a outra, e teste de integração que prova a fronteira no
   banco além do teste unitário que prova no cliente. Se um dia divergirem, o sintoma é
   cruel: o botão some na UI mas o banco ainda aceita, ou o contrário.
3. **`DateTime.now()` dentro do `build`** (hoje em `action_list_page.dart:56`) torna o
   comportamento não testável. Resolvido com `clockProvider`; a armadilha é esquecer de
   trocar alguma chamada direta e ter um teste que passa por acaso.
4. **A contagem sobe a superfície de leitura de `confirmacoes_acao`**. A política já é
   `using (true)` (leitura pública), então nada muda em permissão — mas a consulta precisa
   selecionar **só** `acao_id, status`. Selecionar `*` por preguiça traria `usuario_id` de
   todo mundo para o cliente. É o erro mais fácil e mais caro desta feature.
5. **FR-019 tem um limite real**: recusar só igualdade com o nome do próprio criador não
   impede alguém de digitar o nome de outra pessoa. Está declarado na spec como assumption;
   não vira requisito escondido.

## Ordem entre as features abertas

**`012 → 010 → 011 → 013 → 014`** (ver `specs/012-identificadores-em-ingles/plan.md`).

Consequências para esta feature:

- Ela é escrita sobre o módulo **já renomeado** (`lib/features/action/`), então o desvio do
  Princípio I nunca chega a existir.
- A 010 vem antes e já terá trocado o `IconButton` "Grupos" de `/home` para `/grupos` em
  `action_list_page.dart` — uma linha do `AppBar`, longe do corpo da lista que esta feature
  altera. Conflito nenhum.
- A 013 vem **depois** e vai mexer no mesmo `_ActionCard` (capa) e no
  `action_detail_page.dart`. O conflito é problema da 013, e o `tasks.md` dela já registra.
- Esta feature corrige informação errada em produção e, com a nova ordem, espera as cinco
  etapas do rename. Custo aceito conscientemente quando a ordem foi decidida: o bug é
  irritante, não perigoso.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões (limiar derivado vs. gravado, onde
filtrar, onde reforçar FR-007, como contar sem vazar identidade, como comparar o nome do
criador, relógio injetável), cada uma com a alternativa descartada.

Nenhum `NEEDS CLARIFICATION` restante.

## Fase 1 — Design

Concluída:

- [data-model.md](./data-model.md) — o estado derivado `ActionTimeStatus`, a agregação de
  contagem, e a declaração explícita de que nenhuma entidade nem coluna é criada.
- [contracts/schema.sql](./contracts/schema.sql) — delta de migration: as duas políticas de
  acesso apertadas, com a premissa sobre `excluir_minha_conta` escrita no próprio arquivo.
- [quickstart.md](./quickstart.md) — gates, o que cada teste prova, e a checagem manual.

**Constitution Check pós-design**: reavaliado. Princípios II, IV e V seguem PASS — o design
reforçou o II (a consulta agregada não lê `usuario_id`) e o IV (FR-007 saiu da UI e foi para
o banco, com teste de integração). Princípios I e III seguem com o desvio e a ressalva já
registrados acima; nenhum novo desvio apareceu no design.
