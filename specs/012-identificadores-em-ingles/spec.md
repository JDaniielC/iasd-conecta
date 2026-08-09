# Feature Specification: Identificadores Dart em inglês

**Feature Branch**: `012-identificadores-em-ingles`

**Created**: 2026-08-09

**Status**: Draft

**Input**: User description: "Traduzir os identificadores Dart do app de português para inglês, conforme a fronteira de idioma do Princípio I da constituição. Escopo: lib/ inteiro. Banco de dados, chaves de fromMap/toInsertMap e strings de UI continuam em português. Refatoração sem mudança de comportamento."

## Contexto

A constituição v1.1.0, Princípio I, "Fronteira de idioma (código Dart)", diz que
identificadores Dart DEVEM ser escritos em inglês, usando uma tradução consistente do termo
do glossário — a mesma tradução em todo o código, nunca duas para o mesmo conceito. Banco de
dados e strings visíveis ao usuário continuam em português.

O código das features 001 a 009 foi escrito antes dessa regra e está majoritariamente em
português. O levantamento no repositório:

| Medida | Número |
|---|---|
| Arquivos `.dart` em `lib/` | 57 |
| Arquivos com nome em português | 37 |
| Pastas de módulo em português | 4 (`acao/`, `grupo/`, `perfil/`, `acao_sugerida/`) |
| Tipos em português | ~40 |
| Providers em português | ~16 de 35 |

A constituição prevê tradução gradual — "ao tocar um arquivo por outro motivo, traduza os
identificadores daquele arquivo". Na prática isso travou: a feature 011 precisa tocar
`acao.dart` e, ao tentar cumprir a regra, descobriu que renomear `Acao` quebra ~10 arquivos e
~6 testes de uma vez, o que misturaria um rename mecânico com uma mudança de comportamento no
mesmo diff. A 011 registrou o desvio em Complexity Tracking e adiou. Esta feature é o
pagamento dessa dívida.

**Esta é uma refatoração**: nenhum comportamento observável muda. Ninguém que usa o app
percebe qualquer diferença.

## User Scenarios & Testing *(mandatory)*

> Os beneficiários desta feature são quem escreve, revisa e mantém o código — inclusive
> agentes de IA que trabalham no repositório. Não há cenário de usuário final, porque nada
> que o usuário final vê muda. Essa ausência é o resultado esperado, não uma lacuna.

### User Story 1 - Existe um mapa de tradução único e oficial (Priority: P1)

Quem vai renomear qualquer coisa abre `CONTEXT.md` e encontra, ao lado de cada termo do
glossário, o identificador em inglês correspondente. Não precisa adivinhar se Ação vira
`Action` ou `Event`, nem descobrir tarde demais que outra pessoa já escolheu diferente.

**Why this priority**: sem isso, cada módulo traduzido é um chute novo, e o resultado é
exatamente o que o Princípio I proíbe — duas traduções para o mesmo conceito. Entregue
sozinha, já tem valor: o mapa oficial impede que features futuras criem divergência, mesmo
antes de uma linha de código ser renomeada.

**Independent Test**: abrir `CONTEXT.md` e verificar que cada termo do glossário tem um e
apenas um identificador em inglês declarado, e que nenhum identificador em inglês aparece
para dois termos diferentes.

**Acceptance Scenarios**:

1. **Given** o glossário de `CONTEXT.md`, **When** alguém procura o termo Ação, **Then**
   encontra `Action` declarado como a tradução, sem alternativa.
2. **Given** o mesmo documento, **When** alguém procura qualquer termo do glossário,
   **Then** encontra uma tradução declarada — nenhum termo fica sem.
3. **Given** o mapa completo, **When** alguém verifica as traduções, **Then** nenhum
   identificador em inglês está associado a dois termos diferentes do glossário.
4. **Given** conceitos que já estão em inglês no código (Perfil→`Profile`, Igreja→`Church`,
   Ação sugerida→`SuggestedAction`, Dupla Missionária→`MissionaryPair`, Administrador do
   distrito→`DistrictAdmin`), **When** o mapa é escrito, **Then** ele registra a tradução
   que já está em uso, em vez de inventar outra.

