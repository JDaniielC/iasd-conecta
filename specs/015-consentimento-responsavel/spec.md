# Feature Specification: Consentimento de responsável para menor de idade

**Feature Branch**: `015-consentimento-responsavel`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado #1 da varredura de 2026-08-09 — trabalho pendente sem spec.

## Contexto: o app afirma por escrito algo que o código não faz

A Política de Privacidade, hoje no ar, diz a um pai ou mãe
(`lib/features/legal/presentation/privacy_policy_page.dart:233-236`):

> "Se você é pai, mãe ou responsável por uma criança (até 12 anos), o cadastro dela precisa
> ser feito por você ou com você presente, **e é você quem aceita esta política e os Termos de
> Uso em nome dela**."

**Nada no código coleta, registra ou sequer pergunta isso.** Uma busca por
`responsav|parental|guardian` em `lib/` e `supabase/migrations/` retorna **zero ocorrências**.
O banco aceita qualquer idade (`20260723191202_perfis_igrejas.sql:35` —
`idade integer not null check (idade >= 0)`), e o cadastro de uma criança de 6 anos passa
igual ao de um adulto.

O público infantil não é hipotético: `CATEGORIAS-DE-ACAO.md:13-14` descreve **Aventureiros,
clube para crianças de 6 a 9 anos**, e Desbravadores de 10 a 15.

O mecanismo mínimo já foi proposto e está explicitamente **não implementado** em
`REVISAO-JURIDICA.md:88-112`.

Isto não é dívida técnica. É a divergência entre o que o app promete e o que ele executa — que
a constituição do projeto trata como violação, não como detalhe.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Mãe cadastra a filha de 8 anos e assume a responsabilidade (Priority: P1)

Uma mãe abre o app para inscrever a filha nos Aventureiros. Preenche o cadastro e informa a
idade: 8 anos. Antes de concluir, o app apresenta um passo a mais — nome do responsável,
contato do responsável, e uma autorização destacada, separada do consentimento comum, que ela
marca por si. Só então o cadastro conclui.

**Why this priority**: é o motivo da feature existir. Sem isso, a Política mente.

**Independent Test**: preencher um cadastro com idade abaixo do limiar e verificar que o app
**não conclui** sem os dados do responsável e a autorização marcada.

**Acceptance Scenarios**:

1. **Given** alguém preenchendo o cadastro, **When** informa idade **abaixo do limiar de
   criança**, **Then** o app pede nome do responsável, contato do responsável, e uma
   autorização em caixa separada, antes de concluir.
2. **Given** esse passo, **When** a pessoa tenta concluir sem marcar a autorização, **Then** o
   cadastro é recusado, com o motivo dito em uma frase.
3. **Given** esse passo, **When** a pessoa tenta concluir sem preencher nome ou contato do
   responsável, **Then** o cadastro é recusado.
4. **Given** idade **acima** do limiar, **When** a pessoa preenche o cadastro, **Then** nada
   muda em relação a hoje — nenhum passo novo aparece.
5. **Given** o cadastro concluído de um menor, **When** o registro é gravado, **Then** ficam
   registrados quem autorizou, o contato informado e **quando** a autorização foi dada.
6. **Given** o texto da autorização, **When** alguém o lê, **Then** ele diz em português
   direto o que está sendo autorizado, sem juridiquês.

---

### User Story 2 - A autorização é verificável, não só uma caixa marcada (Priority: P2)

O responsável pelo app precisa poder demonstrar, se questionado, que houve autorização: quem
deu, para qual criança, quando, e sob qual versão do texto legal.

**Why this priority**: uma autorização que não deixa rastro tem o mesmo valor probatório de
nenhuma autorização. Depende da US1 existir.

**Independent Test**: consultar o registro de um cadastro de menor e encontrar quem autorizou,
quando, e sob qual versão do texto.

**Acceptance Scenarios**:

1. **Given** um cadastro de menor concluído, **When** o registro é consultado, **Then** traz
   nome do responsável, contato, data/hora da autorização e a versão do texto legal vigente.
2. **Given** um cadastro de maior de idade, **When** o registro é consultado, **Then** os
   campos de responsável estão vazios — não são preenchidos por engano.
3. **Given** a tentativa de gravar um cadastro de menor sem autorização por um caminho que não
   passe pela tela, **Then** o sistema recusa.

---

### User Story 3 - O responsável exerce os direitos da criança (Priority: P3)

O responsável que autorizou consegue pedir acesso, correção ou exclusão dos dados da criança,
pelo canal que a Política já indica, e o app sabe a quem responder.

**Why this priority**: é o que dá sentido prático à autorização. Vale muito e não bloqueia a
US1.

**Acceptance Scenarios**:

1. **Given** um pedido do responsável pelo canal de contato, **When** o app é consultado,
   **Then** o contato registrado confirma que quem pede é quem autorizou.
2. **Given** a Política de Privacidade, **When** o responsável a lê, **Then** ela descreve como
   ele exerce os direitos da criança, e essa descrição corresponde ao que o app faz.

---

### Edge Cases

- **Idade exatamente no limiar**: a regra precisa dizer de que lado o limiar cai, sem
  ambiguidade.
- **Adolescente entre o limiar de criança e 18**: a Política hoje "recomenda o mesmo
  acompanhamento" sem exigir. A feature precisa decidir se recomenda ou exige.
- **Idade alterada depois do cadastro**: se um dia existir edição de perfil (feature 016),
  baixar a idade para a faixa de criança precisa exigir a autorização.
- **Cadastro já existente de menor, feito antes desta feature**: existem hoje, sem
  autorização. A feature precisa decidir o que fazer com eles.
