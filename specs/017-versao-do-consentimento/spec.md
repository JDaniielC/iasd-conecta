# Feature Specification: Versão do texto aceito no consentimento

**Feature Branch**: `017-versao-do-consentimento`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado #3 da varredura de 2026-08-09 — trabalho pendente sem spec.

## Contexto: já existe aceite sem rastro de qual texto foi aceito

O cadastro grava **só a data/hora** do consentimento
(`supabase/migrations/20260723191202_perfis_igrejas.sql:36` —
`consentimento_lgpd_aceito_em timestamptz not null`). Não grava **qual versão** do texto a
pessoa aceitou.

E o texto **já mudou**: `lib/features/legal/legal_metadata.dart:11` está em `version = '1.1'`,
vigente desde 6 de agosto de 2026. Ou seja, **já existem pessoas que aceitaram a 1.0 e outras
que aceitaram a 1.1, e não há como distinguir umas das outras.**

O próprio código registra a dívida, em `legal_metadata.dart:4-9`:

> "Consentimento colhido sob uma versão não cobre finalidade que uma versão posterior venha a
> adicionar — por isso a versão fica num só lugar. `consentimento_lgpd_aceito_em` hoje grava
> só a data/hora do aceite, sem gravar a versão aceita: **se o texto mudar, não há como saber
> quem aceitou qual versão**."

O conserto é pequeno — uma coluna e uma linha. O que não é pequeno é o ônus: quem trata dado
pessoal precisa demonstrar a base legal, e "aceitou alguma coisa em alguma data" não
demonstra.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Todo aceite novo registra qual texto foi aceito (Priority: P1)

A partir de agora, quem se cadastra tem gravado não só quando aceitou, mas **o quê**: a versão
do texto legal vigente naquele momento.

**Why this priority**: para a hemorragia. Cada cadastro feito sem isso aumenta o problema.

**Independent Test**: cadastrar um Perfil e verificar que o registro traz a versão vigente do
texto legal, não só a data.

**Acceptance Scenarios**:

1. **Given** alguém concluindo o cadastro, **When** o Perfil é gravado, **Then** o registro
   traz a versão do texto legal vigente no momento do aceite.
2. **Given** a versão do texto mudando de 1.1 para 1.2, **When** alguém se cadastra depois,
   **Then** o registro traz 1.2, sem ninguém precisar lembrar de atualizar nada.
3. **Given** um cadastro concluído, **When** o registro é consultado, **Then** a versão e a
   data/hora estão juntas — uma sem a outra não responde a pergunta.
4. **Given** o consentimento destacado de Igreja de origem, **When** é dado, **Then** também
   registra a versão vigente.

---

### User Story 2 - Dá para saber quem ainda não aceitou o texto atual (Priority: P2)

O responsável pelo app consegue responder: destas pessoas cadastradas, quantas aceitaram a
versão vigente e quantas aceitaram uma anterior?

**Why this priority**: é o que transforma o dado gravado em resposta útil. Sem isso, a coluna
existe e ninguém a consulta.

**Acceptance Scenarios**:

1. **Given** cadastros feitos sob versões diferentes, **When** o responsável consulta, **Then**
   consegue distinguir quem está sob qual versão.
2. **Given** a versão vigente mudando, **When** a consulta é refeita, **Then** as pessoas que
   aceitaram a versão anterior aparecem como tal, sem nenhum trabalho manual.

---

### User Story 3 - Os aceites antigos são tratados com honestidade (Priority: P3)

Os cadastros que já existem não têm versão registrada. O sistema não inventa uma — registra que
é **desconhecida**, e os documentos dizem por quê.

**Why this priority**: é a parte que mais tenta a gente a mentir. Preencher retroativamente
com "1.0" seria um chute apresentado como fato.

**Acceptance Scenarios**:

1. **Given** um cadastro anterior a esta feature, **When** o registro é consultado, **Then** a
   versão aparece como **desconhecida**, e não como um palpite.
2. **Given** a consulta da US2, **When** é feita, **Then** os aceites de versão desconhecida
   são contados separadamente.
3. **Given** `MAPA-DE-DADOS.md`, **When** alguém o lê, **Then** encontra registrado que existem
   aceites sem versão conhecida, e desde quando.

---

### Edge Cases

- **A versão muda entre a pessoa abrir a tela e concluir o cadastro**: qual vale — a que ela
  leu ou a vigente ao gravar?
