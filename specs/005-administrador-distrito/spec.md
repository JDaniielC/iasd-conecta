# Feature Specification: Administrador do Distrito

**Feature Branch**: `005-administrador-distrito`

**Created**: 2026-07-24

**Status**: Draft

**Input**: User description: "Administrador do distrito: um Usuário com Conta já Administrador do distrito promove outro Usuário com Conta a Administrador do distrito também (nunca autodeclaração — sempre promoção por quem já é). O primeiro Administrador do distrito é criado fora do fluxo normal do app (seed direto no banco), já que não existe papel acima dele pra promover o primeiro. Administrador do distrito gerencia a lista de Igrejas do distrito: adiciona uma nova Igreja, e arquiva (não exclui de verdade, pra não quebrar vínculos históricos de Perfil/Grupo/Ação que já apontam pra ela) uma Igreja que não deve mais aparecer como opção pra escolher. Administrador do distrito pode cancelar qualquer Ação (avulsa ou de Grupo), além de quem já podia cancelar antes (criador, ou Dono do Grupo). Visitante e Usuário comum veem a lista de Igrejas ativas livremente (já existente desde a feature 001), mas só Administrador do distrito vê/gerencia as arquivadas e promove novos administradores. Fora de escopo: moderação de conteúdo e 'casos excepcionais' genéricos."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Promover Usuário a Administrador do distrito (Priority: P1)

Um Administrador do distrito já existente promove outro Usuário — que precisa
ter Conta, não basta Perfil — a Administrador do distrito também.

**Why this priority**: sem essa capacidade, o papel nunca cresce além de quem
foi semeado direto no banco — é a fundação pra qualquer outra coisa nesta
feature funcionar de forma sustentável.

**Independent Test**: pode ser testado sozinho com um Administrador semeado
promovendo um Usuário com Conta, confirmando que esse Usuário passa a ter
os privilégios de Administrador.

**Acceptance Scenarios**:

1. **Given** um Administrador do distrito, **When** ele promove um Usuário
   que tem Conta, **Then** esse Usuário vira Administrador do distrito
   também.
2. **Given** um Administrador do distrito, **When** ele tenta promover um
   Usuário que só tem Perfil (sem Conta), **Then** o sistema recusa.
3. **Given** um Usuário que não é Administrador do distrito, **When** ele
   tenta promover alguém, **Then** o sistema recusa.

---

### User Story 2 - Gerenciar lista de Igrejas (Priority: P1)

Administrador do distrito adiciona uma nova Igreja à lista do distrito, e
arquiva uma Igreja que não deve mais aparecer como opção pra escolher —
sem apagá-la de verdade, pra não quebrar vínculos já existentes.

**Why this priority**: é a responsabilidade mais citada do papel no
glossário do domínio; sem isso, a lista de Igrejas fica estática desde o
seed inicial, sem forma de evoluir.

**Independent Test**: pode ser testado sozinho adicionando uma Igreja nova
e arquivando outra, confirmando que a arquivada some da lista de opções
mas continua intacta pra quem já a tinha selecionada antes.

**Acceptance Scenarios**:

1. **Given** um Administrador do distrito, **When** ele adiciona uma nova
   Igreja, **Then** ela aparece na lista de Igrejas ativas pra qualquer
   pessoa escolher.
2. **Given** um Administrador do distrito, **When** ele arquiva uma Igreja,
   **Then** ela deixa de aparecer como opção nova, mas Perfis/Grupos/Ações
   que já apontavam pra ela continuam funcionando normalmente.
3. **Given** um Usuário que não é Administrador do distrito, **When** ele
   tenta adicionar ou arquivar uma Igreja, **Then** o sistema recusa.
4. **Given** qualquer pessoa (Visitante ou Usuário), **When** ela vê a lista
   de Igrejas pra escolher, **Then** só as ativas aparecem — as arquivadas
   ficam visíveis só pra Administrador do distrito.

---

### User Story 3 - Cancelar qualquer Ação (Priority: P2)

Administrador do distrito cancela qualquer Ação — avulsa ou de Grupo — além
de quem já podia (quem criou, ou o Dono do Grupo, conforme já valia antes
desta feature).

**Why this priority**: é uma extensão de uma capacidade que já existe
(cancelamento), não uma capacidade nova — soma valor, mas US1 e US2 sozinhas
já entregam o núcleo do papel.

