# Feature Specification: Foto de capa de Grupo e de Ação

**Feature Branch**: `013-foto-de-capa`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Ser possível adicionar foto da ação/grupo criado aprimorando a visibilidade de cada, deve ser aconselhado [a não] ser enviado foto pessoais ou de menores, incentivando sobre imagens ilustrativas"

> **Leitura adotada**: o texto original diz "deve ser aconselhado ser enviado foto pessoais ou
> de menores". Está lido como **"aconselhado a NÃO enviar"**, porque a segunda metade da frase
> — "incentivando sobre imagens ilustrativas" — só faz sentido nessa direção. Toda a spec
> assume isso. Se a intenção era a oposta, esta spec está inteira errada.

## Contexto e o que esta feature quebra

Hoje o app **não coleta imagem alguma**. `MAPA-DE-DADOS.md`, linha 22, declara isso como
fato verificado:

> **Não coletado**: CPF, endereço, foto/avatar, dado de saúde, dado de pagamento (nenhuma
> ocorrência de `foto`/`avatar`/`imagem` em `lib/` ou `supabase/migrations/`, confirmado por
> grep).

Esta feature torna essa frase falsa. Atualizar `MAPA-DE-DADOS.md` e a Política de Privacidade
**não é tarefa de acompanhamento — é parte da entrega**, porque uma política que descreve um
app que não existe mais é uma promessa quebrada, não uma documentação desatualizada.

Segundo ponto: `REVISAO-JURIDICA.md` registra que consentimento parental para menor **não está
resolvido** neste app, e que a via proposta (autodeclaração de responsável) nunca foi
implementada. Publicar foto de menor exigiria justamente esse mecanismo. Por isso a estratégia
desta feature é **não publicar foto de menor**, e não "coletar autorização para publicar" —
é a única saída que não depende de um mecanismo que o app não tem.

Terceiro: `CONTEXT.md`, na entrada Administrador do distrito, diz "cuida de moderação e casos
excepcionais. Escopo exato de moderação ainda não detalhado". Esta feature é o primeiro
detalhamento concreto desse escopo.

## Clarifications

### Session 2026-08-10

- Q: Quando uma operação de imagem falha no meio (o arquivo subiu mas a linha não gravou, ou a
  linha sumiu mas o arquivo não saiu), qual é o comportamento exigido? → A: Falha visível, sem
  compensar — a operação para, diz com precisão o que ficou pela metade, e não tenta consertar
  sozinha; a pessoa refaz.
- Q: Um arquivo que ficou no armazenamento sem nenhum registro que o referencie — qual o prazo
  máximo aceitável até ele ser removido? → A: 24 horas.

**O princípio que as duas respostas formam, e que decide os casos futuros**: *a pessoa cuida do
que ela vê e consegue refazer; a máquina cuida só do que a pessoa não tem como ver.* Capa
perdida numa troca malsucedida a pessoa vê — então o app conta a verdade e ela reenvia, sem
reparo automático no meio. Arquivo órfão ninguém enxerga nem consegue refazer — então a máquina
recolhe, dentro de um prazo declarado. O que é proibido é esconder a falha atrás de uma
mensagem que diz que nada aconteceu.

**Por que isto entrou na spec depois de seis rodadas de convergência**: dos 20 defeitos que a
convergência achou, 10 estavam no caminho de remoção, e não eram independentes — cada conserto
abria o seguinte, porque o comportamento exigido em falha parcial nunca tinha sido escrito.
Cada rodada inventava a resposta de novo. Está escrito agora.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Dar cara ao Grupo e à Ação, com orientação clara (Priority: P1)

O Dono de um Grupo abre o Grupo que administra e envia uma imagem de capa — o logo do
ministério, uma foto do local, uma arte do evento. Antes de escolher o arquivo, ele lê um
aviso destacado: imagem ilustrativa, sem rosto de pessoa e nunca de menor de idade. Depois de
enviada, a capa aparece no Grupo e no card da lista, e qualquer pessoa — inclusive Visitante
sem cadastro — passa a reconhecer o Grupo de relance. O mesmo vale para quem cria uma Ação.

**Why this priority**: é a feature pedida. E o aviso vem junto, não depois: publicar upload
sem a orientação criaria, no primeiro dia, exatamente o problema que a orientação existe para
evitar — e o Princípio II da constituição é NON-NEGOTIABLE. As duas metades são uma entrega
só.

