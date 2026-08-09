# Implementation Plan: Página Home de propósito

**Branch**: `010-pagina-home` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/010-pagina-home/spec.md`

## Summary

Hoje a rota inicial do app é a lista de Grupos: quem abre o app pela primeira vez cai numa
lista sem nenhum contexto do que o app é. Esta feature insere uma Home de propósito antes
dela — conteúdo estático, sem rede, que diz o que é o app, exibe "A Deus seja a glória",
explica o que são Grupo e Ação, e aponta para as duas listas, para o cadastro e para as
páginas legais.

Abordagem técnica: uma tela nova sem estado próprio (`HomePage`), no padrão das páginas
legais já existentes (`SingleChildScrollView` + textos fixos, sem provider de rede). A lista
de Grupos sai de `/home` e ganha rota própria `/grupos`, sem nenhuma mudança de
comportamento interno. O único provider que a Home observa é `hasProfileProvider`, e apenas
para escolher a chamada principal — com fallback neutro em carregando/erro, para a Home
continuar renderizando por completo offline.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2` (`pubspec.yaml:22`)

**Primary Dependencies**: `flutter_riverpod ^3.3.2` (estado), `go_router ^17.3.0`
(navegação), `supabase_flutter ^2.8.0` (não usado por esta feature). Nenhuma dependência
nova.

**Storage**: nenhum. A Home não lê nem grava dado algum.

**Testing**: `flutter_test` (widget) + `mocktail`. Gates de CI em `.github/workflows/ci.yml`:
`flutter analyze`, `flutter test test/unit test/widget`, `flutter build web`.
`dart test test/integration` roda contra Supabase local — não é tocado por esta feature.

**Target Platform**: Flutter multiplataforma; o alvo em uso hoje é **web** (deploy em
`deploy-web.yml`) e Android/iOS. Layout mobile-first, verificado a 375px.

**Project Type**: mobile/web app Flutter, organizado por feature em `lib/features/<nome>/`
com subpastas `domain/`, `data/`, `presentation/`.

**Performance Goals**: 60fps na rolagem; a Home é estática, sem chamada de rede no caminho
crítico — primeira pintura não depende de resposta de servidor.

**Constraints**:
- Renderizar por completo **offline** (SC-005) — nenhum texto da Home pode depender de rede.
- Sem rolagem horizontal em nenhuma largura (FR-019); verificado a 375px e em paisagem.
- Escala de fonte do sistema até o máximo sem corte (FR-014).
- Contraste ≥4,5:1 (FR-012) e alvo de toque ≥44×44pt (FR-013).

**Scale/Scope**: 1 tela nova, 1 rota nova, 1 rota realocada. ~4 arquivos tocados, ~2 arquivos
de teste. Distrito de 15+ igrejas, público de todas as idades.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|-----------|----------|-------------------------------|
| **I. Linguagem Ubíqua do Domínio** | ✅ PASS | Identificadores Dart em inglês: `HomePage`, arquivo `home_page.dart`, pasta `lib/features/home/`. Toda string de UI em português, usando os termos exatos do glossário — **Grupo**, **Ação**, **Visitante**, **Usuário**, **Perfil**, **Participar**. Nenhum sinônimo da lista `_Avoid_` (nada de "evento", "atividade", "comunidade", "cadastro completo"). Nenhum termo novo: não é preciso alterar `CONTEXT.md`. |
| **II. Privacidade e LGPD por Padrão** | ✅ PASS | Nenhum dado pessoal é coletado, exibido ou retido (FR-006). A Home não lê `perfis`, não exibe nome, Apelido, Igreja de origem, idade nem contagem de pessoas. O único estado pessoal consultado é o booleano "tem Perfil?", que já existe e não é exibido — só decide qual botão aparece. |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita e validada (`spec.md`, checklist 16/16). **`/speckit-clarify` foi pulado.** A única ambiguidade real da spec — a lista de Grupos sair da rota inicial — foi resolvida diretamente com o usuário nesta sessão e está registrada em Assumptions. Nenhuma regra de negócio foi decidida ad-hoc: esta feature não tem regra de negócio. |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS (não aplicável) | A Home não toca nenhuma das regras centrais: fila de espera, apuração/desempate de Rodada de votação, revogação de voto ou de Participar, descarte de candidatas, composição de Dupla Missionária. Nenhuma delas muda de comportamento nem precisa de teste novo. O que ganha teste é a Home em si (ver Fase 1). |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel novo, nenhuma permissão nova. Nenhuma dependência nova. Nenhum provider novo. A Home é `StatelessWidget`/`ConsumerWidget` sem estado próprio, no mesmo padrão de `PrivacyPolicyPage`. Sem animação (ver `research.md`, D-004): a forma mais simples de cumprir FR-016 é não ter o que suprimir. |

**Complexity Tracking**: nenhuma violação a justificar — a tabela foi removida.

## Project Structure

### Documentation (this feature)

```text
specs/010-pagina-home/
├── spec.md              # Fase anterior (/speckit-specify)
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — decisões de design e por quê
├── quickstart.md        # Fase 1 — como validar a feature de ponta a ponta
├── checklists/
│   └── requirements.md  # Fase anterior
└── tasks.md             # Fase 2 (/speckit-tasks — NÃO criado aqui)
```

**`data-model.md` e `contracts/` não são gerados**, de propósito: a Home não introduz nem
altera entidade alguma (a própria spec registra "Nenhuma entidade nova"), e o app não expõe
interface externa — não há contrato a documentar. Arquivos vazios com "N/A" seriam ruído.

### Source Code (repository root)

