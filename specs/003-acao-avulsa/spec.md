# Feature Specification: Ação Avulsa

**Feature Branch**: `003-acao-avulsa`

**Created**: 2026-07-23

**Status**: Draft

**Input**: User description: "Ação avulsa: qualquer Usuário com Perfil cria uma Ação avulsa (sem Grupo pai) com data/hora específica, local e detalhes — já nasce confirmada, sem votação. Pode ter um limite de vagas opcional definido por quem cria; sem limite, é ilimitada. Qualquer Usuário com Perfil pode Participar da Ação (confirmar presença), esteja associado a algum Grupo ou não; é revogável, o Usuário pode desistir depois liberando a vaga. Vaga lotada forma fila de espera: se alguém desistir, o próximo da fila assume a vaga automaticamente. Ação avulsa é cancelada por quem a criou ou pelo Administrador do distrito (que ainda não existe como feature — tratar como fora de escopo, só o criador cancela por enquanto). Visitante sem Perfil pode ver a Ação e sua lista de confirmados livremente, mas não confirmar presença. Fora de escopo aqui: Ação de Grupo, Ação candidata, Rodada de votação, Votar (feature futura separada)."

## Clarifications

### Session 2026-07-23

- Q: Quem cria a Ação avulsa vira confirmado automaticamente (ocupando
  vaga, se houver limite), ou precisa confirmar presença separadamente
  como qualquer outro? → A: Vira confirmado automaticamente na criação —
  mesmo padrão já usado em Grupo (Dono vira participante automático).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Criar Ação avulsa (Priority: P1)

Um Usuário com Perfil cria uma Ação avulsa pra um evento pontual (ex:
"Acampamento", "Mutirão de limpeza"), informando nome, data/hora, local,
detalhes e, opcionalmente, um limite de vagas. A Ação já nasce confirmada —
sem passar por votação.

**Why this priority**: sem Ação, não existe nada pra confirmar presença — é
a fundação desta feature.

**Independent Test**: pode ser testado sozinho criando uma Ação avulsa do
zero e confirmando que ela aparece já confirmada, sem etapa extra.

**Acceptance Scenarios**:

1. **Given** um Usuário com Perfil, **When** ele preenche nome, data/hora e
   local (sem limite de vagas) e confirma, **Then** a Ação é criada já
   confirmada, com vagas ilimitadas, e o próprio criador já aparece na
   lista de confirmados.
2. **Given** um Usuário criando uma Ação, **When** ele define um limite de
   vagas, **Then** a Ação é criada com esse limite, já contando a vaga do
   próprio criador (confirmado automaticamente).
3. **Given** um Usuário criando uma Ação, **When** ele tenta enviar sem nome,
   data/hora ou local, **Then** o sistema bloqueia a criação.

---

### User Story 2 - Confirmar presença e desistir (Priority: P1)

Qualquer Usuário com Perfil confirma presença numa Ação — esteja ele
associado ao Grupo dela ou não (Ação avulsa nem tem Grupo pai). Pode desistir
depois, liberando a vaga.

**Why this priority**: é o valor central da Ação — sem confirmar presença,
criar a Ação não teria propósito. Fica no mesmo nível de prioridade da US1.

**Independent Test**: pode ser testado sozinho confirmando presença numa
Ação e depois desistindo, verificando que a vaga é liberada.

**Acceptance Scenarios**:

1. **Given** uma Ação sem limite de vagas, **When** um Usuário confirma
   presença, **Then** ele aparece na lista de confirmados.
2. **Given** um Usuário confirmado numa Ação, **When** ele desiste,
   **Then** ele some da lista de confirmados e a vaga (se houver limite)
   fica disponível.
3. **Given** um Usuário que já confirmou presença, **When** ele tenta
   confirmar de novo na mesma Ação, **Then** o sistema trata como
   não-operação (sem erro, sem duplicar).
4. **Given** um Visitante sem Perfil, **When** ele tenta confirmar presença,
   **Then** o sistema direciona pro cadastro de Perfil antes de permitir.

---

### User Story 3 - Vaga lotada e fila de espera (Priority: P2)

Quando uma Ação tem limite de vagas e todas estão ocupadas, novas
confirmações entram numa fila de espera. Se alguém desistir, o próximo da
fila assume a vaga automaticamente, sem precisar de ação manual de ninguém.

**Why this priority**: só se aplica quando a Ação tem limite de vagas e ele
é atingido — um refinamento sobre a US2, não um valor independente dela.

**Independent Test**: pode ser testado sozinho criando uma Ação com limite
de 1 vaga, confirmando dois Usuários (o segundo cai na fila), e então
fazendo o primeiro desistir — confirmando que o segundo assume a vaga
automaticamente.

**Acceptance Scenarios**:

1. **Given** uma Ação com limite de vagas já ocupado, **When** outro Usuário
   tenta confirmar presença, **Then** ele entra na fila de espera em vez de
   ser confirmado direto.
2. **Given** um Usuário na fila de espera, **When** alguém confirmado
   desiste, **Then** o primeiro da fila é promovido a confirmado
   automaticamente.
3. **Given** um Usuário na fila de espera, **When** ele próprio desiste da
   fila (antes de ser promovido), **Then** ele sai da fila sem afetar os
   demais.

---

### User Story 4 - Cancelar Ação avulsa (Priority: P3)

Quem criou a Ação avulsa pode cancelá-la quando ela não vai mais acontecer.

