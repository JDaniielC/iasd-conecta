# Quickstart — validar a Foto de capa

**Feature**: 013-foto-de-capa | **Date**: 2026-08-09

Duas coisas precisam de prova aqui, e a segunda é a difícil: que a imagem **aparece**, e que
a imagem **some de verdade**. Órfão não tem sintoma — só contagem revela.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start            # Postgres + Storage local
```

## Parte 0 — Verificar as premissas do fornecedor ANTES de escrever a migration

`research.md` D-004 tem duas perguntas cujas respostas mudam o desenho **e o texto da Política
de Privacidade**. Nenhuma delas pode ser respondida de memória.

| # | Pergunta | O que a resposta decide |
|---|---|---|
| 1 | Apagar o registro do objeto remove mesmo o binário, ou deixa órfão invisível? | Se o gatilho da seção 2 de [contracts/schema.sql](./contracts/schema.sql) basta |
| 2 | Objeto público removido continua servível por cache de borda por quanto tempo? Há invalidação síncrona? | **O texto de FR-012 na Política de Privacidade** — e se vale o plano alternativo (endereço assinado de vida curta) |

Consultar a documentação oficial do fornecedor e **citar o trecho literal** no
`research.md` antes de prosseguir.

**Se a resposta a (2) for uma janela de cache não desprezível**: a Política de Privacidade
DEVE dizer "removida imediatamente da origem; pode permanecer em cache por até N", e não a
versão desejada. E a decisão de aceitar N ou trocar para endereço assinado precisa ser tomada
por quem responde pelo app — o caso que motivou a feature é foto de menor.

## Parte 1 — Gates automatizados

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration          # exige supabase start
flutter build web                   # o alvo em produção hoje
```

**Resultado esperado**: 0 falhas. Anotar o número real de cada suíte — nunca "os testes
passaram".

`flutter build web` não é opcional aqui: o seletor de imagem é a parte da feature com maior
chance de quebrar só em web (research D-002).

### O que cada teste novo prova

| Teste | Requisito |
|---|---|
| `test/unit/cover_photo_validation_test.dart` — formato, tamanho e arquivo ilegível recusados | FR-009 |
| `test/widget/cover_photo_advice_test.dart` — o aviso aparece antes do seletor, e **de novo** na troca | FR-004, FR-005, SC-001 |
| `test/widget/cover_photo_advice_test.dart` — quem não administra não vê opção de capa | FR-003 |
| `test/widget/pending_reports_page_test.dart` — pendências agrupadas por imagem, com contagem | FR-016, FR-018 |
| `test/widget/pending_reports_page_test.dart` — a identidade do denunciante não aparece fora da tela do Administrador | FR-020 |
| **`test/integration/foto_capa_orfao_test.dart`** — contagem de arquivos no bucket antes e depois de: remoção manual, troca de capa, cancelamento de Ação, **descarte de candidata perdedora**, exclusão de conta | **FR-021 a FR-024, SC-005** |
| `test/integration/foto_capa_orfao_test.dart` — descartar candidata perdedora não deixa arquivo para trás | risco 2 do plano |
| `test/integration/foto_capa_exclusao_conta_test.dart` — capa de **Ação avulsa** de quem sai some; capa de **Grupo herdado** fica | FR-024, FR-025 |
| `test/integration/foto_capa_exclusao_conta_test.dart` — a exclusão de conta continua funcionando, com toda a anonimização e herança da feature 009 intactas | não-regressão |
| `test/integration/foto_capa_orfao_test.dart` — denúncias pendentes são encerradas quando a imagem some | FR-019 |

**O teste do descarte de candidata é o mais importante da feature.** É o único caminho de
exclusão que não passa por tela nenhuma — `fechar_rodada_se_devido` apaga as perdedoras com um
`delete` direto. Se a limpeza do arquivo morar no cliente, esse caminho nunca apaga nada e
ninguém percebe.

**Testes pré-existentes que devem passar sem edição** — se algum precisar mudar, a feature
vazou do escopo:

```
test/integration/apuracao_vencedora_test.dart
test/integration/apuracao_empate_test.dart
test/integration/apuracao_presenca_test.dart
test/integration/cancelar_acao_grupo_test.dart
test/integration/grupo_dono_participante_test.dart
```

## Parte 2 — Verificação manual

```bash
flutter run -d chrome     # web primeiro: é o alvo em produção
```

