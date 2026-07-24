# Feature Specification: Dupla Missionária

**Feature Branch**: `007-dupla-missionaria`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Dupla Missionária: uma Ação (de Grupo ou avulsa, sem restrição) marcada como visita missionária, com regra de composição por gênero baseada no gênero de quem será visitado. Ao criar, quem cria informa o gênero da pessoa visitada (homem ou mulher) e a Ação fica limitada a exatamente 2 vagas (não configurável, diferente do limite_vagas opcional de Ação comum). Composições válidas ao confirmar presença: 1 homem + 1 mulher (serve para visitar qualquer pessoa), 2 homens (só válida se o visitado for homem), 2 mulheres (só válida se a visitada for mulher). Uma segunda confirmação que formaria 2 homens visitando mulher, ou 2 mulheres visitando homem, deve ser recusada — a regra é checada no momento da confirmação, não depois. Reusar a tabela e triggers de Ação/confirmação já existentes (features 003/004), sem criar uma entidade paralela — mesmo princípio de simplicidade já aplicado em Ação candidata."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Criar Dupla Missionária (Priority: P1)

Quem cria uma Ação (avulsa ou de Grupo) marca que é uma Dupla Missionária e
informa o gênero da pessoa que será visitada. A Ação nasce com exatamente 2
vagas, sem opção de configurar outro limite.

**Why this priority**: sem a Ação existir com o gênero do visitado
registrado, não há como validar composição nenhuma — é a fundação da
feature.

**Independent Test**: pode ser testado sozinho criando uma Dupla
Missionária e confirmando que ela nasce com 2 vagas e o gênero do visitado
salvo.

**Acceptance Scenarios**:

1. **Given** um Usuário criando uma Ação avulsa, **When** ele marca como
   Dupla Missionária e informa o gênero da pessoa visitada, **Then** a Ação
   é criada com exatamente 2 vagas.
2. **Given** um Usuário criando uma Ação candidata dentro de um Grupo,
   **When** ele marca como Dupla Missionária, **Then** a mesma regra de 2
   vagas e gênero do visitado se aplica, igual à Ação avulsa.
3. **Given** uma Ação marcada como Dupla Missionária, **When** alguém tenta
   informar um limite de vagas diferente de 2, **Then** o sistema recusa —
   o limite não é configurável para este tipo de Ação.

---

### User Story 2 - Confirmar presença respeitando a composição de gênero (Priority: P1)

Ao confirmar presença numa Dupla Missionária, o sistema só aceita a
confirmação se o resultado for uma composição válida: 1 homem + 1 mulher
(sempre válida), 2 homens (só se o visitado for homem), ou 2 mulheres (só
se a visitada for mulher).

**Why this priority**: é a regra de negócio central desta feature — sem
ela, Dupla Missionária seria uma Ação comum sem nenhuma diferença de
verdade.

**Independent Test**: pode ser testado sozinho com uma Dupla Missionária já
criada, confirmando presença de uma pessoa e depois tentando confirmar uma
segunda de gênero inválido para a composição.

**Acceptance Scenarios**:

1. **Given** uma Dupla Missionária visitando um homem, sem ninguém
   confirmado ainda, **When** um homem confirma presença, **Then** a
   confirmação é aceita (a dupla ainda pode fechar como 2 homens ou como 1
   homem + 1 mulher).
2. **Given** uma Dupla Missionária visitando um homem, com um homem já
   confirmado, **When** outro homem confirma presença, **Then** a
   confirmação é aceita (2 homens visitando homem é válido).
3. **Given** uma Dupla Missionária visitando uma mulher, com um homem já
   confirmado, **When** outro homem tenta confirmar presença, **Then** o
   sistema recusa (2 homens visitando mulher é inválido).
4. **Given** uma Dupla Missionária visitando um homem, com uma mulher já
   confirmada, **When** outra mulher tenta confirmar presença, **Then** o
   sistema recusa (2 mulheres visitando homem é inválido).
5. **Given** uma Dupla Missionária com qualquer gênero de visitado, com uma
   pessoa de um gênero já confirmada, **When** uma pessoa do gênero oposto
   confirma presença, **Then** a confirmação é aceita (1 homem + 1 mulher
   serve para visitar qualquer pessoa).

