# Feature Specification: Novidades — o que mudou no app

**Feature Branch**: `022-novidades`

**Created**: 2026-08-10

**Status**: Draft

**Input**: "faça uma nova tela 'novidades' no app, considerando que o primeiro deployment foi
realizado na data 06/10/26 e daí em diante auditamos as novidades."

## Contexto: vinte e uma features entraram, e ninguém no distrito soube de nenhuma

O app mudou muito desde 23 de julho de 2026. Entre outras coisas: passou a existir uma Home
que explica o propósito, Ação encerrada parou de aceitar gente, o voto deixou de ser legível
por qualquer um, quem se declarou Líder e foi recusado parou de aparecer publicamente, virou
possível ver e corrigir os próprios dados, arquivar um Grupo, e o cadastro de criança passou a
exigir autorização de um responsável.

**Nada disso foi comunicado a ninguém.** O registro do que mudou existe em três lugares, e os
três são para quem constrói, não para quem usa:

- o histórico do git, que ninguém no distrito vai abrir;
- `PENDENCIAS.md`, que fala do que **falta**, não do que entrou;
- `public.versoes_texto_legal` (feature 017), que é changelog de verdade — mas só dos textos
  legais, e existe por obrigação da LGPD, não para contar novidade.

A consequência prática: uma pessoa que usou o app em agosto e volta em novembro encontra
botões que não existiam e regras que mudaram, sem nenhum lugar que diga o que aconteceu. Pior:
mudanças que **protegem** essa pessoa — o voto que deixou de ser público, a declaração
recusada que saiu do ar — são invisíveis justamente para quem elas protegem.

**O marco**: o primeiro lançamento para o distrito é **6 de outubro de 2026**. Tudo que existe
até essa data é "o app como ele nasceu", e não vira item de Novidades. A partir dela, cada
mudança que a pessoa percebe é registrada.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Descobrir o que mudou desde a última vez (Priority: P1)

Alguém que já usava o app abre uma tela de Novidades e vê, em ordem do mais recente para o
mais antigo, o que mudou desde o lançamento — cada item com data e escrito em português que
ela entende, sem jargão de programação.

**Why this priority**: é a feature. Sem a lista, não há nada.

**Independent Test**: abrir a tela e verificar que os itens aparecem do mais recente para o
mais antigo, com data, e que nenhum deles cita nome de arquivo, número de versão técnica ou
termo que só quem programa entende.

**Acceptance Scenarios**:

1. **Given** novidades registradas, **When** o Usuário abre a tela, **Then** vê a lista em
   ordem do mais recente para o mais antigo, cada item com data.
2. **Given** um item da lista, **When** o Usuário o lê, **Then** entende o que mudou **para
   ele** — o que passou a poder fazer, ou o que passou a ser protegido.
3. **Given** um Visitante sem cadastro, **When** abre a tela, **Then** vê as mesmas novidades:
   o que mudou no app não é informação de quem tem Perfil.
4. **Given** a tela, **When** o Usuário procura por ela, **Then** a encontra a partir da Home,
   com rótulo em texto.

---

### User Story 2 - Saber que há algo novo sem precisar procurar (Priority: P2)

Quem abre o app depois de uma mudança percebe que há novidade, sem ter que lembrar de
conferir. Depois de ler, o aviso some.

**Why this priority**: uma lista que ninguém abre não comunica nada. Mas vem depois da US1
porque um aviso apontando para uma tela vazia é pior que aviso nenhum.

**Independent Test**: registrar uma novidade, abrir o app e verificar que há indicação visual;
abrir a tela; fechar e reabrir o app, e verificar que a indicação sumiu.

**Acceptance Scenarios**:

1. **Given** uma novidade que o Usuário ainda não viu, **When** ele abre o app, **Then** há
   uma indicação visual de que existe algo novo.
2. **Given** essa indicação, **When** ele abre a tela de Novidades, **Then** a indicação some.
3. **Given** que ele já viu tudo, **When** reabre o app, **Then** **não** há indicação.
4. **Given** uma novidade nova depois disso, **When** ele abre o app, **Then** a indicação
   volta.
5. **Given** que ele nunca abriu o app antes, **When** abre pela primeira vez, **Then** **não**
   é recebido com aviso de novidade — para quem chega agora, o app inteiro é novo, e apontar
   uma parte dele como "novidade" não quer dizer nada.

---

### User Story 3 - Nada é registrado sobre quem leu (Priority: P2)

Ler novidades não cria nenhum dado novo sobre a pessoa. O app não sabe, nem guarda, quem leu o
quê.

