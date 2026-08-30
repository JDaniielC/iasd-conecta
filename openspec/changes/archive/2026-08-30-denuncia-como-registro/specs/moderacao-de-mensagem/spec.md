## MODIFIED Requirements

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

## ADDED Requirements

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
