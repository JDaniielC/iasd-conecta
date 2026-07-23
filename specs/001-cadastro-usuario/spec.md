# Feature Specification: Cadastro de Perfil e Upgrade para Conta

**Feature Branch**: `001-cadastro-usuario`

**Created**: 2026-07-23

**Status**: Draft

**Input**: User description: "Cadastro e autenticação de Usuário: pessoa cria conta (nome moderado contra palavrões, Igreja de origem opcional entre as igrejas do distrito, telefone opcional, gênero, idade nunca exibida a outros, consentimento LGPD obrigatório), faz login depois, e se for menor de idade define um Apelido que substitui o nome real em toda exibição pública. Visitante (sem cadastro) continua podendo ver Grupos e Ações livremente sem essa conta."

## Clarifications

### Session 2026-07-23

- Q: Cadastro deve exigir e-mail (ou outro identificador fixo) como credencial de login obrigatória? → A: Não. Todo Usuário começa como Perfil, sem credencial obrigatória. Credencial de login (Conta) é upgrade opcional, só exigido para se declarar Líder/Diretor de Ministério — porque essa identificação é pública e precisa sobreviver troca de aparelho.
- Q: Um Perfil sem Conta sobrevive a reinstalação do app ou troca de aparelho? → A: Não. Perfil é local ao aparelho; se o Usuário reinstalar ou trocar de aparelho sem antes virar Conta, o Perfil se perde, sem forma de recuperação.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Criação de Perfil (Priority: P1)

Uma pessoa sem cadastro decide criar um Perfil para poder participar de Grupos e
Ações. Ela informa nome, gênero, idade, e opcionalmente Igreja de origem e
telefone, e aceita o consentimento LGPD — sem precisar de e-mail nem senha. Ao
final, ela vira Usuário (nível Perfil) e ganha acesso a participar, votar e
criar conteúdo.

**Why this priority**: sem Perfil, nenhuma outra funcionalidade do domínio
(participar de Grupo, votar, propor Ação) existe. É a fundação de tudo mais, e
não pode ter fricção de credencial no caminho.

**Independent Test**: pode ser testado sozinho preenchendo o formulário de
cadastro do zero, sem informar e-mail/senha, e confirmando que o Perfil é
criado e a pessoa passa a ser tratada como Usuário (não mais Visitante).

**Acceptance Scenarios**:

1. **Given** uma pessoa sem cadastro, **When** ela preenche nome, gênero,
   idade e aceita o consentimento LGPD (sem Igreja, telefone, e-mail ou
   senha), **Then** o Perfil é criado com sucesso.
2. **Given** uma pessoa preenchendo o cadastro, **When** ela tenta enviar sem
   marcar o consentimento LGPD, **Then** o sistema bloqueia a criação do
   Perfil.
3. **Given** uma pessoa preenchendo o nome, **When** o nome contém palavrão,
   **Then** o sistema rejeita o nome e pede correção antes de prosseguir.
4. **Given** uma pessoa cadastrando, **When** ela escolhe uma Igreja de
   origem, **Then** só as igrejas da lista do distrito aparecem como opção.
5. **Given** um Perfil já criado, **When** a pessoa fecha e reabre o app no
   mesmo aparelho, **Then** ela continua reconhecida como o mesmo Usuário, sem
   precisar recadastrar nem informar qualquer credencial.

---

### User Story 2 - Apelido obrigatório para menor de idade (Priority: P2)

Uma pessoa menor de idade se cadastrando é levada a definir um Apelido (sem
informação identificável) antes de concluir o cadastro. Daí em diante, esse
Apelido aparece em qualquer lugar público no lugar do nome real dela.

**Why this priority**: proteção de dado sensível de menor de idade é
não-negociável (Princípio II da constituição), mas é um sub-fluxo dentro do
cadastro da P1, não uma jornada isolada de valor equivalente.

**Independent Test**: pode ser testado sozinho cadastrando um Perfil com idade
abaixo de 18 e verificando que o app exige Apelido antes de concluir, e que o
nome real dela nunca aparece em nenhuma tela pública depois.

**Acceptance Scenarios**:

1. **Given** uma pessoa cadastrando com idade abaixo de 18, **When** ela chega
   na etapa final do cadastro, **Then** o sistema exige um Apelido antes de
   permitir concluir.
