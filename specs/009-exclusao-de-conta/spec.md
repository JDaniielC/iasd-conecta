# Feature Specification: Exclusão de conta

**Feature Branch**: `009-exclusao-de-conta`

**Created**: 2026-08-06

**Status**: Draft

**Input**: User description: "Exclusão de conta com anonimização do Perfil e herança de posse (LGPD art. 18, VI). Hoje o pedido de exclusão de quem é Dono de Grupo, criador de Ação, abriu Rodada, é Administrador do distrito ou tem declaração de Líder/Diretor não pode ser atendido: o registro está amarrado ao que outras pessoas usam. A Política de Privacidade já avisa disso. A feature torna o direito exercível: o Perfil é anonimizado em vez de apagado, e o que exige alguém no comando é herdado pelo Administrador do distrito mais antigo. Disparo self-service no app, com confirmação explícita e irreversível."

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Sair do app e não deixar rastro pessoal (Priority: P1)

Um Usuário que não é Dono de nenhum Grupo nem abriu Rodada quer sair. Ele
encontra a opção no próprio app, lê exatamente o que vai acontecer,
confirma, e a partir dali não consegue mais entrar. Quem olhar as Ações de
que ele participou no passado vê "Membro removido" no lugar do nome — o
histórico das outras pessoas continua íntegro, mas não há mais nada que
identifique quem ele era.

**Why this priority**: é o direito do art. 18, VI da LGPD, que a Política de
Privacidade já promete e o app hoje não cumpre. É também o caso mais comum
— a maioria dos Usuários não é Dona de nada — e entrega valor sozinho, sem
depender de nenhuma regra de herança.

**Independent Test**: pode ser testado sozinho criando um Perfil sem posse
nenhuma, pedindo exclusão pelo app, e conferindo que o login deixa de
funcionar e que nenhum dado pessoal dele permanece visível ou armazenado.

**Acceptance Scenarios**:

1. **Given** um Usuário sem Grupo próprio e sem Rodada aberta, **When** ele
   confirma a exclusão, **Then** o acesso é encerrado imediatamente e ele
   não consegue mais entrar com as credenciais antigas.
2. **Given** esse Usuário participou de Ações que já aconteceram, **When**
   a exclusão termina, **Then** a presença dele naquelas Ações continua
   registrada, exibida como "Membro removido", sem nome, Apelido, telefone,
   Igreja de origem, gênero nem idade.
3. **Given** esse Usuário estava confirmado em Ações que ainda vão
   acontecer, **When** a exclusão termina, **Then** ele deixa de ocupar
   essas vagas e a fila de espera de cada uma anda normalmente.
4. **Given** a tela de exclusão, **When** o Usuário chega nela, **Then** ela
   descreve o que será apagado, o que permanecerá como histórico, e deixa
   claro que a ação não tem volta — e nada acontece sem uma confirmação
   explícita.

---

### User Story 2 - Sair sendo Dono de Grupo, sem derrubar o Grupo (Priority: P2)

Uma Dona de Grupo quer sair. Os Grupos que ela administra têm outras
pessoas participando, e uma Rodada de votação dela está aberta. Ao
confirmar a exclusão, os Grupos e a Rodada aberta passam para o
Administrador do distrito mais antigo, que fica responsável por
redistribuir. Nenhum participante perde o Grupo, nenhuma votação em
andamento fica sem quem a apure.

**Why this priority**: é o caso que hoje é impossível de atender, e é o que
justifica a feature existir. Depende da regra de herança, então vem depois
da fatia P1, mas é o que fecha a lacuna jurídica de verdade.

**Independent Test**: pode ser testado sozinho com uma Dona de Grupo que
tenha participantes e uma Rodada aberta, pedindo exclusão e conferindo que
Grupo e Rodada continuam funcionando sob o novo responsável.

**Acceptance Scenarios**:

1. **Given** uma Dona de Grupo com participantes, **When** ela conclui a
   exclusão, **Then** o Grupo continua existindo com todos os
   participantes, sob o Administrador do distrito mais antigo.