### Edge Cases

- Uma pessoa confirmada desiste (libera a vaga) de uma Dupla Missionária
  que já tinha as 2 vagas preenchidas validamente: a vaga libera
  normalmente; se havia fila de espera, o sistema promove o próximo da fila
  cuja confirmação mantenha uma composição válida com quem ainda está
  confirmado — pulando quem formaria composição inválida, e deixando a vaga
  aberta se ninguém na fila for válido no momento.
- Uma Dupla Missionária já com as 2 vagas preenchidas validamente: uma
  terceira tentativa de confirmação (de qualquer gênero) entra na fila de
  espera, igual a qualquer Ação lotada — não é recusada por gênero, só por
  capacidade.
- Cancelamento de uma Dupla Missionária: segue exatamente a mesma regra de
  quem pode cancelar já existente para Ação avulsa ou Ação de Grupo — não
  há regra adicional para este tipo.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir marcar uma Ação (avulsa ou candidata de
  Grupo) como Dupla Missionária no momento da criação.
- **FR-002**: Sistema DEVE exigir o gênero da pessoa visitada (homem ou
  mulher) ao criar uma Dupla Missionária.
- **FR-003**: Sistema DEVE fixar o limite de vagas de uma Dupla Missionária
  em exatamente 2, sem permitir outro valor.
- **FR-004**: Sistema DEVE aceitar uma confirmação de presença numa Dupla
  Missionária quando, junto com quem já está confirmado, formar uma
  composição válida: 1 homem + 1 mulher (qualquer visitado), 2 homens
  (visitado homem), ou 2 mulheres (visitada mulher).
- **FR-005**: Sistema DEVE recusar uma confirmação de presença numa Dupla
  Missionária quando, junto com quem já está confirmado, formaria uma
  composição inválida: 2 homens visitando mulher, ou 2 mulheres visitando
  homem.
- **FR-006**: Sistema DEVE checar a validade da composição no momento da
  confirmação, não depois — uma confirmação inválida nunca é aceita
  temporariamente.
- **FR-007**: Sistema DEVE aceitar a primeira confirmação de presença de
  qualquer gênero numa Dupla Missionária, já que uma única pessoa nunca
  viola a regra de composição sozinha.
- **FR-008**: Sistema DEVE reusar o mesmo mecanismo de fila de espera já
  existente para Ação lotada quando as 2 vagas de uma Dupla Missionária já
  estiverem preenchidas validamente.
- **FR-009**: Sistema DEVE, ao promover alguém da fila de espera pra uma
  vaga liberada numa Dupla Missionária, pular quem formaria composição
  inválida com quem ainda está confirmado, promovendo o próximo válido.

### Key Entities

- **Dupla Missionária**: não é uma entidade própria — é uma Ação (avulsa ou
  candidata) com uma marca de tipo e um gênero da pessoa visitada, reusando
  toda a estrutura de Ação e confirmação já existente.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um Usuário consegue criar uma Dupla Missionária em menos de 1
  minuto.
- **SC-002**: 100% das confirmações que formariam 2 homens visitando
  mulher, ou 2 mulheres visitando homem, são recusadas.
- **SC-003**: 100% das confirmações que formam 1 homem + 1 mulher, ou 2
  pessoas do mesmo gênero do visitado, são aceitas.
- **SC-004**: 100% das tentativas de definir um limite de vagas diferente
  de 2 numa Dupla Missionária são recusadas.

## Assumptions

- O gênero considerado na validação é sempre o gênero cadastrado no Perfil
  de quem confirma (masculino/feminino, os únicos valores hoje suportados
  pelo cadastro de Usuário) — não existe um terceiro valor a tratar.
- Quem cria a Ação escolhe marcá-la como Dupla Missionária de forma
  explícita — não existe detecção automática por nome ou categoria.
- Não existe limite de tentativas de confirmação inválida — uma pessoa
  recusada pode tentar de novo se a composição mudar (ex.: a outra pessoa
  confirmada desistiu).
- A promoção da fila de espera pulando composições inválidas segue a mesma
  ordem de chegada da fila já existente (features 003/004) — só pula quem
  seria inválido, sem reordenar por outro critério.
