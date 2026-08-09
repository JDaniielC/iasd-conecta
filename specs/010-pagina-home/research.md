# Research: Página Home de propósito

**Feature**: 010-pagina-home | **Date**: 2026-08-09

Seis decisões de design tomadas antes de escrever código. Cada uma registra o que foi
escolhido, por quê, e o que foi descartado — o motivo do descarte é a parte que interessa
numa sessão futura.

---

## D-001 — A lista de Grupos vai para `/grupos`, a Home fica em `/home`

**Decisão**: `lib/app.dart:74` passa a construir `HomePage` em `/home`. Uma rota nova
`/grupos` constrói `GroupListPage`. A rota `/` continua redirecionando para `/home`.

**Rationale**: `/home` já é a rota inicial e já é o destino do `redirect` pós-cadastro
(`app.dart:57`) e pós-entrada na Conta (`app.dart:63`). Manter o nome `/home` significando
"a primeira tela" preserva os dois redirects sem tocá-los, e o significado passa a bater com
o nome — hoje `/home` mostra "Grupos", o que já era estranho. `/grupos` também fica coerente
com as rotas irmãs que já existem: `/grupos/novo`, `/grupos/:id`, `/grupos/:id/editar`.

**Ordem de declaração**: `go_router` casa rotas na ordem declarada. `/grupos` deve ser
declarada **antes** de `/grupos/:id`, senão `novo` e a listagem competem com o parâmetro.
`/grupos/novo` já vem antes de `/grupos/:id` no arquivo atual — a nova entrada entra junto,
respeitando essa ordem.

**Alternativas descartadas**:
- *Home em `/` e lista em `/home`*: `/` teria de deixar de ser um redirect puro, e os dois
  `redirect` de `app.dart` passariam a apontar para o lugar errado sem erro de compilação.
- *Home como aba de uma navegação inferior*: introduz estrutura de navegação nova no app
  inteiro, que a spec não pediu. Fere o Princípio V (simplicidade).

---

## D-002 — A Home segue o padrão das páginas legais, não o das listas

**Decisão**: `HomePage` é um `ConsumerWidget` (sem estado próprio) com
`Scaffold` → `SafeArea` → `SingleChildScrollView` → `Column`, no mesmo formato de
`PrivacyPolicyPage` (`lib/features/legal/presentation/privacy_policy_page.dart`).

**Rationale**: é o padrão que o repositório já usa para tela de conteúdo fixo, e ele já
resolve de graça três requisitos: rola verticalmente (FR-019, sem rolagem horizontal),
sobrevive a texto ampliado (FR-014, porque nada tem altura fixa), e não depende de rede.
`ListView` com itens seria a forma errada — a Home tem um número fixo e pequeno de blocos,
não uma coleção.

**`SafeArea` é obrigatório** (FR-015): a Home é a rota inicial e, em web e mobile, é a tela
que encosta nas bordas — recorte de câmera, barra de status e barra de gestos.

**Sobre a AppBar**: a Home não recebe `AppBar` com botão de voltar (é a raiz, não há para
onde voltar). Se um cabeçalho for necessário, é conteúdo dentro do corpo, o que também
devolve altura vertical — que é escassa em paisagem (ver D-005 e o risco 1 do `plan.md`).

**Alternativa descartada**: reusar `LegalHeading`/`LegalParagraph` de
`features/legal/presentation/widgets/legal_text.dart`. São widgets de texto jurídico corrido;
a Home tem hierarquia visual própria (identidade, blocos explicativos, chamada principal).
Reusar acoplaria duas telas sem nada em comum além de "tem texto".

---

## D-003 — Chamada principal com fallback neutro, para a Home renderizar offline

**Decisão**: a Home observa `hasProfileProvider` **só** para escolher a chamada principal
(FR-008), e trata os três estados assim:

| Estado de `hasProfileProvider` | Chamada principal |
|---|---|
| carregando **ou erro** (offline entra aqui) | "Ver Grupos" — funciona para qualquer pessoa |
| resolvido, sem Perfil | "Criar Perfil" |
| resolvido, com Perfil | "Ver Grupos" |

Todo o resto da Home — nome do app, frase de propósito, "A Deus seja a glória", explicações
de Grupo e Ação, caminhos para as listas e para as páginas legais — é construído fora de
qualquer `AsyncValue`, sem observar provider algum.

