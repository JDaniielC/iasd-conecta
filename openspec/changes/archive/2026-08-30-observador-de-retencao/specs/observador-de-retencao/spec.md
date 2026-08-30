## Purpose

Permitir que alguém responda "a promessa de prazo foi cumprida ontem?" sem ir
ao banco à mão, e que a ausência silenciosa de um executor deixe de ser
indistinguível de "não havia nada para apagar".

## ADDED Requirements

### Requirement: Toda faxina de retenção deixa rastro

O sistema DEVE registrar cada execução de uma faxina de retenção, com o
instante, quantas linhas apagou, qual faxina foi e quem a disparou — o
agendamento do banco ou o app.

Registrar **toda** execução, e não só as que apagaram alguma coisa: "rodou e
não havia nada a apagar" e "não rodou" são fatos diferentes, e é justamente a
diferença entre os dois que hoje não se consegue ver.

#### Scenario: Faxina apaga linhas
- **WHEN** uma faxina de retenção roda e apaga linhas
- **THEN** fica registrado o instante, a quantidade e qual faxina foi

#### Scenario: Faxina roda sem nada a apagar
- **WHEN** uma faxina de retenção roda e não encontra nada vencido
- **THEN** fica registrada uma execução com quantidade zero

#### Scenario: Quem disparou fica registrado
- **WHEN** a mesma faxina é disparada pelo agendamento do banco e pelo app
- **THEN** cada execução registra qual dos dois a disparou

### Requirement: A faxina não deixa de acontecer por causa do rastro

O sistema NÃO DEVE deixar de apagar o que venceu porque o registro da execução
falhou. A promessa é o descarte; o rastro serve à promessa e não o contrário.

Do mesmo modo, uma faxina que falha NÃO DEVE estragar a leitura de quem estava
usando o app — a chamada que o app faz continua sendo faxina de fundo.

#### Scenario: O registro da execução falha
- **WHEN** a faxina apaga o que venceu e o registro da execução falha
- **THEN** as linhas vencidas continuam apagadas

#### Scenario: A faxina falha durante a leitura de uma conversa
- **WHEN** a faxina disparada pelo app falha
- **THEN** a conversa aparece do mesmo jeito, sem erro na tela

### Requirement: Quem administra o distrito vê o rastro

O sistema DEVE mostrar as execuções ao Administrador do distrito, e NÃO DEVE
mostrá-las a mais ninguém. O rastro diz quanto o app apagou e quando — é
informação de operação, não de conversa.

#### Scenario: Administrador consulta
- **WHEN** o Administrador do distrito abre a lista de execuções
- **THEN** vê as mais recentes de cada faxina, com instante e quantidade

#### Scenario: Participante comum consulta
- **WHEN** alguém que não é Administrador do distrito consulta as execuções
- **THEN** a consulta devolve zero linhas

#### Scenario: Sem sessão
- **WHEN** uma requisição sem sessão consulta as execuções
- **THEN** a consulta é recusada

### Requirement: A tela diz quando a última execução ficou velha

O sistema DEVE dizer, na tela do Administrador, quando uma faxina não roda há
mais tempo do que deveria. Uma lista de execuções que ninguém sabe interpretar
não responde à pergunta que motivou o registro.

O que **não** existe é alerta que persiga alguém: o app não manda aviso nem
e-mail sobre isso. Quem administra vê quando abre.

#### Scenario: Faxina em dia
- **WHEN** a faxina rodou dentro do intervalo esperado
- **THEN** a tela mostra a última execução sem sinal de alerta

#### Scenario: Faxina atrasada
- **WHEN** a faxina não roda há mais tempo do que o intervalo esperado
- **THEN** a tela diz que ela está atrasada, e desde quando

#### Scenario: Faxina que nunca rodou
- **WHEN** não há nenhuma execução registrada para aquela faxina
- **THEN** a tela diz isso com todas as letras, e não mostra a lista vazia como
  se estivesse tudo bem

### Requirement: O rastro tem prazo

O sistema DEVE apagar registros de execução passado um prazo. Um registro de
faxina que nunca é apagado é a próxima tabela que só cresce, e esta capability
existe justamente por causa de uma dessas.

#### Scenario: Execução antiga
- **WHEN** um registro de execução passa do prazo
- **THEN** ele deixa de existir

#### Scenario: A última execução de cada faxina permanece
- **WHEN** todas as execuções de uma faxina passaram do prazo
- **THEN** a mais recente de cada faxina continua existindo — sem ela, uma
  faxina parada há muito tempo ficaria indistinguível de uma que nunca rodou

### Requirement: O registro de mudanças tem prazo

O sistema DEVE apagar registros de `mudanças` em Grupo e Ação passado um prazo,
e DEVE registrar essa faxina como as demais.

O registro guarda quem fez a mudança, e é dado pessoal. A Política de
Privacidade declara prazos para o que o app guarda; hoje esta é a única tabela
do app que só cresce.

#### Scenario: Mudança antiga
- **WHEN** um registro de mudança passa do prazo
- **THEN** ele deixa de existir
- **AND** a execução dessa faxina fica registrada como as demais

#### Scenario: Mudança recente
- **WHEN** um registro de mudança está dentro do prazo
- **THEN** ele continua existindo e continua aparecendo na tela de quem o lê