- **Contato do responsável inválido ou inventado**: o app não verifica. É autodeclaração.
- **Exclusão de conta de um menor**: quem pode pedir — a criança ou o responsável?

## Requirements *(mandatory)*

### Coleta (US1)

- **FR-001**: Quando a idade informada no cadastro for **abaixo do limiar de criança**, o
  sistema DEVE exigir, antes de concluir: nome do responsável, contato do responsável e uma
  autorização marcada explicitamente.
- **FR-002**: A autorização DEVE ser uma caixa **separada e destacada** do consentimento LGPD
  comum, recusável de forma independente — mesmo padrão que o consentimento de Igreja de
  origem já usa.
- **FR-003**: O texto da autorização DEVE dizer, em português direto, o que está sendo
  autorizado e por quem, sem jargão jurídico.
- **FR-004**: O sistema NÃO DEVE concluir o cadastro de menor sem os três itens de FR-001.
- **FR-005**: Para idade **acima** do limiar, o fluxo de cadastro NÃO DEVE mudar em nada.
- **FR-006**: O sistema NÃO DEVE verificar a identidade do responsável — é autodeclaração,
  como `REVISAO-JURIDICA.md:88-112` propõe, e a Política DEVE dizer isso.

### Registro (US2)

- **FR-007**: O sistema DEVE registrar nome do responsável, contato, data/hora da autorização
  e a versão do texto legal vigente no momento.
- **FR-008**: Para maior de idade, os campos de responsável DEVEM ficar vazios.
- **FR-009**: A exigência DEVE ser garantida **no banco**, não apenas na tela — um cadastro de
  menor sem autorização não pode entrar por nenhum caminho.

### Transparência

- **FR-010**: A Política de Privacidade DEVE ser atualizada para descrever o mecanismo que
  passou a existir, e para declarar que a identidade do responsável não é verificada.
- **FR-011**: `MAPA-DE-DADOS.md` DEVE registrar os campos novos, com finalidade, quem vê e
  prazo, na mesma forma das demais entradas.
- **FR-012**: `REVISAO-JURIDICA.md` DEVE deixar de marcar a proposta como não implementada.
- **FR-013**: `CONTEXT.md` DEVE receber o termo novo — **Responsável** — antes de ele entrar em
  código.

## Key Entities

- **Responsável**: pessoa que autoriza o cadastro e o uso dos dados de um menor. Não tem
  cadastro próprio no app; existe como um conjunto de campos no registro do menor: nome,
  contato, data/hora da autorização e versão do texto aceito.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II — NON-NEGOTIABLE):

- **Qual dado novo é coletado**: nome e contato de uma pessoa **que não é usuária do app** — o
  responsável. É dado pessoal de terceiro, e a feature precisa tratá-lo como tal.
- **Finalidade**: cumprir a exigência de autorização para tratamento de dado de menor, e
  permitir que o responsável exerça os direitos da criança.
- **Quem pode ver**: ninguém além do responsável pelo app. **Nunca** exibido a outros
  Usuários, nem a Visitante.
- **Consentimento**: é o próprio ato de autorizar. Destacado e recusável, como o de Igreja de
  origem.
- **Redução de exposição**: nenhuma. A feature **acrescenta** dado pessoal — o que se ganha é
  legitimidade do tratamento que já acontece hoje sem base.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum. A feature toca só o
cadastro.

**Papéis** (Princípio V): **Responsável não é um papel do sistema.** Não tem login, não tem
permissão, não aparece em nenhuma tela do app. São campos no cadastro de um menor. Se um dia
precisar de acesso próprio, isso é outra feature e exige atualizar `CONTEXT.md`.

## Success Criteria *(mandatory)*

- **SC-001**: 0 cadastros de menor concluídos sem nome do responsável, contato e autorização
  marcada — verificado tanto pela tela quanto por tentativa direta no banco.
- **SC-002**: 100% dos cadastros de menor gravados trazem quem autorizou, quando, e sob qual
  versão do texto.
- **SC-003**: 0 mudanças no fluxo de cadastro de maior de idade — o número de passos e de
  campos é idêntico ao de hoje.
- **SC-004**: 0 exibições do nome ou contato do responsável a qualquer Usuário ou Visitante.
- **SC-005**: 0 afirmações falsas nos documentos: Política, `MAPA-DE-DADOS.md` e
  `REVISAO-JURIDICA.md` descrevem o mecanismo que existe.
- **SC-006**: Uma mãe conclui o cadastro da filha em até 3 minutos, incluindo o passo novo.

## Assumptions

- **Limiar de idade a definir no plano**: a Política fala em "criança (até 12 anos)" e
  `REVISAO-JURIDICA.md:93` propõe "menor que 12". A spec usa "limiar de criança" e a definição
  exata do número, e de que lado ele cai, fica para `/speckit-clarify` — é a decisão que mais
  muda o comportamento.
- **Adolescente de 13 a 17 continua só recomendado**, não exigido, como a Política já diz hoje.
  Exigir para toda a faixa é decisão de produto, não consequência automática.
- **Sem verificação de identidade do responsável**: autodeclaração, conforme a proposta em
  `REVISAO-JURIDICA.md:99-104` — verificação robusta é desproporcional para este produto, e a
  Política vai dizer isso.
- **Cadastros de menor que já existem**: a feature **não** os corrige retroativamente nem os
  bloqueia. O que fazer com eles é decisão de produto, e está registrada aqui como pendência
  em aberto — não como esquecimento.
- **Sem canal de notificação ao responsável**: o app não avisa ninguém por e-mail ou telefone.
  O contato é registro, não canal.
- **Depende da feature 017** para gravar a versão do texto aceito. Se a 017 não estiver
  pronta, esta grava a versão vigente do jeito que der, e a 017 depois unifica.
