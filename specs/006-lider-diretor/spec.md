# Feature Specification: Líder/Diretor de Ministério

**Feature Branch**: `006-lider-diretor`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Líder/Diretor de Ministério: um Ministério é qualquer Grupo que tem um Líder/Diretor confirmado — não é um tipo separado de Grupo, é o mesmo Grupo com esse papel preenchido. Qualquer Usuário com Conta (Perfil sozinho não basta) se autodeclara Líder/Diretor de um Grupo, pra um ano específico (o ano corrente). Isso cria uma declaração pendente. O Administrador do distrito vê a lista de declarações pendentes de todo o distrito e confirma ou rejeita cada uma — nunca o Dono do Grupo, só Administrador do distrito. Uma vez confirmada, a identificação do Líder/Diretor fica pública na página do Grupo/Ministério, visível até pra Visitante sem cadastro — mostra quem é o responsável perante a igreja, independente de quem é o Dono do Grupo no app (podem ser pessoas diferentes). O título vale só pro ano em que foi confirmado: quando o ano vira (em janeiro), a confirmação anterior não conta mais como atual — precisa autodeclarar de novo pro novo ano e o Administrador do distrito confirmar de novo (sem job agendado: a expiração é resolvida comparando o ano da confirmação com o ano corrente, igual o fechamento preguiçoso da Rodada de votação). Mais de um Usuário pode ser Líder/Diretor confirmado do mesmo Grupo ao mesmo tempo (codireção). Fora de escopo: exigir que quem se autodeclara já participe do Grupo (o texto do domínio não pede essa restrição)."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Autodeclarar Líder/Diretor (Priority: P1)

Um Usuário com Conta se autodeclara Líder/Diretor de um Grupo, pro ano
corrente. Isso cria uma declaração pendente, ainda sem efeito público.

**Why this priority**: sem declaração, não existe nada pra confirmar — é a
fundação desta feature.

**Independent Test**: pode ser testado sozinho autodeclarando Líder de um
Grupo e confirmando que a declaração aparece como pendente.

**Acceptance Scenarios**:

1. **Given** um Usuário com Conta, **When** ele se autodeclara Líder/
   Diretor de um Grupo pro ano corrente, **Then** uma declaração pendente
   é criada.
2. **Given** um Usuário com Perfil (sem Conta), **When** ele tenta se
   autodeclarar, **Then** o sistema recusa.
3. **Given** um Usuário que já se autodeclarou Líder de um Grupo neste ano,
   **When** ele tenta se autodeclarar de novo pro mesmo Grupo e ano,
   **Then** o sistema trata como não-operação.

---

### User Story 2 - Administrador confirma ou rejeita (Priority: P1)

O Administrador do distrito vê a lista de declarações pendentes de todo o
distrito e confirma ou rejeita cada uma.

**Why this priority**: sem confirmação, a autodeclaração da US1 nunca vira
identificação de verdade — as duas juntas formam o mínimo necessário pra a
feature entregar valor.

**Independent Test**: pode ser testado sozinho com uma declaração pendente
já existente, confirmando ou rejeitando, e checando o resultado.

**Acceptance Scenarios**:

1. **Given** uma declaração pendente, **When** o Administrador do distrito
   confirma, **Then** ela vira uma liderança confirmada pro ano.
2. **Given** uma declaração pendente, **When** o Administrador do distrito
   rejeita, **Then** ela não vira liderança confirmada.
3. **Given** o Dono do Grupo (que não é Administrador do distrito), **When**
   ele tenta confirmar ou rejeitar uma declaração, **Then** o sistema
   recusa.
4. **Given** um Usuário comum, **When** ele tenta confirmar ou rejeitar
   qualquer declaração, **Then** o sistema recusa.

---

### User Story 3 - Identificação pública do Líder (Priority: P2)

Qualquer pessoa — Visitante ou Usuário — vê quem é o Líder/Diretor
confirmado de um Grupo/Ministério, na página do próprio Grupo.

**Why this priority**: é o valor final entregue às features anteriores
(US1+US2) — sem isso, a confirmação não tem efeito visível pra ninguém.

**Independent Test**: pode ser testado sozinho com uma liderança já
confirmada, verificando que ela aparece na página do Grupo sem exigir
Perfil pra ver.

**Acceptance Scenarios**:

1. **Given** um Grupo com Líder/Diretor confirmado pro ano corrente,
   **When** qualquer pessoa (Visitante incluído) abre a página do Grupo,
   **Then** o Líder/Diretor aparece identificado.
2. **Given** um Grupo com mais de um Líder/Diretor confirmado (codireção),
   **When** alguém vê a página do Grupo, **Then** todos aparecem.
3. **Given** um Grupo sem nenhum Líder/Diretor confirmado, **When** alguém
   vê a página do Grupo, **Then** nenhuma identificação de Líder aparece
   (o Grupo não é um Ministério).

---

### User Story 4 - Redeclarar a cada ano (Priority: P3)

Quando o ano vira, uma confirmação de anos anteriores deixa de contar como
atual — a pessoa precisa se autodeclarar de novo pro novo ano, e o
Administrador do distrito precisa confirmar de novo.

**Why this priority**: é um refinamento temporal sobre o que já funciona —
US1/US2/US3 já entregam o ciclo completo pra um ano; isto garante que ele
se repete corretamente ano a ano.

