## MODIFIED Requirements

### Requirement: O autor sempre desfixa a própria mensagem

O sistema DEVE permitir que o autor desfixe mensagem que ele escreveu, mesmo
sem ter autoridade no espaço **e mesmo que ele já não alcance aquela conversa**.

Fixar tira a mensagem do prazo de expiração. Sem este caminho, o prazo do que
uma pessoa escreveu passaria a depender inteiramente de outra — e ela não teria
como reavê-lo.

O sistema DEVE oferecer esse caminho **fora da conversa**. Quem sai de um
Grupo, desiste de uma Ação ou deixa de passar no corte de idade perde o acesso
à conversa, e é exatamente aí que o texto dele fica preso — o botão que só
existe dentro do chat não serve a quem não entra mais nele.

O sistema NÃO DEVE, por esse caminho, mostrar à pessoa nada além das mensagens
que ela mesma escreveu e que estão fixadas. Alcançar o próprio texto para
tirá-lo do topo não é passar a ler a conversa.

#### Scenario: Autor desfixa
- **WHEN** o autor de uma mensagem fixada por outra pessoa a desfixa
- **THEN** a operação é aceita
- **AND** a mensagem volta a contar prazo de expiração normalmente

#### Scenario: Autor tenta fixar de volta
- **WHEN** o autor, sem autoridade no espaço, tenta fixar de novo a própria
  mensagem
- **THEN** a operação é recusada — desfixar é direito dele, fixar não

#### Scenario: Autor que saiu do Grupo desfixa
- **WHEN** o autor de uma mensagem fixada sai do Grupo e depois a desfixa
- **THEN** a operação é aceita
- **AND** a mensagem volta a contar prazo de expiração normalmente

#### Scenario: Autor que desistiu da Ação desfixa
- **WHEN** o autor de uma mensagem fixada desiste da Ação e depois a desfixa
- **THEN** a operação é aceita

#### Scenario: Autor que deixou de passar no corte de idade desfixa
- **WHEN** o autor de uma mensagem fixada passa a ter menos de 18 anos
  registrados e a desfixa
- **THEN** a operação é aceita — o corte de idade decide o que ela lê, não o
  que ela retira do que escreveu

#### Scenario: A lista de fora da conversa mostra só o que a pessoa escreveu
- **WHEN** alguém abre a lista das próprias mensagens fixadas
- **THEN** aparecem apenas mensagens de autoria dela que estão fixadas
- **AND** nenhuma mensagem de outra pessoa aparece, mesmo das conversas em que
  ela participa

#### Scenario: Ninguém desfixa mensagem alheia por esse caminho
- **WHEN** alguém tenta desfixar, pelo caminho de fora da conversa, uma
  mensagem que outra pessoa escreveu
- **THEN** a operação é recusada

#### Scenario: Fixar continua fora desse caminho
- **WHEN** alguém tenta fixar uma mensagem pelo caminho de fora da conversa
- **THEN** não existe operação de fixar ali — fixar continua sendo da
  autoridade do espaço, de dentro da conversa
