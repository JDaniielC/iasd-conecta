## Purpose

Quem enxerga uma Ação. Hoje a resposta é "todo mundo, inclusive sem login";
esta capability introduz a Ação restrita ao Grupo e define até onde a restrição
alcança — a Ação, a lista de quem vai, a contagem, o destaque e a Rodada de
votação.

## ADDED Requirements

### Requirement: Ação é pública por padrão

Toda Ação DEVE continuar visível para qualquer pessoa, com ou sem login, a
menos que quem a cria marque explicitamente a restrição ao Grupo. Nenhuma Ação
já existente DEVE sumir do feed de ninguém quando esta mudança entrar.

#### Scenario: Ação que já existia continua visível

- **WHEN** a mudança entra em produção sobre a base atual
- **THEN** toda Ação que já existia continua aparecendo em `/acoes` para quem
  está sem login, como antes

#### Scenario: Ação nova nasce pública

- **WHEN** alguém cria uma Ação sem marcar a restrição
- **THEN** ela aparece para qualquer pessoa, inclusive sem login

### Requirement: Só Ação de Grupo pode ser restrita

A restrição DEVE estar disponível apenas para Ação vinculada a um Grupo. Ação
avulsa NÃO DEVE poder ser restrita — não existe a quem restringir. O banco DEVE
recusar a combinação, e a tela NÃO DEVE oferecer o controle quando não há Grupo
escolhido.

#### Scenario: Tela esconde o controle na Ação avulsa

- **WHEN** alguém está criando uma Ação e não escolheu Grupo
- **THEN** o controle de restrição não aparece, ou aparece desabilitado com a
  explicação de que depende de um Grupo

#### Scenario: Banco recusa Ação avulsa restrita

- **WHEN** uma chamada direta à API tenta criar uma Ação sem Grupo e com a
  restrição marcada
- **THEN** o banco recusa a escrita

### Requirement: Quem não participa do Grupo não vê a Ação restrita

Uma Ação restrita NÃO DEVE ser legível por quem não participa do Grupo dono
dela, nem por sessão anônima. A garantia DEVE estar na policy de leitura do
banco, não no filtro da tela: a API REST é pública e responde a chamada direta.

#### Scenario: Chamada direta não devolve Ação restrita

- **WHEN** uma sessão autenticada que não participa do Grupo pede a lista de
  Ações direto pela API
- **THEN** a Ação restrita não vem na resposta

#### Scenario: Sessão anônima não vê Ação restrita

- **WHEN** uma sessão `anon` pede a lista de Ações
- **THEN** nenhuma Ação restrita vem na resposta

#### Scenario: Quem participa vê normalmente

- **WHEN** alguém que participa do Grupo abre `/acoes`
- **THEN** a Ação restrita aparece junto das demais, com uma marca visível de
  que é restrita ao Grupo

#### Scenario: Link direto para Ação restrita

- **WHEN** alguém que não participa do Grupo abre a rota da Ação restrita pelo
  id
- **THEN** vê a tela de Ação não encontrada, sem revelar nome, data, local nem
  a existência da Ação

### Requirement: A restrição alcança quem vai, não só a Ação

Esconder a Ação e deixar aberta a lista de presença seria vazamento por porta
lateral: a lista revela a existência da Ação e quem estará lá. As confirmações
de presença de uma Ação restrita NÃO DEVEM ser legíveis por quem não participa
do Grupo, nem por sessão anônima.

#### Scenario: Lista de presença da Ação restrita não vaza

- **WHEN** uma sessão que não participa do Grupo pede as confirmações daquela
  Ação pela API, pelo id da Ação
- **THEN** a resposta vem vazia

#### Scenario: Confirmações de Ação pública seguem legíveis

- **WHEN** qualquer sessão, inclusive anônima, pede as confirmações de uma Ação
  pública
- **THEN** a resposta vem completa, como antes desta mudança

### Requirement: A restrição alcança a Rodada de votação

Ação candidata restrita NÃO DEVE reaparecer para quem não participa do Grupo
pela tela de Rodada de votação, nem na lista de candidatas, nem como vencedora.

#### Scenario: Candidata restrita não aparece para quem é de fora

- **WHEN** alguém que não participa do Grupo abre uma Rodada que tem candidata
  restrita
