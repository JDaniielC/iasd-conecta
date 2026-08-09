# Feature Specification: Ação — encerramento, contagem de confirmados e clareza do título

**Feature Branch**: `011-acoes-titulo-e-encerramento`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "o título de qualquer ação deve ser a própria ação e não o nome do usuário que a criou, em confirmados adicione a ordem 1.,2.,3., essa ação em especial estava determinada para o dia anterior num horário específico, já passou, porém ainda está lá deveria ter acabado. também na listagem de ações deve apresentar a quantidade de pessoas que confirmaram."

## Contexto observado

Duas telas foram reportadas com problema, a partir de uma Ação real ("visitia a afastado",
08/08/2026 19:15, alto jose leal), vista em 09/08/2026:

1. **Listagem de Ações** — a Ação de ontem continua listada em "Outras datas", como se
   ainda fosse acontecer, e não mostra quantas pessoas confirmaram presença.
2. **Detalhe da Ação** — o título grande da tela é "José Danilo Silva do Carmo", e a lista
   de Confirmados é uma sequência de nomes sem numeração.

**Achado importante sobre o título**: as duas telas já exibem o *nome da Ação*, não o nome
de quem criou. O que aconteceu é que essa Ação foi cadastrada com o nome de uma pessoa
preenchido no campo "Nome da Ação". Ou seja, o problema não é o que a tela mostra — é que
nada no momento da criação deixa claro que aquele campo é o nome da atividade
("Visita a afastado", "Ensaio", "Culto Jovem"), nem impede que vire o nome de alguém.
Esta feature ataca a causa: orientação e validação na criação. Corrigir Ações já criadas
com o nome errado fica fora do escopo (ver Assumptions).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ação que já aconteceu sai da lista (Priority: P1)

Um Usuário abre a lista de Ações no domingo de manhã. A visita marcada para sábado 19:15
já aconteceu — ela não aparece mais entre as Ações da lista. O que está na lista é só o que
ainda vai acontecer ou está acontecendo agora. Quem tem o link direto da Ação encerrada
ainda consegue abri-la, vê que ela encerrou, e vê quem participou; o botão de confirmar
presença não está mais disponível.

**Why this priority**: é o único item que faz o app mostrar informação errada. Uma lista que
anuncia um evento que já passou faz a pessoa se organizar para algo que não existe mais, e
mina a confiança na lista inteira. Entregue sozinha, já corrige isso.

**Independent Test**: criar uma Ação com data/hora no passado (mais de 4h atrás), abrir a
lista de Ações e verificar que ela não aparece; abrir o link direto dela e verificar que
abre marcada como encerrada, sem botão de confirmar presença.

**Acceptance Scenarios**:

1. **Given** uma Ação marcada para 4 horas e 1 minuto atrás, **When** um Usuário abre a
   lista de Ações, **Then** essa Ação não aparece em nenhuma seção da lista.
2. **Given** uma Ação marcada para 1 hora atrás, **When** um Usuário abre a lista de Ações,
   **Then** ela ainda aparece, sinalizada como acontecendo agora.
3. **Given** uma Ação encerrada, **When** um Usuário abre o link direto dela, **Then** vê os
   dados da Ação, o rótulo de encerrada, e a lista de quem participou, sem botão de
   confirmar presença nem de sair da fila de espera.
4. **Given** uma Ação encerrada onde eu havia confirmado presença, **When** abro o link
   direto dela, **Then** minha presença continua registrada e visível; nada foi apagado.
5. **Given** o filtro "Só Sábado" ativo no domingo, **When** um Usuário olha a lista,
   **Then** as Ações do sábado que já encerraram não aparecem.
6. **Given** todas as Ações do distrito já encerraram, **When** um Usuário abre a lista,
   **Then** vê o estado vazio explicado ("Nenhuma Ação ainda."), não uma tela em branco.

---

### User Story 2 - Ver quantas pessoas confirmaram, direto na lista (Priority: P2)