---

### User Story 2 - Cada módulo passa a falar inglês, sem mudar comportamento (Priority: P2)

Um módulo por vez — perfil, grupo, ação, ação sugerida, liderança, administração do distrito,
núcleo — tem seus arquivos, pastas, tipos, métodos, campos e providers renomeados para
inglês, seguindo o mapa. Ao fim de cada módulo o app compila, todos os gates passam, e nada
que o usuário vê mudou.

**Why this priority**: é o trabalho em si. Depende do mapa (US1) existir, mas cada módulo é
entregável e verificável sozinho — dá para parar depois de qualquer um deles sem deixar o
repositório num estado quebrado.

**Independent Test**: escolher um módulo, aplicar o rename, e verificar que o app compila,
que a quantidade de testes que passam é idêntica à de antes, e que nenhuma string visível ao
usuário mudou.

**Acceptance Scenarios**:

1. **Given** um módulo cujo rename foi concluído, **When** o código é compilado, **Then**
   compila sem erro e sem aviso novo.
2. **Given** o mesmo módulo, **When** a suíte de testes roda, **Then** a quantidade de
   testes que passam é exatamente a mesma de antes do rename.
3. **Given** o mesmo módulo, **When** alguém procura identificadores em português nos
   arquivos daquele módulo, **Then** não encontra nenhum.
4. **Given** o mesmo módulo, **When** alguém compara as strings visíveis ao usuário antes e
   depois, **Then** são idênticas, caractere a caractere.
5. **Given** um módulo ainda não traduzido, **When** ele é usado a partir de um módulo já
   traduzido, **Then** tudo continua funcionando — módulos em idiomas diferentes coexistem
   durante a transição.
6. **Given** todos os módulos traduzidos, **When** alguém procura por identificadores em
   português em `lib/`, **Then** não encontra nenhum.

---

### User Story 3 - Quem revisa consegue provar que nada mudou (Priority: P3)

Quem revisa o rename de um módulo consegue afirmar, com evidência e não com confiança, que
aquilo é um rename puro: nenhuma chave de mapa de dados foi alterada, nenhuma string de UI
foi alterada, nenhuma asserção de teste mudou de significado, e nenhum arquivo de banco foi
tocado.

**Why this priority**: é o que separa este trabalho de um acidente. Um rename que
silenciosamente troque a chave `'data_hora'` por `'dateTime'` não quebra a compilação — quebra
em produção, na hora de ler o dado. A revisibilidade é o único guarda-corpo contra isso.

**Independent Test**: para qualquer módulo renomeado, verificar que nenhum literal de string
mudou e que nenhum arquivo de migração foi tocado.

**Acceptance Scenarios**:

1. **Given** o rename de um módulo, **When** alguém compara os literais de string antes e
   depois, **Then** o conjunto de literais é idêntico — inclusive as chaves usadas para ler
   e gravar dados (`'nome'`, `'data_hora'`, `'criador_id'`, `'limite_vagas'`,
   `'cancelada_em'`, `'genero_visitado'`, e as demais).
2. **Given** o rename de qualquer módulo, **When** alguém lista os arquivos alterados,
   **Then** nenhum arquivo de migração de banco aparece.
3. **Given** o rename de um módulo, **When** a suíte de testes roda, **Then** nenhuma
   asserção mudou de significado — o que mudou nos testes é apenas o nome dos símbolos que
   eles referenciam.
4. **Given** o rename completo, **When** alguém verifica os nomes de tabelas, colunas,
   funções e gatilhos do banco, **Then** continuam todos em português, inalterados.

---

### Edge Cases

- **Conceito que já está em inglês**: `Profile`, `Church`, `SuggestedAction`,
  `MissionaryPair`, `DistrictAdmin`, `LeadershipDeclaration`, `Gender`, `VisitedGender` já
  existem. O mapa registra o que está em uso; nada é renomeado só por gosto.
- **Identificador que é campo e chave ao mesmo tempo**: o campo Dart `nome` vira `name`, mas
  o texto `'nome'` usado para ler o dado permanece `'nome'`. É o ponto mais perigoso da
  feature e não gera erro de compilação quando feito errado.
