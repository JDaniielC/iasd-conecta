# Feature Specification: Grupos

**Feature Branch**: `002-grupos`

**Created**: 2026-07-23

**Status**: Draft

**Input**: User description: "Grupos: Usuário cria um Grupo (nome, Categoria de Grupo, horário padrão de encontro recorrente, local, detalhes, Igreja limitada à do próprio criador) e vira automaticamente o Dono do Grupo. Qualquer Usuário pode descobrir Grupos e Participar do Grupo (associação leve e revogável — entra e sai quando quiser), ganhando o direito de aparecer identificado no Grupo. Dono do Grupo pode editar nome/horário/local/detalhes, remover participante, e transferir a posse do Grupo pra outro participante. Visitante sem cadastro pode ver a lista de Grupos e os detalhes de cada um livremente, mas não participar. Fora de escopo aqui: Ação candidata, Rodada de votação e Votar (feature futura separada)."

## Clarifications

### Session 2026-07-23

- Q: Grupo pode ser encerrado/excluído pelo Dono ou pelo Administrador do
  distrito? → A: Não, fora de escopo nesta feature. Grupo criado nunca é
  excluído/encerrado pelo app; decidir isso exigiria antecipar regras de
  Rodada de votação/Ação de Grupo (feature futura, ainda não especificada).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Criar Grupo (Priority: P1)

Um Usuário cria um Grupo pra organizar uma comunidade permanente em torno de
uma atividade recorrente (ex: SevenBikers, um clube de Desbravadores). Ele
informa nome, Categoria de Grupo, horário padrão de encontro, local e
detalhes; a Igreja do Grupo é sempre a do próprio criador. Ao criar, ele vira
automaticamente o Dono do Grupo.

**Why this priority**: sem Grupo, não existe nada pra descobrir ou participar
— é a fundação desta feature.

**Independent Test**: pode ser testado sozinho criando um Grupo do zero e
confirmando que ele aparece na lista de Grupos com o criador como Dono.

**Acceptance Scenarios**:

1. **Given** um Usuário com Perfil, **When** ele preenche nome, Categoria,
   horário, local e detalhes e confirma, **Then** o Grupo é criado com a
   Igreja do próprio criador e ele vira o Dono do Grupo.
2. **Given** um Usuário criando um Grupo, **When** ele tenta enviar sem nome
   ou sem Categoria, **Then** o sistema bloqueia a criação.
3. **Given** um Grupo recém-criado, **When** qualquer pessoa (Usuário ou
   Visitante) abre a lista de Grupos, **Then** o novo Grupo aparece nela.

---

### User Story 2 - Descobrir e participar de Grupo (Priority: P1)

Qualquer pessoa — cadastrada ou não — navega pela lista de Grupos e vê os
detalhes de cada um. Um Usuário cadastrado pode Participar do Grupo (entrar),
passando a aparecer identificado nele, e pode sair quando quiser.

**Why this priority**: é o valor central pro Usuário comum — descobrir e se
associar a Grupos é o motivo do app existir. Fica no mesmo nível de
prioridade da criação porque um sem o outro não entrega nada.

**Independent Test**: pode ser testado sozinho abrindo a lista de Grupos sem
estar logado, confirmando que os detalhes aparecem, depois virando Usuário e
confirmando que dá pra Participar e depois sair do Grupo.

**Acceptance Scenarios**:

1. **Given** um Visitante sem cadastro, **When** ele abre a lista de Grupos
   ou os detalhes de um Grupo específico, **Then** ele vê tudo livremente,
   sem precisar de Perfil.
2. **Given** um Visitante olhando um Grupo, **When** ele tenta Participar,
   **Then** o sistema direciona pro cadastro de Perfil antes de permitir.
3. **Given** um Usuário com Perfil, **When** ele opta por Participar de um
   Grupo, **Then** ele passa a aparecer na lista de participantes do Grupo.
4. **Given** um Usuário que participa de um Grupo, **When** ele opta por
   sair, **Then** ele deixa de aparecer na lista de participantes
   imediatamente, e pode Participar de novo depois se quiser.

---

### User Story 3 - Dono do Grupo administra (Priority: P2)

O Dono do Grupo edita nome, horário, local e detalhes, remove um participante
indesejado, e pode transferir a posse do Grupo pra outro participante quando
quiser parar de administrar.

**Why this priority**: é essencial pra manutenção do Grupo ao longo do tempo,
mas o Grupo já entrega valor (P1) mesmo antes de qualquer edição acontecer.

**Independent Test**: pode ser testado sozinho criando um Grupo, editando um
campo, removendo um participante de teste, e transferindo a posse — sem
depender de Ação/votação.

**Acceptance Scenarios**:

1. **Given** o Dono de um Grupo, **When** ele edita nome/horário/local/
   detalhes, **Then** a mudança aparece pra todo mundo que vê o Grupo.
2. **Given** o Dono de um Grupo, **When** ele remove um participante,
   **Then** essa pessoa deixa de aparecer na lista de participantes e perde
   os direitos de quem participa (mas pode Participar de novo depois).
3. **Given** o Dono de um Grupo, **When** ele transfere a posse pra outro
   participante, **Then** esse participante vira o novo Dono e o antigo Dono
   vira um participante comum (continua no Grupo, sem privilégio de Dono).