Um Usuário está decidindo de qual Ação participar no sábado. Sem abrir cada uma, ele vê na
própria lista quantas pessoas já confirmaram presença em cada Ação — e, quando a Ação tem
limite de vagas, quantas vagas ainda restam.

**Why this priority**: é o que transforma a lista em uma ferramenta de decisão. Uma Ação com
8 confirmados e uma com 0 pedem decisões diferentes, e hoje isso exige abrir uma por uma.

**Independent Test**: com duas Ações, uma com 3 confirmados e uma com 0, abrir a lista e
verificar que cada card mostra a contagem correta sem precisar abrir a Ação.

**Acceptance Scenarios**:

1. **Given** uma Ação com 3 pessoas confirmadas, **When** um Usuário abre a lista de Ações,
   **Then** o card dessa Ação mostra "3 confirmados".
2. **Given** uma Ação sem ninguém confirmado, **When** um Usuário abre a lista, **Then** o
   card mostra "Ninguém confirmado ainda" (não mostra "0").
3. **Given** uma Ação com 1 pessoa confirmada, **When** um Usuário abre a lista, **Then** o
   texto está no singular ("1 confirmado").
4. **Given** uma Ação com limite de 10 vagas e 4 confirmados, **When** um Usuário abre a
   lista, **Then** vê a contagem e as vagas restantes ("4 de 10 vagas").
5. **Given** uma Ação lotada com 2 pessoas na fila de espera, **When** um Usuário abre a
   lista, **Then** vê que está lotada e quantas pessoas estão na fila, separado da contagem
   de confirmados.
6. **Given** um Visitante sem Perfil, **When** abre a lista, **Then** vê as mesmas contagens
   — números agregados não exigem cadastro e não revelam quem é quem.
7. **Given** alguém desiste de uma Ação, **When** um Usuário recarrega a lista, **Then** a
   contagem daquela Ação diminui, e sobe de novo se a fila de espera promover alguém.

---

### User Story 3 - O nome da Ação diz o que vai acontecer (Priority: P3)

Um Usuário vai criar uma Ação de visita. No formulário, o campo de nome deixa claro, por
texto de apoio e exemplo, que ali vai o nome da atividade e não o nome de uma pessoa. Se
ele digitar o próprio nome, o app avisa antes de deixar criar.

**Why this priority**: preventivo. Não corrige o que já está errado, mas impede que a lista
de Ações do distrito vire uma lista de nomes de pessoas. Depende só do formulário de
criação, entrega sozinho.

**Independent Test**: abrir o formulário de criar Ação, digitar no campo de nome exatamente
o próprio nome de cadastro, e verificar que o app recusa com mensagem explicativa.

**Acceptance Scenarios**:

1. **Given** o formulário de criar Ação, **When** um Usuário olha o campo de nome, **Then**
   vê rótulo e texto de apoio que dizem que ali vai a atividade, com exemplo concreto
   ("Ex.: Visita a afastado, Ensaio, Culto Jovem").
2. **Given** um Usuário chamado "José Danilo Silva do Carmo", **When** digita exatamente
   esse nome no campo de nome da Ação e tenta criar, **Then** o app recusa e explica que o
   nome da Ação descreve a atividade, não a pessoa.
3. **Given** o mesmo Usuário, **When** digita o mesmo nome com outra capitalização, sem
   acentos ou com espaços extras, **Then** o app recusa do mesmo jeito.
4. **Given** um Usuário menor de idade exibido por Apelido, **When** digita o próprio
   Apelido como nome da Ação, **Then** o app recusa com a mesma mensagem.
5. **Given** uma Ação legitimamente chamada "Visita a José", **When** o Usuário tenta criar,
   **Then** o app aceita — a recusa vale só para o nome do próprio criador, isolado, não
   para nomes que aparecem dentro de uma descrição de atividade.
6. **Given** o mesmo formulário aplicado a uma Ação candidata proposta numa Rodada de
   votação, **When** o Usuário digita o próprio nome, **Then** recebe a mesma recusa.

---

### User Story 4 - Saber quantos somos, na lista de Confirmados (Priority: P4)