2. **Given** que o novo responsável não participava daquele Grupo, **When**
   ele o recebe, **Then** ele passa a participar automaticamente — um Grupo
   nunca fica com um Dono que não é participante.
3. **Given** uma Rodada de votação aberta por ela, **When** a exclusão
   termina, **Then** a Rodada continua aberta, sob o novo responsável, com
   as candidatas e os votos já registrados preservados.
4. **Given** Rodadas dela que já foram fechadas e Ações que ela criou,
   **When** a exclusão termina, **Then** elas permanecem atribuídas ao
   Perfil anonimizado, como histórico — sem trocar de autor.
5. **Given** que ela era o próprio Administrador do distrito mais antigo,
   **When** a exclusão acontece, **Then** a herança recai sobre o
   Administrador seguinte em ordem de antiguidade.
6. **Given** que ela tinha declaração de Líder/Diretor confirmada, **When**
   a exclusão termina, **Then** a declaração deixa de existir, e as
   declarações de outras pessoas que ela confirmou continuam válidas.

---

### User Story 3 - Recusa quando não há quem herde (Priority: P3)

A única Administradora do distrito pede exclusão. Como não sobraria ninguém
para receber os Grupos e as Rodadas abertas, o app recusa e explica o
motivo em linguagem que ela entende, dizendo o que precisa acontecer antes
— promover outro Administrador. Nada é apagado, nada fica pela metade.

**Why this priority**: é o caso raro, mas é o único em que a alternativa
seria deixar Grupo órfão ou dado meio apagado. Precisa existir antes da
feature ir para produção, e é barato depois que P2 está de pé.

**Independent Test**: pode ser testado sozinho com um distrito de um único
Administrador, pedindo exclusão e conferindo que a recusa é explicada e que
o estado do banco não muda.

**Acceptance Scenarios**:

1. **Given** um distrito com um único Administrador, **When** ele pede a
   exclusão da própria conta, **Then** o app recusa, explica que é preciso
   promover outro Administrador antes, e nada é alterado.
2. **Given** essa recusa, **When** ele promove outro Administrador e tenta
   de novo, **Then** a exclusão acontece normalmente e a herança vai para o
   novo Administrador.
3. **Given** qualquer falha no meio do processo, **When** a exclusão é
   interrompida, **Then** o Perfil continua íntegro e utilizável — nunca
   parcialmente anonimizado.

---

### Edge Cases

- **Herdeiro é a própria pessoa que sai**: se quem pede exclusão é o
  Administrador do distrito mais antigo, a herança pula para o próximo mais
  antigo. Se não houver próximo, cai na recusa da US3.
- **Herdeiro não participa do Grupo herdado**: ele passa a participar junto
  da transferência. A invariante "todo Dono participa do próprio Grupo"
  nunca é violada.
- **Vaga liberada em Ação futura com fila de espera**: a saída libera a
  vaga e a primeira pessoa da fila é promovida, exatamente como em qualquer
  outro cancelamento de presença.
- **Vaga liberada em Dupla Missionária futura**: como o Perfil anonimizado
  nunca permanece em vaga futura, a validação de composição por gênero
  continua avaliando apenas pessoas reais — nenhuma Dupla passa a aceitar
  composição inválida por causa de um Perfil sem gênero.
- **Presença em Ação que já aconteceu**: preservada, exibida como "Membro
  removido". É registro de um evento que ocorreu e conta a história de
  outras pessoas também.
- **Declaração de Líder/Diretor pendente de análise**: some junto com a
  exclusão, como qualquer declaração dela.
- **Menor de idade**: o Apelido também é dado pessoal e é apagado junto —
  não sobra o identificador pelo qual ele era exibido.
- **Voto em Rodada aberta**: é retirado, e a apuração passa a desconsiderá-lo
  — mesma categoria da confirmação de presença em Ação futura: é intenção
  sobre algo que ainda não aconteceu, não registro de algo que aconteceu.
  Voto em Rodada já fechada permanece, como parte do resultado apurado.
