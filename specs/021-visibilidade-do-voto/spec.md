# Feature Specification: Quem pode ver em quem você votou

**Feature Branch**: `021-visibilidade-do-voto`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado durante o planejamento da feature 018 — mesma classe de problema
(`using (true)`), tabela diferente, e desta vez com uma frase na Política de Privacidade
descrevendo algo que ninguém decidiu.

## Contexto: três respostas diferentes para a mesma pergunta

A pergunta é simples: **quem pode ver em quem você votou?** Hoje o app responde de três
jeitos, e os três discordam.

**O banco diz: qualquer pessoa do mundo.**
`supabase/migrations/20260724084300_rodada_votacao.sql:207-210`:

```sql
create policy votos_select_public
  on public.votos for select
  to anon, authenticated
  using (true);
```

Somado ao `grant select on public.votos to anon, authenticated`
(`rodada_votacao.sql:190`), qualquer pessoa sem cadastro consulta a tabela inteira. E a
tabela é exatamente o par que interessa (`rodada_votacao.sql:21-27`):

```sql
create table public.votos (
  rodada_id uuid not null references public.rodadas_votacao(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  candidata_id uuid not null references public.acoes(id) on delete cascade,
  ...
);
```

`usuario_id` mais `candidata_id`. Não é um agregado, não é uma contagem — é a lista
nominal de quem votou em quê.

**A Política de Privacidade diz: os participantes do Grupo.**
`lib/features/legal/presentation/privacy_policy_page.dart:131-133`:

> "Em qual candidata você votou, dentro de uma Rodada de votação do seu Grupo — o voto
> não é anônimo **entre os participantes do Grupo**."

Essa frase é falsa por ser estreita demais: ela promete um círculo, e o círculo real é a
internet.

**O app diz: ninguém.** Nenhuma tela mostra o voto de outra pessoa. O único ponto de
leitura em todo o código Dart filtra pelo próprio usuário
(`lib/features/action/data/voting_round_repository.dart:78-86`):

```dart
Future<Vote?> myVote(String votingRoundId) async {
  final uid = _client.auth.currentUser!.id;
  final row = await _client
      .from('votos')
      .select()
      .eq('rodada_id', votingRoundId)
      .eq('usuario_id', uid)
      .maybeSingle();
```

E `voting_round_detail_page.dart:97` usa isso só para marcar qual candidata **você**
escolheu. Não existe contagem de votos na tela, nem lista de quem votou. A apuração roda
dentro de `fechar_rodada_se_devido`, que é `security definer`
(`rodada_votacao.sql:134-142`) — ou seja, ela conta os votos **por fora da RLS** e não
depende dessa política para nada.

Nenhuma spec, nenhum documento de decisão e nenhum achado registra alguém tendo escolhido
que o voto seria público. O `using (true)` é o padrão que ninguém questionou, e a frase da
Política foi escrita depois, descrevendo-o de forma amenizada.

## Por que isso importa nesta comunidade

Um Grupo é um conjunto de pessoas de um distrito de 15+ igrejas que se conhecem. A Rodada
de votação escolhe entre Ações propostas por pessoas do próprio Grupo. Saber que Fulana
votou na proposta da Beltrana e não na sua não é um dado técnico — é material de
constrangimento numa comunidade pequena, e ninguém foi avisado de que seria legível por
qualquer um.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - O voto deixa de ser legível pela internet (Priority: P1)

Um participante vota numa Rodada. Esse voto deixa de ser legível por qualquer pessoa que
consulte a API. Ele continua legível para quem tem motivo — no mínimo, para a própria
pessoa que votou.

**Why this priority**: é a feature. É o único item que expõe escolha pessoal de gente real
sem ninguém ter decidido isso.

**Independent Test**: consultar a tabela de votos como Visitante sem cadastro e verificar
que não vem voto de ninguém.

**Acceptance Scenarios**:

1. **Given** votos registrados numa Rodada, **When** um Visitante sem cadastro consulta,
   **Then** não recebe nenhum voto.
2. **Given** votos registrados, **When** um Usuário cadastrado que **não** participa do
   Grupo consulta, **Then** não recebe voto de ninguém.
3. **Given** o próprio voto, **When** a pessoa que votou consulta, **Then** recebe o
   próprio voto — é o que a tela dela precisa para marcar a candidata escolhida.
4. **Given** um Usuário qualquer, **When** ele consulta os votos de **outra** pessoa,
   **Then** não os recebe.

---

### User Story 2 - Votar, trocar de voto e apurar continuam funcionando (Priority: P1)

