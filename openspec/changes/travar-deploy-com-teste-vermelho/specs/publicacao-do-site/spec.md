## Purpose

Quando o app compilado pode ir ao ar. A garantia não é sobre o que o build faz
— é sobre o que precisa estar verdadeiro **antes** de alguém alcançar o site.

## ADDED Requirements

### Requirement: Teste vermelho não publica

Um commit cuja suíte de testes falha NÃO DEVE resultar em site publicado, nem em
artefato apresentado como publicável.

#### Scenario: Suíte vermelha interrompe o deploy

- **WHEN** um push em `main` tem `flutter analyze`, os testes de unidade/widget
  ou os de integração falhando
- **THEN** o deploy não constrói e não publica, e a execução aparece como falha

#### Scenario: Suíte verde publica normalmente

- **WHEN** um push em `main` passa em todos os gates
- **THEN** o deploy segue como hoje

#### Scenario: A publicação manual não é rota de fuga

- **WHEN** alguém publica à mão com `make deploy-web`
- **THEN** o comando recusa se a árvore de trabalho não estiver provada verde,
  ou exige uma confirmação explícita de que se está publicando sem prova
