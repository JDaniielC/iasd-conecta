## Purpose

Chamar alguém para uma Ação por dentro do app: de onde sai a lista de quem
pode ser chamado, o que o convite faz (e não faz) com a vaga, o que a pessoa
convidada vê e filtra, e o que sobra do convite quando a Ação, o Grupo ou a
Conta deixam de existir.

## ADDED Requirements

### Requirement: A lista de quem dá pra convidar vem dos Grupos de quem convida

A tela de convidar DEVE mostrar as pessoas dos Grupos em que **quem convida**
participa, agrupadas por Grupo, com o nome de exibição de cada uma. A mesma
pessoa que participa de dois Grupos DEVE aparecer nos dois — o Grupo é o
contexto do convite, não um detalhe visual.

Quem convida NÃO DEVE aparecer na própria lista.

#### Scenario: Lista agrupada pelos Grupos que a pessoa participa

- **WHEN** alguém que participa de dois Grupos abre a tela de convidar de uma
  Ação
- **THEN** vê duas seções, uma por Grupo, cada uma com o nome de exibição dos
  participantes daquele Grupo, e o próprio nome não aparece em nenhuma delas

#### Scenario: Mesma pessoa em dois Grupos aparece duas vezes

- **WHEN** uma pessoa participa dos mesmos dois Grupos que quem convida
- **THEN** ela aparece na seção de cada um dos dois Grupos

#### Scenario: Sem Grupo, sem lista

- **WHEN** alguém que não participa de nenhum Grupo abre a tela de convidar
- **THEN** vê uma tela vazia explicando que a lista vem dos Grupos, e um
  caminho para a lista de Grupos

#### Scenario: Grupo arquivado sai da lista

- **WHEN** um dos Grupos de quem convida está arquivado
- **THEN** aquele Grupo não aparece como seção na tela de convidar

### Requirement: A lista não entrega gente de Grupo que a pessoa não participa

O sistema NÃO DEVE devolver a lista de participantes de um Grupo para quem não
participa daquele Grupo, nem pela tela nem por chamada direta à API. A checagem
de participação DEVE acontecer no banco, não na tela.

Este requisito existe porque a listagem entrega **vários nomes de uma vez**. Um
a um, o nome de exibição já é público hoje; em lote e sem checagem, viraria um
despejo de nomes do distrito inteiro.

A defesa DEVE ser a ausência do parâmetro: a listagem NÃO DEVE aceitar um id de
Grupo vindo do cliente. Aceitá-lo numa função `security definer` seria entregar
a lista de nomes de qualquer Grupo do distrito a qualquer sessão — é o buraco
que esta capability existe para não abrir, e o jeito de não abri-lo é não ter
por onde.

#### Scenario: Não há Grupo alheio a pedir

- **WHEN** uma sessão autenticada pede a lista de contatos de uma Ação
- **THEN** recebe apenas os Grupos de que ela própria participa, e não existe
  parâmetro pelo qual pedir a lista de outro Grupo

#### Scenario: Autenticado sem Grupo em comum não recebe nome nenhum

- **WHEN** uma sessão autenticada que não divide Grupo nenhum com as pessoas da
  Ação pede a lista de contatos
- **THEN** a resposta vem vazia

#### Scenario: Sessão anônima não alcança a listagem

- **WHEN** uma sessão `anon` tenta pedir a lista de contatos
- **THEN** a chamada é recusada por falta de permissão de execução — quem não
  tem cadastro não convida ninguém, e a listagem não é oferecida a ela

### Requirement: Convidar exige Conta

Só quem tem Conta (não-anônima) DEVE conseguir convidar. Quem está com Perfil
anônimo DEVE ver o caminho de virar Conta no lugar do botão de convidar.

Receber convite NÃO DEVE exigir Conta: qualquer Perfil recebe.

#### Scenario: Perfil anônimo não convida

- **WHEN** alguém com Perfil anônimo abre uma Ação
- **THEN** no lugar de "Convidar" vê o convite para criar Conta, e uma
  tentativa direta pela API é recusada

