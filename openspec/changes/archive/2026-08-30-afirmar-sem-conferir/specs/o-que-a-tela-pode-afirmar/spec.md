## Purpose

O que uma tela tem o direito de dizer que aconteceu. No Postgres uma policy que
recusa não levanta erro — ela faz a linha não existir para aquela sessão — então
"deu certo" e "não alcancei nada" chegam ao cliente exatamente iguais. Esta
capability diz o que precisa ser conferido antes de a tela afirmar qualquer
coisa, e o que ela mostra quando a conferência falha.

## ADDED Requirements

### Requirement: Escrita do cliente confere quantas linhas afetou

Todo `update` ou `delete` que o cliente manda ao Supabase DEVE pedir as linhas
afetadas de volta e olhar o resultado.

Quando a escrita não alcança linha nenhuma e isso não é um resultado esperado
(ver a requirement seguinte), o método DEVE lançar, e a mensagem DEVE ser a
frase que a tela mostra à pessoa — não um código, não o nome da tabela.

A regra vale para escrita do cliente. Dentro de função `security definer` a RLS
não se aplica, e lá o que precisa de checagem explícita é a autoridade de quem
chamou — essas funções levantam, e quem as chama trata a exceção.

#### Scenario: A policy recusa uma remoção

- **WHEN** alguém sem autoridade sobre a linha manda removê-la
- **THEN** a escrita afeta zero linhas e não levanta erro no banco
- **AND** o método do cliente lança, e a tela mostra que não deu

#### Scenario: A escrita alcança a linha

- **WHEN** quem tem autoridade manda a mesma escrita
- **THEN** ela afeta a linha e o método retorna sem erro

#### Scenario: A tela não apresenta como feito o que não foi

- **WHEN** uma escrita é recusada
- **THEN** a tela NÃO DEVE recarregar a lista como se a operação tivesse
  acontecido, nem fechar a tela, nem mostrar confirmação
- **AND** o que estava na tela antes continua lá, junto do aviso

### Requirement: Zero linhas é resultado esperado quando o filtro já exige a mudança

Uma escrita PODE legitimamente afetar zero linhas, e nesse caso NÃO DEVE lançar,
quando o próprio filtro carrega a condição que ela vai mudar — ou quando a
operação é a remoção do próprio vínculo de quem chamou.

Nesses casos zero quer dizer **"já estava assim"**, que é o resultado que a
pessoa queria. Lançar ali transformaria uma repetição inofensiva em erro.

Cada escrita nessa situação DEVE carregar, escrita no código, a razão de zero
ser aceitável ali. Sem essa frase a próxima pessoa não distingue "decidido" de
"esquecido" — e foi de "esquecido" que vieram os casos da requirement anterior.

#### Scenario: Marcar como lido o que já estava lido

- **WHEN** a escrita filtra pelas linhas ainda não lidas e todas já estão lidas
- **THEN** zero linhas é sucesso, e a tela não mostra erro

#### Scenario: Resolver uma denúncia que outra pessoa já resolveu

- **WHEN** a escrita filtra pelo estado pendente e a linha já saiu daquele estado
- **THEN** zero linhas é sucesso — a corrida entre duas pessoas moderando
  terminou, e terminou bem

#### Scenario: Sair de um espaço do qual já não se participa

- **WHEN** alguém pede para sair e já não está lá
- **THEN** zero linhas é sucesso
- **AND** quando a saída é barrada por uma regra do banco, ela chega como erro
  levantado, não como zero linhas

### Requirement: Zero ambíguo é desambiguado antes de virar frase

Quando zero linhas pode significar tanto "já estava assim" quanto "a regra
recusou", a contagem sozinha NÃO basta, e o método NÃO DEVE escolher uma das
duas por padrão.

O caso conhecido é desistir de participar de uma Ação: a policy recusa quando a
Ação já encerrou, e quem nunca confirmou presença também afeta zero linhas. As
duas coisas são opostas para quem está olhando a tela — numa ela não precisava
fazer nada, na outra ela continua contando como presente num encontro que
acabou.

O método DEVE distinguir as duas antes de decidir o que dizer, e a frase de cada
uma DEVE ser diferente.

#### Scenario: Desistir de uma Ação que já encerrou

- **WHEN** alguém confirmada tenta desistir depois do encerramento
- **THEN** a tela diz que a Ação já encerrou e que a presença continua registrada
- **AND** NÃO diz que a desistência foi feita

#### Scenario: Desistir sem nunca ter confirmado

- **WHEN** alguém que não estava confirmada pede para desistir de uma Ação aberta
- **THEN** não há erro, e a tela mostra o estado real: essa pessoa não está
  confirmada

### Requirement: Decisão sobre resposta que ainda não chegou é explícita

Uma decisão que depende de dado carregado de forma assíncrona NÃO DEVE ser
tomada a partir do valor ainda ausente como se ele fosse a resposta.

Em particular, um gate que decide se a pessoa pode seguir com uma ação DEVE
esperar a resposta chegar. Tratar "ainda não sei" como "não" manda ao cadastro
quem já tem cadastro; tratar como "sim" libera quem não devia — as duas são
respostas inventadas sobre uma pergunta ainda não respondida.

A corretude desse gate NÃO DEVE depender de outro arquivo ter carregado o dado
antes por conta própria. Quem depende de uma linha distante para estar certo
está certo por acidente, e o acidente termina quando alguém edita aquela linha
sem saber que ela sustenta isto.

#### Scenario: A pessoa aciona a ação antes de o dado chegar

- **WHEN** alguém com cadastro aciona uma ação que exige cadastro, e a resposta
  sobre o cadastro ainda não chegou
- **THEN** o gate espera a resposta e deixa a ação seguir
- **AND** a pessoa NÃO é mandada ao cadastro

#### Scenario: A pessoa realmente não tem cadastro

- **WHEN** alguém sem cadastro aciona a mesma ação
- **THEN** o gate espera a resposta, e só então direciona ao cadastro

#### Scenario: O gate sozinho, sem ninguém ter carregado o dado antes

- **WHEN** o gate é exercitado sem que nenhuma outra parte do app tenha lido o
  dado antes
- **THEN** ele decide certo mesmo assim
