# Destaque de Acoes Specification

## Purpose

Quando uma Ação entra na faixa de destaque de `/acoes`, em qual cor aparece, e
quando some dali — sem mudar o que entra na lista por período, que continua
existindo do jeito que está hoje.

## Requirements

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

O filtro de Igreja da tela NÃO DEVE tirar nada da faixa: "qualquer Igreja" vale
para o que a faixa mostra, não só para a regra de participação. Quem deixa o
filtro na própria Igreja — o mais provável — deixaria de ver a novidade de um
Grupo seu sediado em outra, e ela seria consumida assim mesmo. O filtro
continua valendo para a lista por período, que é o que ele existe para
recortar.

O filtro "Só Sábado" é diferente e continua valendo também na faixa: ele diz
"quero ver só o que é do Sábado", e uma faixa cheia de Ação de outro dia
contrariaria o que a pessoa acabou de pedir.

#### Scenario: Filtro de Igreja não esconde a novidade de um Grupo meu

- **WHEN** o Usuário filtra a lista por uma Igreja e tem Ação nova num Grupo
  seu sediado em outra Igreja
- **THEN** essa Ação continua na faixa de destaque, mesmo não aparecendo na
  lista por período sob aquele filtro

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

O marcador só avança quando a tela teve **o que mostrar**: a lista de Ações e
a consulta de "Grupos que eu participo" precisam ter carregado com sucesso.
Falhando qualquer uma das duas, o marcador NÃO DEVE avançar.

Sem isso, uma falha de rede de um segundo consome em silêncio a novidade de
todos os Grupos, para sempre — a pessoa vê "não deu pra carregar" e perde o
aviso que nunca chegou a receber. O preço aceito é o oposto: com rede ruim a
mesma Ação pode aparecer em destaque mais de uma vez. Repetir um aviso é
barato; perdê-lo, não.

Lista vazia avança o marcador normalmente: não há novidade a perder.

Ler o marcador e avançá-lo são dois passos independentes: falhar ao avançar
NÃO DEVE tirar da tela o destaque que a leitura já tinha resolvido, e falhar ao
ler NÃO DEVE gravar nada por cima.

São as duas metades da mesma ideia — o marcador nunca piora por causa de um
erro. Juntar os dois passos fazia a falha da gravação descartar a leitura boa e
a faixa perdia o destaque de Grupo inteiro, calada; e gravar sem ter conseguido
ler apagaria a fronteira do que já foi visto, deixando toda Ação existente de
ser nova de uma vez.

#### Scenario: Armazenamento recusa a gravação

- **WHEN** o marcador é lido com sucesso mas o aparelho recusa gravá-lo
- **THEN** a faixa continua mostrando o destaque de Grupo que a leitura
  resolveu, e o marcador anterior é preservado

#### Scenario: Armazenamento recusa a leitura

- **WHEN** o aparelho recusa ler o marcador
- **THEN** nada é gravado por cima dele

#### Scenario: Lista que não carrega não consome a novidade

- **WHEN** o Usuário abre `/acoes` e a lista de Ações falha ao carregar
- **THEN** o marcador não avança, e na próxima abertura bem-sucedida as Ações
  de Grupo ainda contam como novas

#### Scenario: Consulta de Grupos que não carrega não consome a novidade

- **WHEN** o Usuário abre `/acoes` e a consulta dos Grupos de que ele
  participa falha
- **THEN** o marcador não avança — sem saber quais são os Grupos, não há como
  ter mostrado a novidade deles

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