**Why this priority**: **é P2 junto com a US2, não depois.** O jeito óbvio de fazer o aviso
sumir é gravar no banco "esta pessoa leu até aqui" — e isso seria um dado de comportamento
novo, coletado sem finalidade que o glossário autorize, num app que acabou de passar três
features fechando exposição. A alternativa custa o mesmo e não coleta nada.

**Independent Test**: usar a tela e verificar que nenhuma informação sobre a leitura chegou ao
servidor.

**Acceptance Scenarios**:

1. **Given** o Usuário lendo as novidades, **When** ele fecha a tela, **Then** nada sobre essa
   leitura é enviado ou guardado no servidor.
2. **Given** o mesmo Usuário em outro aparelho, **When** abre o app, **Then** o estado de
   "já vi" **não** o acompanha — e isso é o resultado esperado, não uma limitação a consertar.
3. **Given** a Política de Privacidade, **When** alguém a lê, **Then** ela continua verdadeira
   sem precisar de nenhuma frase nova sobre novidades.

---

### Edge Cases

- **No dia do lançamento a lista está vazia.** O marco é 6 de outubro de 2026, e nada anterior
  entra — então a tela nasce sem nenhum item. Ela precisa dizer isso de um jeito que faça
  sentido, não mostrar uma área em branco.
- **Alguém instala o app um ano depois**: vê a lista inteira desde o lançamento, o que pode
  ser longo e não significa nada para quem nunca viu o app "antes".
- **Trocar de aparelho ou reinstalar**: o estado de "já vi" some, e a indicação de novidade
  volta para itens que a pessoa já tinha lido.
- **Duas mudanças no mesmo dia**: aparecem como itens separados ou como um só?
- **Uma mudança que ninguém percebe** — correção interna, ajuste de segurança sem efeito
  visível. Vira novidade ou não?
- **Uma mudança que remove alguma coisa**: alguém que usava aquilo precisa entender que sumiu,
  e o texto não pode falar só de coisa nova.
- **Texto escrito por quem programa**: o risco real é a lista virar changelog técnico
  disfarçado — "corrigido bug na RLS de votos" não diz nada a ninguém no distrito.

## Requirements *(mandatory)*

### A lista (US1)

- **FR-001**: O app DEVE ter uma tela de Novidades listando o que mudou, do mais recente para
  o mais antigo.
- **FR-002**: Cada novidade DEVE ter uma data e um texto que descreva a mudança **do ponto de
  vista de quem usa o app**.
- **FR-003**: O texto de cada novidade NÃO DEVE conter jargão técnico — nome de arquivo, nome
  de tabela, número de versão interna, ou termo que só quem programa entende.
- **FR-004**: A tela DEVE ser alcançável a partir da Home, com rótulo em texto.
- **FR-005**: Visitante sem cadastro DEVE ver a mesma lista que um Usuário com Perfil.
- **FR-006**: Novidades anteriores a **6 de outubro de 2026** NÃO DEVEM aparecer — esse é o
  marco do primeiro lançamento, e tudo antes dele é o app como ele nasceu.
- **FR-007**: Com a lista vazia, a tela DEVE explicar o que ela é e por que ainda não há nada,
  em vez de mostrar uma área em branco.

### O aviso (US2)

- **FR-008**: Havendo novidade que o Usuário ainda não viu, o app DEVE indicar isso
  visualmente onde ele já olha.
- **FR-009**: Abrir a tela de Novidades DEVE fazer a indicação sumir.
- **FR-010**: A indicação NÃO DEVE voltar enquanto não houver novidade mais recente que a
  última vista.
- **FR-011**: Quem abre o app pela primeira vez NÃO DEVE receber indicação de novidade.

### Privacidade (US3)

- **FR-012**: O app NÃO DEVE registrar no servidor quem leu quais novidades, nem quando.
- **FR-013**: O controle de "já vi" DEVE ficar **no aparelho**, e sua perda ao trocar de
  aparelho é comportamento aceito, não defeito.
- **FR-014**: Esta feature NÃO DEVE exigir nenhuma frase nova na Política de Privacidade — se
  exigir, é sinal de que passou a coletar algo, e o desenho precisa voltar.

### O conteúdo (US1)

- **FR-015**: Cada novidade DEVE ser escrita **à mão**, por quem entende o que a mudança
  significa para o distrito. NÃO DEVE ser gerada automaticamente do histórico de código.
- **FR-016**: Mudança que **remove** ou **restringe** alguma coisa DEVE poder ser descrita
  tanto quanto mudança que adiciona.
- **FR-017**: DEVE existir, escrito no repositório, o critério do que vira novidade e do que
  não vira — para a lista não virar changelog técnico com o tempo.

