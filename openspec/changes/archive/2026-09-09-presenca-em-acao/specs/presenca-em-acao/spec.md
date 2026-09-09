## Purpose

Registrar quem de fato esteve numa Ação, separando comparecimento de intenção,
sem que o esquecimento de quem organiza vire acusação de ausência contra quem
participa, e mantendo com a pessoa medida o poder de contestar o que outra
pessoa afirmou sobre ela.

## ADDED Requirements

### Requirement: Quem criou a Ação afirma quem esteve nela

O sistema DEVE permitir que quem criou a Ação marque comparecimento de quem
tem confirmação nela, e NÃO DEVE permitir isso a mais ninguém.

A marca é uma afirmação de uma pessoa sobre outra — a primeira do app. Por isso
ela tem autor identificado e instante, e não é anônima.

O comparecimento só existe sobre uma linha de confirmação que já existe, em
qualquer status. **Quem apareceu sem nunca ter confirmado não é registrado**, e
isso é um limite declarado, não um esquecimento: criar confirmação em nome de
terceiro seria afirmar sobre ele um ato que ele não praticou. A consequência é
que essa pessoa fica fora do numerador e também do denominador — invisível, e
nunca ausente.

#### Scenario: Criador marca quem esteve
- **WHEN** quem criou a Ação marca o comparecimento de alguém com confirmação
- **THEN** a marca fica registrada com o instante e com a identidade de quem marcou

#### Scenario: Participante tenta marcar
- **WHEN** alguém que não criou a Ação tenta marcar comparecimento
- **THEN** nenhuma linha é afetada e a tela não afirma que a marca foi feita

#### Scenario: Dono do Grupo tenta marcar
- **WHEN** o dono do Grupo da Ação, que não a criou, tenta marcar comparecimento
- **THEN** nenhuma linha é afetada

#### Scenario: Marca sobre quem não confirmou
- **WHEN** quem criou a Ação tenta marcar comparecimento de alguém sem confirmação nela
- **THEN** nenhuma linha é afetada

#### Scenario: Marca antes de a Ação acontecer
- **WHEN** quem criou a Ação tenta marcar comparecimento antes do horário dela
- **THEN** nenhuma linha é afetada

#### Scenario: Marca em Ação cancelada
- **WHEN** a Ação foi cancelada e quem a criou tenta marcar comparecimento
- **THEN** nenhuma linha é afetada

### Requirement: Não marcado significa não registrado, nunca ausente

O sistema NÃO DEVE tratar a ausência de marca como ausência da pessoa. Enquanto
a lista da Ação não for fechada, o que não foi marcado é **não registrado**, e a
Ação inteira fica fora de qualquer contagem de envolvimento — fora do numerador
e fora do denominador.

Esta é a regra que a change existe para garantir. Sem ela, toda Ação em que quem
organiza esqueceu de marcar produziria um Grupo inteiro de ausentes; e como o
esquecimento é mais provável em Grupo desorganizado, o erro cairia justamente
sobre os Grupos que a liderança mais quer entender. É a mesma doutrina que o
projeto já aplica à versão do consentimento, onde a ausência de valor significa
desconhecida e nunca um palpite.

#### Scenario: Ação passou e ninguém marcou nada
- **WHEN** a Ação já aconteceu, ninguém marcou comparecimento e a lista não foi fechada
- **THEN** nenhuma pessoa daquela Ação conta como ausente
- **AND** a Ação não entra em nenhuma contagem de envolvimento

#### Scenario: Ação com marca parcial e sem fechamento
- **WHEN** algumas pessoas foram marcadas e a lista não foi fechada
- **THEN** quem não foi marcado não conta como ausente
- **AND** a Ação continua fora de qualquer contagem de envolvimento

### Requirement: A ausência só nasce de um fechamento explícito

O sistema DEVE exigir que quem criou a Ação feche a lista de comparecimento para
que o que não foi marcado passe a significar ausência. O fechamento é um ato de
uma pessoa, com instante registrado, e NÃO DEVE acontecer por decurso de prazo:
nenhuma máquina converte desconhecido em ausente.

Depois de fechada, a lista NÃO DEVE aceitar marca nova nem remoção de marca.
Reabrir não existe — o caminho para corrigir uma marca depois do fechamento é a
contestação.

#### Scenario: Fechamento converte o que sobrou
- **WHEN** quem criou a Ação fecha a lista
- **THEN** quem foi marcado conta como presente e quem tem confirmação sem marca conta como ausente
- **AND** a Ação passa a entrar nas contagens de envolvimento

