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
