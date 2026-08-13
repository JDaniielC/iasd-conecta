# visibilidade-de-acao Specification

## Purpose

Quem enxerga uma Ação. Hoje a resposta é "todo mundo, inclusive sem login";
esta capability introduz a Ação restrita ao Grupo e define até onde a restrição
alcança — a Ação, a lista de quem vai, a contagem, o destaque e a Rodada de
votação.

## Requirements

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
recusar a combinação.

Neste app, Ação de Grupo quer dizer **candidata de uma Rodada de votação** e a
Ação que vence essa Rodada: são a mesma linha, e é o único caminho pelo qual uma
Ação ganha Grupo (`acoes_candidata_checar_regras` recusa `grupo_id` sem
`rodada_id`, e deriva o Grupo da Rodada). Logo o controle de restrição DEVE
ficar na tela de propor candidata, e a tela de criar Ação avulsa NÃO DEVE
oferecê-lo — ali não existe Grupo a escolher.

#### Scenario: Criar Ação avulsa não oferece restrição

- **WHEN** alguém abre a tela de criar Ação
- **THEN** não há controle de restrição, porque toda Ação criada por ali é
  avulsa

#### Scenario: Propor candidata oferece a restrição

- **WHEN** alguém propõe uma Ação candidata numa Rodada do Grupo
- **THEN** o controle de restrição aparece, com a explicação de que a Ação some
  do feed de quem não participa daquele Grupo

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

### Requirement: Quem edita a Ação é quem restringe

A restrição NÃO DEVE ganhar regra de escrita própria: quem pode marcar ou
desmarcar é exatamente quem já pode editar a Ação por
`acoes_update_criador_dono_grupo_ou_admin`
(`20260724092132_district_admin.sql`) — quem criou a Ação, o Dono do Grupo dela
e o Administrador do distrito. Quem não está nessa lista NÃO DEVE conseguir
mexer na restrição.

Ser Líder confirmado NÃO DEVE ser exigido: liderança é o caso de uso que
motivou o pedido, mas prender o mecanismo a ela tiraria do participante comum a
possibilidade de marcar algo interno do próprio Grupo.

A restrição DEVE poder ser mudada depois de criada, nos dois sentidos, enquanto
a Ação não estiver encerrada.

#### Scenario: Quem não edita a Ação não muda a restrição

- **WHEN** alguém que não criou a Ação, não é Dono do Grupo dela e não é
  Administrador do distrito tenta marcar a restrição pela API
- **THEN** a escrita é recusada

#### Scenario: Dono do Grupo fecha Ação criada por outra pessoa

- **WHEN** o Dono do Grupo marca a restrição numa Ação do Grupo dele criada por
  um participante
- **THEN** a escrita é aceita, pela mesma permissão que já o deixa editar o
  resto daquela Ação

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

### Requirement: O Administrador do distrito não fecha, mas reabre sem filtro

O Administrador do distrito NÃO DEVE ganhar leitura de Ação restrita. Não
existe `bypass` de RLS de leitura em lugar nenhum deste app, e criar o primeiro
aqui abriria acesso amplo sem que ninguém tenha pedido moderação de Ação de
Grupo.

Ele continua na policy de `update`, porque ela é uma só e esta mudança não a
divide. O que isso permite e o que não permite DEVE ser conhecido e verificado,
nunca descoberto em produção.

Medido contra o Postgres local, e é o próprio banco que fecha o lado perigoso:
a policy de `select` também vale como `with check` implícito do `update`, então
**ninguém consegue tornar restrita uma Ação que passaria a não enxergar** — a
escrita é recusada com `new row violates row-level security policy`. Fechar só
é possível para quem participa do Grupo, e quem participa continua vendo.

Fica de pé o sentido inverso: a policy de `select` alcança o `update` só quando
a escrita tem filtro. Com `where`, a linha invisível não é encontrada
(`0` linhas); sem filtro nenhum, a escrita alcança a linha invisível — e
desmarcar a restrição deixa a linha mais visível, não menos, então o
`with check` implícito não barra.

#### Scenario: Administrador não restringe Ação de Grupo do qual não participa

- **WHEN** o Administrador do distrito tenta marcar a restrição numa Ação de
  Grupo do qual não participa
- **THEN** a escrita é recusada pelo banco, porque a linha resultante seria
  invisível para quem a escreveu

#### Scenario: Administrador não reabre pelo id o que não enxerga

- **WHEN** o Administrador pede a reabertura de uma Ação restrita pelo id dela
- **THEN** nenhuma linha é afetada, porque o filtro traz junto a regra de
  leitura

#### Scenario: Escrita sem filtro reabre a Ação restrita

- **WHEN** o Administrador manda uma escrita de `restrita_ao_grupo` sem filtro
  nenhum
- **THEN** toda Ação restrita do distrito é reaberta, inclusive a que ele nunca
  pôde ler — dívida aceita e registrada em `SECURITY-AUDIT.md`, não defeito a
  corrigir nesta change

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
