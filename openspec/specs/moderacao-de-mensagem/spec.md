# moderacao-de-mensagem Specification

## Purpose

Definir quem tem autoridade para tirar uma mensagem do ar em cada espaço, como
qualquer participante pede isso, e o que continua visível depois — para que
remover não vire apagar o rastro.

## Requirements

### Requirement: Qualquer participante do chat denuncia uma mensagem

O sistema DEVE permitir que qualquer pessoa com acesso de leitura ao chat
denuncie uma mensagem dele, informando o motivo em texto. NÃO DEVE aceitar
denúncia assinada por outra pessoa, nem denúncia sem motivo.

O sistema NÃO DEVE aceitar uma segunda denúncia **pendente** da mesma pessoa
sobre a mesma mensagem. Repetir a denúncia não acrescenta informação e enche a
fila de quem modera, que lê cada motivo à mão.

Isto NÃO é limite de ritmo, e a distinção é decisão registrada: **não há limite
de ritmo em denúncia**, porque um limite por tempo atrapalha quem está
denunciando abuso em série — justamente o caso em que a denúncia importa. A
pessoa continua podendo denunciar quantas mensagens diferentes quiser, na
velocidade que precisar.

#### Scenario: Participante denuncia
- **WHEN** alguém que lê o chat denuncia uma mensagem com motivo preenchido
- **THEN** a denúncia é registrada como pendente, apontando para a mensagem e
  para quem denunciou

#### Scenario: Denúncia assinada por outro
- **WHEN** alguém registra denúncia declarando outro Perfil como denunciante
- **THEN** a operação é recusada

#### Scenario: Denúncia sem motivo
- **WHEN** alguém denuncia com motivo vazio ou só com espaços
- **THEN** a operação é recusada

#### Scenario: Quem não lê o chat denuncia
- **WHEN** alguém sem acesso de leitura tenta denunciar uma mensagem daquele
  chat
- **THEN** a operação é recusada

#### Scenario: A mesma pessoa denuncia a mesma mensagem de novo
- **WHEN** alguém que já tem denúncia pendente sobre uma mensagem denuncia a
  mesma mensagem outra vez
- **THEN** a operação é recusada
- **AND** a tela diz que aquela denúncia já está aguardando desfecho

#### Scenario: Denunciar de novo depois do desfecho
- **WHEN** a denúncia anterior daquela pessoa sobre aquela mensagem já teve
  desfecho e ela denuncia de novo
- **THEN** a operação é aceita — fato novo depois de um julgamento é outro caso

#### Scenario: Muitas mensagens diferentes, em sequência
- **WHEN** alguém denuncia várias mensagens diferentes uma atrás da outra
- **THEN** todas são aceitas — não há limite de ritmo em denúncia

### Requirement: A denúncia registrada não se reescreve

O sistema NÃO DEVE aceitar alteração do motivo, de quem denunciou, da mensagem
denunciada ou do instante em que a denúncia foi feita. O que se altera numa
denúncia é o **desfecho**, e só ele.

O motivo é o que fica como história do caso — é ele que sobrevive ao expurgo da
mensagem, e é sobre ele que os Termos de Uso fazem a promessa. Uma história que
quem julga pode reescrever não é registro.

Trocar quem denunciou é pior do que revelar quem denunciou: é **atribuir** a
denúncia a outra pessoa.

#### Scenario: Quem modera tenta reescrever o motivo
- **WHEN** quem tem autoridade sobre o espaço altera o motivo de uma denúncia
- **THEN** a operação é recusada

#### Scenario: Quem modera tenta trocar o denunciante
- **WHEN** quem tem autoridade sobre o espaço altera quem denunciou
- **THEN** a operação é recusada

#### Scenario: Quem denunciou tenta reescrever o próprio motivo
- **WHEN** a pessoa que denunciou altera o motivo depois de registrado
- **THEN** a operação é recusada — o registro é do que ela disse na hora

#### Scenario: A denúncia é apontada para outra mensagem
- **WHEN** alguém altera qual mensagem a denúncia aponta
- **THEN** a operação é recusada

#### Scenario: O desfecho continua alterável por quem tem autoridade
- **WHEN** quem tem autoridade sobre o espaço registra o desfecho
- **THEN** a operação é aceita

### Requirement: O motivo tem prazo e sai com a conta de quem escreveu