**Independent Test**: como Dono de um Grupo, enviar uma imagem e verificar que ela aparece no
Grupo e na lista; verificar que o aviso sobre imagem ilustrativa apareceu antes da escolha do
arquivo.

**Acceptance Scenarios**:

1. **Given** um Dono de Grupo na tela do seu Grupo, **When** aciona a opção de capa, **Then**
   lê, antes de qualquer seletor de arquivo, um aviso destacado orientando a usar imagem
   ilustrativa e a não enviar foto de pessoa nem de menor de idade.
2. **Given** o mesmo Dono, **When** envia uma imagem válida, **Then** ela aparece como capa do
   Grupo e no card do Grupo na listagem.
3. **Given** quem criou uma Ação, **When** envia uma imagem, **Then** ela aparece na Ação e no
   card da Ação na listagem.
4. **Given** um Grupo ou Ação sem capa, **When** qualquer pessoa abre a lista, **Then** vê uma
   apresentação padrão íntegra — capa é opcional, e a ausência dela nunca é um buraco na tela.
5. **Given** um Visitante sem Perfil, **When** abre a lista de Grupos ou de Ações, **Then** vê
   as capas — imagem de Grupo e de Ação é pública, como o Grupo e a Ação já são.
6. **Given** um Usuário que **não** é Dono do Grupo nem criou a Ação, **When** abre a tela,
   **Then** não encontra opção de enviar, trocar ou remover a capa.
7. **Given** um Dono de Grupo com capa já enviada, **When** aciona a opção de capa, **Then**
   pode trocar por outra ou remover, e o aviso aparece de novo antes da troca.
8. **Given** um arquivo grande, de formato não suportado, ou corrompido, **When** o Usuário
   tenta enviar, **Then** o app recusa antes de publicar e explica o que fazer, sem perder o
   resto do que ele estava preenchendo.
9. **Given** a Política de Privacidade e `MAPA-DE-DADOS.md`, **When** esta feature entra no
   ar, **Then** ambos já descrevem que o app passa a hospedar imagens enviadas por Usuários,
   com finalidade, visibilidade e prazo.

---

### User Story 2 - O Administrador do distrito consegue tirar do ar (Priority: P2)

Alguém publicou uma capa com rosto de criança. O Administrador do distrito abre o Grupo ou a
Ação, remove a imagem, e ela some de todos os lugares onde aparecia — imediatamente, sem
depender de quem enviou.

**Why this priority**: sem isso, o aviso da US1 é só um pedido. Um app que hospeda imagem
pública de menor e não tem ninguém capaz de tirá-la do ar não tem defesa nenhuma. É o que
transforma a orientação em execução.

**Independent Test**: como Administrador do distrito, remover a capa de um Grupo que não é seu
e verificar que sumiu da tela do Grupo e do card da lista.

**Acceptance Scenarios**:

1. **Given** um Administrador do distrito, **When** abre qualquer Grupo ou Ação com capa,
   **Then** tem a opção de remover a imagem, seja ele dono dela ou não.
2. **Given** essa remoção, **When** é confirmada, **Then** a imagem some da tela do Grupo/Ação
   e do card da listagem para todo mundo.
3. **Given** uma imagem removida, **When** alguém tenta alcançá-la pelo endereço direto que
   ela tinha, **Then** não a obtém.
4. **Given** um Usuário comum ou um Dono de Grupo, **When** procura remover a capa de um Grupo
   que não administra, **Then** não encontra essa opção.
5. **Given** um Grupo cuja capa foi removida pelo Administrador, **When** o Dono do Grupo abre
   o Grupo, **Then** vê o Grupo sem capa e pode enviar outra.

---

### User Story 3 - Qualquer pessoa consegue avisar que uma imagem é imprópria (Priority: P3)

Uma mãe abre o app, sem cadastro, e vê a foto da filha na capa de uma Ação. Ela aciona a
opção de denunciar aquela imagem, escreve o motivo em uma frase, e a denúncia chega ao
Administrador do distrito, que vê a lista de denúncias pendentes e decide.

**Why this priority**: o Administrador não pode remover o que não sabe que existe. A denúncia
é o canal que fecha o ciclo. Vem depois da US2 porque denunciar sem ninguém capaz de agir não
serve para nada.

**Independent Test**: como Visitante sem cadastro, denunciar uma imagem e verificar que ela
aparece na lista de pendências do Administrador do distrito.