- **Cadastro que falha e é refeito**: grava a versão da tentativa que deu certo.
- **Aceite de Igreja de origem dado depois do cadastro** (feature 016): registra a versão do
  momento, que pode ser diferente da do cadastro.
- **Autorização de responsável** (feature 015): é um terceiro aceite, e também precisa de
  versão.
- **Texto legal despublicado ou revertido**: o app não guarda os textos antigos, só o número
  da versão. Saber que alguém aceitou a 1.0 não recupera o que a 1.0 dizia.

## Requirements *(mandatory)*

### Registro (US1)

- **FR-001**: Todo consentimento LGPD dado no cadastro DEVE registrar a versão do texto legal
  vigente no momento do aceite, junto com a data/hora.
- **FR-002**: A versão registrada DEVE vir da fonte única que o app já tem — não de um valor
  digitado ou repetido em outro lugar.
- **FR-003**: O consentimento destacado de Igreja de origem DEVE registrar a versão do mesmo
  jeito.
- **FR-004**: A versão DEVE ser gravada pelo **banco ou pelo servidor**, não por um valor que o
  cliente envia — senão o registro vale o que o cliente disser.

### Consulta (US2)

- **FR-005**: DEVE ser possível distinguir, entre os cadastros existentes, quem aceitou qual
  versão.
- **FR-006**: A consulta DEVE separar os aceites de versão **desconhecida** dos de versão
  conhecida.

### Honestidade sobre o passado (US3)

- **FR-007**: Cadastros anteriores a esta feature DEVEM ficar com a versão explicitamente
  **desconhecida**. O sistema NÃO DEVE preencher retroativamente com um palpite.
- **FR-008**: `MAPA-DE-DADOS.md` DEVE registrar a existência dos aceites sem versão conhecida,
  e o período em que foram colhidos.
- **FR-009**: O comentário em `lib/features/legal/legal_metadata.dart:4-9`, que hoje descreve
  a dívida, DEVE ser atualizado para descrever o que passou a existir.

## Key Entities

Nenhuma entidade nova. **Perfil** ganha, ao lado da data do consentimento, a versão do texto
aceito. É um campo, não um conceito.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): **nenhum dado pessoal novo.** A versão de um documento não é
dado sobre a pessoa — é dado sobre o que ela aceitou. Nenhuma exposição muda: a versão não é
exibida a outros Usuários nem a Visitante. A feature **fortalece** a base legal do tratamento
que já acontece, que é justamente o que o Princípio II protege.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum.

**Papéis** (Princípio V): nenhum papel novo.

## Success Criteria *(mandatory)*

- **SC-001**: 100% dos cadastros feitos após esta feature registram a versão do texto aceito.
- **SC-002**: 0 registros com versão preenchida retroativamente por palpite.
- **SC-003**: Uma consulta responde, em um passo, quantas pessoas estão sob cada versão e
  quantas estão sob versão desconhecida.
- **SC-004**: 0 mudanças no que o Usuário vê ou faz no cadastro — o passo novo é invisível.
- **SC-005**: Quando a versão do texto muda, 0 alterações de código são necessárias para o
  registro passar a gravar a nova.

## Assumptions

- **A versão vem da fonte única que já existe** (`LegalMetadata.version`). Se um dia o texto
  legal virar conteúdo de banco, a fonte muda de lugar mas a regra continua: um lugar só.
- **Não guardamos os textos antigos**, só o número da versão. Saber que alguém aceitou a 1.0
  não recupera o que a 1.0 dizia. Versionar o conteúdo é outra feature, mais cara, e não foi
  pedida.
- **Ninguém é forçado a reaceitar** quando a versão muda. Pedir novo aceite a quem está sob
  versão antiga é decisão de produto — esta feature só torna a pergunta respondível.
- **Sem aviso ao Usuário** de que o texto mudou. Não há canal de notificação no app.
- **Interação com a 015**: a autorização de responsável é um terceiro aceite e também precisa
  de versão. Se a 015 vier antes, ela grava a versão do jeito que der e esta unifica; se vier
  depois, já nasce usando o mecanismo daqui.
- **Interação com a 016**: dar o consentimento de Igreja pela tela de perfil registra a versão
  daquele momento, que pode diferir da do cadastro. São dois aceites distintos, e é correto que
  tenham versões distintas.