- **Nome com duas leituras possíveis**: "Participar" é ação (entrar num Grupo) e é também
  confirmar presença numa Ação. São conceitos diferentes no glossário e recebem traduções
  diferentes, declaradas separadamente.
- **Classe privada e variável local**: também entram, dentro do módulo que está sendo
  traduzido — `_AcaoCard`, `_FiltrosBar`, `_OrdenacaoAcao`, `_CabecalhoSecao`.
- **Comentário em português**: permanece em português. A regra é sobre identificador, não
  sobre prosa.
- **Módulo pela metade**: não acontece. A unidade de entrega é o módulo inteiro; parar no
  meio de um módulo deixa o repositório sem compilar.
- **Conflito com feature aberta**: se uma feature de comportamento estiver aberta sobre o
  mesmo módulo, uma das duas espera. Renomear e mudar comportamento no mesmo diff é o que
  esta feature existe para evitar.

## Requirements *(mandatory)*

### Mapa de tradução (US1)

- **FR-001**: `CONTEXT.md` DEVE declarar, para cada termo do glossário, um e apenas um
  identificador correspondente em inglês.
- **FR-002**: Nenhum identificador em inglês DEVE aparecer como tradução de dois termos
  diferentes do glossário.
- **FR-003**: O mapa DEVE registrar as traduções **já em uso no código** em vez de propor
  alternativas: Perfil→`Profile`, Conta→`Account`, Apelido→`Nickname`, Igreja→`Church`,
  Ação sugerida→`SuggestedAction`, Dupla Missionária→`MissionaryPair`, Administrador do
  distrito→`DistrictAdmin`, Líder/Diretor→`Leader`.
- **FR-004**: O mapa DEVE cobrir também os termos ainda sem tradução em uso, no mínimo:
  Visitante, Usuário, Categoria de Grupo, Grupo, Participar do Grupo, Dono do Grupo, Ação,
  Ação candidata, Rodada de votação, Votar, Ministério, e os conceitos operacionais
  recorrentes fila de espera, confirmar presença e desistir.
- **FR-005**: O mapa DEVE ser escrito antes de qualquer módulo ser renomeado, e qualquer
  tradução nova descoberta durante o trabalho DEVE entrar nele antes de entrar no código.

### Rename por módulo (US2)

- **FR-006**: Todos os identificadores Dart de `lib/` DEVEM ficar em inglês: nomes de classe,
  enum, método, função, variável, parâmetro, campo, getter, provider e **nome de arquivo**.
- **FR-007**: As pastas de módulo em português DEVEM ser renomeadas para inglês
  (`lib/features/acao/`, `grupo/`, `perfil/`, `acao_sugerida/`).
- **FR-008**: Identificadores privados e locais (classes com prefixo `_`, enums privados,
  variáveis dentro de método) DEVEM ser traduzidos junto com o módulo a que pertencem.
- **FR-009**: A tradução DEVE seguir o mapa de FR-001, sem exceção e sem variação — o mesmo
  conceito recebe o mesmo identificador em todo o código.
- **FR-010**: O trabalho DEVE ser entregue **um módulo por vez**, e ao fim de cada módulo o
  código DEVE compilar e todos os gates de verificação DEVEM passar.
- **FR-011**: Módulos já traduzidos e módulos ainda não traduzidos DEVEM coexistir sem
  quebra durante a transição.

### Fronteira preservada (US3)

- **FR-012**: Nenhuma string visível ao usuário DEVE ser alterada — nem traduzida, nem
  reescrita, nem reformatada.
- **FR-013**: Nenhuma chave usada para ler ou gravar dados DEVE ser alterada. Elas continuam
  em português, exatamente como estão.
- **FR-014**: Nenhum nome de tabela, coluna, função ou gatilho do banco DEVE ser alterado.
- **FR-015**: Nenhum arquivo de migração de banco DEVE ser criado ou modificado por esta
  feature.
- **FR-016**: Nenhuma asserção de teste DEVE mudar de significado. A única mudança permitida
  em teste é o nome dos símbolos que ele referencia.
