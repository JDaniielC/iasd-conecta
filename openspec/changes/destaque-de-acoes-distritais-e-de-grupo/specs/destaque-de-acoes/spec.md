## Purpose

Quando uma Ação entra na faixa de destaque de `/acoes`, em qual cor aparece, e
quando some dali — sem mudar o que entra na lista por período, que continua
existindo do jeito que está hoje.

## ADDED Requirements

### Requirement: Ação avulsa sempre entra no destaque

Toda Ação avulsa (sem Grupo) DEVE aparecer na faixa de destaque, no topo de
`/acoes`, acima da lista agrupada por período — incondicional, para qualquer
pessoa que abra a tela, com ou sem Perfil.

#### Scenario: Ação avulsa nova aparece em destaque forte

- **WHEN** existe uma Ação avulsa não encerrada
- **THEN** ela aparece na faixa de destaque, com a cor de destaque forte, e
  também continua na lista por período de sempre

### Requirement: Ação cancelada não entra no destaque

Uma Ação cancelada NÃO DEVE aparecer na faixa de destaque, nem sendo avulsa,
nem sendo Ação nova de um Grupo de que a pessoa participa. Ela continua na
lista por período, marcada como cancelada, como hoje.

#### Scenario: Ação avulsa cancelada fica só na lista por período

- **WHEN** uma Ação avulsa é cancelada
- **THEN** ela sai da faixa de destaque e continua aparecendo na lista por
  período com a marcação de cancelada

### Requirement: A novidade de Grupo abre a faixa

Quando há Ação de Grupo em destaque, ela DEVE vir antes das Ações avulsas na
faixa, independentemente da data.

Ação avulsa está na faixa todos os dias e continua logo abaixo; a Ação nova de
um Grupo é a única que a pessoa não tem como saber que existe, e é ela que a
faixa existe para mostrar. Herdando a ordem por data da lista, ela pode cair
depois do corte e não aparecer.

#### Scenario: Ação nova de Grupo mais distante ainda abre a faixa

- **WHEN** há quatro Ações avulsas próximas e uma Ação nova de um Grupo do
  Usuário marcada para muito depois de todas elas
- **THEN** a Ação do Grupo aparece como primeiro item da faixa

### Requirement: A faixa mostra no máximo três Ações de cada vez

A faixa de destaque DEVE mostrar no máximo três Ações. Havendo mais, ela
oferece abrir o restante, e abrir também DEVE poder ser desfeito.

O corte existe porque Ação avulsa entra na faixa **sem sair** da lista por
período: sem ele, num distrito onde a maioria das Ações é avulsa a faixa vira
uma segunda cópia da lista e empurra o primeiro cabeçalho de período para
fora da tela.

#### Scenario: Com mais de três, a faixa mostra três e oferece o resto

- **WHEN** cinco Ações se qualificam para a faixa de destaque
- **THEN** a faixa mostra três e oferece ver as outras duas; abrindo, todas
  as cinco aparecem, e é possível fechar de volta para três

#### Scenario: Fechar um item promove o que estava escondido

- **WHEN** quatro Ações se qualificam e a pessoa fecha uma das três visíveis
- **THEN** a quarta passa a aparecer na faixa, e a oferta de "ver mais" some

### Requirement: Ação de Grupo entra no destaque só para quem participa e só enquanto nova

Uma Ação de Grupo confirmada DEVE aparecer na faixa de destaque, com a cor de
destaque neutra, apenas quando as duas condições valem: quem está vendo a
tela participa do Grupo dono da Ação (qualquer Igreja — participação não filtra
por Igreja), e a Ação é **nova** para essa pessoa.

Uma Ação de Grupo cujo Usuário não participa NÃO DEVE aparecer na faixa de
destaque — continua só na lista por período, como hoje.

#### Scenario: Ação nova de um Grupo que participo entra em destaque neutro

- **WHEN** um Grupo que o Usuário participa tem uma Ação confirmada criada
  depois da última vez que o Usuário abriu `/acoes`
- **THEN** ela aparece na faixa de destaque com a cor neutra, e continua
  também na lista por período

#### Scenario: Ação de Grupo que não participo não entra em destaque

- **WHEN** um Grupo que o Usuário NÃO participa tem uma Ação confirmada nova
- **THEN** ela não aparece na faixa de destaque — só na lista por período

#### Scenario: Ação de Grupo deixa de ser nova

- **WHEN** o Usuário abre `/acoes` depois de uma Ação de um Grupo seu já ter
  aparecido em destaque
- **THEN** nas aberturas seguintes essa Ação não aparece mais na faixa de
  destaque (deixou de ser nova), mesmo continuando confirmada e futura

### Requirement: Marcador de "nova" é único e por instalação

O que separa uma Ação de Grupo nova de uma já vista é um único marcador —
a última vez que o Usuário abriu `/acoes` nesta instalação — não um marcador
por Grupo.

#### Scenario: Abrir a tela por causa de um Grupo consome a novidade de todos

- **WHEN** o Usuário tem Ação nova em dois Grupos diferentes e abre `/acoes`
- **THEN** nenhuma das duas aparece mais em destaque na próxima abertura,
  mesmo que o Usuário só tenha reparado numa delas

### Requirement: Fechar um item do destaque é por sessão, não persiste

O Usuário PODE fechar (dispensar) um item da faixa de destaque individualmente.
Esse fechamento vale só para a sessão atual do app — não é gravado em disco
nem no banco.

#### Scenario: Item fechado some da tela

- **WHEN** o Usuário fecha um item específico do destaque
- **THEN** esse item some da faixa de destaque, e os demais itens continuam

#### Scenario: Item fechado reaparece na próxima abertura do app

- **WHEN** o Usuário fecha um item do destaque e depois fecha e reabre o app
- **THEN** esse item volta a aparecer na faixa de destaque, se ainda contar
  como distrital-avulsa ou ainda-nova pelas regras acima