#### Scenario: Fechamento antes de a Ação acontecer
- **WHEN** quem criou a Ação tenta fechar a lista antes do horário dela
- **THEN** nenhuma linha é afetada

#### Scenario: Marca depois do fechamento
- **WHEN** quem criou a Ação tenta marcar ou desmarcar comparecimento numa lista fechada
- **THEN** nenhuma linha é afetada

#### Scenario: Fechamento por quem não criou
- **WHEN** alguém que não criou a Ação tenta fechar a lista
- **THEN** nenhuma linha é afetada

#### Scenario: Ação antiga nunca fechada
- **WHEN** a Ação aconteceu há muito tempo e nunca foi fechada
- **THEN** ela permanece fora das contagens de envolvimento, indefinidamente

### Requirement: A pessoa vê e contesta o que foi afirmado sobre ela

O sistema DEVE mostrar a cada pessoa toda marca de comparecimento feita sobre
ela, e DEVE permitir que ela conteste qualquer uma. Quem criou a Ação decide a
contestação — confirmando a marca ou desfazendo-a.

Nem a contestação nem a decisão são apagadas. O registro descreve o que
aconteceu, inclusive quando termina em discordância.

#### Scenario: A pessoa vê a marca sobre si
- **WHEN** alguém abre o próprio histórico de comparecimento
- **THEN** vê cada Ação em que foi marcado, com o instante e quem marcou

#### Scenario: A pessoa contesta
- **WHEN** alguém contesta uma marca feita sobre si
- **THEN** a contestação fica registrada com o instante
- **AND** quem criou a Ação passa a ver que há contestação a decidir

#### Scenario: Contestar marca de outra pessoa
- **WHEN** alguém tenta contestar uma marca feita sobre outra pessoa
- **THEN** nenhuma linha é afetada

#### Scenario: O criador desfaz a marca
- **WHEN** quem criou a Ação aceita a contestação
- **THEN** a marca deixa de afirmar comparecimento
- **AND** a contestação e a decisão continuam registradas

#### Scenario: O criador mantém a marca
- **WHEN** quem criou a Ação nega a contestação
- **THEN** a marca continua como estava
- **AND** a contestação e a decisão continuam registradas

#### Scenario: Decisão por quem não criou a Ação
- **WHEN** alguém que não criou a Ação tenta decidir uma contestação
- **THEN** nenhuma linha é afetada

#### Scenario: Contestação some
- **WHEN** alguém tenta apagar ou reescrever uma contestação já registrada
- **THEN** nenhuma linha é afetada

### Requirement: Linha contestada nunca conta, decida o criador o que decidir

O sistema NÃO DEVE incluir em nenhuma contagem de envolvimento uma linha de
comparecimento que tenha sido contestada — nem como presença, nem como ausência,
nem antes nem depois da decisão, e independentemente do resultado dela.

O titular precisa ter efeito real sem precisar vencer uma disputa que o software
não tem como arbitrar. O preço é um ponto de dado; o preço da alternativa é uma
métrica que gera visita pastoral em cima de um fato que a pessoa nega.

#### Scenario: Contestação pendente
- **WHEN** existe contestação ainda não decidida sobre uma marca
- **THEN** aquela linha fica fora do numerador e do denominador

#### Scenario: Contestação negada
- **WHEN** quem criou a Ação nega a contestação
- **THEN** aquela linha continua fora do numerador e do denominador, permanentemente

#### Scenario: Contestação aceita
- **WHEN** quem criou a Ação aceita a contestação
- **THEN** aquela linha continua fora do numerador e do denominador, permanentemente

### Requirement: O alcance do titular sobrevive à saída

O sistema DEVE permitir que a pessoa veja e conteste marca feita sobre ela mesmo
depois de sair do Grupo da Ação, de o Grupo ser arquivado, ou de a Ação ter
deixado de ser visível para ela por qualquer outro motivo.

Desistir da Ação **não** entra nesta lista, e a ausência é deliberada: a
desistência é recusada em Ação encerrada, e comparecimento só existe em Ação que
já aconteceu. Não há estado em que alguém tenha marca de comparecimento e tenha
desistido.

A promessa não pode viver só na tela: no Postgres, um `update` só alcança o que
a política de leitura deixa a sessão enxergar. Um direito que depende de a pessoa
continuar participando é um direito que evapora exatamente quando é mais
necessário — e este projeto já mediu esse defeito uma vez, na fixação de
mensagem.

