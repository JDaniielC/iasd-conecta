## Purpose

Registrar, em ordem cronológica, o que mudou num Grupo e numa Ação, para que
quem participa consiga ver que o horário foi adiado, que a Ação foi cancelada
ou que alguém entrou — sem depender de ter memorizado o valor anterior.

## ADDED Requirements

### Requirement: Mudança de horário ou de local de Ação vira registro

Quando a data e hora ou o local de uma Ação mudam, o sistema DEVE registrar o
evento com o instante da mudança e quem a fez. O registro NÃO DEVE guardar o
valor anterior nem o novo — ele diz **que mudou**, e a tela mostra o valor
vigente.

#### Scenario: Horário adiado
- **WHEN** o criador da Ação ou o dono do Grupo dela altera a data e hora
- **THEN** um registro de mudança de horário passa a existir para aquela Ação
- **AND** o registro aponta para o Perfil de quem alterou

#### Scenario: Local alterado
- **WHEN** o local da Ação é alterado
- **THEN** um registro de mudança de local passa a existir para aquela Ação

#### Scenario: Horário e local alterados na mesma operação
- **WHEN** data e hora e local mudam numa única atualização
- **THEN** existem dois registros, um de cada tipo, com o mesmo instante

#### Scenario: Atualização que não toca horário nem local
- **WHEN** só `detalhes`, `nome` ou `limite_vagas` mudam
- **THEN** nenhum registro é criado

### Requirement: Cancelamento de Ação vira registro

Quando uma Ação é cancelada, o sistema DEVE registrar o evento. Uma Ação já
cancelada que sofra outra atualização NÃO DEVE gerar um segundo registro de
cancelamento.

#### Scenario: Ação cancelada
- **WHEN** a Ação passa a ter data de cancelamento
- **THEN** um registro de cancelamento passa a existir para aquela Ação

#### Scenario: Ação cancelada sofre outra atualização
- **WHEN** uma Ação que já está cancelada é atualizada de novo
- **THEN** nenhum registro de cancelamento novo é criado

### Requirement: Criação de Ação dentro de um Grupo vira registro

Quando uma Ação é criada vinculada a um Grupo, o sistema DEVE registrar o
evento no Grupo. Ação avulsa (sem Grupo) NÃO DEVE gerar este registro — não há
Grupo onde ele apareceria.

#### Scenario: Ação criada num Grupo
- **WHEN** uma Ação é criada com Grupo
- **THEN** um registro de Ação criada passa a existir para aquele Grupo

#### Scenario: Ação avulsa criada
- **WHEN** uma Ação é criada sem Grupo
- **THEN** nenhum registro de criação é criado

### Requirement: Entrada e saída de Grupo viram registro

Quando alguém passa a participar de um Grupo ou deixa de participar, o sistema
DEVE registrar o evento.

#### Scenario: Alguém entra no Grupo
- **WHEN** uma participação em Grupo é criada
- **THEN** um registro de entrada passa a existir para aquele Grupo, apontando
  para o Perfil de quem entrou

#### Scenario: Alguém sai do Grupo
- **WHEN** uma participação em Grupo é removida
- **THEN** um registro de saída passa a existir para aquele Grupo

#### Scenario: Criador vira participante do próprio Grupo
- **WHEN** um Grupo é criado e seu dono vira participante automaticamente
- **THEN** um registro de entrada passa a existir, igual ao de qualquer outra
  entrada — a origem automática não é distinguida

### Requirement: Confirmação de presença vira registro

Quando alguém confirma presença numa Ação ou entra na fila de espera dela, o
sistema DEVE registrar o evento com o status decidido pelo banco, não com o
status pedido pelo cliente.

#### Scenario: Presença confirmada
- **WHEN** a confirmação é gravada com status confirmado
- **THEN** um registro de presença confirmada passa a existir para aquela Ação

#### Scenario: Vagas esgotadas
- **WHEN** a confirmação é gravada com status de fila porque o limite de vagas
  foi atingido
- **THEN** o registro criado é de entrada em fila, não de presença confirmada

#### Scenario: Vaga liberada promove quem estava na fila

- **WHEN** quem tinha vaga desiste e a próxima pessoa da fila é promovida
- **THEN** o registro passa a dizer que essa pessoa tem presença confirmada, e
  não fica parado em "entrou na fila" — um registro que afirma o contrário do
  estado atual é pior que registro nenhum

#### Scenario: Confirmação recusada
- **WHEN** a gravação da confirmação falha (Ação cancelada, encerrada, ou
  regra de composição não atendida)
- **THEN** nenhum registro é criado

### Requirement: Desconfirmação de presença vira registro

Quem confirmou presença pode desconfirmar. O sistema DEVE registrar essa saída;
sem ela, o registro afirma que a pessoa vai a uma Ação a que ela já não vai
mais. Sair da fila e desistir de uma presença confirmada DEVEM gerar o mesmo
tipo de registro — para quem lê, os dois são "não vem mais".

#### Scenario: Presença confirmada é desfeita
- **WHEN** alguém remove a própria confirmação numa Ação
- **THEN** um registro de desconfirmação passa a existir para aquela Ação
- **AND** o registro anterior de confirmação continua existindo, na posição
  cronológica em que aconteceu

#### Scenario: Saída da fila
- **WHEN** alguém que estava em fila remove a própria confirmação
- **THEN** o registro criado é do mesmo tipo que o de quem estava confirmado

