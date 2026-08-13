## Purpose

Avisos dirigidos a uma pessoa dentro do app: o que gera um aviso, quem
consegue lê-lo, como o não lido é contado e zerado, o que acontece quando o
assunto do aviso deixa de existir, e por quanto tempo o aviso fica guardado.

## ADDED Requirements

### Requirement: Ser convidado gera aviso para quem foi convidado

Todo convite criado DEVE gerar um aviso para a pessoa convidada, dizendo quem
convidou, para qual Ação e por qual Grupo. O aviso DEVE nascer não lido.

Convidar a mesma pessoa para a mesma Ação pelo mesmo Grupo é idempotente e NÃO
DEVE gerar um segundo aviso.

#### Scenario: Convite gera aviso não lido

- **WHEN** alguém é convidado para uma Ação
- **THEN** um aviso não lido aparece para a pessoa convidada, identificando
  quem convidou, a Ação e o Grupo de origem

#### Scenario: Convite em lote gera um aviso por pessoa

- **WHEN** alguém convida cinco pessoas de uma vez
- **THEN** cada uma das cinco recebe um aviso, e ninguém recebe cinco

#### Scenario: Convite repetido não gera aviso repetido

- **WHEN** alguém convida a mesma pessoa para a mesma Ação pelo mesmo Grupo
  duas vezes
- **THEN** existe um aviso só

#### Scenario: Convidada pelo mesmo Grupo por duas pessoas diferentes

- **WHEN** duas pessoas do mesmo Grupo convidam a mesma pessoa para a mesma
  Ação
- **THEN** ela recebe dois avisos, um por quem convidou

### Requirement: A resposta ao convite gera aviso para quem convidou

Quando a pessoa convidada **confirma presença** na Ação para a qual foi
convidada, quem convidou DEVE receber um aviso. Quando ela **recusa** o
convite, quem convidou também DEVE receber um aviso, distinto do de aceite.

Se a mesma pessoa foi convidada para a mesma Ação por duas pessoas, **cada uma
que convidou** DEVE receber o aviso da resposta.

Confirmar presença numa Ação sem ter sido convidado NÃO DEVE gerar aviso para
ninguém — não há a quem responder.

#### Scenario: Aceite avisa quem convidou

- **WHEN** a pessoa convidada confirma presença na Ação
- **THEN** quem a convidou recebe um aviso não lido de que ela vem

#### Scenario: Recusa avisa quem convidou

- **WHEN** a pessoa convidada recusa o convite
- **THEN** quem a convidou recebe um aviso não lido, distinto do de aceite

#### Scenario: Duas pessoas convidaram, as duas ficam sabendo

- **WHEN** a pessoa foi convidada para a mesma Ação por duas pessoas e confirma
  presença
- **THEN** as duas recebem o aviso de aceite

#### Scenario: Quem chegou sozinho não gera aviso

- **WHEN** alguém confirma presença numa Ação sem ter recebido convite para ela
- **THEN** nenhum aviso é criado

#### Scenario: Entrar na fila conta como aceite

- **WHEN** a pessoa convidada confirma presença numa Ação lotada e cai na fila
- **THEN** quem convidou recebe o aviso de aceite, e o aviso deixa claro que
  ela está na fila

#### Scenario: Desistir depois de aceitar não gera aviso novo

- **WHEN** a pessoa convidada aceita e depois desiste
- **THEN** nenhum aviso novo é criado, e o aviso de aceite já entregue continua
  como está

### Requirement: Aviso só é lido por quem ele é

Um aviso NÃO DEVE ser legível por ninguém além da pessoa a quem ele se dirige,
nem por sessão anônima, nem por chamada direta à API.

#### Scenario: Terceiro não lê aviso alheio

- **WHEN** uma sessão autenticada pede a lista de avisos pela API
- **THEN** recebe apenas os próprios avisos, e nenhum de outra pessoa

#### Scenario: Sessão anônima não recebe aviso nenhum

- **WHEN** uma sessão `anon` pede a lista de avisos
- **THEN** a resposta vem vazia

### Requirement: Só o banco cria aviso

Nenhuma sessão do cliente DEVE conseguir criar, alterar o conteúdo, ou apagar
um aviso. A única escrita permitida ao cliente é marcar o próprio aviso como
lido.

#### Scenario: Cliente não cria aviso

- **WHEN** uma sessão autenticada tenta inserir uma linha de aviso pela API,
  inclusive para si mesma
- **THEN** a escrita é recusada

