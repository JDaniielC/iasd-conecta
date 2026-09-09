## Purpose

Fazer o app comparar a versão do texto legal que a pessoa aceitou com a vigente,
avisá-la com destaque quando as duas divergem, deixá-la aceitar ou não, e recusar
o tratamento de finalidade que a versão aceita por ela não cobre.

## ADDED Requirements

### Requirement: Quem está com versão defasada é avisado com destaque

O sistema DEVE comparar a versão do texto legal aceita pela pessoa com a versão
vigente e, quando divergirem, DEVE mostrar com destaque o que mudou e o que isso
significa na prática.

Hoje nada faz essa comparação: a versão é carimbada na criação do Perfil e nunca
mais olhada. O aviso existente vive na tela de Novidades, cujo marcador de lido é
por instalação — quem reinstala não é alcançado, e não fica registro de quem foi
informado. O art. 8º, §6º pede aviso *com destaque de forma específica do teor
das alterações* quando muda a forma ou a duração do tratamento, e é isso que esta
capability passa a cumprir.

O aviso NÃO DEVE depender de a pessoa abrir uma tela específica, e NÃO DEVE ser
um alerta que persiga — ele aparece no caminho normal de uso, e some quando a
pessoa decide.

#### Scenario: Aceite defasado
- **WHEN** alguém com aceite de versão anterior à vigente usa o app
- **THEN** vê, com destaque, o que mudou entre a versão que aceitou e a vigente

#### Scenario: Aceite em dia
- **WHEN** o aceite da pessoa é da versão vigente
- **THEN** nenhum aviso de mudança é mostrado

#### Scenario: Aceite de versão desconhecida
- **WHEN** o aceite da pessoa não tem versão registrada
- **THEN** o aviso é mostrado, e diz que a versão do aceite anterior não é conhecida
- **AND** NÃO afirma de qual versão ela era

#### Scenario: Sem Perfil
- **WHEN** quem ainda não tem Perfil usa o app
- **THEN** nenhum aviso de mudança é mostrado

#### Scenario: Reinstalação
- **WHEN** a pessoa reinstala o app e o aceite dela continua defasado
- **THEN** o aviso é mostrado de novo

### Requirement: O reaceite grava a versão vigente, carimbada pelo banco

O sistema DEVE registrar o novo aceite com a data e a versão vigente no momento,
e o valor da versão DEVE vir do banco, nunca do cliente. Um registro de base
legal que valesse o que o cliente afirma não demonstraria nada.

#### Scenario: A pessoa aceita a versão nova
- **WHEN** a pessoa aceita a versão vigente
- **THEN** o aceite passa a registrar a versão vigente e o instante do aceite

#### Scenario: Cliente tenta escolher a versão
- **WHEN** o cliente manda um número de versão diferente da vigente
- **THEN** o valor mandado é descartado e a versão vigente é a registrada

#### Scenario: O reaceite falha
- **WHEN** o registro do reaceite falha
- **THEN** o aceite anterior permanece intacto
- **AND** a tela não afirma que o aceite foi atualizado

### Requirement: Recusar a versão nova não tira o que a antiga já cobria

O sistema NÃO DEVE bloquear o uso do app de quem não aceita a versão nova. A
pessoa continua com tudo o que a versão que ela aceitou já cobria; o que ela não
recebe é o tratamento de finalidade nova.

Consentimento obtido sob ameaça de perder o que já se tinha não é livre. E o
projeto já tem o caminho de saída completo — revogar ou excluir a conta — para
quem não quiser continuar de jeito nenhum.

#### Scenario: A pessoa fecha o aviso sem aceitar
- **WHEN** a pessoa fecha o aviso sem aceitar a versão nova
- **THEN** continua usando o app normalmente
- **AND** o aceite dela continua registrando a versão anterior

#### Scenario: Recusa e finalidade nova
- **WHEN** a pessoa não aceitou a versão que descreve uma finalidade nova
- **THEN** nenhum tratamento dessa finalidade acontece sobre os dados dela

### Requirement: Finalidade que a versão aceita não cobre é recusada, e a recusa não vaza

O sistema DEVE recusar qualquer tratamento cuja finalidade só apareça em versão
posterior à aceita pela pessoa, e a recusa NÃO DEVE revelar a terceiro qual
versão essa pessoa aceitou nem qualquer outro dado do Perfil dela.

A recusa é ausência, não erro: quem tenta a operação vê que ela não aconteceu, e
o caminho oferecido é o titular atualizar o próprio aceite — nunca um terceiro
atualizar por ele.

#### Scenario: Terceiro tenta uma operação de finalidade nova
- **WHEN** alguém tenta uma operação de finalidade nova sobre uma pessoa com aceite defasado
- **THEN** nenhuma linha é afetada
- **AND** a tela diz que a operação não aconteceu, sem dizer por qual versão

#### Scenario: A própria pessoa consulta a versão dela
- **WHEN** a pessoa abre o próprio aceite
- **THEN** vê a versão que aceitou, ou que ela é desconhecida, e a data

#### Scenario: Consulta da versão alheia
- **WHEN** alguém tenta ler a versão aceita por outra pessoa
- **THEN** a consulta devolve zero linhas