4. **Given** um Usuário que não é o Dono, **When** ele tenta editar o Grupo,
   remover alguém, ou transferir a posse, **Then** o sistema recusa.

### Edge Cases

- Dono do Grupo tenta transferir a posse pra alguém que não participa do
  Grupo: sistema recusa — só dá pra transferir pra quem já participa.
- Dono do Grupo sai do próprio Grupo (deixa de participar) sem transferir a
  posse antes: sistema impede a saída até ele transferir pra outro
  participante, ou recusa a saída se não houver ninguém pra transferir
  (Grupo fica sem Dono sem essa garantia).
- Usuário tenta Participar de um Grupo do qual já participa: sistema trata
  como não-operação, sem duplicar a associação.
- Grupo fica sem nenhum participante além do Dono, e o Dono tenta sair:
  mesma regra acima — precisa transferir antes, e só existe alguém pra
  transferir se houver outro participante.
- Igreja do criador muda depois (ex.: pessoa se desvincula da Igreja no
  Perfil): a Igreja do Grupo já criado não muda retroativamente.
- Criador não tem Igreja de origem definida no Perfil (campo em branco): o
  Grupo criado também fica sem Igreja — não é obrigatório escolher uma.
- Não existe operação de excluir/encerrar Grupo nesta feature: um Grupo
  criado permanece visível e listável indefinidamente (ver Clarifications).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que um Usuário com Perfil crie um Grupo
  informando nome, Categoria de Grupo, horário padrão de encontro
  (recorrente), local e detalhes — todos obrigatórios exceto detalhes.
- **FR-002**: Sistema DEVE atribuir ao Grupo criado a Igreja do próprio
  criador (a que estiver no Perfil dele no momento da criação, podendo ser
  nenhuma se o criador não tiver Igreja definida), sem permitir escolher
  outra.
- **FR-003**: Sistema DEVE tornar automaticamente o criador de um Grupo o seu
  Dono do Grupo.
- **FR-004**: Sistema DEVE restringir a Categoria de Grupo à lista de
  referência (ver CATEGORIAS-DE-ACAO.md), mas permitir nome livre quando a
  pessoa não encontrar uma categoria adequada.
- **FR-005**: Sistema DEVE permitir que qualquer pessoa — Visitante ou
  Usuário — veja a lista de Grupos e os detalhes de qualquer Grupo
  individual, sem exigir Perfil.
- **FR-006**: Sistema DEVE permitir que um Usuário com Perfil Participe de
  um Grupo (associação leve e revogável), passando a aparecer identificado
  na lista de participantes desse Grupo.
- **FR-007**: Sistema DEVE permitir que um Usuário que participa de um Grupo
  saia quando quiser, deixando de aparecer na lista de participantes.
- **FR-008**: Sistema DEVE impedir que um Visitante sem Perfil participe de
  um Grupo, direcionando-o ao cadastro quando tentar.
- **FR-009**: Sistema DEVE permitir que somente o Dono do Grupo edite
  nome, Categoria, horário, local e detalhes do Grupo.
- **FR-010**: Sistema DEVE permitir que somente o Dono do Grupo remova um
  participante do Grupo.
- **FR-011**: Sistema DEVE permitir que somente o Dono do Grupo transfira a
  posse do Grupo para outro participante que já participa do Grupo.
- **FR-012**: Sistema DEVE impedir que o Dono do Grupo saia do próprio Grupo
  sem antes transferir a posse para outro participante.
- **FR-013**: Sistema DEVE tratar uma tentativa de Participar de um Grupo do
  qual a pessoa já participa como não-operação (sem erro, sem duplicar).

### Key Entities

- **Grupo**: nome, Categoria de Grupo, horário padrão de encontro
  (recorrente), local, detalhes (opcional), Igreja (herdada do criador no
  momento da criação, fixa depois), Dono do Grupo (um Usuário).
- **Participação em Grupo**: associação entre um Usuário e um Grupo — leve,
  revogável, sem outros atributos além de quem e qual Grupo.
- **Categoria de Grupo**: nome de categoria, da lista de referência ou livre.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um Usuário consegue criar um Grupo em menos de 2 minutos.
- **SC-002**: Visitantes conseguem ver a lista completa de Grupos e os
  detalhes de qualquer um deles sem nenhuma barreira de cadastro.
- **SC-003**: Participar ou sair de um Grupo reflete na lista de
  participantes em menos de 2 segundos após a ação.
- **SC-004**: 100% das tentativas de edição, remoção de participante ou
  transferência de posse por quem não é o Dono são recusadas.
- **SC-005**: 0% dos Grupos ficam sem Dono em qualquer momento (garantido
  pela regra de transferência obrigatória antes de sair).

## Assumptions

- Um Usuário pode criar e participar de quantos Grupos quiser — sem limite
  nesta feature.
- Um Usuário pode ser Dono de mais de um Grupo simultaneamente.
- Não há aprovação do Dono para alguém Participar — é auto-serviço, qualquer
  Usuário entra livremente (a associação "leve" do glossário implica isso).
- Edição do Grupo pelo Dono não exige confirmação adicional além da própria
  ação (sem fluxo de aprovação).
- Notificar participantes sobre edições do Grupo fica fora de escopo desta
  feature (feature futura de notificações, se vier a existir).
- Busca/filtro avançado na lista de Grupos (por Categoria, Igreja, etc.) é
  desejável mas não obrigatório nesta versão — listagem simples já atende.