#### Scenario: Perfil anônimo recebe convite normalmente

- **WHEN** alguém com Conta convida uma pessoa de Perfil anônimo que divide um
  Grupo com ela
- **THEN** o convite é criado e aparece na tela de convites da pessoa convidada

### Requirement: Convite aponta para a Ação, não reserva vaga

O convite NÃO DEVE ocupar, reservar nem segurar vaga da Ação. Quem foi
convidado DEVE continuar precisando confirmar presença, e o resultado
(`confirmado` ou `fila`) DEVE ser decidido pela mesma regra de capacidade que
vale para quem chegou sozinho, no momento em que confirma.

#### Scenario: Ação lota entre o convite e a resposta

- **WHEN** alguém é convidado para uma Ação com uma vaga sobrando, outra
  pessoa confirma antes e ocupa essa vaga, e só depois a pessoa convidada
  confirma
- **THEN** a pessoa convidada entra na fila, e a Ação não fica com vaga vazia
  esperando por ela

#### Scenario: Convite não confirma presença sozinho

- **WHEN** um convite é criado
- **THEN** a lista de confirmados da Ação não muda, e a contagem de confirmados
  continua a mesma

#### Scenario: Ignorar o convite não custa vaga a ninguém

- **WHEN** uma pessoa convidada nunca responde
- **THEN** a Ação enche normalmente com quem confirmar, sem vaga bloqueada

### Requirement: O convite guarda o Grupo pelo qual foi feito

Todo convite DEVE registrar o Grupo pelo qual foi feito — aquele em cuja seção
a pessoa foi escolhida. É esse Grupo que a pessoa convidada usa para filtrar, e
é ele que aparece no convite como explicação de origem ("pelo Grupo X").

Convidar a mesma pessoa para a mesma Ação pelo mesmo Grupo DEVE ser
idempotente: não duplica e não é erro.

#### Scenario: O convite diz de onde veio

- **WHEN** alguém escolhe uma pessoa na seção do Grupo "Jovens" e convida
- **THEN** a pessoa convidada vê o convite identificado como vindo do Grupo
  "Jovens"

#### Scenario: Convidar de novo não duplica

- **WHEN** alguém convida a mesma pessoa para a mesma Ação pelo mesmo Grupo
  duas vezes
- **THEN** existe um convite só, e a segunda tentativa não mostra erro

#### Scenario: Mesma pessoa por dois Grupos

- **WHEN** alguém convida a mesma pessoa para a mesma Ação uma vez pelo Grupo
  "Jovens" e outra pelo Grupo "Música"
- **THEN** a pessoa vê os dois convites, cada um com seu Grupo, e ambos apontam
  para a mesma Ação

### Requirement: Convidar várias pessoas de uma vez é tudo ou nada por pessoa

Ao convidar mais de uma pessoa numa mesma ação de tela, o sistema DEVE informar
quantos convites foram feitos e quais falharam, **nominalmente**. Uma falha no
meio da lista NÃO DEVE desfazer os convites já criados nem deixar a pessoa sem
saber o que aconteceu.

#### Scenario: Uma pessoa da lista falha

- **WHEN** alguém seleciona cinco pessoas e o convite de uma delas falha
- **THEN** os outros quatro convites permanecem criados, e a tela diz quem
  ficou de fora e oferece tentar de novo só para essa pessoa

#### Scenario: Rede cai no meio

- **WHEN** a conexão cai durante o envio
- **THEN** a tela informa a falha sem afirmar sucesso, e reabrir a tela mostra
  o estado real — quem já foi convidado aparece como já convidado

### Requirement: Convite só é visto por quem convidou e por quem foi convidado

Um convite NÃO DEVE ser legível por terceiros. Quem convidou DEVE ver os
convites que fez para uma Ação; quem foi convidado DEVE ver os que recebeu.
Nenhuma outra sessão, autenticada ou anônima, DEVE conseguir ler a linha.

