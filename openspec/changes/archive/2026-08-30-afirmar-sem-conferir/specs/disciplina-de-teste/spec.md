## ADDED Requirements

### Requirement: Toda tela é julgada na largura de celular

Todo teste de widget de uma tela DEVE renderizá-la na largura de um celular
estreito, e não na largura padrão do ambiente de teste.

Estouro de layout é a única classe de defeito neste projeto que o próprio
framework transforma em falha de teste — e só onde alguém escreveu o teste na
largura certa. Cobertura não pega: ela mede execução, não largura, e uma tela
pode estar 100% coberta e ilegível no aparelho de toda a comunidade.

Não é hipótese. A change `cobertura-e-tdd` julgou dez telas a 360 pela primeira
vez e achou **três estouros** — 229px, 72px e 39px — em telas que estavam no ar,
verdes em `flutter analyze` e sem uma única reclamação registrada.

#### Scenario: Tela nova ganha teste de widget

- **WHEN** um teste de widget é escrito para uma tela
- **THEN** ele a renderiza na largura de celular estreito
- **AND** um estouro horizontal faz o teste falhar

#### Scenario: A tela precisa de mais espaço do que cabe

- **WHEN** o conteúdo legitimamente não cabe na largura
- **THEN** ele quebra em linhas, rola na vertical, ou elide — nunca escapa na
  horizontal
- **AND** a rolagem lateral da página inteira não é a solução aceita

## MODIFIED Requirements

### Requirement: O denominador da cobertura é declarado

O que entra e o que sai da conta de cobertura DEVE estar escrito junto do
comando que mede, com o motivo de cada exclusão.

Exclusão sem motivo escrito é como o número sobe sem o código melhorar: basta
tirar do denominador o que não tem teste. O motivo escrito é o que permite
alguém, depois, discordar dele.

Neste projeto a exclusão que existe é a camada de repositório
(`lib/features/*/data/`): quem a exercita é a suíte de integração, que roda
contra Postgres e não entra nesta medição. Mantê-la no denominador faria o
número medir a ausência da integração, não a cobertura do código.

**Um número que exclui parte do código NÃO DEVE ser apresentado como a cobertura
do projeto.** O gate rápido mede o que roda sem banco, e é isso que ele reporta.
O projeto DEVE ter também um comando que mede **todas** as suítes sobre **todo**
o `lib/`, sem exclusão nenhuma — porque enquanto ninguém mede o número inteiro,
o tamanho do que ficou de fora é palpite.

Esse comando completo NÃO DEVE entrar no gate rápido. Ele depende de subir e
derrubar o banco local, e um alvo que faz isso no meio do dia pode derrubar uma
sessão de desenvolvimento em andamento na mesma máquina — custo já medido e
recusado antes, para o alvo de publicação.

#### Scenario: Um caminho é excluído da conta

- **WHEN** um caminho de `lib/` fica fora do denominador
- **THEN** o motivo está escrito junto da exclusão, e diz onde aquele código é
  provado, ou por que não precisa ser

#### Scenario: Código sem teste em nenhuma suíte

- **WHEN** um caminho é excluído do denominador e não é coberto por nenhuma
  outra suíte
- **THEN** a exclusão não é aceita — o número precisa refletir que aquele
  código não está provado

#### Scenario: A medição completa, sobre todo o lib/

- **WHEN** alguém pede a cobertura do projeto inteiro
- **THEN** existe um comando que roda todas as suítes, sem exclusão de caminho,
  e reporta o número sobre todo o `lib/`
- **AND** esse número é menor que o do gate rápido, e isso é esperado

#### Scenario: A medição completa não bloqueia o gate rápido

- **WHEN** o gate rápido roda na integração contínua
- **THEN** ele não sobe banco nenhum, e não depende da medição completa
