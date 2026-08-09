# Feature Specification: Arquivar Grupo

**Feature Branch**: `014-arquivar-grupo`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "ser possível deletar um grupo no app"

## Contexto

Hoje não existe apagar Grupo — nem na tela nem por trás dela.
`lib/features/group/data/group_repository.dart` só apaga vínculos de participação
(linhas 96 e 105): sair do Grupo e remover participante.

E o banco **recusa ativamente**. Das quatro coisas que apontam para um Grupo, só uma cai em
cascata:

| O que aponta para o Grupo | Comportamento hoje |
|---|---|
| Participações no Grupo | cai em cascata — vínculo leve e revogável |
| Rodadas de votação | **recusa** — a exclusão do Grupo falha |
| Ações de Grupo | **recusa** — a exclusão do Grupo falha |
| Declarações de Líder/Diretor | **recusa** — a exclusão do Grupo falha |

Ou seja: um Grupo que já teve qualquer atividade **não pode ser apagado** sem antes decidir o
que acontece com cada uma dessas coisas. Não é uma tela faltando; é o desenho do banco
protegendo o que outras pessoas construíram.

**"Deletar" neste app vira "arquivar"**, por decisão registrada abaixo. É o mesmo espírito da
feature 009, que resolveu "excluir conta" com anonimização em vez de apagar: o que uma pessoa
sozinha não pode destruir é o que outras pessoas fizeram.

> **Padrão de idioma (Princípio I, e vale para código de teste também).** Todo identificador
> Dart criado nesta feature — classe, enum e seus valores, método, função, variável local,
> parâmetro, campo, provider e nome de arquivo — é escrito **em inglês**, seguindo o mapa de
> `CONTEXT.md`. Isso inclui os arquivos de teste: só o **nome do arquivo** de teste continua
> em português. Banco de dados, chaves de leitura/gravação (`map['nome']`, `'data_hora'`) e
> strings visíveis ao usuário continuam em português, sem exceção.
>
> Aprendido na 011, onde helpers de teste e variáveis locais nasceram em português
> (`_comoUsuario`, `acaoId`, `pumpDetalhe`, `comAcento`) e precisaram de um passe de
> correção depois.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Arquivar o próprio Grupo, sabendo o estrago (Priority: P1)

O Dono de um Grupo que não vai mais existir — a turma se desfez, o ministério mudou de nome,
o Grupo foi criado por engano — aciona a opção de arquivar. Antes de confirmar, ele lê
exatamente o que vai acontecer: quantas Ações futuras serão canceladas, quantas pessoas já
tinham presença confirmada nelas, quantas Rodadas de votação abertas serão encerradas sem
apuração, e quantas pessoas participam do Grupo. Confirma, e o Grupo sai do ar.

**Why this priority**: é a feature pedida. E o aviso vem junto porque, sem ele, uma pessoa
desfaz o compromisso de dezenas de outras sem saber que fez isso.

**Independent Test**: como Dono de um Grupo com 2 Ações futuras, 5 presenças confirmadas e 1
Rodada aberta, acionar arquivar e verificar que a confirmação mostra esses quatro números
antes de qualquer coisa acontecer.

**Acceptance Scenarios**:

1. **Given** um Dono de Grupo, **When** aciona arquivar, **Then** vê, antes de confirmar, a
   contagem de Ações de Grupo futuras que serão canceladas, de presenças já confirmadas
   nelas, de Rodadas de votação abertas que serão encerradas, e de participantes do Grupo.
2. **Given** essa confirmação, **When** ele confirma, **Then** o Grupo é arquivado e todas
   essas consequências acontecem de uma vez.
3. **Given** essa confirmação, **When** ele desiste, **Then** nada muda — nem o Grupo, nem as
   Ações, nem as Rodadas, nem as presenças.
4. **Given** um Grupo sem nenhuma Ação futura, Rodada aberta ou participante além do Dono,
   **When** ele aciona arquivar, **Then** a confirmação diz que nada será perdido, em vez de
   mostrar quatro zeros.
5. **Given** um Usuário que participa do Grupo mas não é o Dono, **When** abre o Grupo,
   **Then** não encontra opção de arquivar.
6. **Given** um Grupo que é Ministério, com Líder/Diretor confirmado no ano, **When** o Dono
   aciona arquivar, **Then** a confirmação avisa **explicitamente** que a identificação
   pública do Líder/Diretor daquele Ministério deixará de ser exibida.
7. **Given** um Grupo já arquivado, **When** alguém o alcança por link direto, **Then** não
   encontra opção de arquivar de novo.

---