- **FR-017**: Nenhuma rota de navegação DEVE ser alterada — os endereços que o usuário pode
  ter salvo ou compartilhado continuam válidos.
- **FR-018**: Comentários e documentação em português DEVEM permanecer em português.

### Verificação (US3)

- **FR-019**: Ao fim de cada módulo, DEVE ser possível demonstrar que a quantidade de testes
  que passam é idêntica à de antes do rename daquele módulo.
- **FR-020**: Ao fim do trabalho, uma busca por identificadores em português em `lib/` DEVE
  retornar vazio.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): esta feature não coleta, não exibe, não retém e não move
nenhum dado pessoal. Nenhuma consulta, nenhuma permissão e nenhuma regra de exibição muda.
A regra de exibir menor de idade por Apelido continua exatamente onde está, com outro nome
de símbolo.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum comportamento muda —
nem promoção da fila de espera, nem desempate por sorteio, nem revogabilidade de voto ou de
Participar, nem descarte de candidatas perdedoras, nem composição de Dupla Missionária.
A prova disso é FR-016 e FR-019: as mesmas asserções, na mesma quantidade, passando.

**Papéis** (Princípio V): nenhum papel novo, nenhuma permissão nova.

**Princípio I**: esta feature **é** o cumprimento do Princípio I. Ao fim dela, a ressalva
registrada no Complexity Tracking da feature 011 deixa de existir.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: 0 identificadores em português em `lib/`, verificado por busca ao fim do
  trabalho.
- **SC-002**: 0 arquivos e 0 pastas com nome em português em `lib/` — de 37 arquivos e 4
  pastas no início, para 0.
- **SC-003**: A quantidade de testes que passam é idêntica antes e depois de cada módulo, e
  ao fim de tudo — número anotado a cada etapa, não "passou".
- **SC-004**: 0 strings visíveis ao usuário alteradas, verificado comparando o conjunto de
  literais antes e depois.
- **SC-005**: 0 chaves de leitura/gravação de dados alteradas.
- **SC-006**: 0 arquivos de migração de banco tocados.
- **SC-007**: 0 rotas de navegação alteradas.
- **SC-008**: 100% dos termos do glossário de `CONTEXT.md` com tradução declarada, e 0
  identificadores em inglês servindo a dois termos.
- **SC-009**: Cada etapa entregue deixa o repositório compilando e com os gates passando —
  0 etapas que exigem "a próxima etapa para funcionar".

## Assumptions

- **Testes não são renomeados**: os 37 arquivos de teste com nome em português mantêm seus
  nomes, e os identificadores dentro deles mudam **apenas onde a compilação exige** (o tipo
  ou o símbolo referenciado foi renomeado). Variáveis locais de teste em português
  permanecem. É uma exceção deliberada ao FR-006, restrita a `test/`: nome de teste de
  integração descreve cenário de domínio e se lê como spec, e spec é português por decisão da
  constituição. Se essa exceção incomodar depois, vira trabalho separado.
- **Entrega por módulo, em série**: a ordem sugerida vai do mais isolado ao mais acoplado —
  perfil, grupo, ação sugerida, ação, liderança, administração do distrito, núcleo. Cada um
  é uma etapa fechada.
- **Nenhuma feature de comportamento em paralelo sobre o mesmo módulo**: as features 010 e
  011 estão abertas. A 011 toca o módulo de Ação inteiro; a 010 toca uma linha do módulo de
  Ação e o núcleo. Ordem e coexistência ficam para a fase de plano.
- **Sem mudança de estrutura**: nenhum arquivo é dividido, unido ou movido de camada. Só
  renomeado. Melhorias de organização que aparecerem viram anotação, não commit.
- **Sem ferramenta nova**: nenhuma dependência é adicionada. O rename é feito com o
  ferramental que o projeto já tem.
- **`CONTEXT.md` é o lar do mapa**: a constituição já diz que um termo novo ou renomeado só
  entra em código depois de atualizado em `CONTEXT.md`. O mapa de tradução vive lá pelo mesmo
  motivo, e não num documento novo que ninguém vai lembrar de abrir.
