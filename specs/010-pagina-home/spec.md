# Feature Specification: Página Home de propósito

**Feature Branch**: `010-pagina-home`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Página home que descreva seu propósito, adicione a frase 'A Deus seja a glória' e utilize /ui-ux-pro-max:ui-ux-pro-max"

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Visitante entende para que serve o app (Priority: P1)

Uma pessoa da igreja recebe o link do app pelo grupo de WhatsApp do distrito e abre pela
primeira vez, sem cadastro. Hoje ela cai direto numa lista de Grupos e precisa deduzir o
que o app é. Nesta feature, ela chega numa Home que diz, em uma frase, o que o app é —
uma rede do distrito de Vitória de Santo Antão para descobrir e participar de Grupos e
Ações — explica em poucos blocos o que ela pode fazer ali, e fecha a página com "A Deus
seja a glória" no rodapé.

**Why this priority**: é o motivo da feature existir. Sem ela, a primeira impressão do app
é uma lista sem contexto, e o Visitante não sabe se aquilo é para ele. Entregue sozinha,
já resolve o problema: uma Home que explica o propósito é útil mesmo que a navegação
continue como está hoje.

**Independent Test**: abrir o app sem Perfil, na rota inicial, e verificar que o propósito
do app está visível sem nenhuma interação prévia, e que "A Deus seja a glória" fecha a
página no rodapé.

**Acceptance Scenarios**:

1. **Given** um Visitante sem Perfil, **When** abre o app pela primeira vez, **Then** a
   primeira tela é a Home, com o nome do app e uma frase de propósito visíveis sem rolar.
2. **Given** a Home aberta, **When** o Visitante rola até o fim, **Then** encontra "A Deus
   seja a glória" fechando a página.
3. **Given** a Home aberta, **When** o Visitante lê a tela, **Then** encontra explicação
   do que são Grupos e do que são Ações, em linguagem do glossário e sem jargão técnico.
4. **Given** um Usuário com Perfil, **When** abre o app, **Then** vê a mesma Home, sem
   nenhum dado pessoal dele ou de terceiros exibido na tela.
5. **Given** a Home aberta em um aparelho com fonte do sistema no tamanho máximo, **When**
   a tela é renderizada, **Then** todo o texto continua legível e nenhum texto é cortado.

---

### User Story 2 - Chegar às atividades a partir da Home (Priority: P2)

Depois de entender o propósito, a pessoa quer ver o que existe de verdade: os Grupos do
distrito e as Ações abertas. A Home oferece caminhos claros e nomeados para as duas
listas, e continua acessível depois — a pessoa consegue voltar para a Home de dentro das
listas.

**Why this priority**: sem isso a Home vira um beco sem saída e o app perde a porta de
entrada para o conteúdo que já existe. Depende da US1 existir, mas é testável sozinha.

**Independent Test**: a partir da Home, alcançar a lista de Grupos e a lista de Ações, e
voltar para a Home de cada uma delas.

**Acceptance Scenarios**:

1. **Given** um Visitante na Home, **When** aciona o caminho para Grupos, **Then** vê a
   lista de Grupos do distrito.
2. **Given** um Visitante na Home, **When** aciona o caminho para Ações, **Then** vê a
   lista de Ações.
3. **Given** um Visitante na lista de Grupos ou de Ações, **When** usa o gesto/controle de
   voltar do sistema, **Then** retorna à Home, sem a pilha de navegação ser reiniciada.
4. **Given** um Visitante na Home, **When** a lista de Grupos ainda está vazia no distrito,
   **Then** o caminho para Grupos continua visível e a lista mostra estado vazio explicado,
   não uma tela em branco.

---

### User Story 3 - Saber como participar e o que o app faz com meus dados (Priority: P3)

O Visitante decidiu que quer participar. A Home diz, em uma linha, que participar exige
cadastro simples (Perfil), oferece o caminho para o cadastro, e dá acesso à Política de
Privacidade e aos Termos de Uso antes de a pessoa se cadastrar.