O motivo é texto livre escrito por uma pessoa, e o sistema DEVE tratá-lo como
trata o resto do texto livre dela.

O sistema DEVE apagar o motivo passado um prazo contado do **desfecho** da
denúncia — não da criação. Denúncia pendente não expira: pendente que some sem
desfecho é o pior resultado para quem denunciou, e é a razão de a denúncia
sobreviver ao expurgo da mensagem.

O sistema DEVE apagar o motivo quando quem denunciou exclui a conta, no mesmo
ato em que apaga o texto das mensagens dela.

**Custo declarado:** apagar o motivo de uma denúncia julgada apaga o registro
de por que uma mensagem foi removida. O desfecho e o instante dele permanecem;
o texto que os explicava, não. É a mesma escolha que a remoção de mensagem já
faz — o texto do titular não é conservado para servir de prova contra ele.

#### Scenario: Denúncia julgada passa do prazo
- **WHEN** uma denúncia com desfecho registrado passa do prazo
- **THEN** o motivo dela deixa de existir
- **AND** o desfecho e o instante da resolução continuam existindo

#### Scenario: Denúncia pendente não expira
- **WHEN** uma denúncia sem desfecho passa do mesmo prazo
- **THEN** o motivo continua existindo

#### Scenario: Quem denunciou exclui a conta
- **WHEN** a pessoa que denunciou exclui a conta
- **THEN** o motivo escrito por ela deixa de existir
- **AND** a denúncia continua existindo, com o desfecho que tiver

#### Scenario: A exclusão de conta não alcança o motivo de terceiro
- **WHEN** alguém exclui a conta e outra pessoa havia denunciado uma mensagem
  dela
- **THEN** aquele motivo continua existindo — é texto de outra pessoa

### Requirement: A autoridade de remover segue quem manda no espaço

O sistema DEVE permitir remover mensagem a:

- **no chat de Grupo**: o dono do Grupo e o Administrador do distrito;
- **no chat de Ação**: o criador da Ação, o dono do Grupo dela quando houver, e
  o Administrador do distrito;
- **em qualquer chat**: o autor da própria mensagem.

É o mesmo par de autoridade que a alteração de Ação já usa
(`acoes_update_criador_ou_dono_grupo`). Nenhum outro papel PODE remover.

#### Scenario: Dono do Grupo remove
- **WHEN** o dono do Grupo remove uma mensagem do chat daquele Grupo
- **THEN** a operação é aceita

#### Scenario: Participante comum tenta remover a de outro
- **WHEN** um participante sem autoridade tenta remover mensagem de outra
  pessoa
- **THEN** a operação é recusada

#### Scenario: Autor remove a própria mensagem
- **WHEN** o autor remove uma mensagem que escreveu
- **THEN** a operação é aceita, em qualquer chat

#### Scenario: Dono de outro Grupo
- **WHEN** o dono de um Grupo tenta remover mensagem do chat de um Grupo que
  não é dele
- **THEN** a operação é recusada

#### Scenario: Criador da Ação avulsa
- **WHEN** o criador de uma Ação sem Grupo remove mensagem do chat dela
- **THEN** a operação é aceita

#### Scenario: Administrador do distrito
- **WHEN** um Administrador do distrito remove mensagem de qualquer chat
- **THEN** a operação é aceita

### Requirement: Remover apaga o conteúdo e conserta a denúncia, não a conversa

Remover DEVE apagar o texto da mensagem e conservar a linha, com o registro de
quando e por quem foi removida. A conversa DEVE continuar mostrando que houve
uma mensagem ali — sem isso, as respostas seguintes ficam sem referência e
ninguém consegue auditar o que foi retirado.

O sistema NÃO DEVE devolver o texto removido a ninguém, incluindo o
Administrador do distrito. Guardar o texto para consulta posterior recriaria,
dentro do banco, exatamente o dado que a remoção existe para eliminar; o motivo
escrito pelo denunciante é o que fica como registro do caso.

#### Scenario: Mensagem removida na conversa
- **WHEN** uma mensagem é removida
- **THEN** quem lê o chat vê no lugar dela a marca de mensagem removida
- **AND** as mensagens seguintes continuam na mesma ordem

#### Scenario: Administrador consulta o texto removido
- **WHEN** um Administrador do distrito consulta a mensagem removida pela API
- **THEN** o conteúdo não vem — nem para ele