A pessoa vota, muda de ideia, vota de novo, e a Rodada fecha apurando corretamente. Nada
disso muda.

**Why this priority**: **é P1 junto com a US1, não depois.** Apertar a leitura de uma
tabela pode quebrar a escrita nela sem ninguém perceber, porque o app grava o voto por
`upsert` — uma operação que precisa achar a linha anterior para substituí-la. Uma feature
de privacidade que impeça alguém de trocar o próprio voto trocou um problema por outro.

**Independent Test**: votar, trocar de candidata, e fechar a Rodada — verificando que a
vencedora apurada é a que tem mais votos.

**Acceptance Scenarios**:

1. **Given** uma Rodada aberta, **When** um participante vota, **Then** o voto é
   registrado.
2. **Given** um voto já registrado, **When** a mesma pessoa vota em outra candidata,
   **Then** o voto anterior é substituído e só o último conta — como hoje.
3. **Given** uma Rodada com votos de várias pessoas, **When** ela fecha, **Then** a
   candidata mais votada vence, com a mesma contagem de hoje.
4. **Given** um empate, **When** a Rodada fecha, **Then** o sorteio entre as empatadas
   funciona como hoje.
5. **Given** a tela da Rodada, **When** a pessoa a abre, **Then** continua vendo marcada a
   candidata em que ela votou.

---

### User Story 3 - A Política passa a descrever o que acontece (Priority: P2)

Quem lê a Política de Privacidade encontra a regra real de quem enxerga o voto, e não uma
descrição amenizada de uma tabela aberta.

**Why this priority**: enquanto o texto disser "entre os participantes do Grupo" e a regra
for outra, o app está descrevendo errado a si mesmo — divergência entre promessa e
execução, que a constituição trata como violação.

**Acceptance Scenarios**:

1. **Given** a Política de Privacidade, **When** alguém lê o item sobre voto, **Then**
   encontra descrita a regra que o banco de fato aplica.
2. **Given** `MAPA-DE-DADOS.md`, **When** alguém o lê, **Then** ele não registra mais a
   leitura irrestrita como fato vigente.
3. **Given** a decisão sobre quem vê o voto, **When** alguém procura por que ela é essa,
   **Then** encontra registrado — para não voltar a ser um padrão que ninguém escolheu.

---

### Edge Cases

- **Trocar de voto com a leitura fechada**: o app grava por `upsert`, que resolve conflito
  com a linha existente. Se a nova regra impedir a pessoa de **ler** a própria linha, é
  preciso confirmar que ela ainda consegue **substituí-la**. Esta é a armadilha principal
  da feature.
- **Apuração**: roda dentro de função `security definer`, que ignora RLS. Precisa continuar
  ignorando — se alguém a converter para função normal depois, a apuração para de contar
  votos e ninguém percebe até uma Rodada fechar errado.
- **Rodada já fechada**: o voto continua guardado. A regra de visibilidade vale igual
  depois do fechamento? Um voto não vira histórico público por a Rodada ter acabado.
- **Contagem por diferença**: uma resposta vazia não pode revelar, pelo tamanho ou pelo
  código de erro, quantos votos existem escondidos.
- **A pessoa excluiu a conta**: a feature 009 apaga os votos de Rodadas em aberto e
  anonimiza o Perfil. Votos de Rodadas já apuradas continuam apontando para um Perfil
  anonimizado — e portanto para "Membro removido", não para um nome.
- **Grupo arquivado** (feature 014): a Rodada do Grupo arquivado some da exibição, mas os
  votos continuam na tabela.

## Requirements *(mandatory)*

### Fechar a exposição (US1)

- **FR-001**: Visitante sem cadastro NÃO DEVE conseguir ler nenhum voto.
- **FR-002**: Usuário cadastrado que não participa do Grupo dono da Rodada NÃO DEVE
  conseguir ler nenhum voto daquela Rodada.
- **FR-003**: A pessoa que votou DEVE conseguir ler o **próprio** voto.
- **FR-004**: Nenhum Usuário DEVE conseguir ler o voto de outra pessoa.
- **FR-005**: A restrição DEVE ser garantida **no banco**, não na tela — a tela já esconde
  hoje, e esconder não é proteger. É exatamente essa diferença que motiva a feature.
- **FR-006**: A restrição DEVE valer também depois que a Rodada fecha.

### Não quebrar o que existe (US2)

- **FR-007**: Registrar um voto DEVE continuar funcionando.
- **FR-008**: Trocar de candidata DEVE continuar substituindo o voto anterior, com só o
  último contando.