**Why this priority**: é conversão e transparência. Vale muito, mas o app já tem os fluxos
de cadastro e as páginas legais — a Home só precisa apontar para eles.

**Independent Test**: a partir da Home, alcançar o cadastro de Perfil, a Política de
Privacidade e os Termos de Uso.

**Acceptance Scenarios**:

1. **Given** um Visitante sem Perfil na Home, **When** lê a chamada principal, **Then**
   entende que ver é livre e que participar/votar/criar exige cadastro.
2. **Given** um Visitante sem Perfil na Home, **When** aciona a chamada principal, **Then**
   chega ao cadastro de Perfil.
3. **Given** um Usuário que já tem Perfil na Home, **When** olha a chamada principal,
   **Then** ela não convida a se cadastrar de novo, e sim a explorar Grupos e Ações.
4. **Given** um Visitante na Home, **When** procura informação sobre uso de dados,
   **Then** alcança a Política de Privacidade e os Termos de Uso a partir da própria Home.

---

### Edge Cases

- **Sem conexão ou serviço indisponível**: a Home é conteúdo estático (propósito, frase,
  explicações, caminhos de navegação) e DEVE continuar renderizando por completo mesmo
  sem rede. Só as listas para onde ela aponta dependem de rede.
- **Distrito ainda vazio** (nenhum Grupo, nenhuma Ação): a Home não esconde nem desabilita
  os caminhos; a lista de destino é quem explica o vazio.
- **Estado de Perfil ainda carregando**: a Home não pisca entre duas versões da chamada
  principal; enquanto o estado é desconhecido, mostra a versão neutra e só então adapta.
- **Aparelho pequeno (375px) e paisagem**: nenhum conteúdo essencial fica inacessível; a
  Home rola verticalmente e nunca rola horizontalmente.
- **Leitor de tela ativo**: a ordem de leitura acompanha a ordem visual, e a frase "A Deus
  seja a glória" é lida como texto, não ignorada como elemento decorativo.
- **Usuário chega por link direto** a um Grupo ou Ação: não é redirecionado para a Home; a
  Home é a rota inicial, não uma barreira.

## Requirements *(mandatory)*

### Functional Requirements

#### Conteúdo

- **FR-001**: A rota inicial do app DEVE apresentar a Home; a lista de Grupos deixa de ser
  a primeira tela e passa a ser um destino alcançável a partir da Home.
- **FR-002**: A Home DEVE exibir o nome do app — **Conecta IASD** — e uma frase de propósito
  que identifique (a) a comunidade atendida — membros das igrejas do distrito de Vitória de
  Santo Antão — e (b) o que se faz ali — descobrir e participar de Grupos e Ações.
- **FR-003**: A Home DEVE exibir a frase exata "A Deus seja a glória", com acentuação e
  capitalização idênticas, **no rodapé da página**, como fecho — e não no bloco de
  identidade.
- **FR-004**: A Home DEVE explicar, em blocos curtos, o que é um Grupo (comunidade
  permanente em torno de uma atividade recorrente) e o que é uma Ação (evento pontual com
  data, hora e local), usando os termos exatos do glossário em `CONTEXT.md`.
- **FR-005**: A Home DEVE deixar explícito que Visitante vê Grupos e Ações livremente, e
  que participar, votar ou criar exige cadastro.
- **FR-006**: A Home NÃO DEVE exibir nenhum dado pessoal — nem do próprio Usuário, nem de
  terceiros (sem nome, Apelido, contagem de participantes identificados, foto ou Igreja de
  origem de ninguém).

#### Navegação

- **FR-007**: Usuários e Visitantes DEVEM conseguir alcançar a lista de Grupos e a lista de
  Ações a partir da Home, por controles rotulados com texto (não apenas ícone).