#### Scenario: Remoção é registrada
- **WHEN** uma mensagem é removida
- **THEN** ficam gravados o instante e o Perfil de quem removeu

#### Scenario: Remover de novo
- **WHEN** alguém remove uma mensagem já removida
- **THEN** nada muda, e o registro original de quem removeu é preservado

### Requirement: A denúncia é visível só para quem pode resolvê-la

O sistema DEVE mostrar a denúncia apenas a quem tem autoridade de remoção
naquele espaço e ao Administrador do distrito. NÃO DEVE mostrá-la aos demais
participantes, nem revelar a eles quem denunciou.

#### Scenario: Dono do Grupo vê as denúncias do Grupo dele
- **WHEN** o dono do Grupo consulta as denúncias
- **THEN** vê as do chat do Grupo dele e as dos chats das Ações daquele Grupo

#### Scenario: Participante comum consulta denúncias
- **WHEN** um participante sem autoridade consulta as denúncias do chat
- **THEN** a consulta devolve zero linhas, inclusive para a denúncia que ele
  mesmo registrou

#### Scenario: Dono de outro Grupo
- **WHEN** o dono de outro Grupo consulta essas denúncias
- **THEN** a consulta devolve zero linhas

### Requirement: A denúncia tem desfecho registrado

Toda denúncia DEVE terminar em um de dois estados — mensagem removida ou
improcedente — com o instante da resolução. Estado inicial é pendente. Só quem
tem **autoridade sobre o espaço** PODE resolvê-la: o dono do Grupo, o criador
da Ação, o dono do Grupo dela, e o Administrador do distrito.

**O autor da mensagem denunciada NÃO resolve a denúncia contra si, ainda que
possa remover a própria mensagem.** As duas coisas são autoridades diferentes e
esta requirement precisou dizê-lo: "quem pode remover" inclui o autor, e lido
junto com este parágrafo sem a ressalva, o denunciado arquivava como
improcedente o caso sobre o próprio texto. Foi defeito real, medido e corrigido
durante esta change — o banco separa `pode_moderar_espaco` (sem o autor), que
governa a denúncia, de `pode_moderar_mensagem` (com o autor), que governa a
remoção. Quem simplificar as duas numa só reabre o defeito.

Remover a própria mensagem continua valendo e não depende de idade: apagar o
que você mesmo escreveu é minimização de dado. **Ler e resolver denúncia, sim**
— o corte de 18 anos alcança `denuncias_mensagem` como alcança as mensagens,
porque o motivo escrito por quem denunciou é texto livre da mesma natureza.

#### Scenario: Denúncia acolhida
- **WHEN** quem tem autoridade remove a mensagem denunciada
- **THEN** a denúncia passa a mensagem removida, com instante de resolução

#### Scenario: Denúncia recusada
- **WHEN** quem tem autoridade marca a denúncia como improcedente
- **THEN** a mensagem continua visível, e a denúncia fica com instante de
  resolução

#### Scenario: Participante comum tenta resolver
- **WHEN** um participante sem autoridade tenta alterar o estado de uma
  denúncia
- **THEN** a operação é recusada

#### Scenario: O autor da mensagem denunciada tenta resolver
- **WHEN** o autor da mensagem denunciada tenta ler ou alterar o estado da
  denúncia contra ela
- **THEN** a operação é recusada — remover a própria mensagem é dele, julgar a
  denúncia não

#### Scenario: Administrador do distrito menor de idade
- **WHEN** um Administrador do distrito com menos de 18 anos consulta ou tenta
  resolver uma denúncia
- **THEN** a operação é recusada, como para qualquer mensagem — o motivo
  escrito por quem denunciou é texto livre da mesma natureza

### Requirement: A denúncia sobrevive à expiração da conversa

Quando as mensagens de uma Ação expiram, a denúncia sobre elas NÃO DEVE
desaparecer sem desfecho. Denúncia pendente que perde a mensagem DEVE ficar
registrada como tal, e não sumir junto.

#### Scenario: Ação expira com denúncia pendente
- **WHEN** as mensagens de uma Ação expiram e havia denúncia pendente sobre uma
  delas
- **THEN** a denúncia continua existindo, marcada como sem mensagem para
  resolver
- **AND** o motivo escrito pelo denunciante é preservado