- **FR-009**: A apuração ao fechar a Rodada DEVE continuar contando **todos** os votos,
  independentemente de quem os leia.
- **FR-010**: A tela da Rodada DEVE continuar marcando a candidata escolhida pela própria
  pessoa.
- **FR-011**: A regra de desempate por sorteio NÃO DEVE ser alterada.

### Dizer a verdade (US3)

- **FR-012**: A Política de Privacidade DEVE descrever a regra real de visibilidade do
  voto, substituindo a frase que hoje promete um círculo diferente do que existe.
- **FR-013**: `MAPA-DE-DADOS.md` DEVE deixar de registrar `votos_select_public` como
  leitura irrestrita vigente, e passar a descrever a regra que existe.
- **FR-014**: A decisão sobre quem enxerga o voto DEVE ficar registrada com o motivo — foi
  a ausência desse registro que deixou `using (true)` sobreviver.

## Key Entities

Nenhuma entidade nova. **Voto** já existe, com os campos que já existem. O que muda é
**quem consegue lê-lo**.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II — e a feature existe por causa dele): **a feature só reduz
exposição.** Nenhum dado novo é coletado, nenhum campo é adicionado. O que muda é que a
informação "esta pessoa votou naquela proposta" deixa de ser legível por qualquer um.

Vale nomear o dano concreto: a escolha de voto de uma pessoa identificada, dentro de um
Grupo de gente que se conhece, é dado de comportamento — e está hoje aberto a quem nem
cadastro tem. A Política afirma um círculo menor, o que significa que quem leu e aceitou
os termos aceitou algo diferente do que acontece.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): a feature encosta em
Rodada de votação, e é por isso que a US2 é P1 e não polimento. As bordas que precisam
continuar valendo: **voto revogável** (trocar de candidata substitui, só a última conta),
**apuração da mais votada**, e **desempate por sorteio**. Nenhuma delas muda — mas todas
podem quebrar por acidente, e por isso estão escritas como requisito.

**Papéis** (Princípio V): nenhum papel novo. Usa Visitante, Usuário e participante do
Grupo, que já existem.

## Success Criteria *(mandatory)*

- **SC-001**: 0 votos retornados a Visitante sem cadastro — verificado por **consulta
  direta à API**, não por inspeção de tela.
- **SC-002**: 0 votos de terceiros retornados a qualquer Usuário, participante do Grupo ou
  não.
- **SC-003**: 100% das pessoas continuam conseguindo ler o próprio voto.
- **SC-004**: 100% das trocas de voto continuam funcionando, incluindo a troca feita
  depois que a leitura foi fechada.
- **SC-005**: A apuração continua elegendo a mesma vencedora que elegia antes, para o
  mesmo conjunto de votos.
- **SC-006**: 0 afirmações desatualizadas sobre visibilidade de voto na Política de
  Privacidade e em `MAPA-DE-DADOS.md`.

## Assumptions

- **A regra escolhida é "só o próprio voto"**, e não "os participantes do Grupo" como a
  Política hoje promete. Três razões, nesta ordem: (a) **nenhuma tela mostra voto alheio**,
  então abrir para o Grupo entregaria acesso que nada consome — exposição sem finalidade,
  que é o oposto do Princípio II; (b) a apuração é `security definer` e não precisa da
  política; (c) a frase da Política não é decisão registrada, é descrição posterior de um
  `using (true)`.

  **Se você quiser o contrário** — voto visível aos participantes do Grupo, mantendo a
  frase atual da Política —, é a única linha desta spec que muda, e `/speckit-clarify`
  resolve. O trabalho é o mesmo; muda só o alcance da regra.

- **Nada é apagado**: os votos continuam gravados como estão. A feature muda leitura, não
  conteúdo.
- **Sem aviso a quem votou** de que o voto esteve exposto. Não há canal de notificação no
  app, e a spec não inventa um.
- **Sem tela nova**: a feature não adiciona "ver quem votou" para ninguém, nem contagem de
  votos por candidata. Se isso for desejado, é feature de produto separada — e aí a
  visibilidade vira decisão consciente, que é justamente o que faltou aqui.
- **Mesma classe da feature 018**: as duas fecham um `using (true)` que ninguém escolheu.
  São separadas porque tocam tabelas, telas e promessas diferentes, e porque a 018 não
  encosta em regra de domínio enquanto esta encosta em Rodada de votação.
- **A apuração não é reescrita.** `fechar_rodada_se_devido` continua como está. A feature
  não a toca — só depende de ela continuar `security definer`, o que vira requisito
  testado (FR-009).
