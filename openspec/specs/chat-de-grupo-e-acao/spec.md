# chat-de-grupo-e-acao Specification

## Purpose

Dar a quem participa de um Grupo ou vai a uma Ação um lugar dentro do app para
combinar as coisas, com regra clara de quem entra, quem lê, quanto tempo a
conversa dura e o que sobra dela quando alguém exclui a conta.

## Requirements

### Requirement: Só maior de 18 anos entra no chat

O sistema NÃO DEVE permitir que alguém com menos de 18 anos leia ou escreva
mensagem, em nenhum chat. A regra DEVE valer no banco, não apenas na tela: uma
chamada direta à API com credencial de menor precisa ser recusada.

Visitante — login anônimo, sem Perfil — NÃO DEVE ler nem escrever.

#### Scenario: Menor de idade tenta ler pela API
- **WHEN** alguém com idade menor que 18 consulta mensagens diretamente pela API
- **THEN** a consulta devolve zero linhas, e não uma lista parcial

#### Scenario: Menor de idade tenta escrever pela API
- **WHEN** alguém com idade menor que 18 tenta inserir mensagem pela API
- **THEN** a operação é recusada

#### Scenario: Menor de idade abre um Grupo em que participa
- **WHEN** alguém com menos de 18 anos abre o detalhe de um Grupo do qual
  participa
- **THEN** não existe aba de conversa na tela
- **AND** o resto da tela funciona igual, inclusive a seção de mudanças

#### Scenario: Visitante abre um Grupo
- **WHEN** alguém sem Perfil, em login anônimo, abre o detalhe de um Grupo
- **THEN** não existe aba de conversa na tela

#### Scenario: Perfil anonimizado por exclusão de conta
- **WHEN** um Perfil teve a idade removida pela exclusão de conta
- **THEN** ele não passa no corte de idade, como qualquer outro caso sem idade
  conhecida

### Requirement: O Administrador do distrito alcança qualquer chat

O Administrador do distrito DEVE conseguir ler e remover mensagem de qualquer
chat, de qualquer Grupo e de qualquer Ação. O corte de 18 anos continua valendo
para ele.

Isto é poder amplo e é declarado de propósito, não efeito colateral. A primeira
versão deste desenho dava a ele autoridade para remover **sem** acesso de
leitura — "moderar não é ler" —, e essa separação não sobrevive ao banco:
remover é alterar uma linha filtrada por id, e uma alteração filtrada aplica
também a regra de leitura. Sem leitura, a remoção não alcança a linha e falha
sem erro.

O preço de não ter isso seria não haver instância de recurso quando o abuso vem
de quem manda no espaço — o dono do Grupo denunciado por quem ele mesmo
modera.

#### Scenario: Administrador remove mensagem de Grupo do qual não participa
- **WHEN** um Administrador do distrito remove uma mensagem denunciada de um
  Grupo em que não participa
- **THEN** a remoção acontece, e o texto some para todo mundo

#### Scenario: Administrador menor de idade
- **WHEN** um Administrador do distrito tem menos de 18 anos
- **THEN** ele não lê nem remove mensagem, como qualquer outra pessoa — a
  autoridade não levanta o corte de idade

### Requirement: O chat do Grupo é de quem participa do Grupo

O sistema DEVE permitir ler e escrever no chat de um Grupo apenas a quem tem
participação naquele Grupo e passa no corte de idade.

#### Scenario: Participante escreve
- **WHEN** alguém que participa do Grupo e tem 18 anos ou mais envia mensagem
- **THEN** a mensagem é gravada e passa a aparecer para os demais participantes

#### Scenario: Não participante tenta ler
- **WHEN** alguém que não participa do Grupo consulta as mensagens dele
- **THEN** a consulta devolve zero linhas

#### Scenario: Alguém sai do Grupo
- **WHEN** uma pessoa deixa de participar do Grupo
- **THEN** ela deixa de ler as mensagens daquele Grupo, inclusive as anteriores
  à saída
- **AND** as mensagens que ela escreveu continuam visíveis para quem ficou

### Requirement: O chat da Ação é de quem vai à Ação e de quem manda nela

O sistema DEVE permitir ler e escrever no chat de uma Ação a quem tem
confirmação naquela Ação — com status confirmado **ou** de fila —, ao criador
da Ação, e ao dono do Grupo dela quando a Ação pertence a um Grupo. Todos
sujeitos ao corte de idade.

Estar em fila NÃO DEVE restringir a conversa: quem está na fila precisa
acompanhar a combinação para saber se vale continuar esperando.

#### Scenario: Pessoa em fila lê e escreve
- **WHEN** alguém com status de fila abre o chat da Ação
- **THEN** lê e escreve como quem está confirmado

#### Scenario: Participante do Grupo sem confirmação
- **WHEN** alguém participa do Grupo da Ação mas não confirmou presença nela
- **THEN** não lê o chat daquela Ação
- **AND** continua lendo o chat do Grupo

#### Scenario: Dono do Grupo sem confirmar
- **WHEN** o dono do Grupo abre o chat de uma Ação do Grupo dele sem ter
  confirmado presença
- **THEN** lê e escreve — a autoridade sobre o espaço não depende de ir

#### Scenario: Alguém desconfirma presença
- **WHEN** uma pessoa remove a própria confirmação
- **THEN** deixa de ler o chat daquela Ação

### Requirement: A mensagem tem autor verificável e conteúdo limitado

O sistema NÃO DEVE aceitar mensagem assinada por outra pessoa. DEVE recusar
mensagem vazia ou só com espaços, e mensagem acima do limite de tamanho.