Um Usuário abre uma Ação e olha a lista de Confirmados. Cada pessoa aparece numerada — 1.,
2., 3. — então dá para ver de relance quantas pessoas são e em que ordem confirmaram, sem
contar de cabeça.

**Why this priority**: é polimento de leitura. Melhora a tela, mas nada fica errado sem
isso.

**Independent Test**: abrir uma Ação com 3 confirmados e verificar que aparecem numerados
1., 2. e 3., na ordem de confirmação.

**Acceptance Scenarios**:

1. **Given** uma Ação com 3 pessoas confirmadas, **When** um Usuário abre o detalhe da Ação,
   **Then** vê "1.", "2." e "3." antes de cada nome, na ordem em que confirmaram.
2. **Given** a mesma Ação com 2 pessoas na fila de espera, **When** o Usuário olha a fila,
   **Then** a fila também é numerada e recomeça em 1., separada dos confirmados.
3. **Given** uma Ação onde a segunda pessoa desiste, **When** o Usuário recarrega,
   **Then** a numeração é contígua de novo (1., 2.), sem buraco.
4. **Given** uma Ação sem ninguém confirmado, **When** o Usuário abre o detalhe, **Then**
   vê uma mensagem de lista vazia, não uma lista numerada vazia.
5. **Given** um leitor de tela ativo, **When** percorre a lista de Confirmados, **Then** a
   posição é anunciada junto do nome, sem ler o ponto como pontuação solta.

---

### Edge Cases

- **Ação acontecendo agora**: entre a hora marcada e 4h depois, a Ação continua na lista,
  sinalizada como acontecendo agora, e ainda aceita confirmação de presença — quem está a
  caminho precisa achá-la.
- **Ação encerrada durante a sessão**: se a Ação encerra enquanto a tela está aberta, ela
  não desaparece sozinha embaixo do dedo do Usuário; sai na próxima carga da lista.
- **Ação cancelada e encerrada ao mesmo tempo**: prevalece "Cancelada" — é a informação que
  explica por que ninguém foi.
- **Ação candidata em Rodada de votação cuja data já passou**: a candidata continua visível
  dentro da Rodada até a Rodada fechar (o encerramento por data vale para a lista de Ações,
  não para a apuração), mas nasce encerrada se vencer com a data no passado.
- **Fila de espera em Ação encerrada**: ninguém é promovido depois do encerramento; a fila
  congela como estava.
- **Contagem em Ação cancelada**: o card continua mostrando quem havia confirmado, com o
  rótulo de cancelada.
- **Fuso e virada de dia**: o encerramento é calculado no horário local de quem está
  olhando, o mesmo horário já exibido no card.
- **Muitos confirmados**: a numeração continua legível acima de 100 confirmados, sem
  desalinhar os nomes.
- **Nome da Ação de tamanho extremo**: nome muito longo não quebra o card da lista nem
  esconde a contagem de confirmados.

## Requirements *(mandatory)*

### Functional Requirements

#### Encerramento de Ação (US1)

- **FR-001**: O sistema DEVE considerar uma Ação **encerrada** quando o horário atual passar
  de 4 horas após a data/hora marcada da Ação.
- **FR-002**: Entre a data/hora marcada e o encerramento, a Ação DEVE ser apresentada como
  **acontecendo agora**, e continuar aceitando confirmação de presença e desistência.
- **FR-003**: A listagem de Ações NÃO DEVE exibir Ações encerradas, em nenhuma de suas
  seções de período e sob nenhum filtro ou ordenação.
- **FR-004**: Uma Ação encerrada DEVE continuar acessível pelo seu link direto, exibindo os
  mesmos dados de antes, um rótulo visível de encerrada, e a lista de quem participou.
- **FR-005**: Em uma Ação encerrada, o sistema NÃO DEVE oferecer confirmar presença,
  desistir, sair da fila de espera nem cancelar a Ação.
- **FR-006**: O encerramento NÃO DEVE apagar, alterar ou reordenar nenhuma confirmação de
  presença nem a fila de espera já registradas.
