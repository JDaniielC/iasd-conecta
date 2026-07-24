# Feature Specification: Rodada de Votação

**Feature Branch**: `004-rodada-votacao`

**Created**: 2026-07-23

**Status**: Draft

**Input**: User description: "Ação de Grupo, Ação candidata, Rodada de votação e Votar: qualquer participante de um Grupo abre uma Rodada de votação com um prazo (data/hora de fechamento automático). Um Grupo pode ter várias Rodadas abertas em paralelo, para Ações diferentes. Enquanto a Rodada está aberta, qualquer participante do Grupo pode propor uma Ação candidata (nome, data/hora, local, detalhes — mesmos campos de uma Ação avulsa, mas dentro do Grupo e concorrendo na Rodada). Cada Ação candidata aceita confirmação de presença (Participar) independente de receber Voto ou não, igual Ação avulsa. Qualquer participante do Grupo vota numa candidata da Rodada — revogável, pode trocar de candidata quantas vezes quiser enquanto a Rodada estiver aberta, só a última escolha conta. Ao fechar (pelo prazo vencido, ou pelo Dono do Grupo encerrando antes do prazo), apura-se a candidata mais votada; empate é resolvido por sorteio aleatório entre as empatadas. A candidata vencedora vira Ação confirmada do Grupo, carregando as presenças já confirmadas nela; as demais candidatas são descartadas junto com suas presenças confirmadas. Ação de Grupo (já confirmada) é cancelada por quem propôs a candidata vencedora, pelo Dono do Grupo, ou pelo Administrador do distrito (ainda não existe — só os dois primeiros por enquanto). Visitante vê Rodadas, candidatas e Ações de Grupo livremente, sem votar nem participar. Reusa a mesma tabela/conceito de Ação e confirmação de presença já existentes (feature 003), mesma base Flutter + Supabase."

## Clarifications

### Session 2026-07-24

- Q: Fechamento por prazo vencido é um job agendado (fecha exatamente no
  prazo) ou preguiçoso (fecha na próxima interação após o prazo)? → A:
  Preguiçoso — confirma a Assumption já registrada, evita depender de
  infraestrutura de agendamento (pg_cron) só pra isso.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Abrir Rodada e propor Ação candidata (Priority: P1)

Um participante de um Grupo abre uma Rodada de votação com um prazo. Enquanto
ela está aberta, qualquer participante do Grupo (incluindo quem abriu) propõe
Ações candidatas — mesmos dados de uma Ação avulsa (nome, data/hora, local,
detalhes), mas vinculadas à Rodada e ao Grupo.

**Why this priority**: sem Rodada e sem candidata, não existe nada pra votar
— é a fundação desta feature.

**Independent Test**: pode ser testado sozinho abrindo uma Rodada num Grupo
e propondo duas candidatas, confirmando que ambas aparecem listadas na
Rodada.

**Acceptance Scenarios**:

1. **Given** um participante de um Grupo, **When** ele abre uma Rodada com
   um prazo futuro, **Then** a Rodada aparece como aberta pra esse Grupo.
2. **Given** uma Rodada aberta, **When** um participante do Grupo propõe uma
   candidata (nome, data/hora, local), **Then** ela aparece na lista de
   candidatas da Rodada.
3. **Given** um Grupo, **When** alguém abre uma segunda Rodada enquanto a
   primeira ainda está aberta, **Then** as duas coexistem, cada uma com suas
   próprias candidatas.
4. **Given** um Usuário que não participa do Grupo, **When** ele tenta abrir
   Rodada ou propor candidata nele, **Then** o sistema recusa.

---

### User Story 2 - Votar numa candidata (Priority: P1)

Qualquer participante do Grupo escolhe uma candidata da Rodada. Pode trocar
de escolha quantas vezes quiser enquanto a Rodada estiver aberta — só a
última conta na apuração.

**Why this priority**: votar é o propósito central da Rodada — sem isso, as
candidatas nunca se resolvem em nada.

**Independent Test**: pode ser testado sozinho votando numa candidata,
trocando o voto pra outra, e confirmando que só a última escolha é
considerada.

**Acceptance Scenarios**:

1. **Given** um participante do Grupo, **When** ele vota numa candidata da
   Rodada, **Then** o voto é registrado.
2. **Given** um participante que já votou, **When** ele vota noutra
   candidata da mesma Rodada, **Then** só a última escolha conta —
   o voto anterior não soma mais.
3. **Given** um Usuário que não participa do Grupo, **When** ele tenta
   votar, **Then** o sistema recusa.

---

### User Story 3 - Fechar Rodada e apurar a vencedora (Priority: P2)

Quando o prazo da Rodada vence, ou o Dono do Grupo a encerra antes, apura-se
a candidata mais votada. Empate é resolvido por sorteio aleatório entre as
empatadas. A vencedora vira Ação confirmada do Grupo, carregando as
presenças já confirmadas nela; as demais candidatas somem, junto com as
presenças confirmadas nelas.