**Acceptance Scenarios**:

1. **Given** qualquer pessoa vendo uma capa, inclusive Visitante sem Perfil, **When** aciona a
   opção de denunciar, **Then** consegue registrar a denúncia com um motivo em texto curto.
2. **Given** uma denúncia registrada, **When** o Administrador do distrito abre suas
   pendências, **Then** vê a denúncia com a imagem, o Grupo ou Ação a que pertence, e o
   motivo.
3. **Given** uma denúncia, **When** o Administrador decide, **Then** pode remover a imagem ou
   marcar a denúncia como improcedente, e a denúncia sai das pendências nos dois casos.
4. **Given** uma imagem já denunciada, **When** outra pessoa a denuncia, **Then** a nova
   denúncia é registrada sem duplicar o item na lista do Administrador.
5. **Given** uma imagem removida por outro caminho, **When** havia denúncia pendente sobre
   ela, **Then** a denúncia é encerrada automaticamente.
6. **Given** o denunciante, **When** registra a denúncia, **Then** a identidade dele não é
   exibida a quem enviou a imagem.

---

### User Story 4 - A imagem some junto com o que ela ilustra (Priority: P3)

Ninguém precisa lembrar de limpar nada. Quando o Grupo é apagado, a capa vai junto. Quando a
Ação é cancelada, idem. Quando alguém exclui a conta, as imagens que ela enviou para Ações
avulsas somem, e a capa de um Grupo que passou para outro dono fica — o Grupo continua vivo,
e a capa é dele agora.

**Why this priority**: é higiene de dado, exigida pela LGPD e pelo compromisso de retenção que
a Política vai passar a fazer. Não é visível no dia a dia, e por isso vem por último — mas
sem ela o app acumula imagem órfã para sempre.

**Independent Test**: apagar um Grupo com capa e verificar que a imagem deixa de ser
alcançável por qualquer caminho.

**Acceptance Scenarios**:

1. **Given** um Grupo com capa, **When** o Grupo é apagado, **Then** a imagem deixa de existir
   e não é alcançável por nenhum endereço.
2. **Given** uma Ação com capa, **When** a Ação é cancelada, **Then** a imagem deixa de
   existir.
3. **Given** uma Ação encerrada por tempo, **When** alguém abre o link direto dela, **Then** a
   capa continua lá — Ação encerrada é histórico, não lixo.
4. **Given** um Usuário que excluiu a conta e tinha enviado capa para Ações avulsas suas,
   **When** a exclusão é concluída, **Then** essas imagens deixam de existir.
5. **Given** um Usuário que excluiu a conta e era Dono de um Grupo com capa, **When** o Grupo
   é herdado pelo Administrador do distrito, **Then** a capa permanece — ela ilustra o Grupo,
   que continua existindo com outro dono.
6. **Given** qualquer remoção de imagem, **When** ela acontece, **Then** nenhum outro dado do
   Grupo, da Ação ou do Perfil é alterado.

---

### Edge Cases

- **Imagem enviada sem conexão estável**: o envio falha de forma explícita e o Grupo/Ação
  continua íntegro, sem capa pela metade.
- **Imagem removida enquanto alguém a vê**: quem já estava com a tela aberta não quebra; na
  próxima carga a capa não está mais lá.
- **Grupo ou Ação sem capa**: é o estado padrão e majoritário. A tela precisa ficar boa assim,
  não "faltando alguma coisa".
- **Imagem de proporção extrema** (muito alta ou muito larga): o card da lista não deforma nem
  empurra o resto do conteúdo.
- **Conteúdo impróprio que ninguém denunciou**: fica no ar. Não existe detecção automática, e
  a spec não finge que existe — o caminho é humano, e é a US2 mais a US3.
- **Denúncia caluniosa ou em massa**: o Administrador decide; a spec não cria punição
  automática nem bloqueio por volume.
- **Quem enviou a capa deixou de ser Dono do Grupo**: quem controla a capa é quem administra
  hoje, não quem enviou.
- **Ação candidata em Rodada de votação**: pode ter capa como qualquer Ação; se perder a
  votação e for descartada, a capa some junto.

## Requirements *(mandatory)*

### Capa e orientação (US1)

- **FR-001**: Um Grupo DEVE poder ter, no máximo, **uma** imagem de capa. Uma Ação também.
- **FR-002**: A capa DEVE ser opcional. Grupo e Ação sem capa continuam plenamente
  utilizáveis e bem apresentados.