- **FR-007**: Após o encerramento, o sistema NÃO DEVE promover ninguém da fila de espera,
  mesmo que uma vaga seja liberada.
- **FR-008**: Quando uma Ação estiver simultaneamente cancelada e encerrada, o rótulo
  exibido DEVE ser "Cancelada".

#### Contagem de confirmados na listagem (US2)

- **FR-009**: Cada Ação na listagem DEVE exibir a quantidade de pessoas com presença
  confirmada, contando apenas quem está com vaga — quem está na fila de espera não entra
  nessa contagem.
- **FR-010**: A contagem DEVE ser exibida em texto legível, com concordância de número
  ("1 confirmado" / "4 confirmados"), e NÃO DEVE depender de cor ou ícone isolado para ser
  compreendida.
- **FR-011**: Quando ninguém confirmou, a listagem DEVE dizer que ninguém confirmou ainda,
  em vez de exibir o número zero solto.
- **FR-012**: Quando a Ação tem limite de vagas, a listagem DEVE exibir confirmados e limite
  juntos ("4 de 10 vagas").
- **FR-013**: Quando a Ação está lotada e há fila de espera, a listagem DEVE indicar que
  está lotada e quantas pessoas estão na fila, visualmente separado da contagem de
  confirmados.
- **FR-014**: A contagem DEVE ser visível para Visitante sem Perfil, e NÃO DEVE revelar
  identidade de ninguém — apenas o número agregado.
- **FR-015**: A contagem DEVE refletir desistências e promoções da fila de espera na próxima
  carga da lista.

#### Nome da Ação (US3)

- **FR-016**: O campo de nome, no formulário de criação de Ação (avulsa e candidata), DEVE
  ter rótulo e texto de apoio persistente indicando que ali vai o nome da atividade, com ao
  menos um exemplo concreto.
- **FR-017**: O sistema DEVE recusar a criação de uma Ação cujo nome, comparado sem
  diferenciar maiúsculas/minúsculas, sem acentuação e com espaços das pontas removidos, seja
  igual ao nome ou ao Apelido de exibição de quem está criando.
- **FR-018**: A recusa DEVE explicar o motivo em uma frase e apontar o caminho ("O nome da
  Ação descreve a atividade, não a pessoa. Ex.: Visita a afastado"), exibida junto ao campo.
- **FR-019**: A validação NÃO DEVE recusar nomes que apenas contenham um nome próprio dentro
  de uma descrição de atividade — só a igualdade com o nome do próprio criador é recusada.

#### Numeração dos confirmados (US4)

- **FR-020**: A lista de Confirmados no detalhe da Ação DEVE numerar cada pessoa em ordem
  crescente a partir de 1, na ordem de confirmação.
- **FR-021**: A fila de espera DEVE ter numeração própria, recomeçando em 1, visualmente
  separada da lista de confirmados.
- **FR-022**: A numeração DEVE ser contígua após qualquer desistência — sem números
  pulados.
- **FR-023**: Quando não há ninguém confirmado, o sistema DEVE exibir mensagem de lista
  vazia em vez de uma lista numerada sem itens.
- **FR-024**: A posição na lista DEVE ser anunciada junto do nome para leitores de tela.

### Key Entities

Nenhuma entidade nova. Muda a **apresentação** e a **disponibilidade de ações** sobre
entidades existentes:

- **Ação**: ganha um estado derivado de tempo — *a acontecer*, *acontecendo agora*,
  *encerrada* — calculado a partir da data/hora já existente, sem novo dado armazenado.
- **Confirmação de presença**: passa a ser contada de forma agregada na listagem e numerada
  no detalhe. Nem o registro nem sua ordem mudam.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): nenhum dado pessoal novo é coletado, exibido ou retido. A
contagem de confirmados é um número agregado, sem identificar ninguém, e por isso é visível
a Visitante (FR-014). A numeração dos confirmados apenas ordena nomes que a tela já exibe,
com a regra de exibição já vigente (menor de idade aparece por Apelido). Idade, telefone e
Igreja de origem continuam fora dessas telas.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV):