- **Empate criado ou desfeito pela retirada do voto**: a Rodada segue a
  regra que já existe — desempate por sorteio ao fechar. A saída de uma
  pessoa não introduz critério novo.
- **Participação em Grupo**: some. Quem saiu do app não continua na lista
  de participantes de um Grupo — deixar "Membro removido" ali infla a
  contagem e engana quem lê. Diferente da presença em Ação passada, que é
  registro de um evento e permanece.
- **Nova conta depois de sair**: nada impede que a pessoa se cadastre de
  novo mais tarde. Será um Perfil novo, sem vínculo com o anterior — o
  anterior é irrecuperável.
- **Exclusão pedida duas vezes**: a segunda tentativa não encontra sessão
  válida, porque o acesso já foi encerrado na primeira.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: O Usuário MUST conseguir pedir a exclusão da própria conta
  pelo app, sem depender de contato por outro canal.
- **FR-002**: O sistema MUST exigir confirmação explícita antes de excluir,
  em tela que descreva o que é apagado, o que permanece como histórico, e
  que a ação é irreversível.
- **FR-003**: O sistema MUST permitir que uma pessoa exclua apenas a própria
  conta — nenhum papel, incluindo Administrador do distrito, exclui a conta
  de outra pessoa por esta funcionalidade.
- **FR-004**: Concluída a exclusão, o sistema MUST encerrar o acesso
  imediatamente e impedir novo login com as credenciais anteriores.
- **FR-005**: O sistema MUST remover todo dado pessoal do Perfil — nome,
  Apelido, telefone, Igreja de origem, gênero e idade — substituindo a
  identificação visível por "Membro removido".
- **FR-006**: O sistema MUST registrar o momento em que o Perfil foi
  anonimizado, de forma auditável.
- **FR-007**: O sistema MUST transferir para o Administrador do distrito
  mais antigo os Grupos de que a pessoa era Dona e as Rodadas de votação
  que ela abriu e ainda estão abertas.
- **FR-008**: Ao transferir um Grupo, o sistema MUST garantir que o novo
  Dono passe a participar dele.
- **FR-009**: Quando quem sai é o Administrador do distrito mais antigo, o
  sistema MUST eleger como herdeiro o Administrador seguinte em ordem de
  antiguidade.
- **FR-010**: O sistema MUST recusar a exclusão, sem alterar nada, quando
  não houver nenhum Administrador do distrito apto a herdar, e MUST
  explicar ao Usuário o que precisa acontecer antes.
- **FR-011**: O sistema MUST manter atribuídos ao Perfil anonimizado, como
  histórico, as Ações que a pessoa criou, as Rodadas que ela abriu e já
  fechou, e o registro de declarações de Líder/Diretor que ela confirmou
  para outras pessoas.
- **FR-012**: O sistema MUST apagar as declarações de Líder/Diretor da
  própria pessoa e o registro dela como Administradora do distrito, quando
  existirem.
- **FR-013**: O sistema MUST liberar as confirmações de presença da pessoa
  em Ações que ainda não aconteceram, acionando a promoção da fila de
  espera onde houver.
- **FR-014**: O sistema MUST preservar as confirmações de presença em Ações
  que já aconteceram.
- **FR-015**: A exclusão MUST ser tudo-ou-nada: qualquer falha no meio
  deixa o Perfil exatamente como estava antes.
- **FR-016**: A Política de Privacidade e os Termos de Uso MUST ser
  reescritos para descrever o que esta feature realmente faz, substituindo
  a ressalva atual de que pode ser necessário transferir responsabilidades
  antes de sair.
- **FR-017**: O sistema MUST remover a pessoa da lista de participantes dos
  Grupos de que ela participava, sem afetar o registro de presença dela em
  Ações que já aconteceram.
- **FR-018**: O sistema MUST retirar os votos da pessoa em Rodadas de
  votação ainda abertas, de modo que não contem na apuração. Votos em
  Rodadas já fechadas permanecem, atribuídos ao Perfil anonimizado.

### Key Entities