- **FR-003**: Só o Dono do Grupo (para Grupo), quem criou a Ação (para Ação) e o Administrador
  do distrito DEVEM poder enviar, trocar ou remover a capa.
- **FR-004**: Antes de qualquer seleção de arquivo, o sistema DEVE exibir um aviso destacado
  orientando a enviar **imagem ilustrativa** — logo, arte, foto de local ou objeto — e a
  **não** enviar foto de pessoa, e **nunca** foto de menor de idade.
- **FR-005**: O aviso DEVE reaparecer a cada envio ou troca, não apenas na primeira vez.
- **FR-006**: O aviso DEVE ser escrito em português direto, dizendo o motivo em uma frase, sem
  jargão jurídico.
- **FR-007**: A capa DEVE ser exibida na tela de detalhe do Grupo/Ação e no card
  correspondente da listagem.
- **FR-008**: A capa DEVE ser visível a Visitante sem Perfil, como o Grupo e a Ação já são.
- **FR-009**: O sistema DEVE recusar arquivo acima do tamanho máximo, de formato não suportado
  ou ilegível, explicando o motivo, **antes** de publicar qualquer coisa.
- **FR-010**: Uma falha no envio da imagem NÃO DEVE alterar nenhum outro dado do Grupo ou da
  Ação, nem perder o que o Usuário estava preenchendo.

### Poder de retirada (US2)

- **FR-011**: O Administrador do distrito DEVE poder remover a capa de qualquer Grupo ou Ação,
  independentemente de quem a enviou.
- **FR-012**: Uma imagem removida DEVE sair da origem imediatamente. Por ser servida como
  objeto público atrás de CDN, ela PODE continuar acessível por até **60 segundos** a quem já
  tiver o endereço, enquanto a invalidação de cache se propaga.

  **Reescrito em 2026-08-10.** A versão original dizia "NÃO DEVE continuar alcançável por
  nenhum endereço, para ninguém" — e isso é **falso** com objeto público: a documentação do
  fornecedor afirma que a invalidação leva *"up to 60 seconds"* (research D-004, resposta 2).
  A alternativa que tornaria a frase verdadeira — endereço assinado de vida curta — foi
  apresentada ao responsável pelo app com o custo de cada uma, e ele escolheu o objeto
  público, avaliando que o risco é baixo para um app cuja finalidade é convidar pessoas para
  encontros. **A Política de Privacidade tem de dizer os 60 segundos**, e não a versão
  desejada: FR-027 depende disto.
- **FR-013**: A remoção da capa NÃO DEVE apagar nem alterar o Grupo, a Ação, as presenças
  confirmadas ou qualquer outro dado.
- **FR-014**: Depois de uma remoção, quem administra o Grupo/Ação DEVE poder enviar outra
  capa.

### Denúncia (US3)

- **FR-015**: Qualquer pessoa que veja uma capa, **inclusive Visitante sem Perfil**, DEVE
  poder denunciá-la, informando um motivo em texto curto.
- **FR-016**: O Administrador do distrito DEVE ter uma lista de denúncias pendentes, com a
  imagem, o Grupo ou Ação de origem e o motivo.
- **FR-017**: O Administrador DEVE poder resolver uma denúncia removendo a imagem ou marcando
  como improcedente; nos dois casos ela sai das pendências.
- **FR-018**: Denúncias repetidas sobre a mesma imagem NÃO DEVEM duplicar o item na lista de
  pendências.
- **FR-019**: Quando a imagem denunciada é removida por qualquer caminho, as denúncias
  pendentes sobre ela DEVEM ser encerradas.
- **FR-020**: A identidade de quem denuncia NÃO DEVE ser exibida a quem enviou a imagem.

### Ciclo de vida (US4)

- **FR-021**: Quando um Grupo é apagado, sua capa DEVE deixar de existir.
- **FR-022**: Quando uma Ação é cancelada ou descartada por perder uma Rodada de votação, sua
  capa DEVE deixar de existir.
- **FR-023**: Uma Ação encerrada por tempo DEVE manter sua capa — encerrada é histórico.
- **FR-024**: Na exclusão de conta, as capas enviadas por quem sai para **Ações avulsas suas**
  DEVEM deixar de existir.
- **FR-025**: Na exclusão de conta, a capa de um **Grupo herdado** DEVE permanecer — o Grupo
  continua existindo, com outro Dono.