- **THEN** aquela candidata não aparece na lista

#### Scenario: Vencedora restrita não vaza pela Rodada

- **WHEN** a candidata vencedora de uma Rodada é restrita e alguém de fora do
  Grupo abre a Rodada
- **THEN** a tela não revela nome, data nem local da vencedora

### Requirement: Quem restringe é quem criou a Ação

Só quem criou a Ação DEVE conseguir marcar ou desmarcar a restrição. Ser Líder
confirmado NÃO DEVE ser exigido: liderança é o caso de uso que motivou o
pedido, mas prender o mecanismo a ela tiraria do participante comum a
possibilidade de marcar algo interno do próprio Grupo.

A restrição DEVE poder ser mudada depois de criada, nos dois sentidos, enquanto
a Ação não estiver encerrada.

#### Scenario: Terceiro não muda a restrição

- **WHEN** alguém que não criou a Ação tenta marcar a restrição pela API
- **THEN** a escrita é recusada

#### Scenario: Fechar uma Ação que estava pública

- **WHEN** quem criou uma Ação pública de Grupo marca a restrição
- **THEN** a Ação some do feed de quem não participa do Grupo, e continua no de
  quem participa

#### Scenario: Abrir uma Ação que estava restrita

- **WHEN** quem criou marca a Ação restrita como pública de novo
- **THEN** ela passa a aparecer para todo mundo, e quem já tinha confirmado
  presença continua confirmado

#### Scenario: Quem confirmou e depois perdeu o acesso

- **WHEN** alguém confirma presença numa Ação de Grupo pública, ela é depois
  marcada como restrita, e essa pessoa não participa do Grupo
- **THEN** ela deixa de ver a Ação, e a confirmação dela continua contando para
  quem participa — a vaga não é devolvida em silêncio

### Requirement: Sair do Grupo tira o acesso à Ação restrita

Participação é a chave da restrição, então perder a participação DEVE tirar o
acesso na hora, sem depender de recarregar o app.

#### Scenario: Sair do Grupo esconde a Ação restrita

- **WHEN** alguém sai de um Grupo que tem Ação restrita
- **THEN** aquela Ação deixa de vir nas leituras seguintes, inclusive por
  chamada direta à API

#### Scenario: Ser removido pelo Dono esconde a Ação restrita

- **WHEN** o Dono remove alguém do Grupo
- **THEN** a pessoa removida deixa de enxergar as Ações restritas daquele Grupo

#### Scenario: Grupo arquivado mantém a restrição

- **WHEN** um Grupo com Ação restrita é arquivado
- **THEN** a Ação restrita continua visível apenas para quem participava do
  Grupo, e continua invisível para quem não participava

### Requirement: Ação restrita não aparece em destaque, contagem nem busca de quem não participa

Nenhuma outra tela DEVE reintroduzir a Ação restrita para quem não participa —
nem faixa de destaque, nem contagem de Ações, nem qualquer listagem por
período. Onde houver contagem, o número DEVE bater com o que a pessoa consegue
abrir.

#### Scenario: Destaque não mostra Ação restrita a quem é de fora

- **WHEN** alguém que não participa do Grupo abre `/acoes`
- **THEN** a Ação restrita não aparece na faixa de destaque nem na lista por
  período

#### Scenario: Contagem bate com o que dá pra abrir

- **WHEN** uma tela mostra quantas Ações existem num período em que há Ação
  restrita de Grupo alheio
- **THEN** o número não conta a Ação restrita

### Requirement: Convidar para Ação restrita só alcança quem participa do Grupo

Quando existir convite para Ação (capability `convite-para-acao`), convidar
para uma Ação restrita NÃO DEVE alcançar quem não participa do Grupo dono da
Ação. Um convite para algo que a pessoa não consegue abrir é um convite morto,
e ainda revela que a Ação existe.

#### Scenario: Lista de convite de Ação restrita fica no Grupo

- **WHEN** quem criou uma Ação restrita abre a tela de convidar
- **THEN** só aparece a seção do Grupo dono da Ação, com a explicação de que a
  Ação é restrita a ele

#### Scenario: Convite direto para pessoa de fora é recusado

- **WHEN** uma chamada direta tenta criar convite de Ação restrita para alguém
  que não participa do Grupo
- **THEN** a escrita é recusada