- **Perfil anonimizado**: um Perfil que perdeu todo conteúdo pessoal mas
  continua existindo como âncora do histórico de outras pessoas. Exibido
  como "Membro removido", sem gênero e sem idade, e marcado com a data em
  que foi anonimizado. Não pertence a ninguém e não tem acesso ao app.
- **Herdeiro**: o Administrador do distrito mais antigo entre os que
  permanecem. Recebe os Grupos e as Rodadas abertas de quem sai, e passa a
  participar dos Grupos herdados.
- **Vínculo herdável**: o que exige alguém capaz de agir — posse de Grupo e
  Rodada de votação aberta. Distingue-se do **vínculo histórico** — autoria
  de Ação, Rodada já fechada, confirmação de declaração alheia, presença em
  Ação passada — que permanece com o Perfil anonimizado.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% dos pedidos de exclusão feitos por quem tem herdeiro
  disponível são concluídos sem intervenção manual de ninguém.
- **SC-002**: Depois da exclusão, nenhuma tela do app exibe nome, Apelido,
  telefone, Igreja de origem, gênero ou idade da pessoa que saiu.
- **SC-003**: Nenhum Grupo fica sem Dono e nenhuma Rodada aberta fica sem
  responsável em consequência de uma exclusão.
- **SC-004**: Nenhum participante perde acesso a um Grupo, e nenhum
  registro de presença em Ação passada desaparece, por causa da saída de
  outra pessoa.
- **SC-005**: O Usuário conclui o pedido em menos de 1 minuto a partir da
  tela de Perfil, e nunca sem uma confirmação explícita.
- **SC-006**: O texto da Política de Privacidade descreve o comportamento
  real do sistema, sem ressalva que o código não cumpra.

## Assumptions

- O volume de exclusões é baixo (comunidade de um distrito), então o
  processo pode ser síncrono — a pessoa espera a conclusão na tela.
- A pessoa que sai não precisa receber cópia dos próprios dados antes: o
  direito de portabilidade (art. 18, V) é pedido separado e está fora
  desta feature.
- Não há período de arrependimento nem exclusão agendada: a confirmação é
  final e imediata. Se essa decisão mudar, muda também o texto da Política.
- O Perfil anonimizado permanece indefinidamente, porque é o que sustenta
  o histórico de terceiros. Não há rotina de expurgo posterior.
- A pessoa pode se cadastrar novamente depois; será um Perfil novo, sem
  qualquer ligação com o anterior.
- A tela de exclusão vive junto do Perfil do próprio Usuário, não numa
  área administrativa.
- Não é criado nenhum papel novo: o herdeiro é o Administrador do distrito
  que já existe no glossário (Princípio V da constituição).
- As restrições técnicas levantadas na investigação — a amarração do Perfil
  ao login, a invariante que exige o Dono participar do próprio Grupo, e a
  atomicidade da operação — são tratadas em `plan.md`, não aqui.

## Dados pessoais tratados *(exigido pela constituição, § Requisitos de Domínio e Compliance)*

- **Quais dados são afetados**: nome, Apelido, telefone, Igreja de origem,
  gênero e idade — todos removidos. O registro de consentimento LGPD e a
  data de criação permanecem, sem conteúdo identificável associado.
- **Finalidade**: atender ao art. 18, VI da LGPD, mantendo a base do art.
  16 para conservar o histórico de terceiros de forma anonimizada.
- **Quem pode ver**: ninguém vê dado pessoal da pessoa que saiu. O que
  permanece visível é a expressão "Membro removido" onde antes havia nome
  ou Apelido.
- **Consentimento adicional**: nenhum. A exclusão é exercício de direito, e
  não coleta de dado novo.
- **Comportamento de borda do Princípio IV declarado**: fila de espera
  (promoção ao liberar vaga em Ação futura), Rodada de votação (aberta é
  herdada, fechada é histórico), revogação de presença (aplicada às Ações
  futuras) e composição de Dupla Missionária (preservada pela regra de não
  ocupar vaga futura). Voto em Rodada aberta é retirado (FR-018); desempate
  continua por sorteio ao fechar.