A lista de quem foi convidado NÃO DEVE aparecer na tela pública da Ação —
convite recusado ou ignorado é informação da pessoa, não do grupo.

#### Scenario: Terceiro não lê convite alheio

- **WHEN** uma sessão que não é a de quem convidou nem a de quem foi convidado
  pede os convites de uma Ação pela API
- **THEN** a resposta vem vazia

#### Scenario: Tela da Ação não mostra quem foi convidado

- **WHEN** qualquer pessoa abre a tela de uma Ação
- **THEN** vê a lista de confirmados e da fila como hoje, e nenhuma lista de
  convidados

#### Scenario: Quem convidou acompanha os próprios convites

- **WHEN** quem convidou reabre a Ação
- **THEN** vê quem já convidou por ali, e quem daquela lista já confirmou
  presença

### Requirement: Quem foi convidado filtra os convites por Grupo

A tela de convites recebidos DEVE listar os convites em aberto e permitir
filtrar por Grupo, oferecendo como opções **apenas os Grupos em que a pessoa
participa**. Sem filtro escolhido, DEVE mostrar todos.

#### Scenario: Filtrar por um Grupo

- **WHEN** alguém com convites vindos de três Grupos filtra por um deles
- **THEN** vê só os convites daquele Grupo, e a contagem exibida corresponde ao
  que está na tela

#### Scenario: Convite de Grupo que a pessoa não participa

- **WHEN** alguém recebe um convite pelo Grupo "Jovens" e depois sai desse
  Grupo
- **THEN** o convite continua na lista sem filtro, e "Jovens" não aparece mais
  como opção de filtro

#### Scenario: Sem convite nenhum

- **WHEN** alguém abre a tela de convites sem ter recebido nenhum
- **THEN** vê uma tela vazia explicando que convites chegam de pessoas dos seus
  Grupos, sem controle de filtro aparecendo

### Requirement: Convite morre com a Ação e sobrevive à saída do Grupo

Convite que aponta para Ação **cancelada** ou **encerrada** NÃO DEVE aparecer
na lista de convites em aberto de quem foi convidado.

Sair do Grupo, o Grupo ser arquivado, ou quem convidou sair do Grupo NÃO DEVEM
apagar convite já feito. O convite já foi entregue; retirá-lo em silêncio
confundiria mais do que ajudaria.

#### Scenario: Ação cancelada some dos convites

- **WHEN** a Ação de um convite em aberto é cancelada
- **THEN** o convite deixa de aparecer na lista de convites em aberto de quem
  foi convidado

#### Scenario: Abrir convite de Ação cancelada

- **WHEN** alguém abre um convite por link ou notificação e a Ação já foi
  cancelada
- **THEN** vê que a Ação foi cancelada, sem erro e sem tela quebrada, e não é
  oferecida a opção de confirmar presença

#### Scenario: Sair do Grupo não apaga o convite

- **WHEN** quem foi convidado sai do Grupo pelo qual o convite veio, e a Ação
  segue de pé
- **THEN** o convite continua na lista e ainda dá para confirmar presença por
  ele

#### Scenario: Grupo arquivado não apaga convite feito

- **WHEN** o Grupo pelo qual um convite foi feito é arquivado
- **THEN** o convite em aberto continua aparecendo para quem foi convidado

### Requirement: Convite não sobrevive à exclusão de Conta como dado pessoal

Quando um Perfil é anonimizado pela exclusão de Conta, o convite NÃO DEVE
continuar exibindo o nome real de quem convidou nem de quem foi convidado. O
convite DEVE referenciar o Perfil, nunca guardar cópia do nome.

#### Scenario: Quem convidou exclui a Conta

- **WHEN** a pessoa que fez um convite exclui a Conta
- **THEN** o convite passa a exibir o Perfil anonimizado, e o nome anterior não
  aparece em lugar nenhum da tela de convites

#### Scenario: Quem foi convidado exclui a Conta

- **WHEN** a pessoa convidada exclui a Conta
- **THEN** quem convidou não vê o nome dela na lista de convites feitos