#### Scenario: Cliente não apaga aviso

- **WHEN** uma sessão autenticada tenta apagar um aviso, inclusive um seu
- **THEN** a escrita é recusada

#### Scenario: Marcar o próprio como lido funciona

- **WHEN** alguém marca um aviso seu como lido
- **THEN** o aviso passa a contar como lido

#### Scenario: Marcar aviso alheio como lido não funciona

- **WHEN** alguém tenta marcar como lido um aviso de outra pessoa
- **THEN** nada muda

### Requirement: Contador de não lidas aparece e se atualiza sozinho

O app DEVE mostrar quantos avisos não lidos a pessoa tem, em lugar visível de
qualquer tela. Com o app aberto, o contador DEVE subir ao chegar um aviso novo
**sem que a pessoa precise recarregar ou navegar**.

O contador DEVE bater com o que a tela de avisos mostra.

#### Scenario: Aviso novo com o app aberto

- **WHEN** alguém convida a pessoa enquanto ela está com o app aberto em outra
  tela
- **THEN** o contador sobe sozinho, em segundos, sem recarregar

#### Scenario: Contador bate com a lista

- **WHEN** a pessoa abre a tela de avisos
- **THEN** a quantidade de avisos não lidos na tela é a mesma do contador

#### Scenario: Sem aviso, sem contador

- **WHEN** a pessoa não tem nenhum aviso não lido
- **THEN** o contador não aparece, em vez de aparecer zerado

#### Scenario: Conexão de tempo real cai

- **WHEN** a conexão de tempo real se perde
- **THEN** o app não mostra erro por isso, e o contador se corrige na próxima
  vez que a pessoa abre a tela de avisos ou volta para o app

### Requirement: Abrir a tela de avisos zera o não lido do que foi mostrado

Ao abrir a tela de avisos, os avisos exibidos DEVEM passar a contar como lidos.
A tela DEVE continuar mostrando os avisos já lidos, distinguindo-os
visualmente dos não lidos, em vez de esvaziar.

#### Scenario: Abrir a tela zera o contador

- **WHEN** a pessoa com três avisos não lidos abre a tela de avisos
- **THEN** o contador some, e os três continuam na lista, marcados como lidos

#### Scenario: Aviso que chega com a tela aberta

- **WHEN** um aviso chega enquanto a pessoa está com a tela de avisos aberta
- **THEN** ele aparece na lista sem recarregar

### Requirement: Aviso não sobrevive ao assunto

Aviso de convite cuja Ação foi **cancelada** ou **encerrada** NÃO DEVE aparecer
na lista nem contar como não lido. O mesmo vale quando a Ação é apagada.

Um aviso NÃO DEVE levar a pessoa a uma tela quebrada.

#### Scenario: Ação cancelada tira o aviso da lista

- **WHEN** a Ação de um convite com aviso não lido é cancelada
- **THEN** o aviso deixa de aparecer e o contador diminui

#### Scenario: Tocar num aviso cujo assunto sumiu

- **WHEN** a pessoa toca num aviso e a Ação já não existe mais
- **THEN** vê que a Ação não está mais disponível, sem erro e sem tela quebrada

### Requirement: Aviso tem prazo de guarda

Aviso já lido DEVE ser apagado depois de um prazo declarado, sem intervenção
manual. Aviso não lido NÃO DEVE ser apagado pelo prazo.

O prazo DEVE estar registrado em `MAPA-DE-DADOS.md` junto da tabela.

#### Scenario: Lido antigo é apagado

- **WHEN** um aviso está lido há mais tempo que o prazo
- **THEN** ele deixa de existir, sem que ninguém precise rodar nada à mão

#### Scenario: Não lido antigo permanece

- **WHEN** um aviso continua não lido há mais tempo que o prazo
- **THEN** ele continua na lista e continua contando

#### Scenario: A limpeza não trava o app

- **WHEN** a limpeza roda
- **THEN** nenhuma operação do app falha ou fica presa por causa dela

### Requirement: Aviso não guarda cópia de nome

O aviso DEVE referenciar o Perfil de quem o gerou, nunca o nome copiado. Depois
da exclusão de Conta de quem convidou, o nome anterior NÃO DEVE aparecer no
aviso.

#### Scenario: Quem convidou exclui a Conta

- **WHEN** a pessoa que gerou um aviso exclui a Conta
- **THEN** o aviso passa a exibir o Perfil anonimizado, e o nome anterior não
  aparece na tela de avisos