- **FR-026**: Nenhuma remoção de imagem DEVE alterar qualquer outro dado.

### Transparência (US1, obrigatório para entrar no ar)

- **FR-027**: A Política de Privacidade DEVE ser atualizada, **na mesma entrega**, para
  descrever que o app hospeda imagens enviadas por Usuários: qual a finalidade, quem pode ver,
  quanto tempo ficam, e como pedir remoção.
- **FR-028**: `MAPA-DE-DADOS.md` DEVE deixar de afirmar que foto/imagem não é coletada, e
  passar a descrever a imagem de capa com a mesma evidência `arquivo:linha` das demais
  entradas.
- **FR-029**: `CONTEXT.md` DEVE receber os termos novos deste domínio — **Foto de capa** e
  **Denúncia de imagem** — antes de eles entrarem em código.
- **FR-030**: A Política DEVE declarar que o app **não** solicita nem verifica consentimento
  de responsável para imagem de menor, e que por isso imagem de menor não deve ser enviada.

### Falha no meio do caminho (US1, US2)

- **FR-031**: Quando uma operação de imagem falha **depois de já ter mudado alguma coisa**, o
  app DEVE dizer **o que exatamente ficou pela metade**, e a tela DEVE passar a mostrar o
  estado real. Uma mensagem genérica de "tente de novo" sobre um estado que mudou é proibida:
  ela informa o contrário do que aconteceu.
- **FR-032**: O app NÃO DEVE tentar reparar automaticamente o que a pessoa consegue refazer.
  Numa troca de capa malsucedida, a capa anterior pode se perder — ela é o dado que estava
  sendo trocado, e FR-010 fala dos **demais** dados —, desde que a pessoa seja informada disso
  com essas palavras e possa reenviar.
- **FR-033**: Arquivo que ficou no armazenamento **sem nenhum registro que o referencie** DEVE
  ser removido automaticamente. Este é o caso oposto ao de FR-032: não há tela onde ele
  apareça, não há pessoa que saiba que ele existe, e portanto não há quem o refaça. Prazo em
  SC-010.

## Key Entities

- **Foto de capa**: imagem única e opcional associada a um Grupo **ou** a uma Ação. Guarda quem
  a enviou e quando. É pública. Não existe sozinha — some com o Grupo/Ação a que pertence.
- **Denúncia de imagem**: registro de que alguém considerou uma Foto de capa imprópria. Tem
  motivo em texto curto, a imagem denunciada e um estado (pendente, imagem removida,
  improcedente). Pode ser criada por quem não tem Perfil.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II — NON-NEGOTIABLE, e a seção "Requisitos de Domínio e
Compliance"):

- **Qual dado é coletado**: uma imagem enviada por Usuário, por Grupo ou por Ação, mais quem
  a enviou e quando. Uma imagem **pode** conter dado pessoal de terceiro (rosto), e é
  exatamente isso que a feature tenta evitar.
- **Finalidade**: identificação visual do Grupo/Ação na listagem e na tela de detalhe.
- **Quem pode ver**: qualquer pessoa, inclusive Visitante sem cadastro (FR-008).
- **Consentimento adicional**: o consentimento LGPD do cadastro **não cobre** imagem de
  terceiro. Por isso a estratégia é preventiva (aviso, FR-004) somada a corretiva (remoção,
  FR-011; denúncia, FR-015), e **não** coleta de autorização — o app não tem mecanismo de
  consentimento de responsável, como `REVISAO-JURIDICA.md` registra.
- **Menor de idade**: o app já protege o menor não exibindo seu nome real, só o Apelido.
  Publicar a foto dele desfaz essa proteção de uma vez. Daí a proibição explícita no aviso e o
  poder de retirada sem depender de quem enviou.
- **Documentos**: FR-027, FR-028 e FR-030 fazem parte da entrega, não são acompanhamento.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nada muda. Fila de espera,
desempate por sorteio, revogação de voto e de Participar, descarte de candidatas perdedoras e
composição de Dupla Missionária seguem idênticos. A única interação é FR-022: a candidata
descartada leva sua capa junto.

**Papéis** (Princípio V): nenhum papel novo. Usa os que existem — Visitante denuncia, Dono do
Grupo e criador da Ação controlam a própria capa, Administrador do distrito remove qualquer
uma. Isto detalha, pela primeira vez, o "escopo de moderação" que `CONTEXT.md` deixou em
aberto na entrada do Administrador do distrito.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 100% das tentativas de enviar capa exibem o aviso antes do seletor de arquivo,
  inclusive em troca de imagem já existente.
