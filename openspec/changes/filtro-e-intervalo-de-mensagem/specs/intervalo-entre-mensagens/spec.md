## Purpose

Limitar o ritmo com que uma pessoa manda mensagem, para que encher um chat
deixe de ser possível — e para que a moderação humana não vire remover mensagem
uma a uma.

## ADDED Requirements

### Requirement: Há intervalo mínimo entre duas mensagens da mesma pessoa

O sistema NÃO DEVE aceitar mensagem enviada antes de decorrido o intervalo
mínimo desde a última mensagem da mesma pessoa no mesmo chat.

O intervalo é por pessoa e por chat: conversar em dois Grupos ao mesmo tempo é
uso normal, e um limite global puniria isso.

#### Scenario: Duas mensagens em sequência rápida
- **WHEN** alguém envia uma mensagem e tenta enviar outra no mesmo chat antes
  do intervalo
- **THEN** a segunda é recusada
- **AND** a primeira continua gravada

#### Scenario: Envio depois do intervalo
- **WHEN** alguém envia a segunda mensagem depois de decorrido o intervalo
- **THEN** ela é aceita

#### Scenario: Dois chats ao mesmo tempo
- **WHEN** alguém envia uma mensagem num Grupo e, em seguida, uma em outro
  Grupo
- **THEN** as duas são aceitas — o intervalo de um chat não conta no outro

### Requirement: Há teto de mensagens por janela de tempo

O sistema NÃO DEVE aceitar mais que o teto de mensagens da mesma pessoa no
mesmo chat dentro da janela de tempo, mesmo que cada uma respeite o intervalo
mínimo.

O intervalo sozinho não impede encher o chat; só torna o processo mais lento.

#### Scenario: Teto atingido
- **WHEN** alguém envia o número máximo de mensagens permitido na janela,
  todas respeitando o intervalo mínimo
- **THEN** a mensagem seguinte é recusada

#### Scenario: Janela deslizou
- **WHEN** as mensagens mais antigas saem da janela
- **THEN** a pessoa volta a poder enviar

### Requirement: O limite vale no banco, não na tela

O sistema DEVE recusar no banco. Uma chamada direta à API, sem passar pela
tela, NÃO DEVE conseguir ultrapassar o limite.

Duas escritas simultâneas da mesma pessoa NÃO DEVEM passar as duas por lerem o
mesmo estado anterior.

#### Scenario: Chamada direta à API
- **WHEN** alguém envia mensagens direto pela API, sem intervalo
- **THEN** são recusadas a partir da segunda, igual pela tela

#### Scenario: Duas escritas simultâneas
- **WHEN** duas mensagens da mesma pessoa no mesmo chat chegam ao mesmo tempo
- **THEN** exatamente uma é gravada

### Requirement: A recusa por ritmo diz quanto falta esperar

O sistema DEVE informar a quem enviou quanto tempo falta, e a tela DEVE
impedir o reenvio até lá em vez de deixar a pessoa tentar de novo e ser
recusada de novo.

#### Scenario: Recusa por intervalo
- **WHEN** a mensagem é recusada por não ter decorrido o intervalo
- **THEN** a tela mostra o tempo restante
- **AND** o texto digitado não se perde

#### Scenario: Recusa por teto
- **WHEN** a mensagem é recusada por teto na janela
- **THEN** a tela distingue esse caso do intervalo, com o tempo até liberar

### Requirement: Nenhum dado novo é guardado para contar o ritmo

O sistema NÃO DEVE gravar contador, tentativa recusada, histórico de envio nem
qualquer registro criado só para aplicar o limite. A contagem DEVE sair do
`created_at` que as mensagens já têm.

Contador de tentativa é dado de comportamento — quando esta pessoa tentou
falar, e quantas vezes. O projeto já recusou por escrito criar dado desse tipo
por conveniência (`lib/features/news/data/news_repository.dart:7-16`).

#### Scenario: Mensagem recusada pelo ritmo
- **WHEN** uma mensagem é recusada por intervalo ou por teto
- **THEN** nada é gravado em lugar nenhum sobre a tentativa

#### Scenario: Mensagens do chat foram expurgadas
- **WHEN** as mensagens de uma Ação expiram e são apagadas
- **THEN** o limite volta a permitir o envio, porque não há mais o que contar
- **AND** isso é aceitável: o chat expirado não é chat que se possa encher