2. **Given** um Perfil de menor de idade já cadastrado com Apelido, **When**
   qualquer outro Usuário ou Visitante visualiza esse Perfil em Grupo ou Ação,
   **Then** o Apelido é exibido, nunca o nome real.
3. **Given** uma pessoa cadastrando com idade 18 ou mais, **When** ela chega
   no fim do cadastro, **Then** o sistema não exige Apelido (é opcional).

---

### User Story 3 - Upgrade de Perfil para Conta (Priority: P3)

Um Usuário que já tem Perfil decide vincular uma credencial de login (Conta)
para não perder sua identificação ao trocar de aparelho, ou porque quer se
declarar Líder/Diretor de um Ministério (o que exige Conta).

**Why this priority**: cobre um caso de uso mais avançado (persistência entre
aparelhos, pré-requisito de Líder/Diretor) que não bloqueia o valor central de
participar de Grupos e Ações entregue pela P1.

**Independent Test**: pode ser testado sozinho criando um Perfil, fazendo o
upgrade para Conta, e então recuperando esse mesmo Perfil (mesmo nome,
Apelido, participações) em outro aparelho usando a credencial vinculada.

**Acceptance Scenarios**:

1. **Given** um Usuário com Perfil, **When** ele opta por criar uma Conta,
   **Then** o sistema vincula uma credencial de login sem alterar nenhum dado
   já cadastrado no Perfil.
2. **Given** um Usuário com Conta, **When** ele instala o app em outro
   aparelho e informa a credencial, **Then** o mesmo Perfil (dados,
   participações) é recuperado.
3. **Given** um Usuário informando credenciais erradas, **When** ele tenta
   entrar, **Then** o sistema recusa o acesso com mensagem clara, sem revelar
   se o erro foi no identificador ou na senha.
4. **Given** um Usuário só com Perfil (sem Conta), **When** ele tenta se
   autodeclarar Líder/Diretor de um Ministério, **Then** o sistema exige o
   upgrade para Conta antes de prosseguir.

### Edge Cases

- Perfil sem Conta, aparelho reinstala o app ou é trocado: Perfil se perde,
  sem forma de recuperação — comportamento esperado, não um bug.
- O que acontece se a pessoa mudar a idade cadastrada de menor para maior (ou
  vice-versa) depois? Apelido deixa de ser obrigatório mas, se já definido,
  continua disponível para uso.
- Nome moderado como impróprio em loop (pessoa insiste em variações do mesmo
  palavrão): sistema continua rejeitando, sem limite de tentativas.
- Igreja de origem escolhida deixa de existir na lista do distrito depois do
  cadastro (removida pelo Administrador do distrito): Perfil existente mantém
  o vínculo antigo como histórico, sem forçar recadastro.
- Pessoa tenta acessar tela de Perfil de outro Usuário: idade nunca aparece,
  mesmo em rotas diretas ou exportação de dados.
- Visitante navegando sem cadastro tenta participar de uma Ação ou votar:
  sistema bloqueia a ação e direciona para o cadastro de Perfil, mas a
  navegação de Grupos/Ações em si nunca é bloqueada.
- Usuário só com Perfil tenta se autodeclarar Líder/Diretor: sistema pede
  upgrade para Conta antes; o fluxo de autodeclaração e confirmação pelo
  Administrador do distrito em si é uma feature futura, fora de escopo aqui.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: Sistema DEVE permitir que qualquer pessoa crie um Perfil
  informando nome, gênero, idade e consentimento LGPD (todos obrigatórios),
  com Igreja de origem e telefone como campos opcionais, sem exigir e-mail
  nem senha.
- **FR-002**: Sistema DEVE moderar o nome informado contra uma lista de
  palavrões antes de aceitar o cadastro, rejeitando e pedindo correção quando
  encontrar violação.
- **FR-003**: Sistema DEVE exigir aceite explícito do consentimento LGPD
  antes de concluir a criação do Perfil; sem aceite, o Perfil não é criado.
- **FR-004**: Sistema NUNCA DEVE exibir a idade de um Usuário a nenhum outro
  Usuário ou Visitante, em nenhuma tela, exportação ou resposta.
- **FR-005**: Sistema DEVE exigir que um Perfil com idade abaixo de 18 anos
  defina um Apelido antes de considerar o cadastro concluído.