- **Fila de espera**: a promoção automática ao liberar vaga continua exatamente como está
  enquanto a Ação não encerra. Depois do encerramento, nenhuma promoção acontece (FR-007) e
  a fila congela (FR-006).
- **Revogação de Participar**: continua revogável enquanto a Ação não encerra, incluindo o
  período de "acontecendo agora" (FR-002); depois do encerramento, deixa de ser oferecida
  (FR-005).
- **Rodada de votação, empate e descarte**: nada muda. O encerramento por tempo age sobre a
  listagem de Ações, não sobre a apuração de uma Rodada; candidatas continuam visíveis
  dentro da Rodada até ela fechar.
- **Dupla Missionária**: a validação de composição por gênero não muda. A contagem da
  listagem mostra o mesmo formato das demais ("1 de 2 vagas").

**Papéis** (Princípio V): nenhum papel novo. Nada aqui depende de ser Dono do Grupo,
Líder/Diretor ou Administrador do distrito.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 Ações com data/hora anterior a 4 horas atrás aparecem na listagem, sob
  qualquer combinação de filtro de Igreja, "Só Sábado" e ordenação.
- **SC-002**: 100% das Ações da listagem exibem contagem de confirmados, incluindo as que
  têm zero, sem que o Usuário precise abrir a Ação.
- **SC-003**: Um Usuário identifica a Ação com mais confirmados de uma lista de 5 Ações em
  menos de 10 segundos, sem abrir nenhuma delas.
- **SC-004**: Uma Ação encerrada aberta por link direto carrega por completo e não oferece
  nenhum controle de confirmar, desistir ou cancelar — verificado em 100% das tentativas.
- **SC-005**: Nenhuma confirmação de presença é perdida no encerramento: a contagem de
  participantes de uma Ação, medida antes e depois de ela encerrar, é idêntica.
- **SC-006**: Uma tentativa de criar Ação com o nome do próprio criador é recusada em 100%
  das variações testadas (capitalização, acentuação, espaços nas pontas).
- **SC-007**: Todos os confirmados aparecem numerados de 1 a N sem número repetido nem
  pulado, verificado em uma Ação com pelo menos 3 confirmados e uma desistência.

## Assumptions

- **Duração fixa de 4 horas**: a Ação não guarda hora de término. Assume-se 4 horas após a
  data/hora marcada como janela padrão de todas as Ações, sem campo novo no formulário.
  Acampamentos e Ações de vários dias ficam mal cobertos por essa regra — se isso virar
  problema real, a saída é um campo de duração, decisão adiada de propósito.
- **Encerramento é calculado, não gravado**: o estado *encerrada* é derivado da data/hora a
  cada vez que a tela é montada; nada é gravado nem agendado. Um app aberto há horas só
  reflete o encerramento na próxima carga da lista.
- **Corrigir Ação já criada fica fora do escopo**: não existe edição de Ação hoje e esta
  feature não a introduz. Uma Ação com o nome errado é cancelada por quem a criou (ou pelo
  Administrador do distrito) e criada de novo. A Ação "José Danilo Silva do Carmo" do
  reporte permanece como está até alguém fazer isso.
- **Contagem conta só quem tem vaga**: quem está na fila de espera é informado à parte
  (FR-013), não somado aos confirmados. Somar os dois faria uma Ação de 10 vagas parecer ter
  15 participantes.
- **Nome do criador não é exibido em lugar nenhum**: esta feature não adiciona "criado por
  fulano" às telas de Ação. Quem criou continua sem aparecer, como hoje.
- **Sem histórico navegável**: não existe tela de "Ações passadas". Ação encerrada só é
  alcançada por link direto. Uma aba de histórico é decisão de produto separada.
- **Regra de recusa é só igualdade com o próprio nome**: não há moderação semântica nem
  detecção genérica de nome de pessoa. Alguém que digite o nome de *outra* pessoa continua
  conseguindo criar.