**Independent Test**: pode ser testado sozinho com uma confirmação de um
ano anterior já existente, verificando que ela não aparece como atual, e
que a mesma pessoa consegue se autodeclarar de novo pro ano corrente.

**Acceptance Scenarios**:

1. **Given** uma liderança confirmada num ano anterior, **When** o ano
   corrente é diferente, **Then** ela não conta como atual e não aparece
   na identificação pública do Grupo.
2. **Given** uma liderança de ano anterior já expirada, **When** a mesma
   pessoa se autodeclara de novo pro ano corrente, **Then** uma nova
   declaração pendente é criada normalmente.

### Edge Cases

- Usuário que não participa do Grupo se autodeclara Líder dele: permitido
  — o domínio não exige participação prévia (ver Assumptions).
- Dois Usuários diferentes se autodeclaram Líder do mesmo Grupo no mesmo
  ano: ambos ficam pendentes; o Administrador do distrito decide cada um
  independentemente (codireção é permitida se confirmar os dois).
- Usuário confirmado como Líder num Grupo faz upgrade de Perfil pra Conta
  depois de já ter Conta: não se aplica — Conta é pré-requisito pra
  autodeclarar, não algo que se perde depois.
- Administrador do distrito rejeita uma declaração e a mesma pessoa tenta
  se autodeclarar de novo pro mesmo Grupo/ano: permitido — uma nova
  declaração pendente é criada (rejeição não bloqueia nova tentativa).
- Declaração feita no fim de um ano (ex.: 30 de dezembro) só é confirmada
  pelo Administrador do distrito já no ano seguinte (ex.: 5 de janeiro): a
  confirmação vale pro ano que foi declarado, que já não é mais o ano
  corrente — não aparece como atual. A pessoa precisa se autodeclarar de
  novo pro novo ano.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que um Usuário com Conta se
  autodeclare Líder/Diretor de um Grupo pro ano corrente, criando uma
  declaração pendente.
- **FR-002**: Sistema DEVE impedir que um Usuário só com Perfil (sem
  Conta) se autodeclare Líder/Diretor.
- **FR-003**: Sistema DEVE tratar uma tentativa de autodeclaração
  duplicada (mesmo Usuário, mesmo Grupo, mesmo ano) como não-operação.
- **FR-004**: Sistema DEVE permitir que somente um Administrador do
  distrito confirme ou rejeite uma declaração pendente.
- **FR-005**: Sistema DEVE impedir que o Dono do Grupo, ou qualquer
  Usuário que não seja Administrador do distrito, confirme ou rejeite uma
  declaração.
- **FR-006**: Sistema DEVE exibir, na página do Grupo, todo Líder/Diretor
  com declaração confirmada pro ano corrente — visível a qualquer pessoa,
  Visitante incluído, sem exigir Perfil.
- **FR-007**: Sistema DEVE permitir mais de um Líder/Diretor confirmado
  simultaneamente pro mesmo Grupo (codireção).
- **FR-008**: Sistema DEVE considerar uma confirmação de um ano diferente
  do ano corrente como não-atual, sem exigir nenhum processo agendado —
  a comparação é feita no momento da consulta.
- **FR-009**: Sistema DEVE permitir que a mesma pessoa se autodeclare de
  novo pro ano corrente depois de uma confirmação de ano anterior deixar
  de valer.
- **FR-010**: Sistema DEVE permitir que a mesma pessoa se autodeclare de
  novo pro mesmo Grupo/ano depois de uma rejeição anterior.
- **FR-011**: Sistema NÃO DEVE exigir que quem se autodeclara já participe
  do Grupo.

### Key Entities

- **Declaração de Liderança**: associação entre um Usuário, um Grupo, e um
  ano — com estado (pendente, confirmada, ou rejeitada) e, quando
  decidida, quem decidiu (o Administrador do distrito responsável).
- **Líder/Diretor**: não é uma entidade própria — é a Declaração de
  Liderança no estado confirmada, pro ano corrente.
- **Ministério**: não é uma entidade própria — é um Grupo que tem ao menos
  uma Declaração de Liderança confirmada pro ano corrente.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um Usuário com Conta consegue se autodeclarar Líder/Diretor
  em menos de 1 minuto.
- **SC-002**: 100% das autodeclarações de Usuário sem Conta são recusadas.
- **SC-003**: Uma confirmação do Administrador do distrito reflete na
  identificação pública do Grupo em menos de 2 segundos.
- **SC-004**: 100% das tentativas de confirmar/rejeitar por quem não é
  Administrador do distrito são recusadas.
- **SC-005**: 100% das confirmações de anos anteriores ao corrente somem
  da identificação pública sem exigir nenhuma ação manual de migração.

## Assumptions

- Quem se autodeclara Líder/Diretor não precisa já participar do Grupo —
  o glossário do domínio não pede essa restrição, e adicioná-la seria
  inventar uma regra não pedida.
- Não existe limite de quantas pessoas podem estar com declaração pendente
  ou confirmada pro mesmo Grupo/ano simultaneamente (codireção é permitida
  sem limite explícito).
- Rejeição não é permanente — a mesma pessoa pode tentar se autodeclarar
  de novo a qualquer momento pro mesmo Grupo/ano.
- Não existe notificação automática pro Administrador do distrito quando
  uma nova declaração pendente aparece — ele consulta a lista quando
  quiser (feature futura de notificações, se vier a existir).
- "Ano corrente" é sempre o ano civil (calendário), consistente com o mês
  de expiração citado (janeiro) no glossário do domínio.