```text
lib/
├── app.dart                                   # ALTERADO: /home passa a ser HomePage;
│                                              #   nova rota /grupos para GroupListPage
├── core/
│   └── theme/app_theme.dart                   # inalterado — a Home usa o tema existente
└── features/
    ├── home/                                  # NOVO
    │   └── presentation/
    │       └── home_page.dart                 # NOVO: a tela inteira
    ├── group/presentation/group_list_page.dart   # ALTERADO: só o comentário de topo,
    │                                               #   que hoje diz "Home do app"
    └── action/presentation/action_list_page.dart     # ALTERADO: 1 linha — o botão
                                                    #   "Grupos" aponta pra /grupos

test/
└── widget/
    ├── home_page_test.dart                    # NOVO
    ├── router_visitante_test.dart             # ALTERADO: hoje espera cair em "Grupos"
    └── lista_acoes_page_test.dart             # verificar (pode assertar a navegação)
```

**Structure Decision**: mantida a organização por feature já usada em todo o `lib/features/`.
A Home ganha sua própria pasta `lib/features/home/presentation/` — não entra em `core/` (não
é infraestrutura compartilhada) nem em `grupo/` (não é sobre Grupo). Só a subpasta
`presentation/` é criada: sem `domain/` e sem `data/`, porque a Home não tem regra nem dado.

## Ordem entre as features abertas

**`012 → 010 → 011 → 013 → 014`** (ver `specs/012-identificadores-em-ingles/plan.md`).

A 012 vem antes desta, então os caminhos citados aqui já são os pós-rename:
`lib/features/action/presentation/action_list_page.dart`,
`lib/features/group/presentation/group_list_page.dart`, `GroupListPage`, `hasProfileProvider`.
Nomes de arquivo de teste continuam em português, por decisão registrada na 012.

Esta feature é a primeira de comportamento a entrar, e é a menor de todas — uma linha em
`action_list_page.dart` e um módulo novo (`home/`) que já nasce em inglês.

### Ponto de conflito com a feature 011

A `011-acoes-titulo-e-encerramento` vem logo depois. As duas tocam **um arquivo em comum**:

| Arquivo | O que a 010 faz | O que a 011 vai fazer | Risco |
|---------|-----------------|-----------------------|-------|
| `lib/features/action/presentation/action_list_page.dart` | 1 linha: `action_list_page.dart:60`, o `IconButton` com tooltip "Grupos" hoje faz `context.go('/home')` — passa a `context.go('/grupos')`, senão o botão "Grupos" leva à Home de propósito, não aos Grupos | Filtrar Ações encerradas da lista (FR-003 da 011) e adicionar contagem de confirmados ao card (FR-009 a FR-013 da 011) — mexe no `build` e no `_ActionCard` | **Baixo**: partes diferentes do arquivo (uma linha no `AppBar` vs. corpo da lista e o card). Conflito de merge, se houver, é trivial |
| `test/widget/lista_acoes_page_test.dart` | possivelmente nada | reescrita significativa | **Baixo** |

**Armadilha a evitar**: se a 011 for implementada sem a 010, `context.go('/home')` continua
correto. Se a 010 entrar e essa linha for esquecida, o app fica com um botão rotulado
"Grupos" que leva à Home — bug silencioso, sem erro de compilação. Está registrado como item
explícito do plano por isso.

## Riscos e decisões que precisam de olho

1. **SC-002 vs. FR-014 (conflito real na spec)**. SC-002 exige a frase "A Deus seja a glória"
   visível sem rolagem "em retrato e em paisagem" a partir de 375px. FR-014 exige suportar a
   fonte do sistema no tamanho máximo. Em paisagem (~375px de altura) com fonte no máximo,
   nome do app + frase de propósito + doxologia não cabem — é fisicamente impossível atender
   os dois ao mesmo tempo. **Interpretação adotada**: SC-002 é medido no tamanho de fonte
   padrão; com fonte ampliada vale FR-014 (nada cortado, rola). Se essa leitura estiver
   errada, é a primeira coisa a corrigir.
2. **A rota `/home` muda de significado sem quebrar compilação**. Qualquer `context.go('/home')`
   existente continua compilando e passa a levar a outro lugar. Há um em
   `action_list_page.dart:60` e dois no `redirect` de `app.dart` (linhas 57 e 63) — nestes
   dois, ir para a Home depois de cadastrar ou entrar na Conta é o comportamento desejado,
   e ficam como estão.
3. **`hasProfileProvider` vai à rede** (`core/providers.dart:40` → `PerfilRepository.hasPerfil()`).
   Se a Home o observar sem tratar carregando/erro, ela deixa de renderizar offline e SC-005
   cai. Tratamento definido em `research.md` (D-003).

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões registradas (rota, estrutura da
página, chamada principal offline, ausência de animação, semântica de acessibilidade,
estratégia de teste), cada uma com a alternativa descartada e o motivo.

Nenhum `NEEDS CLARIFICATION` restante no Technical Context.

## Fase 1 — Design

Concluída. Ver [quickstart.md](./quickstart.md): roteiro de validação executável — comandos
de gate (`flutter analyze`, `flutter test test/widget`), o que cada teste de widget prova, e
a checagem manual que só o olho resolve (paisagem, fonte no máximo, offline, leitor de tela).

`data-model.md` e `contracts/` não se aplicam (justificado em Project Structure).

**Constitution Check pós-design**: reavaliado, sem mudança — os cinco princípios continuam
PASS, com a mesma ressalva no Princípio III (`/speckit-clarify` pulado, ambiguidade resolvida
direto com o usuário e registrada). O design não introduziu papel, dependência, provider nem
dado novo.
