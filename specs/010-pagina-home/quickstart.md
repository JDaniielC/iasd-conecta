# Quickstart — validar a Página Home de propósito

**Feature**: 010-pagina-home | **Date**: 2026-08-09

Como provar que a feature funciona. Duas partes: o que a máquina verifica (e é gate de CI) e
o que só o olho resolve.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
```

## Parte 1 — Gates automatizados

Mesmos comandos que `.github/workflows/ci.yml` roda. Todos precisam passar antes de
considerar a feature pronta.

```bash
flutter analyze
flutter test test/unit test/widget
flutter build web
```

**Resultado esperado**: `flutter analyze` sem issue; `flutter test` com 0 falhas — anotar o
número real de testes que passaram, não "os testes passaram"; `flutter build web` concluindo.

`dart test test/integration` **não** precisa rodar: exige Supabase local e cobre regra de
banco, que esta feature não toca.

### O que cada teste de widget prova

| Teste | Requisito coberto |
|---|---|
| `router_visitante_test.dart` — rota inicial constrói a Home | FR-001 |
| `home_page_test.dart` — frase exata `A Deus seja a glória` presente | FR-003 |
| `home_page_test.dart` — nome do app e frase de propósito presentes | FR-002 |
| `home_page_test.dart` — explicações citam **Grupo** e **Ação** | FR-004, Princípio I |
| `home_page_test.dart` — caminhos rotulados para Grupos e Ações | FR-007 |
| `home_page_test.dart` — caminhos para Política de Privacidade e Termos de Uso | FR-009 |
| `home_page_test.dart` — sem Perfil, chamada principal é "Criar Perfil" | FR-008 |
| `home_page_test.dart` — com Perfil, chamada principal é "Ver Grupos" | FR-008 |
| `home_page_test.dart` — `hasProfileProvider` em erro, chamada principal é "Ver Grupos" e a Home renderiza inteira | SC-005, decisão D-003 |

**Como simular offline no teste**: sobrescrever `hasProfileProvider` com um erro
(`overrideWith((ref) async => throw Exception('offline'))`) e afirmar que os textos fixos da
Home continuam presentes. É essa asserção que impede alguém de, numa refatoração futura,
embrulhar a Home inteira num `.when` e quebrar o comportamento offline sem quebrar nenhum
outro teste.

### Teste existente que vai falhar até ser atualizado

`test/widget/router_visitante_test.dart` hoje afirma `expect(find.text('Grupos'), findsOneWidget)`
na rota inicial. Com a Home no lugar, essa asserção passa a ser falsa. Atualizar para afirmar
a Home, e mover a verificação de "Visitante alcança a lista de Grupos" para depois da
navegação. Não apagar o caso — o que ele protege (Visitante não é empurrado ao cadastro)
continua valendo.

## Parte 2 — Verificação manual

O que teste de widget não mede. Rodar o app e conferir com o olho.

```bash
flutter run -d chrome        # web, o alvo em deploy hoje
# ou
flutter run                  # aparelho/emulador conectado
```

| # | Checagem | Requisito | Como fazer | Esperado |
|---|---|---|---|---|
| 1 | Primeira tela | FR-001, SC-002 | Abrir o app | A Home aparece; "A Deus seja a glória" visível sem rolar |
| 2 | Largura mínima | FR-019 | Estreitar a janela do Chrome até 375px | Nada rola horizontalmente; nenhum texto cortado nas laterais |
| 3 | Paisagem | SC-002, SC-006 | Girar o aparelho, ou janela ~812×375 | Sem rolagem horizontal; a doxologia continua visível sem rolar, em tamanho de fonte padrão |
| 4 | Fonte no máximo | FR-014, SC-006 | Ajustes do sistema → tamanho de texto no máximo; reabrir o app | Nenhum texto cortado nem sobreposto; a página rola verticalmente |
| 5 | Offline de verdade | SC-005 | DevTools → Network → Offline; recarregar | A Home renderiza inteira, sem erro visível e sem área em branco; chamada principal é "Ver Grupos" |
| 6 | Áreas seguras | FR-015 | Aparelho com recorte de câmera / barra de gestos | Nenhum conteúdo ou botão sob a barra de status, o recorte ou a barra de gestos |
| 7 | Contraste | FR-012, SC-004 | Medir cada par texto/fundo (DevTools ou verificador WCAG) | Todo texto de corpo ≥4,5:1 |
| 8 | Alvo de toque | FR-013, SC-004 | Inspecionar cada elemento tocável | ≥44×44pt, ≥8pt de separação entre vizinhos |
| 9 | Movimento reduzido | FR-016 | Ativar redução de movimento no sistema | Sem diferença — a Home não anima (decisão D-004) |
| 10 | Leitor de tela | FR-020, FR-003 | VoiceOver (iOS/macOS) ou TalkBack (Android) | Ordem de leitura acompanha a ordem visual; todo controle tem rótulo; "A Deus seja a glória" é lida |
| 11 | Ida e volta | FR-007, FR-010, SC-003 | Home → Grupos → voltar; Home → Ações → voltar | Um toque para cada lista; o voltar do sistema retorna à Home com a rolagem preservada |
| 12 | Páginas legais | FR-009 | Da Home, alcançar Política de Privacidade e Termos de Uso | Ambas abrem |
| 13 | **Botão "Grupos" dentro de Ações** | conflito com a 011 | Home → Ações → tocar o ícone "Grupos" no topo | Vai para a **lista de Grupos**, não de volta à Home. Se voltar à Home, `action_list_page.dart:60` ficou com `/home` |
| 14 | Nenhum dado pessoal | FR-006, Princípio II | Olhar a Home logado e deslogado | Nenhum nome, Apelido, Igreja de origem, foto ou contagem de pessoas |

## Definição de pronto

- [ ] Parte 1 verde, com o número real de testes anotado
- [ ] Parte 2, itens 1 a 14, conferidos
- [ ] Item 13 conferido especificamente — é o bug silencioso que não quebra compilação
- [ ] `CONTEXT.md` **não** precisou de alteração (nenhum termo novo de domínio)
