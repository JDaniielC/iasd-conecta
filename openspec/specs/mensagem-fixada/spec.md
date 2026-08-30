# mensagem-fixada Specification

## Purpose
Permitir que a combinação que precisa sobreviver à conversa fique visível acima
dela e escape do prazo de expiração, sem que fixar vire uma forma de desligar a
retenção do chat.
## Requirements
### Requirement: Fixar é de quem manda no espaço

O sistema DEVE permitir fixar e desfixar mensagem a quem tem autoridade naquele
espaço: o dono do Grupo, o criador da Ação, o dono do Grupo da Ação quando
houver, e o Administrador do distrito. É o mesmo conjunto que pode remover
mensagem.

Participante comum NÃO DEVE fixar, nem a própria mensagem — fixar decide o que
todo mundo vê primeiro.

#### Scenario: Dono do Grupo fixa
- **WHEN** o dono do Grupo fixa uma mensagem do chat daquele Grupo
- **THEN** a operação é aceita, e a mensagem passa a aparecer acima da conversa

#### Scenario: Participante comum tenta fixar
- **WHEN** um participante sem autoridade tenta fixar uma mensagem
- **THEN** a operação é recusada

#### Scenario: Participante comum tenta fixar a própria mensagem
- **WHEN** um participante sem autoridade tenta fixar mensagem que ele mesmo
  escreveu
- **THEN** a operação é recusada

#### Scenario: Dono de outro Grupo
- **WHEN** o dono de outro Grupo tenta fixar mensagem neste chat
- **THEN** a operação é recusada

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

### Requirement: Mensagem fixada não expira

O sistema NÃO DEVE apagar mensagem fixada quando as demais mensagens da Ação
expiram.

#### Scenario: Ação de 31 dias com uma mensagem fixada
- **WHEN** as mensagens de uma Ação passam do prazo e uma delas está fixada
- **THEN** a fixada continua existindo
- **AND** todas as demais deixam de existir

#### Scenario: Mensagem desfixada depois do prazo
- **WHEN** uma mensagem fixada de uma Ação já passada é desfixada
- **THEN** ela passa a poder ser apagada pelo expurgo seguinte, sem precisar de
  novo prazo

### Requirement: Há teto de mensagens fixadas por chat

O sistema NÃO DEVE aceitar fixar acima do teto por chat. Sem teto, fixar vira
uma forma de desligar a retenção da conversa inteira.

#### Scenario: Teto atingido
- **WHEN** o chat já tem o número máximo de mensagens fixadas e alguém tenta
  fixar mais uma
- **THEN** a operação é recusada
- **AND** a tela diz que é preciso desfixar alguma antes

#### Scenario: Desfixar libera vaga
- **WHEN** uma mensagem fixada é desfixada
- **THEN** passa a ser possível fixar outra

#### Scenario: Duas fixações simultâneas com uma vaga
- **WHEN** duas pessoas com autoridade fixam mensagens ao mesmo tempo e há
  apenas uma vaga
- **THEN** exatamente uma é fixada

### Requirement: Fixar registra quem e quando

O sistema DEVE gravar o instante da fixação e o Perfil de quem fixou. Desfixar
DEVE limpar os dois.

#### Scenario: Mensagem fixada
- **WHEN** alguém com autoridade fixa uma mensagem
- **THEN** ficam gravados o instante e o Perfil de quem fixou

#### Scenario: Fixar mensagem já fixada
- **WHEN** alguém fixa uma mensagem que já está fixada
- **THEN** nada muda, e o registro de quem fixou primeiro é preservado

### Requirement: Lápide não fica fixada

O sistema DEVE desfixar sozinho a mensagem que perde o conteúdo — removida por
moderação ou esvaziada pela exclusão de conta do autor. Uma marca de mensagem
removida no topo do chat ocupa vaga do teto e não informa nada.

Desfixada, ela volta a contar prazo de expiração como qualquer outra.

#### Scenario: Mensagem fixada é removida por moderação
- **WHEN** quem tem autoridade remove uma mensagem que estava fixada
- **THEN** ela deixa de estar fixada
- **AND** a vaga volta a ficar disponível

#### Scenario: Autor de mensagem fixada exclui a conta
- **WHEN** o autor de uma mensagem fixada exclui a conta
- **THEN** o conteúdo dela deixa de existir, como o das demais
- **AND** ela deixa de estar fixada

### Requirement: Só quem lê o chat vê as fixadas

O sistema NÃO DEVE mostrar mensagem fixada a quem não pode ler aquele chat.
Fixar muda a posição da mensagem, não quem a alcança.

#### Scenario: Não participante consulta as fixadas
- **WHEN** alguém sem acesso de leitura ao chat consulta as mensagens fixadas
  dele
- **THEN** a consulta devolve zero linhas

#### Scenario: Menor de idade consulta as fixadas
- **WHEN** alguém com menos de 18 anos consulta as fixadas de um Grupo em que
  participa
- **THEN** a consulta devolve zero linhas

### Requirement: A faixa de fixadas não engole a conversa

O sistema DEVE mostrar as fixadas acima da conversa sem impedir o acesso a ela.
Numa tela estreita, o teto de fixadas ocuparia a tela inteira se cada uma
aparecesse por extenso.

#### Scenario: Chat com o teto de fixadas, em tela de celular
- **WHEN** alguém abre num celular um chat com o número máximo de fixadas, cada
  uma com o tamanho máximo de mensagem
- **THEN** a conversa continua visível e rolável sem interação extra
- **AND** a faixa se expande sob toque, em vez de vir expandida

#### Scenario: Chat sem nenhuma fixada
- **WHEN** o chat não tem mensagem fixada
- **THEN** não há faixa nenhuma ocupando espaço