**Why this priority**: é manutenção — a Ação já entrega valor (P1/P2) antes
de qualquer cancelamento acontecer.

**Independent Test**: pode ser testado sozinho criando uma Ação, cancelando,
e confirmando que ninguém mais consegue confirmar presença nela.

**Acceptance Scenarios**:

1. **Given** quem criou a Ação, **When** ele a cancela, **Then** a Ação
   aparece como cancelada pra quem visualiza.
2. **Given** uma Ação cancelada, **When** alguém tenta confirmar presença,
   **Then** o sistema recusa.
3. **Given** um Usuário que não criou a Ação, **When** ele tenta cancelá-la,
   **Then** o sistema recusa.

### Edge Cases

- Criador da Ação também confirma presença e depois desiste: permitido
  normalmente, como qualquer outro confirmado — não existe uma regra
  equivalente à do Dono do Grupo prendendo o criador na Ação.
- Duas pessoas tentam confirmar a última vaga ao mesmo tempo: resolvido por
  ordem de chegada no sistema — quem chegar primeiro fica com a vaga, a
  outra cai na fila de espera. Não é sorteio (sorteio é exclusivo de empate
  em Rodada de votação, fora de escopo aqui).
- Ação cancelada com pessoas já confirmadas ou na fila: o histórico de quem
  tinha confirmado antes do cancelamento não é apagado; só fica bloqueada
  qualquer confirmação nova.
- Ação sem limite de vagas nunca forma fila de espera, por definição.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que um Usuário com Perfil crie uma Ação
  avulsa informando nome, data/hora, local e detalhes (obrigatórios exceto
  detalhes), com limite de vagas opcional.
- **FR-002**: Sistema DEVE considerar toda Ação avulsa criada como já
  confirmada, sem etapa de votação.
- **FR-003**: Sistema DEVE permitir que qualquer Usuário com Perfil confirme
  presença numa Ação avulsa, esteja ele associado a algum Grupo ou não.
- **FR-004**: Sistema DEVE permitir que um Usuário desista de uma Ação da
  qual confirmou presença (ou da qual está na fila de espera), liberando a
  vaga ou saindo da fila.
- **FR-005**: Sistema DEVE colocar novas confirmações em fila de espera
  quando o limite de vagas da Ação estiver totalmente ocupado.
- **FR-006**: Sistema DEVE promover automaticamente o próximo da fila de
  espera pra confirmado quando uma vaga se libera, sem exigir ação manual.
- **FR-007**: Sistema DEVE aceitar confirmações ilimitadas em Ações sem
  limite de vagas definido, nunca formando fila nesse caso.
- **FR-008**: Sistema DEVE permitir que somente quem criou a Ação avulsa a
  cancele.
- **FR-009**: Sistema DEVE impedir novas confirmações de presença (e
  entradas na fila de espera) numa Ação cancelada.
- **FR-010**: Sistema DEVE permitir que qualquer pessoa — Visitante ou
  Usuário — veja os detalhes de uma Ação avulsa e a lista de confirmados,
  sem exigir Perfil.
- **FR-011**: Sistema DEVE impedir que um Visitante sem Perfil confirme
  presença, direcionando-o ao cadastro de Perfil quando tentar.
- **FR-012**: Sistema DEVE tratar uma tentativa de confirmar presença numa
  Ação da qual a pessoa já confirmou, ou na qual já está na fila, como
  não-operação (sem erro, sem duplicar).
- **FR-013**: Sistema DEVE confirmar presença automaticamente de quem cria
  a Ação, ocupando uma vaga do limite (se houver) desde a criação.

### Key Entities

- **Ação**: nome, data/hora, local, detalhes (opcional), limite de vagas
  (opcional — ausente significa ilimitada), criador (um Usuário),
  cancelada (sim/não, com data do cancelamento).
- **Confirmação de Presença**: associação entre um Usuário e uma Ação, com
  status (confirmado ou em fila de espera) e ordem de chegada (pra saber
  quem é o próximo a ser promovido).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um Usuário consegue criar uma Ação avulsa em menos de 2
  minutos.
- **SC-002**: Confirmar ou desistir reflete na lista de confirmados em
  menos de 2 segundos após a ação.
- **SC-003**: 100% das promoções de fila de espera acontecem
  automaticamente quando uma vaga se libera, sem intervenção manual de
  ninguém.
- **SC-004**: Visitantes conseguem ver detalhes e lista de confirmados de
  qualquer Ação avulsa sem nenhuma barreira de cadastro.
- **SC-005**: 0% das Ações com limite de vagas ficam, em qualquer momento,
  com mais confirmados do que o limite definido.

## Assumptions

- O nome da Ação é texto livre nesta versão; o atalho de "Ação sugerida"
  (nomes pré-cadastrados por Categoria de Grupo) fica pra uma feature
  futura.
- Esta feature não valida se a data/hora informada já passou — checagem de
  "Ação no passado" fica pra um polimento futuro, fora de escopo aqui.
- A fila de espera é ordenada por ordem de chegada (quem confirmou primeiro
  fica na frente); não há prioridade nem sorteio — sorteio é conceito
  exclusivo de empate em Rodada de votação (Ação de Grupo, feature futura).
- Cancelamento da Ação não apaga o histórico de confirmações anteriores; só
  bloqueia confirmações novas e marca a Ação como cancelada pra quem vê.
- Administrador do distrito cancelar qualquer Ação fica fora de escopo
  aqui — esse papel ainda não existe como feature no app.
