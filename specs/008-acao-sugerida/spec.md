# Feature Specification: Ação Sugerida

**Feature Branch**: `008-acao-sugerida`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Ação sugerida: nome de Ação pré-cadastrado, associado a uma Categoria de Grupo, oferecido como atalho na hora de criar uma Ação avulsa ou propor uma Ação candidata (ex: \"Ensaio\", \"Culto Jovem\", \"Acampamento\" — lista de referência em CATEGORIAS-DE-ACAO.md). Não obriga: quem cria sempre pode digitar um nome livre em vez de escolher uma sugestão. Ao propor uma Ação candidata dentro de um Grupo, as sugestões vêm automaticamente da Categoria do próprio Grupo (sem escolha extra). Ao criar uma Ação avulsa (sem Grupo), quem cria escolhe uma Categoria de Grupo só pra filtrar quais sugestões aparecem — essa escolha não fica salva na Ação avulsa em si, é só um filtro de tela, já que Ação avulsa não tem Categoria como atributo no domínio. O Administrador do distrito é quem cadastra/mantém a lista de Ações sugeridas (mesmo papel que já mantém a lista de Categorias de Grupo e Igrejas). Stack: Flutter + Dart + Supabase, mesma base das features anteriores — código Dart novo em inglês (constituição v1.1.0), banco em português."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sugestão automática ao propor Ação candidata (Priority: P1)

Ao propor uma Ação candidata dentro de um Grupo, quem propõe vê uma lista
de nomes sugeridos, vinda automaticamente da Categoria do próprio Grupo —
sem precisar escolher a Categoria de novo.

**Why this priority**: é o caso de uso mais frequente (toda Ação de Grupo
nasce como candidata) e o mais simples de entregar valor — a Categoria já
existe no contexto, só falta aproveitá-la.

**Independent Test**: pode ser testado sozinho com Ações sugeridas já
cadastradas pra uma Categoria, propondo uma candidata num Grupo dessa
Categoria e conferindo que as sugestões aparecem.

**Acceptance Scenarios**:

1. **Given** um Grupo de uma Categoria com Ações sugeridas cadastradas,
   **When** um participante propõe uma Ação candidata nesse Grupo,
   **Then** as sugestões daquela Categoria aparecem como atalho.
2. **Given** uma Categoria sem nenhuma Ação sugerida cadastrada, **When**
   alguém propõe uma candidata num Grupo dessa Categoria, **Then** nenhuma
   sugestão aparece, e digitar um nome livre continua funcionando
   normalmente.
3. **Given** as sugestões exibidas, **When** quem propõe prefere digitar um
   nome que não está na lista, **Then** o sistema aceita normalmente — a
   sugestão nunca é obrigatória.

---

### User Story 2 - Sugestão filtrada por Categoria ao criar Ação avulsa (Priority: P2)

Ao criar uma Ação avulsa (sem Grupo), quem cria escolhe uma Categoria de
Grupo só pra filtrar quais sugestões aparecem — essa escolha não é salva
na Ação avulsa, é usada só na hora de montar a lista de sugestões.

**Why this priority**: mesmo valor do US1, mas pra um fluxo sem Grupo
associado — depende do US1 já existir (a fonte de sugestões é a mesma),
por isso prioridade um degrau abaixo.

**Independent Test**: pode ser testado sozinho escolhendo uma Categoria na
tela de criar Ação avulsa e conferindo que só as sugestões daquela
Categoria aparecem, sem a Ação avulsa criada ganhar nenhum campo de
Categoria.

**Acceptance Scenarios**:

1. **Given** a tela de criar Ação avulsa, **When** quem cria escolhe uma
   Categoria de Grupo, **Then** aparecem só as sugestões daquela
   Categoria.
2. **Given** uma Ação avulsa criada depois de escolher uma Categoria pra
   filtrar sugestões, **When** alguém consulta os dados da Ação avulsa
   salva, **Then** nenhuma Categoria aparece associada a ela — a escolha
   era só um filtro de tela.
3. **Given** a tela de criar Ação avulsa, **When** quem cria não escolhe
   nenhuma Categoria, **Then** nenhuma sugestão aparece, e o campo de nome
   livre continua disponível normalmente.

---

### User Story 3 - Administrador mantém a lista de Ações sugeridas (Priority: P2)

O Administrador do distrito cadastra, edita e remove Ações sugeridas,
cada uma vinculada a uma Categoria de Grupo.

**Why this priority**: sem alguém populando a lista, US1/US2 não têm nada
pra sugerir — mas a prioridade fica abaixo das duas porque o cadastro
inicial pode ser feito uma vez só (seed), enquanto US1/US2 são o valor
recorrente pro dia a dia.

**Independent Test**: pode ser testado sozinho cadastrando uma Ação
sugerida numa Categoria e conferindo que ela aparece na lista mantida
pelo Administrador.

**Acceptance Scenarios**:

1. **Given** o Administrador do distrito, **When** ele cadastra uma nova
   Ação sugerida associada a uma Categoria, **Then** ela passa a aparecer
   nas sugestões daquela Categoria.
2. **Given** uma Ação sugerida já cadastrada, **When** o Administrador a
   remove, **Then** ela para de aparecer nas sugestões, sem afetar
   nenhuma Ação já criada anteriormente a partir dela.
3. **Given** um Usuário que não é Administrador do distrito, **When** ele
   tenta cadastrar ou remover uma Ação sugerida, **Then** o sistema
   recusa.

### Edge Cases

- Duas Ações sugeridas com o mesmo nome em Categorias diferentes (ex.:
  "Retiro" em Ministério da Mulher e em Ministério do Homem): permitido —
  o nome é só texto de atalho, não é identificador único global.
- Remover uma Categoria de Grupo que tem Ações sugeridas associadas: fora
  de escopo desta feature — a feature 002 já não previu remoção de
  Categoria, só cadastro; Ação sugerida segue a mesma regra (sem exclusão
  em cascata a resolver aqui).
- Ação candidata proposta num Grupo cuja Categoria não bate com nenhuma
  Categoria cadastrada (texto livre digitado na criação do Grupo, feature
  002): nenhuma sugestão aparece, mesmo comportamento de uma Categoria sem
  Ações sugeridas.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que o Administrador do distrito
  cadastre uma Ação sugerida com nome e Categoria de Grupo associada.
- **FR-002**: Sistema DEVE permitir que o Administrador do distrito remova
  uma Ação sugerida já cadastrada.
- **FR-003**: Sistema DEVE impedir que qualquer Usuário que não seja
  Administrador do distrito cadastre ou remova uma Ação sugerida.
- **FR-004**: Sistema DEVE exibir, ao propor uma Ação candidata dentro de
  um Grupo, as Ações sugeridas cuja Categoria bate com a Categoria do
  próprio Grupo, sem exigir escolha adicional de quem propõe.
- **FR-005**: Sistema DEVE exibir, ao criar uma Ação avulsa, as Ações
  sugeridas da Categoria de Grupo que quem cria escolher como filtro.
- **FR-006**: Sistema NÃO DEVE persistir a Categoria escolhida como filtro
  na Ação avulsa criada — é usada só pra montar a lista de sugestões na
  tela.
- **FR-007**: Sistema DEVE permitir que quem cria uma Ação (avulsa ou
  candidata) digite um nome livre em vez de escolher uma sugestão, em
  qualquer situação.
- **FR-008**: Sistema DEVE funcionar normalmente sem exibir nenhuma
  sugestão quando a Categoria relevante não tiver nenhuma Ação sugerida
  cadastrada.
- **FR-009**: Sistema DEVE permitir mais de uma Ação sugerida com o mesmo
  nome em Categorias diferentes.

### Key Entities

- **Ação sugerida**: nome de Ação pré-cadastrado, associado a exatamente
  uma Categoria de Grupo; puramente um atalho de preenchimento — não tem
  nenhum efeito sobre a Ação criada a partir dele além de sugerir o nome.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Quem propõe uma Ação candidata vê as sugestões da Categoria
  do Grupo em menos de 1 segundo, sem escolha adicional.
- **SC-002**: 100% das tentativas de cadastrar/remover Ação sugerida por
  quem não é Administrador do distrito são recusadas.
- **SC-003**: 100% das Ações avulsas criadas depois de um filtro de
  Categoria não têm nenhuma Categoria persistida nos seus dados.
- **SC-004**: Quem cria continua conseguindo digitar um nome livre em
  100% dos casos, mesmo quando existem sugestões disponíveis.

## Assumptions

- A lista de Ações sugeridas em `CATEGORIAS-DE-ACAO.md` é a base do
  cadastro inicial (seed), mas o Administrador do distrito pode adicionar
  ou remover itens depois — a lista não é fixa/imutável.
- Ação sugerida não tem edição de nome ou de Categoria depois de
  cadastrada — corrigir um erro é remover e cadastrar de novo (mesmo
  padrão de simplicidade já usado nas features anteriores para entidades
  de cadastro simples).
- Categoria de Grupo (feature 002) já existe e não é alterada por esta
  feature — Ação sugerida só referencia uma Categoria já cadastrada, nunca
  cria uma nova.