#### Scenario: Tentativa de assinar por outro
- **WHEN** alguém insere mensagem declarando outro Perfil como autor
- **THEN** a operação é recusada

#### Scenario: Mensagem vazia
- **WHEN** alguém envia mensagem sem conteúdo ou só com espaços
- **THEN** a operação é recusada

#### Scenario: Mensagem longa demais
- **WHEN** alguém envia mensagem acima do limite de tamanho
- **THEN** a operação é recusada, e a tela diz o limite antes do envio

### Requirement: Mensagem enviada não se edita

O sistema NÃO DEVE permitir alterar o conteúdo de uma mensagem já enviada. Uma
mensagem errada se remove; não se reescreve.

#### Scenario: Autor tenta editar
- **WHEN** o autor tenta alterar o texto da própria mensagem pela API
- **THEN** a operação é recusada

### Requirement: Mensagem nova chega sem recarregar

O sistema DEVE entregar mensagem nova a quem já está com o chat aberto, sem
ação da pessoa.

#### Scenario: Duas pessoas com o chat aberto
- **WHEN** uma envia mensagem
- **THEN** a outra passa a ver a mensagem sem recarregar nem puxar a tela

#### Scenario: Conexão cai e volta
- **WHEN** a conexão de tempo real cai e depois volta
- **THEN** a tela mostra as mensagens que chegaram durante a queda
- **AND** nenhuma mensagem aparece duplicada

#### Scenario: Conexão indisponível
- **WHEN** a conexão de tempo real não se estabelece
- **THEN** o chat continua utilizável pela consulta comum, e a tela sinaliza
  que não está ao vivo
- **AND** a tela não fica em carregamento perpétuo

### Requirement: O canal de tempo real entrega exatamente o que a consulta entregaria

O sistema NÃO DEVE entregar por tempo real nenhuma mensagem que a mesma pessoa
não obteria consultando. Divergência entre o canal e a consulta é vazamento,
mesmo que a tela descarte a mensagem depois de recebê-la.

#### Scenario: Alguém assina o canal de um Grupo em que não participa
- **WHEN** alguém que não participa do Grupo assina o canal daquele Grupo
- **THEN** não recebe nenhuma mensagem daquele Grupo

#### Scenario: Menor de idade assina o canal
- **WHEN** alguém com menos de 18 anos assina o canal de um Grupo em que
  participa
- **THEN** não recebe nenhuma mensagem

### Requirement: Chat de Ação expira; chat de Grupo permanece

O sistema DEVE apagar toda mensagem de uma Ação 30 dias depois da data e hora
dela. Mensagem de Grupo NÃO DEVE expirar por tempo.

O prazo DEVE ser cumprido mesmo que o agendamento no banco não rode — o
projeto está em plano que pausa o banco por inatividade
(`20260810170000_varredura_segundo_gatilho.sql:9-14`), e o app precisa ser o
segundo gatilho, como já é para a drenagem de capas.

#### Scenario: Ação passou de 30 dias
- **WHEN** se passam mais de 30 dias da data e hora de uma Ação
- **THEN** as mensagens daquela Ação deixam de existir

#### Scenario: Ação de ontem
- **WHEN** uma Ação aconteceu ontem
- **THEN** as mensagens dela continuam legíveis por quem tinha acesso

#### Scenario: Banco ficou pausado e alguém abre o app
- **WHEN** o agendamento não rodou por dias e alguém volta a usar o app
- **THEN** o expurgo acontece assim mesmo, disparado pelo uso
- **AND** quem disparou não percebe demora perceptível

#### Scenario: Ação cancelada
- **WHEN** uma Ação é cancelada
- **THEN** o chat dela continua legível e utilizável até o prazo de expiração —
  cancelar é justamente quando mais se precisa avisar

### Requirement: Grupo arquivado tem chat só de leitura

O sistema NÃO DEVE aceitar mensagem nova em Grupo arquivado, e DEVE manter o
histórico legível para quem participava.

#### Scenario: Envio em Grupo arquivado
- **WHEN** alguém tenta enviar mensagem num Grupo arquivado
- **THEN** a operação é recusada
- **AND** as mensagens antigas continuam legíveis

### Requirement: Excluir a conta apaga o texto escrito pelo titular

Anonimizar o Perfil não anonimiza um nome, um telefone ou um endereço digitado
dentro de uma mensagem. Por isso o sistema DEVE, na exclusão de conta, apagar o
conteúdo de toda mensagem do titular, conservando apenas a marca de que houve
mensagem ali — sem a qual a conversa restante fica sem sentido.

O sistema NÃO DEVE, na exclusão de conta, tocar em mensagem escrita por outra
pessoa, ainda que ela cite o titular. Esse caso se resolve por denúncia, e o
limite DEVE estar escrito na Política de Privacidade.

#### Scenario: Titular exclui a conta depois de conversar
- **WHEN** alguém que escreveu mensagens exclui a conta
- **THEN** o conteúdo dessas mensagens deixa de existir
- **AND** resta no lugar a marca de mensagem removida, na mesma posição da
  conversa

#### Scenario: Terceiro citou o titular
- **WHEN** outra pessoa escreveu uma mensagem citando o nome de quem excluiu a
  conta
- **THEN** essa mensagem continua intacta
- **AND** o caminho para removê-la é a denúncia

#### Scenario: Exclusão de conta continua funcionando
- **WHEN** a exclusão de conta é executada
- **THEN** ela conclui em uma transação, como hoje, sem novo caminho de falha
  parcial