- **FR-007a**: Os **rótulos de tela** que hoje dizem "Grupo" — título de página, botão,
  rótulo de campo e tooltip — DEVEM dizer "Grupo/Ministério" (ou "Grupos/Ministérios" no
  plural). Vale só para rótulo: prosa explicativa, mensagem de erro e páginas legais
  continuam usando "Grupo", o termo do glossário.
- **FR-008**: A Home DEVE ter exatamente uma chamada principal, visualmente destacada
  acima das demais: cadastrar-se, para quem não tem Perfil; explorar Grupos, para quem já
  tem.
- **FR-009**: A Home DEVE dar acesso à Política de Privacidade e aos Termos de Uso.
- **FR-010**: O retorno do sistema (gesto ou botão de voltar) a partir de qualquer destino
  alcançado pela Home DEVE trazer o usuário de volta à Home, preservando a posição de
  rolagem, sem reiniciar a pilha de navegação.
- **FR-011**: A Home DEVE ter endereço próprio e estável, de forma que possa ser
  compartilhada por link e usada como destino de retorno a partir de telas internas.

#### Qualidade de experiência (transversal, verificável)

- **FR-012**: Todo texto de corpo DEVE ter contraste mínimo de 4,5:1 contra o fundo, e todo
  elemento gráfico com significado, no mínimo 3:1.
- **FR-013**: Todo elemento tocável DEVE ter área de toque de no mínimo 44×44pt (iOS) /
  48×48dp (Android), com no mínimo 8pt de separação entre alvos vizinhos.
- **FR-014**: A Home DEVE respeitar o tamanho de fonte do sistema até o maior nível, sem
  cortar texto nem sobrepor elementos.
- **FR-015**: A Home DEVE respeitar as áreas seguras da tela (recorte de câmera, barra de
  status, barra de gestos) — nenhum conteúdo ou controle fica sob elas.
- **FR-016**: A Home DEVE respeitar a preferência de movimento reduzido do sistema:
  qualquer animação de entrada é suprimida quando essa preferência está ativa, e o conteúdo
  aparece legível de imediato.
- **FR-017**: Ícones da Home DEVEM vir de um conjunto vetorial único e consistente;
  emoji NÃO DEVE ser usado como ícone estrutural.
- **FR-018**: A Home DEVE seguir o tema visual já existente do app (paleta azul-marinho e
  branco, cartões com espaço em branco, tipografia limpa) — esta feature não introduz uma
  identidade visual nova.
- **FR-019**: A Home NÃO DEVE rolar horizontalmente em nenhuma largura de tela suportada,
  incluindo 375px e orientação paisagem.
- **FR-020**: A ordem de leitura por leitor de tela DEVE acompanhar a ordem visual, e todo
  controle DEVE ter rótulo descritivo audível.

### Key Entities

Nenhuma entidade nova. A Home é uma tela de conteúdo estático que aponta para as entidades
existentes (Grupo, Ação) sem lê-las nem gravá-las.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II e seção "Requisitos de Domínio e Compliance"): esta feature
não coleta, não exibe e não retém nenhum dado pessoal. Não exige consentimento adicional
além do consentimento LGPD já dado no cadastro. FR-006 torna essa ausência verificável.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): a Home apenas navega até as
listas. Não altera fila de espera, apuração de Rodada de votação, desempate por sorteio,
revogação de voto ou de Participar, nem descarte de candidatas perdedoras. Nenhum desses
comportamentos muda por causa desta feature.

**Papéis** (Princípio V): nenhum papel novo. A Home distingue apenas Visitante (sem Perfil)
de Usuário (com Perfil), distinção que já existe.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: Uma pessoa que nunca viu o app consegue dizer, em uma frase e em até 30
  segundos na Home, para quem o app serve e o que se faz nele — verificado com no mínimo 5
  membros da igreja, com 4 dos 5 acertando.
- **SC-002**: A frase "A Deus seja a glória" está presente no rodapé da Home, alcançável
  rolando até o fim, em telas a partir de 375px de largura, em retrato e em paisagem.