### User Story 2 - O Grupo arquivado sai do caminho de todo mundo (Priority: P2)

Quem participava do Grupo abre o app e ele não está mais lá. Não aparece na lista, não aceita
novos participantes, não aceita proposta de Ação candidata nem voto. As Ações futuras dele
aparecem canceladas para quem tinha confirmado presença. O que já aconteceu continua tendo
acontecido — Rodadas fechadas, apurações, Ações passadas.

**Why this priority**: é a metade que o Usuário percebe. Arquivar sem que o Grupo suma de fato
seria não arquivar. Depende da US1 existir, mas é verificável sozinha.

**Independent Test**: arquivar um Grupo e verificar, como outro Usuário, que ele sumiu da
lista e que nenhuma ação sobre ele é mais possível.

**Acceptance Scenarios**:

1. **Given** um Grupo arquivado, **When** qualquer pessoa abre a lista de Grupos, **Then** ele
   não aparece, sob nenhum filtro de Igreja nem ordenação.
2. **Given** um Grupo arquivado, **When** um Usuário tenta participar dele, **Then** não
   consegue.
3. **Given** um Grupo arquivado, **When** um participante tenta propor Ação candidata, abrir
   Rodada de votação ou votar, **Then** não consegue.
4. **Given** um Grupo arquivado, **When** o Usuário que tinha presença confirmada em uma Ação
   futura dele abre a lista de Ações, **Then** aquela Ação aparece como cancelada.
5. **Given** um Grupo arquivado, **When** alguém abre uma Rodada de votação já fechada dele
   por link direto, **Then** o resultado da apuração continua lá, intacto.
6. **Given** um Grupo arquivado que era Ministério, **When** um Visitante procura quem é o
   Líder/Diretor, **Then** não encontra — a identificação sai do ar junto com o Ministério.
7. **Given** um Grupo arquivado, **When** alguém o alcança por link direto, **Then** vê que
   está arquivado, em vez de um erro.

---

### User Story 3 - O Administrador do distrito conserta o engano (Priority: P3)

Alguém arquivou um Grupo que não devia. O Administrador do distrito encontra os Grupos
arquivados, entende o que aconteceu, e devolve o Grupo ao ar. Os participantes voltam. As
Ações canceladas **não** voltam, e a tela diz isso antes de ele confirmar.

**Why this priority**: é a rede de segurança. Vale muito no dia em que precisar, e não faz
falta no dia a dia. Depende da US1 e da US2.

**Independent Test**: arquivar um Grupo e, como Administrador do distrito, desarquivá-lo,
verificando que ele volta à lista com os participantes.

**Acceptance Scenarios**:

1. **Given** um Administrador do distrito, **When** procura Grupos arquivados, **Then**
   encontra a lista, com quem arquivou e quando.
2. **Given** essa lista, **When** ele desarquiva um Grupo, **Then** o Grupo volta à listagem e
   volta a aceitar participação, proposta de Ação candidata, Rodada e voto.
3. **Given** o desarquivamento, **When** ele confirma, **Then** os participantes que estavam
   no Grupo continuam participando — ninguém precisa entrar de novo.
4. **Given** o desarquivamento, **When** ele o aciona, **Then** a tela avisa, antes de
   confirmar, que as Ações canceladas e as Rodadas encerradas **não** voltam.
5. **Given** um Usuário comum ou o próprio Dono do Grupo, **When** procura desarquivar,
   **Then** não encontra essa opção — só o Administrador do distrito desarquiva.

---

### Edge Cases

- **Grupo arquivado por engano com Ação amanhã**: as pessoas veem a Ação cancelada. Desarquivar
  não a ressuscita. É a consequência mais dura da feature, e a confirmação da US1 precisa
  deixá-la clara antes, não depois.
- **Rodada de votação aberta no momento do arquivamento**: é encerrada **sem apuração**, e
  todas as candidatas são descartadas. Apurar produziria uma Ação confirmada dentro de um
  Grupo que acabou de sair do ar.
- **Fila de espera em Ação futura cancelada**: ninguém é promovido — não há vaga a preencher
  numa Ação que não vai acontecer.
- **Ação de Grupo que já aconteceu**: não é tocada. Histórico é histórico.
- **Grupo arquivado enquanto alguém está na tela dele**: quem já estava não quebra; na próxima
  carga vê que foi arquivado.
- **Duas pessoas arquivando ao mesmo tempo**: o segundo pedido não duplica nada nem produz
  erro confuso.
- **Dono do Grupo exclui a conta**: a posse do Grupo, arquivado ou não, é herdada como já
  acontece hoje — arquivar não muda a herança.