- **FR-006**: Sistema DEVE exibir o Apelido no lugar do nome real em toda
  exibição pública de um Perfil que tenha Apelido definido.
- **FR-007**: Sistema DEVE manter o Perfil reconhecido no mesmo aparelho
  entre sessões, sem exigir recadastro nem qualquer ação de login.
- **FR-008**: Sistema DEVE continuar permitindo que Visitantes sem cadastro
  vejam Grupos e Ações livremente, sem exigir Perfil para essa visualização.
- **FR-009**: Sistema DEVE impedir que um Visitante sem Perfil participe,
  vote ou crie qualquer conteúdo, direcionando-o ao cadastro quando tentar.
- **FR-010**: Sistema DEVE restringir a escolha de Igreja de origem no
  cadastro à lista atual de igrejas do distrito, ou permitir deixar em branco.
- **FR-011**: Sistema DEVE oferecer, como ação opcional e não bloqueante, o
  upgrade de um Perfil para Conta, vinculando uma credencial de login sem
  alterar os dados já cadastrados.
- **FR-012**: Sistema DEVE exigir que o Usuário tenha Conta (Perfil sem
  credencial não é suficiente) antes de permitir a autodeclaração de
  Líder/Diretor de um Ministério.
- **FR-013**: Sistema DEVE permitir que um Usuário com Conta recupere seu
  Perfil (mesmos dados e participações) em outro aparelho ao informar a
  credencial vinculada.
- **FR-014**: Sistema DEVE recusar login com credenciais incorretas sem
  revelar qual parte (identificador ou senha) estava errada.

### Key Entities

- **Usuário**: pessoa cadastrada, em um de dois níveis — Perfil ou Conta (ver
  Perfil e Conta abaixo). Atributos comuns: nome (moderado), Apelido
  (opcional, obrigatório se menor de idade), Igreja de origem (opcional),
  telefone (opcional), gênero, idade (privada — nunca exibida a outros),
  consentimento LGPD (obrigatório, com data de aceite).
- **Perfil**: nível padrão de um Usuário, sem credencial de login. Local ao
  aparelho — perdido se o app for reinstalado sem upgrade prévio para Conta.
- **Conta**: upgrade opcional do Perfil que adiciona uma credencial de login
  recuperável entre aparelhos. Pré-requisito exclusivo para se autodeclarar
  Líder/Diretor.
- **Igreja**: nome de uma igreja do distrito, mantido pelo Administrador do
  distrito. Usada apenas como opção selecionável no cadastro nesta feature.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Uma pessoa nova consegue concluir a criação do Perfil em menos
  de 2 minutos, sem precisar de e-mail nem senha.
- **SC-002**: 100% das exibições públicas de um Perfil marcado como menor de
  idade mostram o Apelido, nunca o nome real.
- **SC-003**: Auditoria de qualquer tela ou resposta do sistema encontra 0
  ocorrências de idade de Usuário exposta a outra pessoa.
- **SC-004**: Um Usuário reabre o app no mesmo aparelho e continua
  reconhecido em menos de 5 segundos, sem nenhuma ação de login.
- **SC-005**: Visitantes conseguem navegar por Grupos e Ações sem nenhuma
  tela de cadastro bloqueando essa visualização.
- **SC-006**: Um Usuário que fez upgrade para Conta consegue recuperar seu
  Perfil completo (dados e participações) em um novo aparelho.

## Assumptions

- Perfil não exige nenhuma credencial; os métodos de login oferecidos no
  upgrade para Conta (e-mail/senha, telefone, ou outro suportado nativamente)
  ficam a critério do plano técnico, não fixados nesta spec.
- "Menor de idade" segue o limite legal brasileiro: idade abaixo de 18 anos.
- Moderação de nome nesta versão é automática (lista de bloqueio), sem
  revisão humana.
- A lista de Igrejas do distrito já existe como dado consumível (mantida pelo
  Administrador do distrito); esta feature não cria a tela de gestão dessa
  lista, só a consome como opção no cadastro.
- O fluxo de autodeclaração de Líder/Diretor e confirmação pelo Administrador
  do distrito é uma feature futura separada; esta feature só garante que a
  capacidade de Conta exista como pré-requisito para ela.
- Recuperação de credencial de Conta (ex.: esqueci minha senha) segue os
  mecanismos padrão do provedor de autenticação, sem redesenho nesta spec.