## Key Entities

**Novidade**: um item da lista. Tem uma **data** (quando a mudança chegou às pessoas) e um
**texto** em português voltado a quem usa. Não tem autor exibido, não tem categoria, não tem
link. É deliberadamente pobre: cada campo a mais é uma decisão de produto que ninguém pediu.

Não é entidade de banco por natureza — ver Assumptions.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): **nenhum dado pessoal é coletado, exibido ou retido.** A
feature não lê Perfil, não escreve em `perfis`, e não cria coluna nenhuma. O único estado que
ela guarda é "até onde esta instalação já viu", **no aparelho**, e isso é escolha de desenho,
não acaso: gravar isso no servidor criaria um dado de comportamento — quem abriu o app, quando
— que nenhuma entrada do glossário autoriza e que nenhuma tela precisa.

FR-014 existe para tornar isso verificável: se a feature obrigar a Política a ganhar uma frase
nova, ela passou a coletar algo, e o desenho errou.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): **nenhum.** A feature não toca
fila de espera, empate, revogação de voto, descarte de candidatas nem Dupla Missionária. Ela
não lê nem escreve nenhuma dessas tabelas.

**Papéis** (Princípio V): nenhum papel novo. A tela é igual para Visitante, Usuário, Dono do
Grupo, Líder/Diretor e Administrador do distrito — o que mudou no app não é privilégio de
ninguém.

## Success Criteria *(mandatory)*

- **SC-001**: 100% das novidades listadas têm data e texto compreensível por alguém que nunca
  programou — verificado pedindo a **três** pessoas do distrito que leiam a lista e digam, com
  as palavras delas, o que mudou.
- **SC-002**: 0 termos técnicos na lista — sem nome de arquivo, de tabela, de função, e sem
  número de versão interna.
- **SC-003**: 0 informações sobre leitura de novidades enviadas ao servidor — verificado
  observando o tráfego do app enquanto a tela é usada.
- **SC-004**: Quem já leu tudo abre o app e vê 0 indicações de novidade.
- **SC-005**: Quem instala o app pela primeira vez vê 0 indicações de novidade.
- **SC-006**: Uma pessoa encontra a tela de Novidades a partir da Home em menos de 15
  segundos, sem ajuda.
- **SC-007**: 0 frases novas na Política de Privacidade por causa desta feature.

## Assumptions

- **A data 06/10/26 é 6 de outubro de 2026** (dia/mês/ano, como se escreve no Brasil). Ela é
  **futura**: o projeto começou em 23 de julho de 2026 e hoje é 10 de agosto de 2026. Logo, o
  "primeiro deployment" é o **lançamento para o distrito**, ainda por vir, e não um fato
  passado. **Consequência concreta**: no dia em que esta feature entrar, a lista de Novidades
  estará **vazia**, e é por isso que FR-007 existe. Se a intenção era outra data — ou incluir
  retroativamente o que já foi feito — é uma linha que muda, e `/speckit-clarify` resolve.

- **As novidades vivem no código, não no banco.** São conteúdo de release: publicar uma
  novidade é, por definição, publicar uma versão. Mesmo arranjo dos textos legais, que já são
  compilados no app. Guardá-las no banco exigiria tela de administração, permissão de escrita e
  moderação — três coisas que ninguém pediu, contra o Princípio V. Se um dia for preciso
  publicar novidade sem lançar versão, aí sim a decisão muda.

- **Escritas à mão, uma a uma.** Gerar a lista do histórico de código transformaria "fecha a
  leitura pública de votos" em item de Novidades — verdadeiro, inútil e assustador. O que a
  pessoa precisa saber é "em quem você votou agora só você vê".

- **Nem toda mudança vira novidade.** Correção interna sem efeito visível não entra. O critério
  fica escrito no repositório (FR-017), senão a lista degenera em changelog técnico.

- **Sem "marcar como lida" item a item.** O aviso é um só, para a lista inteira. Estado por
  item multiplicaria a complexidade e ninguém pediu.

- **Sem notificação push, sem e-mail.** O app não tem canal de notificação hoje, e esta feature
  não inventa um. A pessoa descobre quando abre o app.

- **Sem histórico de versões técnico.** `pubspec.yaml` está em `1.0.0+1` desde o começo e esta
  feature **não** o toca — número de versão é para quem constrói, e FR-003 o proíbe na tela.

- **Sem tradução, sem acessibilidade além do que o app já tem.** A tela segue o mesmo padrão de
  contraste e alvo de toque das demais; nada novo é prometido aqui.