### Requirement: Arquivamento de Grupo vira registro

Quando um Grupo é arquivado, o sistema DEVE registrar o evento.

#### Scenario: Grupo arquivado
- **WHEN** o Grupo passa a ter data de arquivamento
- **THEN** um registro de arquivamento passa a existir para aquele Grupo

### Requirement: O registro é escrito só pelo banco

O sistema NÃO DEVE aceitar escrita no registro vinda do cliente. Inserir,
alterar ou apagar um registro DEVE ser impossível para os papéis `anon` e
`authenticated`, inclusive para o dono do Grupo, o criador da Ação e o
Administrador do distrito.

#### Scenario: Cliente tenta inserir registro
- **WHEN** um usuário autenticado tenta inserir uma linha no registro pela API
- **THEN** a operação é recusada

#### Scenario: Dono do Grupo tenta apagar registro
- **WHEN** o dono do Grupo tenta apagar um registro do próprio Grupo
- **THEN** a operação é recusada

#### Scenario: Administrador do distrito tenta alterar registro
- **WHEN** um Administrador do distrito tenta alterar um registro
- **THEN** a operação é recusada

### Requirement: Falha ao registrar desfaz a operação que a originou

O sistema NÃO DEVE concluir a operação de origem quando o registro
correspondente não puder ser gravado. Um registro com buraco é pior que uma
operação recusada: a pessoa que vê o registro passa a confiar num histórico
incompleto sem nenhum sinal de que ele está incompleto.

#### Scenario: Gravação do registro falha
- **WHEN** a alteração de uma Ação acontece mas o registro correspondente não
  pode ser gravado
- **THEN** a alteração da Ação também não é aplicada
- **AND** quem tentou recebe erro, não sucesso silencioso

### Requirement: O registro tem a mesma visibilidade do fato que ele registra

O sistema DEVE expor cada registro exatamente para quem já pode ler a linha de
origem. Nenhum registro PODE revelar fato que quem o lê não conseguiria obter
lendo as tabelas de origem.

#### Scenario: Visitante lê o registro de um Grupo
- **WHEN** alguém sem login abre o detalhe de um Grupo
- **THEN** vê os mesmos registros que um usuário autenticado veria, porque
  Grupo, participação e confirmação de Ação pública já são legíveis sem login

#### Scenario: Registro de Ação que quem lê não pode ver
- **WHEN** uma Ação não é legível por quem está lendo o registro, e essa Ação
  gerou eventos de criação, de mudança de horário e de confirmação de presença
- **THEN** nenhum desses eventos aparece para quem lê, nem pela tela nem por
  chamada direta à API
- **AND** a ausência é linha faltando, não erro de permissão — a diferença
  entre "não aconteceu" e "não posso ver" seria contável

#### Scenario: Evento de Grupo continua público mesmo com Ação escondida
- **WHEN** um Grupo tem eventos de entrada e saída de participante e também
  eventos de uma Ação que quem lê não pode ver
- **THEN** os eventos de entrada e saída continuam aparecendo para qualquer
  pessoa, porque a participação em Grupo já é legível sem login

### Requirement: Perfil anonimizado aparece anonimizado no registro

O registro DEVE referenciar o Perfil, nunca uma cópia do nome. Depois que um
Perfil é anonimizado pela exclusão de conta, todo registro que aponta para ele
DEVE passar a exibir a identidade anonimizada, sem intervenção manual.

#### Scenario: Conta excluída depois de gerar registros
- **WHEN** alguém entra num Grupo, altera uma Ação e depois exclui a conta
- **THEN** os registros continuam existindo
- **AND** exibem a identidade anonimizada, não o nome que a pessoa tinha

### Requirement: Registro some junto com o Grupo ou a Ação

Quando um Grupo ou uma Ação deixa de existir, seus registros DEVEM deixar de
existir junto.

#### Scenario: Ação apagada
- **WHEN** uma Ação é removida
- **THEN** os registros dela deixam de existir

### Requirement: Não há registro retroativo

O sistema NÃO DEVE inventar registro para o que aconteceu antes de a
funcionalidade existir. Grupo e Ação criados antes DEVEM aparecer com registro
vazio, e a tela DEVE dizer isso em vez de parecer quebrada.

#### Scenario: Grupo antigo, sem nenhum evento novo
- **WHEN** alguém abre um Grupo que existe desde antes desta funcionalidade e
  no qual nada mudou depois
- **THEN** a seção de mudanças aparece vazia, com texto explicando que o
  registro começa agora
- **AND** a tela não some, não erra e não fica em carregamento perpétuo

### Requirement: A seção de mudanças aparece no detalhe do Grupo e da Ação

O sistema DEVE mostrar uma seção "Mudanças recentes" no detalhe do Grupo e no
detalhe da Ação, em ordem do mais recente para o mais antigo.

#### Scenario: Detalhe do Grupo
- **WHEN** alguém abre o detalhe de um Grupo
- **THEN** vê os eventos daquele Grupo e os eventos das Ações daquele Grupo

#### Scenario: Detalhe da Ação
- **WHEN** alguém abre o detalhe de uma Ação
- **THEN** vê só os eventos daquela Ação, esteja ela num Grupo ou avulsa

#### Scenario: Grupo com muitos eventos
- **WHEN** um Grupo acumulou mais eventos do que a seção mostra
- **THEN** a seção mostra os mais recentes e indica que há mais
- **AND** o tempo de carregamento do detalhe não cresce com o total acumulado
