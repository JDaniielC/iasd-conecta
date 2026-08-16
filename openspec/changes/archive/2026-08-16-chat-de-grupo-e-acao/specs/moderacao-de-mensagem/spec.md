## Purpose

Definir quem tem autoridade para tirar uma mensagem do ar em cada espaço, como
qualquer participante pede isso, e o que continua visível depois — para que
remover não vire apagar o rastro.

## ADDED Requirements

### Requirement: Qualquer participante do chat denuncia uma mensagem

O sistema DEVE permitir que qualquer pessoa com acesso de leitura ao chat
denuncie uma mensagem dele, informando o motivo em texto. NÃO DEVE aceitar
denúncia assinada por outra pessoa, nem denúncia sem motivo.

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