**Rationale**: `hasProfileProvider` (`lib/core/providers.dart:40`) chama
`PerfilRepository.hasPerfil()`, que vai ao Supabase. Sem rede ele nunca resolve com sucesso.
Se a Home inteira ficasse dentro de um `.when`, ela mostraria um indicador de carregamento ou
uma mensagem de erro no lugar do conteúdo — e SC-005 ("renderiza integralmente sem conexão,
sem erro visível e sem área em branco") cairia. Isolar o provider em um único bloco resolve.

**Escolha do fallback**: "Ver Grupos" é seguro nos dois casos — quem não tem Perfil vê os
Grupos livremente (é o direito do Visitante no glossário) e encontra o cadastro logo abaixo,
como ação secundária. O contrário não vale: oferecer "Criar Perfil" a quem já tem Perfil é um
beco sem saída.

**Uma única troca é aceitável**: a spec permite ("mostra a versão neutra e só então adapta"),
e como o estado neutro e o estado "com Perfil" são o mesmo botão, quem já tem Perfil não vê
troca nenhuma.

---

## D-004 — Sem animação de entrada

**Decisão**: a Home não tem animação de entrada, revelação escalonada nem transição própria.
O conteúdo aparece pintado de uma vez.

**Rationale**: FR-016 exige respeitar a preferência de movimento reduzido do sistema. A forma
mais simples e mais barata de cumprir isso é não ter movimento a suprimir — nada de
`MediaQuery.disableAnimationsOf`, nada de ramo condicional, nada para testar em dois modos.
Princípio V, direto. O ganho estético de uma animação de entrada numa tela que a pessoa vê
uma vez por sessão não paga o custo de manutenção nem o risco de acessibilidade.

**Alternativa descartada**: revelação escalonada dos blocos (padrão sugerido pelo material de
UI/UX). Exigiria o ramo de movimento reduzido, um teste a mais e uma variável de estado —
justamente o que o Princípio V manda evitar sem necessidade comprovada.

---

## D-005 — Acessibilidade: o que o tema já dá e o que precisa ser feito à mão

**Já resolvido pelo tema e pelos padrões do Flutter — não precisa de código novo**:

| Requisito | Por que já está coberto |
|---|---|
| FR-012 contraste ≥4,5:1 | `AppColors.navy` (`#17284C`) sobre `#FFFFFF` fica em torno de 13:1. Texto de corpo padrão do Material 3 sobre `surface` branco também passa. A conferir só se um cinza claro for introduzido. |
| FR-013 alvo de toque ≥44×44pt | `ElevatedButton` do tema tem `padding` vertical de 16 (`app_theme.dart:53`), e o Material usa `MaterialTapTargetSize.padded` (48dp mínimo) por padrão. `TextButton` também. |
| FR-014 escala de fonte | Nenhum bloco com altura fixa (D-002); o texto empurra o layout e a página rola. |
| FR-019 sem rolagem horizontal | `Column` dentro de `SingleChildScrollView` vertical, com largura restrita ao pai. |

**Precisa de trabalho explícito**:

| Requisito | O que fazer |
|---|---|
| FR-015 áreas seguras | Envolver o corpo em `SafeArea`. |
| FR-017 ícones vetoriais consistentes | Usar só `Icons.*` do Material (a família já usada em todo o app: `Icons.groups_outlined`, `Icons.event_outlined`). Nenhum emoji como ícone. |
| FR-020 ordem de leitura e rótulos | Ordem de leitura já acompanha a ordem visual por construção (`Column`). Cada controle precisa de rótulo audível: botões com texto visível já resolvem; nada de botão só-ícone na Home. |
| FR-003 doxologia lida como texto | "A Deus seja a glória" é um `Text` comum, não decoração — leitor de tela lê. Não marcar como `ExcludeSemantics`. |

**Texto exato a fixar** (FR-003, verificado caractere a caractere): `A Deus seja a glória`.

---

## D-006 — Estratégia de teste: widget test, e o que só o olho resolve

**Decisão**: cobrir por teste de widget (`test/widget/home_page_test.dart` + atualização de
`test/widget/router_visitante_test.dart`) tudo que é verificável por asserção, e listar
explicitamente no `quickstart.md` o que exige verificação manual.

**Coberto por teste automatizado**:
- A rota inicial constrói a Home, não a lista de Grupos (é o teste que hoje falha: 
  `router_visitante_test.dart` espera `find.text('Grupos')`).
- A frase exata "A Deus seja a glória" está presente.
- Os termos do glossário (Grupo, Ação) aparecem nas explicações.
- Existem caminhos para Grupos, Ações, Política de Privacidade e Termos de Uso.
- A chamada principal é "Criar Perfil" com `hasProfileProvider` resolvido em `false`, e
  "Ver Grupos" com `true`.
- **A chamada principal é "Ver Grupos" quando `hasProfileProvider` falha** — é o teste que
  protege SC-005 (offline) e o que mais fácil se perde numa refatoração.
- Nenhum dado pessoal na tela (FR-006): a Home renderiza sem nenhum override de repositório
  de Perfil além do `hasProfileProvider`, provando que não consulta mais nada.

**Não coberto por teste automatizado — vai para o `quickstart.md` como checagem manual**:
paisagem a 375px, fonte do sistema no máximo, contraste medido, comportamento real offline,
e leitura por leitor de tela. Teste de widget não mede pixel de contraste nem simula
VoiceOver de forma confiável; fingir que mede seria pior do que declarar a lacuna.

**Sem teste de integração**: `test/integration/` roda contra Supabase local e cobre regra de
banco. A Home não toca banco — não há o que cobrir ali.