**Independent Test**: pode ser testado sozinho com um Administrador do
distrito cancelando uma Ação que não criou e que não é de um Grupo que ele
administra, confirmando que o cancelamento funciona.

**Acceptance Scenarios**:

1. **Given** um Administrador do distrito, **When** ele cancela uma Ação
   avulsa que não criou, **Then** o cancelamento funciona.
2. **Given** um Administrador do distrito, **When** ele cancela uma Ação de
   Grupo que não propôs e cujo Grupo não administra, **Then** o
   cancelamento funciona.

### Edge Cases

- Igreja arquivada é a única selecionada num Perfil/Grupo/Ação existente:
  esses vínculos continuam mostrando o nome da Igreja normalmente — arquivar
  não afeta dado histórico, só remove da lista de novas escolhas.
- Administrador do distrito tenta arquivar uma Igreja já arquivada: tratado
  como não-operação.
- Um Usuário promovido a Administrador do distrito depois faz downgrade de
  Conta pra Perfil: não é uma operação que existe no app (upgrade de
  Perfil→Conta é uma via, não há caminho de volta) — fora de escopo.
- Não existe fluxo de "remover" um Administrador do distrito nesta feature
  — só promoção; revogar o papel fica fora de escopo.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que um Administrador do distrito
  promova outro Usuário a Administrador do distrito.
- **FR-002**: Sistema DEVE exigir que o Usuário promovido tenha Conta (não
  basta Perfil) antes de completar a promoção.
- **FR-003**: Sistema DEVE impedir que quem não é Administrador do distrito
  promova alguém.
- **FR-004**: Sistema DEVE permitir que um Administrador do distrito
  adicione uma nova Igreja à lista do distrito.
- **FR-005**: Sistema DEVE permitir que um Administrador do distrito
  arquive uma Igreja, sem apagá-la, preservando todo vínculo histórico já
  existente (Perfil, Grupo, Ação) que aponte pra ela.
- **FR-006**: Sistema DEVE impedir que quem não é Administrador do distrito
  adicione ou arquive uma Igreja.
- **FR-007**: Sistema DEVE excluir Igrejas arquivadas da lista de opções
  oferecida a quem está escolhendo uma Igreja (cadastro de Perfil, criação
  de Grupo/Ação).
- **FR-008**: Sistema DEVE permitir que só um Administrador do distrito veja
  a lista de Igrejas arquivadas.
- **FR-009**: Sistema DEVE permitir que um Administrador do distrito cancele
  qualquer Ação (avulsa ou de Grupo), somando-se a quem já podia cancelar
  (criador, ou Dono do Grupo).
- **FR-010**: Sistema DEVE tratar uma tentativa de arquivar uma Igreja já
  arquivada como não-operação.

### Key Entities

- **Administrador do distrito**: papel atribuído a um Usuário com Conta;
  concedido só por promoção de outro Administrador do distrito já
  existente (nunca autodeclaração). Sem processo de revogação nesta
  feature.
- **Igreja**: nome de uma igreja do distrito (já existente desde a feature
  001), com um estado novo — ativa ou arquivada. Arquivamento é reversível
  em termos de dado (a linha nunca é apagada), mas esta feature não expõe
  um fluxo de "reativar".

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Um Administrador do distrito consegue promover outro Usuário
  em menos de 1 minuto.
- **SC-002**: 100% das tentativas de promoção de Usuário sem Conta são
  recusadas.
- **SC-003**: Uma Igreja recém-arquivada some da lista de opções em menos
  de 2 segundos, sem afetar nenhum vínculo histórico existente.
- **SC-004**: 100% das tentativas de gerenciar Igrejas ou promover
  Administrador por quem não é Administrador do distrito são recusadas.

## Assumptions

- O primeiro Administrador do distrito é criado fora do fluxo do app (seed
  direto no banco/painel do Supabase) — esta feature não inclui uma tela
  pra isso, só a documentação de como fazer.
- Não existe limite de quantos Administradores do distrito podem existir
  simultaneamente.
- Revogar o papel de Administrador do distrito de alguém fica fora de
  escopo nesta versão.
- Reativar uma Igreja arquivada fica fora de escopo nesta versão (dado
  nunca é apagado, mas o fluxo de UI pra reverter não é construído agora).
- Moderação de conteúdo e "casos excepcionais" genéricos permanecem sem
  escopo detalhado, como já registrado no glossário do domínio.