- **Grupo arquivado com foto de capa**: a capa permanece, porque o Grupo permanece. Só some se
  o Grupo for apagado de verdade um dia.
- **Nome de Grupo arquivado**: continua ocupado. Criar outro Grupo com o mesmo nome não é
  bloqueado nem liberado por esta feature — nada muda nessa regra.

## Requirements *(mandatory)*

### Arquivar (US1)

- **FR-001**: O Dono do Grupo e o Administrador do distrito DEVEM poder arquivar um Grupo.
- **FR-002**: Nenhum outro papel DEVE ter essa opção, nem participante, nem Líder/Diretor.
- **FR-003**: Antes de qualquer efeito, o sistema DEVE exibir uma confirmação com quatro
  números reais daquele Grupo: Ações de Grupo futuras que serão canceladas, presenças já
  confirmadas nelas, Rodadas de votação abertas que serão encerradas, e participantes.
- **FR-004**: Quando não houver nada a perder, a confirmação DEVE dizer isso em palavras, em
  vez de exibir zeros.
- **FR-005**: Quando o Grupo for Ministério com Líder/Diretor confirmado no ano vigente, a
  confirmação DEVE avisar explicitamente que a identificação pública do Líder/Diretor deixará
  de ser exibida.
- **FR-006**: Desistir da confirmação NÃO DEVE alterar absolutamente nada.
- **FR-007**: Ao confirmar, o sistema DEVE, de uma vez só: marcar o Grupo como arquivado,
  cancelar as Ações de Grupo futuras não canceladas, e encerrar as Rodadas de votação abertas
  **sem apurar**, descartando todas as candidatas.
- **FR-008**: O sistema DEVE registrar quem arquivou e quando.
- **FR-009**: Um Grupo já arquivado NÃO DEVE poder ser arquivado de novo.

### O que "arquivado" significa (US2)

- **FR-010**: Um Grupo arquivado NÃO DEVE aparecer na listagem de Grupos, sob nenhum filtro
  nem ordenação.
- **FR-011**: Um Grupo arquivado NÃO DEVE aceitar novo participante.
- **FR-012**: Um Grupo arquivado NÃO DEVE aceitar proposta de Ação candidata, abertura de
  Rodada de votação nem voto.
- **FR-013**: Um Grupo arquivado DEVE continuar alcançável por link direto, exibindo que está
  arquivado, em vez de erro.
- **FR-014**: Ações de Grupo que já aconteceram, Rodadas já fechadas e suas apurações NÃO
  DEVEM ser alteradas pelo arquivamento.
- **FR-015**: As presenças já confirmadas nas Ações canceladas NÃO DEVEM ser apagadas — a Ação
  aparece cancelada, com quem havia confirmado, como já acontece com qualquer Ação cancelada.
- **FR-016**: Um Ministério arquivado NÃO DEVE exibir a identificação pública de
  Líder/Diretor.
- **FR-017**: As participações no Grupo NÃO DEVEM ser apagadas pelo arquivamento — elas ficam
  suspensas, para que o desarquivamento as devolva.

### Desarquivar (US3)

- **FR-018**: Só o Administrador do distrito DEVE poder desarquivar um Grupo.
- **FR-019**: O Administrador do distrito DEVE ter acesso à lista de Grupos arquivados, com
  quem arquivou e quando.
- **FR-020**: Ao desarquivar, o Grupo DEVE voltar à listagem e voltar a aceitar participação,
  proposta de Ação candidata, Rodada de votação e voto.
- **FR-021**: Ao desarquivar, os participantes que estavam no Grupo DEVEM voltar a participar,
  sem precisar entrar de novo.
- **FR-022**: Antes de confirmar o desarquivamento, o sistema DEVE avisar que as Ações
  canceladas e as Rodadas encerradas **não** voltam.

### Vocabulário (Princípio I)

- **FR-023**: `CONTEXT.md` DEVE receber as entradas **Arquivar o Grupo** e **Grupo arquivado**
  antes de o termo entrar em código.

## Key Entities

Nenhuma entidade nova. **Grupo** ganha um estado: ativo ou arquivado, com o registro de quem
arquivou e quando. Todo o resto — participações, Rodadas, Ações, declarações de Líder/Diretor
— permanece exatamente como está, apenas com o comportamento condicionado a esse estado.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): nenhum dado pessoal novo é coletado. O arquivamento registra
**quem arquivou**, que é um vínculo entre um Perfil já existente e um Grupo já existente, e é
visível apenas ao Administrador do distrito (FR-019). Nada de novo é exibido a Visitante. O
arquivamento **reduz** exposição: o Ministério arquivado deixa de exibir publicamente a
identificação do Líder/Diretor (FR-016).

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV) — esta feature toca quatro das
cinco regras centrais, e por isso todas estão declaradas:

- **Fila de espera**: ninguém é promovido nas Ações canceladas pelo arquivamento. Não há vaga
  a preencher em Ação que não vai acontecer.
- **Desempate por sorteio**: **não acontece**. As Rodadas abertas são encerradas **sem
  apuração** (FR-007) — apurar criaria uma Ação confirmada dentro de um Grupo que acabou de
  sair do ar.
- **Descarte de candidatas**: todas as candidatas das Rodadas abertas são descartadas, sem
  vencedora. É descarte total, não o descarte parcial da apuração normal.
- **Revogação de Participar**: as participações não são apagadas, ficam suspensas (FR-017),
  para o desarquivamento poder devolvê-las.
- **Dupla Missionária**: a validação de composição por gênero não muda. Uma Dupla Missionária
  futura do Grupo arquivado é cancelada como qualquer outra Ação.

**Papéis** (Princípio V): nenhum papel novo. Dono do Grupo e Administrador do distrito
arquivam; só o Administrador desarquiva. Isso detalha um pouco mais o "escopo de moderação"
que `CONTEXT.md` deixa em aberto na entrada do Administrador do distrito.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das confirmações de arquivamento exibem os quatro números reais daquele
  Grupo antes de qualquer efeito.
- **SC-002**: Desistir da confirmação altera 0 registros — verificado comparando o estado do
  Grupo, das Ações, das Rodadas e das presenças antes e depois.
- **SC-003**: Um Grupo arquivado aparece em 0 resultados da listagem, sob qualquer combinação
  de filtro de Igreja e ordenação.
- **SC-004**: 0 tentativas de participar, propor Ação candidata, abrir Rodada ou votar em
  Grupo arquivado são aceitas.
- **SC-005**: 0 Rodadas de votação são apuradas por causa de um arquivamento — nenhuma Ação
  confirmada nasce de um Grupo sendo arquivado.
- **SC-006**: 0 presenças confirmadas são apagadas pelo arquivamento.
- **SC-007**: Após desarquivar, 100% dos participantes que estavam no Grupo voltam a
  participar sem ação nenhuma da parte deles.
- **SC-008**: Um Dono consegue arquivar o próprio Grupo em menos de 1 minuto, do toque inicial
  à confirmação.
- **SC-009**: 0 Ações já ocorridas, Rodadas já fechadas ou apurações são alteradas por
  arquivamento ou desarquivamento.

## Assumptions

- **"Deletar" virou "arquivar"**: o pedido foi "deletar um grupo". A entrega arquiva. O motivo
  está no Contexto: o banco recusa apagar um Grupo com Rodada, Ação ou declaração de
  Líder/Diretor, e apagar de verdade destruiria registro de votação de outras pessoas. Se a
  intenção era mesmo remover do banco, esta spec está errada e precisa ser refeita.
- **Rodada aberta encerra sem apurar**: decisão tomada aqui, sem consulta, porque a
  alternativa — apurar e criar uma Ação vencedora num Grupo recém-arquivado — não tem leitura
  sensata. É a decisão mais discutível da spec.
- **Ministério não tem proteção extra**: o Dono do Grupo pode arquivar um Ministério com
  Líder/Diretor confirmado, mesmo sendo pessoas diferentes. Decisão registrada do usuário. O
  aviso de FR-005 é a única salvaguarda.
- **Sem prazo e sem apagar de vez**: arquivado fica arquivado indefinidamente. Não há
  expurgo automático depois de N dias — isso exigiria algo rodando sozinho no tempo, que o app
  não tem.
- **Sem notificação**: quem participava do Grupo e quem tinha presença confirmada nas Ações
  canceladas **não é avisado**. O app não tem canal de notificação, e criar um é outra
  feature. As pessoas descobrem ao abrir o app.
- **Apagar de verdade continua não existindo**: esta feature não cria exclusão definitiva de
  Grupo. O requisito FR-021 da feature `013-foto-de-capa` — "quando um Grupo é apagado, sua
  capa deve deixar de existir" — continua descrevendo um evento que não acontece.
- **A herança da exclusão de conta não muda**: um Grupo arquivado cujo Dono exclui a conta é
  herdado como qualquer outro (feature 009).
- **Sem exportar antes de arquivar**: não há como levar o histórico do Grupo embora. Ele fica
  no sistema, alcançável por link direto.