**Why this priority**: completa o ciclo da Rodada iniciado na US1/US2 — sem
isso, votos ficam registrados mas nunca viram uma Ação de verdade.

**Independent Test**: pode ser testado sozinho abrindo uma Rodada, propondo
candidatas, votando (inclusive criando um empate proposital), forçando o
fechamento, e confirmando que uma vencedora emerge e as demais somem.

**Acceptance Scenarios**:

1. **Given** uma Rodada cujo prazo já passou, **When** alguém interage com
   ela (vota, tenta propor, ou abre a tela), **Then** ela é fechada e
   apurada nesse momento, antes de a ação prosseguir.
2. **Given** o Dono do Grupo, **When** ele encerra a Rodada antes do prazo,
   **Then** ela fecha e apura imediatamente.
3. **Given** uma apuração com uma candidata clara na frente, **When** a
   Rodada fecha, **Then** essa candidata vira Ação confirmada do Grupo, e as
   demais candidatas (e suas presenças confirmadas) somem.
4. **Given** um empate entre duas ou mais candidatas, **When** a Rodada
   fecha, **Then** uma delas é escolhida por sorteio aleatório como
   vencedora.
5. **Given** uma Rodada sem nenhuma candidata proposta, **When** ela fecha,
   **Then** não há vencedora — a Rodada só fecha sem gerar Ação confirmada.
6. **Given** um Usuário que não é o Dono do Grupo, **When** ele tenta
   encerrar a Rodada antes do prazo, **Then** o sistema recusa.

---

### User Story 4 - Confirmar presença numa Ação candidata (Priority: P2)

Enquanto uma candidata está em votação, qualquer Usuário com Perfil pode
confirmar presença nela — igual uma Ação avulsa — independente de ter
votado nela ou não.

**Why this priority**: é o mesmo mecanismo de presença já existente (feature
003), aplicado a candidatas; agrega valor mas não é o núcleo da votação em
si.

**Independent Test**: pode ser testado sozinho confirmando presença numa
candidata e verificando que a confirmação aparece nela, com ou sem voto.

**Acceptance Scenarios**:

1. **Given** uma candidata numa Rodada aberta, **When** um Usuário confirma
   presença nela, **Then** ele aparece como confirmado nessa candidata,
   independente de ter votado ou não.
2. **Given** uma candidata que perde a apuração, **When** a Rodada fecha,
   **Then** as presenças confirmadas nela somem junto com a candidata.
3. **Given** uma candidata que vence a apuração, **When** ela vira Ação
   confirmada, **Then** as presenças já confirmadas nela continuam valendo,
   sem precisar reconfirmar.

---

### User Story 5 - Cancelar Ação de Grupo confirmada (Priority: P3)

Quem propôs a candidata vencedora, ou o Dono do Grupo, cancela a Ação de
Grupo já confirmada.

**Why this priority**: é manutenção — a Ação de Grupo já entrega valor
(US1-US4) antes de qualquer cancelamento acontecer.

**Independent Test**: pode ser testado sozinho cancelando uma Ação de Grupo
já confirmada e checando que ninguém mais confirma presença nela.

**Acceptance Scenarios**:

1. **Given** quem propôs a candidata vencedora, **When** ele cancela a Ação
   de Grupo, **Then** ela aparece como cancelada.
2. **Given** o Dono do Grupo (mesmo sem ter proposto a candidata vencedora),
   **When** ele cancela a Ação de Grupo, **Then** ela aparece como
   cancelada.
3. **Given** um participante do Grupo que não é o Dono nem propôs a
   vencedora, **When** ele tenta cancelar, **Then** o sistema recusa.

### Edge Cases

- Rodada com prazo vencido, mas ninguém interage com ela: fica "fechável"
  mas não fecha sozinha até a próxima interação (ver Assumptions —
  fechamento é preguiçoso, não um job agendado).
- Empate entre TODAS as candidatas quando ninguém votou em nenhuma (zero
  votos no total): tratado como empate geral — sorteio entre todas.
- Participante vota, depois desiste de participar do Grupo: o voto
  registrado continua contando até a Rodada fechar (sair do Grupo não
  revoga voto automaticamente — fora de escopo revogar por esse caminho).
- Duas candidatas da mesma Rodada com o mesmo nome: permitido — nome não é
  único, cada candidata tem identidade própria.
- Ação de Grupo cancelada não pode ser "reaberta" nem gerar nova Rodada
  automaticamente — cancelar é definitivo, como já vale pra Ação avulsa.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que um participante de um Grupo abra uma
  Rodada de votação informando um prazo (data/hora de fechamento).
