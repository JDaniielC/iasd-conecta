## Purpose

Recusar na entrada a mensagem que contém palavra que o distrito não aceita, com
uma lista e uma regra de casamento próprias da conversa — que não são as mesmas
que barram um nome de cadastro.

## ADDED Requirements

### Requirement: Mensagem com palavra bloqueada é recusada na escrita

O sistema NÃO DEVE gravar mensagem que contenha palavra da lista de conversa.
A recusa DEVE acontecer na escrita, não na exibição: mensagem gravada e depois
escondida já foi entregue a quem estava com o chat aberto em tempo real.

#### Scenario: Mensagem com palavra bloqueada
- **WHEN** alguém envia mensagem contendo palavra da lista
- **THEN** a mensagem não é gravada
- **AND** nenhum assinante do canal de tempo real recebe qualquer evento

#### Scenario: Mensagem limpa
- **WHEN** alguém envia mensagem sem nenhuma palavra da lista
- **THEN** a mensagem é gravada normalmente

### Requirement: O casamento é por palavra inteira, não por trecho

O sistema DEVE casar a palavra bloqueada como palavra inteira, ignorando
maiúsculas e acentos. NÃO DEVE recusar uma palavra legítima só porque a
sequência bloqueada aparece dentro dela.

É a diferença deliberada em relação a `nome_valido()`, que casa por trecho
(`20260806090000_nome_valido_security_definer.sql:38-41`): num nome de
cadastro, trecho é a regra certa; em texto corrido, produz recusa que ninguém
entende.

#### Scenario: Palavra bloqueada dentro de palavra legítima
- **WHEN** a lista contém uma palavra e alguém envia mensagem com uma palavra
  maior que a contém como trecho
- **THEN** a mensagem é aceita

#### Scenario: Maiúsculas e acentos
- **WHEN** a palavra aparece com maiúsculas, com acento ou sem acento
- **THEN** a mensagem é recusada igual

#### Scenario: Palavra colada em pontuação
- **WHEN** a palavra aparece seguida de vírgula, ponto ou fim da mensagem
- **THEN** a mensagem é recusada — pontuação não é parte da palavra

### Requirement: A lista da conversa é separada da lista de nomes

O sistema DEVE manter a lista de palavras da conversa separada da lista que
valida nome de Perfil. Alterar uma NÃO DEVE alterar a outra.

O padrão aceitável num nome de cadastro é mais estrito que numa conversa entre
adultos; misturar as duas listas obriga a escolher um dos dois errados.

#### Scenario: Palavra bloqueada só para nome
- **WHEN** uma palavra está na lista de nomes e não na lista de conversa
- **THEN** ela é recusada num nome de Perfil e aceita numa mensagem

#### Scenario: Palavra bloqueada só para conversa
- **WHEN** uma palavra está na lista de conversa e não na lista de nomes
- **THEN** ela é recusada numa mensagem e aceita num nome de Perfil

### Requirement: A lista não é legível por quem usa o app

O sistema NÃO DEVE expor a lista de palavras da conversa aos papéis públicos.
Uma lista legível é um roteiro de como contorná-la.

#### Scenario: Usuário consulta a lista
- **WHEN** um usuário autenticado consulta a tabela da lista pela API
- **THEN** a consulta devolve zero linhas

#### Scenario: Administrador do distrito consulta a lista
- **WHEN** um Administrador do distrito consulta a lista pela API
- **THEN** a consulta devolve zero linhas — a lista se administra fora do app,
  como a de nomes

### Requirement: Quem escreveu fica sabendo qual palavra barrou

O sistema DEVE devolver a quem enviou a palavra que causou a recusa, e apenas
ela. NÃO DEVE devolver nenhuma outra palavra da lista.

Devolver a palavra não vaza a lista: quem enviou acabou de digitá-la. Não
devolver nada produz uma recusa que a pessoa não sabe corrigir, e ela reenvia
até desistir.

#### Scenario: Recusa informa a palavra
- **WHEN** a mensagem é recusada pelo filtro
- **THEN** a tela mostra qual palavra da mensagem causou a recusa
- **AND** não mostra nenhuma palavra que não estava na mensagem

#### Scenario: Mais de uma palavra bloqueada na mesma mensagem
- **WHEN** a mensagem contém duas palavras da lista
- **THEN** a tela mostra ao menos uma delas, e a mensagem continua não gravada

### Requirement: O motivo de uma denúncia passa pelo mesmo filtro

O sistema DEVE aplicar o mesmo filtro ao texto do motivo de uma denúncia. Sem
isso, o campo de denúncia vira a via aberta que o chat deixou de ser — e ele é
lido por quem modera.

#### Scenario: Denúncia com palavra bloqueada no motivo
- **WHEN** alguém registra denúncia cujo motivo contém palavra da lista
- **THEN** a denúncia não é gravada
- **AND** a recusa informa a palavra, como no chat

### Requirement: Lista vazia não desliga o filtro em silêncio

Com a lista vazia, o sistema DEVE aceitar toda mensagem — mas essa passagem
DEVE ser consequência de uma lista vazia de verdade, nunca de a consulta à
lista ter falhado ou ter sido bloqueada.

É o modo de falha que `20260806090000` documenta e corrige para os nomes: RLS
sem policy não levanta erro, devolve zero linhas, e a moderação some sem nada
ficar vermelho.

#### Scenario: Lista vazia
- **WHEN** a lista não tem nenhuma palavra
- **THEN** toda mensagem é aceita

#### Scenario: Filtro rodando sob papel sem acesso à lista
- **WHEN** o filtro é executado por um papel que não tem permissão de ler a
  tabela da lista
- **THEN** ele continua enxergando a lista completa e recusando o que deve
- **AND** não passa a aceitar tudo