#### Scenario: Contesta depois de sair do Grupo
- **WHEN** alguém sai do Grupo e depois contesta uma marca feita sobre si
- **THEN** a contestação é registrada

#### Scenario: Vê depois de a Ação ficar invisível
- **WHEN** alguém sai do Grupo de uma Ação restrita e depois abre o próprio histórico
- **THEN** continua vendo a marca feita sobre si naquela Ação
- **AND** NÃO vê a marca feita sobre outra pessoa na mesma Ação

#### Scenario: Grupo arquivado
- **WHEN** o Grupo da Ação é arquivado e a pessoa contesta uma marca
- **THEN** a contestação é registrada

### Requirement: Sem consentimento da versão que descreve a medição, não há registro

O sistema NÃO DEVE registrar comparecimento de quem não aceitou a versão do
texto legal que descreve essa coleta e a finalidade dela.

A trava é na **coleta**, não na consulta. Gravar primeiro e filtrar na hora de
medir guardaria por anos um dado provavelmente sensível sobre quem nunca
consentiu com a finalidade — e a Política vigente já promete o contrário, ao
dizer que o aceite dado numa versão não cobre finalidade nova de versão
posterior.

A recusa NÃO DEVE revelar a versão que a outra pessoa aceitou nem qualquer outro
dado do Perfil dela: quem organiza a Ação vê que não pôde marcar, e o caminho
oferecido é a própria pessoa atualizar o aceite.

#### Scenario: Marca sobre quem está com versão defasada
- **WHEN** quem criou a Ação tenta marcar comparecimento de alguém cujo aceite é de versão anterior
- **THEN** nenhuma linha é afetada
- **AND** a tela diz que a marca não foi feita, sem expor dado do Perfil da outra pessoa

#### Scenario: Marca sobre quem tem aceite de versão desconhecida
- **WHEN** o aceite da pessoa não tem versão registrada
- **THEN** nenhuma linha é afetada

#### Scenario: Marca depois do reaceite
- **WHEN** a pessoa aceita a versão vigente e quem criou a Ação marca de novo
- **THEN** a marca é registrada

### Requirement: A idade não restringe o registro de comparecimento

O sistema DEVE registrar comparecimento de participante de qualquer idade. O
corte de maioridade que restringe a conversa NÃO DEVE ser aplicado aqui.

Os ministérios infantis do distrito são os que mais acompanham presença, e hoje
o fazem no papel. O que protege criança e adolescente não é a ausência do
registro — é o consentimento do responsável, que a versão nova do texto legal
passa a cobrir explicitamente, e é o fato de que menor de idade nunca aparece em
lista nominal de afastamento.

#### Scenario: Comparecimento de criança
- **WHEN** quem criou a Ação marca o comparecimento de participante abaixo do limiar de criança, cujo responsável autorizou na versão vigente
- **THEN** a marca é registrada

#### Scenario: Criança com autorização de versão anterior
- **WHEN** a autorização do responsável é de versão anterior à que descreve a medição
- **THEN** nenhuma linha é afetada

### Requirement: A presença nominal tem prazo, o agregado não

O sistema DEVE apagar a linha nominal de comparecimento dois anos depois da
Ação, por faxina agendada, e DEVE registrar cada execução dessa faxina como toda
faxina de retenção deste projeto.

A contagem por Ação — quantas pessoas estiveram — NÃO tem prazo, porque deixa de
ser dado pessoal assim que perde o nome, e é ela que serve de histórico ao
ministério.

Excluir a conta apaga o comparecimento da pessoa junto com o resto, e apaga
também a identificação de quem marcou e de quem decidiu contestação, quando for
ela.

#### Scenario: Linha vencida
- **WHEN** a faxina roda e há comparecimento de Ação com mais de dois anos
- **THEN** a linha nominal é apagada
- **AND** a execução fica registrada com a quantidade apagada

#### Scenario: Faxina sem nada a apagar
- **WHEN** a faxina roda e nada venceu
- **THEN** a execução fica registrada com quantidade zero

#### Scenario: Contagem sobrevive
- **WHEN** as linhas nominais de uma Ação antiga são apagadas
- **THEN** a quantidade de pessoas que estiveram naquela Ação continua disponível

#### Scenario: Exclusão de conta
- **WHEN** alguém exclui a própria conta
- **THEN** o comparecimento dela deixa de ser atribuível a ela
- **AND** as marcas que ela fez sobre outras pessoas deixam de identificá-la