| # | Checagem | Requisito | Esperado |
|---|---|---|---|
| 1 | Como Dono de Grupo, acionar a opção de capa | FR-004 | O aviso aparece **antes** de qualquer seletor de arquivo |
| 2 | Ler o aviso | FR-006 | Português direto, motivo em uma frase, sem juridiquês |
| 3 | Enviar uma imagem | FR-007, SC-002 | Aparece no Grupo e no card da listagem, em menos de 1 minuto do toque inicial |
| 4 | Trocar a capa | FR-005 | O aviso aparece **de novo** |
| 5 | Grupo e Ação **sem** capa | FR-002, SC-006 | Tela e card íntegros, sem buraco no lugar da imagem |
| 6 | Como Visitante sem cadastro | FR-008 | Vê as capas normalmente |
| 7 | Como Usuário que não administra | FR-003 | Nenhuma opção de enviar, trocar ou remover |
| 8 | Enviar arquivo grande demais, de formato não suportado, e corrompido | FR-009, FR-010 | Recusa antes de publicar, explica, e **não perde o resto do formulário** |
| 9 | Imagem muito alta e muito larga | edge case | O card não deforma nem empurra o resto |
| 10 | Como Administrador do distrito, remover a capa de um Grupo alheio | FR-011, SC-003 | Some da tela e do card, em até 3 toques |
| 11 | Guardar o endereço da imagem antes, e tentar abri-lo depois de removida | **FR-012, SC-004** | Não obtém a imagem. **Se ainda obtiver, é a janela de cache de D-004 — anotar o tempo real até parar** |
| 12 | Como Visitante sem cadastro, denunciar uma capa | FR-015, SC-008 | Consegue registrar com motivo, sem cadastro |
| 13 | Denunciar a mesma imagem duas vezes | FR-018 | Um item só nas pendências, com contagem |
| 14 | Como Administrador, abrir as pendências | FR-016 | Vê a imagem, o Grupo/Ação e o motivo |
| 15 | Resolver como improcedente | FR-017 | Sai das pendências, imagem fica |
| 16 | Denunciar e depois remover a imagem por outro caminho | FR-019 | A denúncia some das pendências sozinha |
| 17 | Confirmar presença em Ação com capa | FR-026, SC-009 | Nada relacionado a presença mudou |
| 18 | Rodar em Android ou iOS | research D-002 | O seletor funciona igual ao de web |
| 19 | Ler a Política de Privacidade no app | **FR-027, FR-030, SC-007** | Descreve a imagem: finalidade, quem vê, prazo, como pedir remoção — e diz que o app não solicita nem verifica consentimento de responsável |
| 20 | Ler `MAPA-DE-DADOS.md` | **FR-028, SC-007** | Não diz mais que foto/imagem não é coletada |
| 21 | Ler `CONTEXT.md` | FR-029 | Tem as entradas **Foto de capa** e **Denúncia de imagem** |

## Parte 3 — Contagem de órfãos, à mão

O que o teste automatizado faz, feito uma vez com o olho, porque é a coisa que mais
silenciosamente dá errado:

1. Anotar quantos objetos existem no bucket `fotos-capa`.
2. Criar um Grupo com capa, uma Ação avulsa com capa, e uma Rodada com 3 candidatas, cada uma
   com capa. Anotar a nova contagem (deve ter subido 5).
3. Fechar a Rodada. Duas candidatas são descartadas.
4. Cancelar a Ação avulsa.
5. Remover a capa do Grupo.
6. Conferir: a contagem voltou ao valor do passo 1 **mais um** (a capa da candidata vencedora,
   que virou Ação confirmada e continua viva).

Qualquer valor acima disso é órfão, e órfão de imagem enviada por usuário é dado pessoal
retido sem finalidade.

## Definição de pronto

- [ ] Parte 0 respondida com **citação literal** da documentação do fornecedor, antes da migration
- [ ] Texto de FR-012 na Política de Privacidade escrito **depois** dessa resposta, refletindo o que o sistema garante
- [ ] `CONTEXT.md` com os dois termos novos, commitado **antes** do código (FR-029)
- [ ] Política de Privacidade e `MAPA-DE-DADOS.md` atualizados **na mesma entrega** que o upload — nunca depois (FR-027, FR-028)
- [ ] Parte 1 verde, com o número real de cada suíte
- [ ] Os 5 testes de integração pré-existentes passando sem edição
- [ ] Parte 2, itens 1 a 21
- [ ] Parte 3 conferida à mão, com os números anotados
- [ ] Item 11 com o tempo real medido, se a imagem ainda for obtida após a remoção