- **FR-002**: Sistema DEVE permitir múltiplas Rodadas abertas
  simultaneamente para o mesmo Grupo.
- **FR-003**: Sistema DEVE permitir que qualquer participante do Grupo
  proponha uma Ação candidata (nome, data/hora, local, detalhes) numa
  Rodada aberta desse Grupo.
- **FR-004**: Sistema DEVE impedir que quem não participa do Grupo abra
  Rodada ou proponha candidata nele.
- **FR-005**: Sistema DEVE permitir que um participante do Grupo vote numa
  candidata de uma Rodada aberta.
- **FR-006**: Sistema DEVE permitir que um participante troque seu voto
  quantas vezes quiser enquanto a Rodada estiver aberta, contando sempre só
  a escolha mais recente.
- **FR-007**: Sistema DEVE impedir que quem não participa do Grupo vote.
- **FR-008**: Sistema DEVE fechar e apurar uma Rodada cujo prazo já passou
  na próxima vez que qualquer interação com ela ocorrer (votar, propor
  candidata, ou visualizar), antes de processar essa interação.
- **FR-009**: Sistema DEVE permitir que o Dono do Grupo encerre e apure uma
  Rodada antes do prazo.
- **FR-010**: Sistema DEVE impedir que quem não é o Dono do Grupo encerre
  uma Rodada antes do prazo.
- **FR-011**: Sistema DEVE apurar, ao fechar, a candidata com mais votos como
  vencedora.
- **FR-012**: Sistema DEVE resolver empate entre candidatas mais votadas por
  sorteio aleatório entre as empatadas.
- **FR-013**: Sistema DEVE transformar a candidata vencedora em Ação
  confirmada do Grupo, preservando as presenças já confirmadas nela.
- **FR-014**: Sistema DEVE descartar as candidatas não vencedoras ao fechar
  a Rodada, junto com as presenças confirmadas nelas.
- **FR-015**: Sistema DEVE permitir confirmar presença numa Ação candidata
  do mesmo jeito que numa Ação avulsa, independente de voto.
- **FR-016**: Sistema DEVE permitir que somente quem propôs a candidata
  vencedora, ou o Dono do Grupo, cancele a Ação de Grupo confirmada.
- **FR-017**: Sistema DEVE permitir que qualquer pessoa — Visitante ou
  Usuário — veja Rodadas, candidatas e Ações de Grupo livremente, sem
  exigir Perfil.
- **FR-018**: Sistema NÃO DEVE gerar Ação confirmada quando uma Rodada
  fecha sem nenhuma candidata proposta.

### Key Entities

- **Rodada de votação**: Grupo dono, prazo, quem abriu, momento de
  fechamento (nulo enquanto aberta), candidata vencedora (definida só ao
  fechar).
- **Ação candidata**: mesma entidade de Ação (feature 003) — nome,
  data/hora, local, detalhes, quem propôs — vinculada a um Grupo e a uma
  Rodada enquanto não vence nem perde. Aceita Confirmação de Presença
  normalmente.
- **Voto**: associação entre um Usuário, uma Rodada, e a candidata
  escolhida — uma linha por Usuário por Rodada (trocar de escolha
  atualiza, não duplica).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um participante consegue abrir uma Rodada e propor uma
  candidata em menos de 2 minutos, juntos.
- **SC-002**: Trocar de voto reflete a escolha mais recente em menos de 2
  segundos.
- **SC-003**: 100% das Rodadas fechadas têm exatamente uma vencedora
  definida quando havia ao menos uma candidata proposta.
- **SC-004**: 100% dos empates são resolvidos automaticamente, sem
  exigir intervenção manual.
- **SC-005**: Visitantes conseguem ver Rodadas, candidatas e Ações de Grupo
  sem nenhuma barreira de cadastro.

## Assumptions

- Fechamento por prazo vencido é preguiçoso (avaliado na próxima interação
  com a Rodada), não um job agendado rodando em segundo plano — evita
  depender de infraestrutura de agendamento (ex.: pg_cron) só pra isso.
  Consequência: uma Rodada vencida sem nenhuma interação fica
  "tecnicamente fechável" até alguém abrir a tela ou tentar votar/propor
  nela.
- Reusa integralmente a entidade Ação e o mecanismo de Confirmação de
  Presença da feature 003 — Ação candidata é uma Ação normal vinculada a
  Grupo/Rodada, não uma tabela nova.
- Sair do Grupo não revoga automaticamente um voto já registrado — fora de
  escopo nesta versão.
- Notificar participantes sobre abertura/fechamento de Rodada fica fora de
  escopo (feature futura de notificações, se vier a existir).
- Administrador do distrito cancelar Ação de Grupo fica fora de escopo —
  esse papel ainda não existe como feature no app (mesma decisão já
  registrada na feature 001 sobre Líder/Diretor).