- **SC-002**: Uma pessoa que administra um Grupo consegue enviar a capa em menos de 1 minuto,
  do toque inicial até ver a imagem publicada.
- **SC-003**: O Administrador do distrito consegue remover qualquer imagem em até 3 toques a
  partir da tela onde ela aparece.
- **SC-004**: Uma imagem removida retorna "não encontrada" em 100% das tentativas de alcance
  **feitas mais de 60 segundos depois da remoção**, por qualquer caminho, inclusive endereço
  direto anotado antes. Dentro da janela de 60 segundos, o endereço já conhecido pode ainda
  responder — é o limite do cache de borda, não uma falha da remoção.

  **Reescrito em 2026-08-10 junto com FR-012.** A versão original exigia 100% sem janela, o
  que a documentação do fornecedor contradiz. Medir isso é o item 11 do quickstart, e ele
  passa a ter um número esperado em vez de zero.
- **SC-005**: 0 imagens órfãs após apagar um Grupo, cancelar uma Ação, descartar uma candidata
  perdedora ou excluir uma conta — verificado contando as imagens existentes antes e depois.
- **SC-006**: Grupo e Ação sem capa continuam com 100% das funções disponíveis, e a listagem
  não apresenta espaço vazio no lugar da imagem.
- **SC-007**: 0 afirmações falsas nos documentos: nem a Política de Privacidade nem
  `MAPA-DE-DADOS.md` continuam dizendo que o app não coleta imagem.
- **SC-008**: Uma denúncia registrada por Visitante sem cadastro aparece nas pendências do
  Administrador do distrito em 100% dos casos.
- **SC-009**: 0 dados de Grupo, Ação, presença ou Perfil alterados por qualquer operação de
  imagem — verificado antes e depois de enviar, trocar e remover.
- **SC-010**: Um arquivo sem nenhum registro que o referencie deixa de existir em **no máximo
  24 horas** — verificável por consulta, sem varrer o armazenamento à mão. Cobre o caso que
  SC-005 não menciona: SC-005 lista quatro eventos de exclusão, e este arquivo não nasce de
  nenhum deles, mas de um envio que falhou pela metade.

## Assumptions

- **Sem detecção automática de conteúdo**: o app não analisa a imagem. Não identifica rosto,
  idade nem conteúdo impróprio. A moderação é inteiramente humana — aviso, denúncia e remoção.
  Fingir o contrário seria a promessa mais perigosa desta spec.
- **Sem consentimento parental**: a feature não introduz coleta de autorização de responsável.
  A saída para foto de menor é não publicar, e retirar quando aparecer. Se um dia o app
  implementar o mecanismo proposto em `REVISAO-JURIDICA.md`, esta decisão pode ser revista.
- **Sem edição de imagem no app**: nada de recorte, filtro, rotação ou redimensionamento pelo
  Usuário. Ele envia o arquivo como está.
- **Formatos e tamanho**: aceitos os formatos de imagem comuns em aparelho de celular, com um
  limite de tamanho definido e informado ao Usuário antes do envio. O valor exato fica para o
  plano — é decisão técnica, não de produto.
- **Uma capa, sem galeria**: várias imagens por Grupo/Ação está fora do escopo. Multiplicaria a
  superfície de moderação, que é o custo real desta feature.
- **Imagem é pública, sem exceção**: não há capa restrita a participantes. Grupo e Ação já são
  públicos; a capa segue a mesma regra.
- **Denúncia não é anônima no armazenamento**: ela não é exibida a quem enviou a imagem
  (FR-020), mas o Administrador do distrito precisa poder distinguir denúncias para julgar
  abuso. Denúncia de Visitante sem Perfil não tem autor identificável, e isso é aceito.
- **Sem notificação**: nem quem enviou é avisado da remoção, nem quem denunciou é avisado da
  decisão. O app não tem canal de notificação hoje, e criar um é outra feature.
- **Sem histórico de imagens**: trocar a capa descarta a anterior; não há versões anteriores
  guardadas.
- **Depende da feature 011 para FR-023**: "Ação encerrada" é o estado definido pela feature
  `011-acoes-titulo-e-encerramento`. Se a 011 não estiver no ar, FR-023 se aplica a qualquer
  Ação com data no passado.