- **SC-003**: A partir da Home, a lista de Grupos e a lista de Ações são alcançadas em um
  único toque cada.
- **SC-004**: 100% dos pares texto/fundo da Home atingem contraste de 4,5:1, e 100% dos
  alvos tocáveis atingem 44×44pt — verificado por inspeção antes de considerar pronto.
- **SC-005**: A Home renderiza integralmente sem conexão de rede, sem erro visível e sem
  área em branco no lugar do conteúdo.
- **SC-006**: A Home é utilizável com a fonte do sistema no maior tamanho, sem texto
  cortado nem sobreposição — verificado em 375px e em paisagem.

## Assumptions

- **Lista de Grupos ganha rota própria**: hoje a rota inicial mostra a lista de Grupos.
  Assume-se que a lista continua existindo sem mudanças de comportamento, apenas passa a
  ter endereço próprio, e a Home passa a ser a rota inicial. Os atalhos administrativos e
  de Conta que hoje moram na barra da lista de Grupos permanecem onde estão — movê-los está
  fora do escopo desta feature.
- **Home é a mesma para todos**: o conteúdo não é personalizado por Igreja de origem, por
  papel (Líder/Diretor, Administrador do distrito) nem por histórico. A única variação é a
  chamada principal (FR-008), que depende apenas de ter ou não Perfil. Personalização por
  Igreja fica fora do escopo.
- **Conteúdo estático e em português**: os textos da Home são fixos no app, não vêm do
  banco e não são editáveis por Administrador do distrito nesta versão.
- **Sem métricas de comunidade**: a Home não mostra contagem de membros, de Grupos ou de
  Ações. Números vivos exigiriam leitura de rede e quebrariam FR-005/SC-005; ficam fora do
  escopo.
- **Modo escuro fora do escopo**: o app hoje define apenas tema claro. A Home segue o tema
  claro existente; suporte a modo escuro é decisão de produto separada, para o app inteiro.
- **Nada muda nos dados**: nenhum dado armazenado é criado, lido, alterado ou apagado por
  esta feature.


## Emendas

**2026-08-09 — nome do app, doxologia no rodapé e rótulo Grupo/Ministério**

Pedido do responsável pelo app, depois da primeira implementação:

1. **FR-002**: o nome passa a ser **Conecta IASD**, em vez de "Rede IASD Vitória de Santo
   Antão". Aplicado também ao título da janela, ao `manifest.json` e ao `index.html`.
2. **FR-003 e SC-002**: "A Deus seja a glória" sai do bloco de identidade e vai para o
   **rodapé**. Deixa de ser exigida sem rolagem. Efeito colateral bom: some o conflito que o
   `plan.md` registrava entre SC-002 e FR-014 — não há mais como a doxologia e a fonte no
   tamanho máximo brigarem pelo mesmo espaço em paisagem.
3. **FR-007a** (novo): rótulo de tela diz "Grupo/Ministério".
4. **Ícone do app**: `web/favicon.png` e os quatro `web/icons/` passam a ter uma marca
   própria do Conecta IASD — três nós ligados, no azul-marinho do tema. **Não** usa o
   símbolo oficial da Igreja Adventista do Sétimo Dia, que é marca registrada de uma
   organização real; desenhar uma imitação de memória e chamá-la de oficial seria errado.
   Se o arquivo oficial for fornecido, é só substituir os cinco PNGs.

**Tensão registrada no item 3**: Grupo e Ministério são entradas **distintas** do glossário —
Ministério é um Grupo que tem Líder/Diretor, e Grupo informal não é Ministério. Juntá-los no
rótulo funde dois conceitos que o Princípio I manda manter separados. A decisão foi do
responsável pelo app, o escopo ficou restrito a rótulo (nunca a identificador, banco, prosa
ou texto legal), e `CONTEXT.md` registra a convenção para que glossário e tela não divirjam.
