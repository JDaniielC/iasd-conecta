# Feature Specification: Meu Perfil — ver e corrigir os próprios dados

**Feature Branch**: `016-meu-perfil`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado #2 da varredura de 2026-08-09 — trabalho pendente sem spec.

## Contexto: o direito existe, a permissão existe, a tela não

A LGPD dá ao titular o direito de **acessar** (art. 18, II) e **corrigir** (art. 18, III) os
próprios dados. Hoje o app atende os dois por e-mail, manualmente, e **diz isso ao usuário**
na própria Política de Privacidade
(`lib/features/legal/presentation/privacy_policy_page.dart:173-179`):

> "Hoje isso é respondido manualmente — **ainda não existe uma tela própria de 'meu perfil'**
> para conferir sozinho."
>
> "Corrigir um dado errado: mesmo canal, por e-mail, **enquanto não existe tela de edição de
> perfil dentro do app**."

O mais notável: **a permissão de escrita já existe e ninguém a usa.** A política
`perfis_update_own` (`supabase/migrations/20260723191202_perfis_igrejas.sql:76-79`) autoriza o
Usuário a alterar o próprio Perfil, e nenhuma linha de código a consome. Em
`lib/features/profile/presentation/` só existem cadastro, entrar, virar Conta e excluir conta
— não há rota de perfil em `lib/app.dart`.

Não é uma promessa quebrada como a da feature 015 — a Política é honesta sobre a ausência. É
uma lacuna que o app assume ter, e que faz o titular depender de e-mail para ver o próprio
nome.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Ver o que o app sabe sobre mim (Priority: P1)

Um Usuário abre o app e chega a uma tela que mostra, num lugar só, tudo que está guardado
sobre ele: nome, Apelido se houver, Igreja de origem, telefone, gênero, idade, quando aceitou
os termos. Sem pedir por e-mail, sem esperar resposta.

**Why this priority**: é o direito de acesso, e é a metade que resolve sozinha o
constrangimento de ter que escrever para alguém para saber o próprio cadastro.

**Independent Test**: entrar no app com um Perfil e verificar que a tela mostra os mesmos
dados que estão gravados.

**Acceptance Scenarios**:

1. **Given** um Usuário com Perfil, **When** abre a tela de perfil, **Then** vê nome, Apelido
   (se houver), Igreja de origem, telefone, gênero, idade e a data do consentimento.
2. **Given** um campo opcional em branco, **When** o Usuário olha a tela, **Then** vê que está
   em branco, não um espaço vazio ambíguo.
3. **Given** um Visitante sem Perfil, **When** tenta alcançar a tela, **Then** é direcionado ao
   cadastro, como qualquer outra ação que exige Perfil.
4. **Given** a tela aberta, **When** o Usuário a lê, **Then** **não vê dado de mais ninguém**.

---

### User Story 2 - Corrigir um dado errado, sem pedir para ninguém (Priority: P2)

O Usuário percebe que digitou o nome errado no cadastro, ou mudou de igreja, ou quer tirar o
telefone. Ele corrige na própria tela e pronto.

**Why this priority**: é o direito de correção. Depende da US1 existir, mas é o que tira o
e-mail do caminho.

**Acceptance Scenarios**:

1. **Given** o Usuário na tela de perfil, **When** corrige o nome e salva, **Then** o novo nome
   passa a aparecer onde o nome dele aparece.
2. **Given** o Usuário menor de idade, **When** edita, **Then** o Apelido continua obrigatório
   — a regra que protege o menor não afrouxa aqui.
3. **Given** um nome que a moderação recusa, **When** o Usuário tenta salvar, **Then** é
   recusado com a mesma regra e a mesma mensagem do cadastro.
4. **Given** o Usuário limpando o telefone, **When** salva, **Then** o campo fica vazio — é
   opcional, e continuar opcional depois do cadastro faz parte da promessa.
5. **Given** o Usuário escolhendo uma Igreja de origem pela primeira vez, **When** salva,
   **Then** o consentimento destacado de Igreja é exigido, como no cadastro.
6. **Given** uma falha de rede ao salvar, **When** acontece, **Then** o Usuário é avisado e
   **nenhum dado é alterado pela metade**.

---

### User Story 3 - A Política deixa de descrever uma ausência (Priority: P3)

Quem lê a Política de Privacidade encontra o caminho dentro do app, não uma desculpa.

**Why this priority**: é o fecho. Enquanto a tela existir e a Política disser que não existe,
o app está descrevendo errado a si mesmo — que a constituição trata como violação.

**Acceptance Scenarios**:

1. **Given** a Política de Privacidade, **When** o Usuário lê a seção de direitos, **Then**
   ela indica a tela dentro do app, e não mais só o e-mail.
2. **Given** as duas frases que hoje dizem "ainda não existe", **When** a feature entra,
   **Then** elas não existem mais.

---

### Edge Cases

- **Idade alterada para faixa de menor**: se a feature 015 estiver no ar, baixar a idade para
  a faixa de criança precisa exigir a autorização do responsável. Se não estiver, a regra do
  Apelido obrigatório continua valendo sozinha.
- **Perfil sem Conta**: quem tem só Perfil, sem credencial, edita normalmente — a sessão
  anônima já o identifica.
- **Nome alterado enquanto aparece em outro lugar**: o nome exibido em Grupos e Ações vem do
  Perfil, então muda junto. Não há cópia a sincronizar.
- **Menor de idade editando o Apelido**: pode, desde que não fique vazio.
- **Perfil anonimizado** (quem excluiu a conta): não alcança a tela — não há sessão.
- **Idade e gênero**: são editáveis? Idade muda de verdade uma vez por ano; gênero é usado
  para validar Dupla Missionária. Editar não é óbvio.

## Requirements *(mandatory)*

### Ver (US1)

- **FR-001**: O Usuário com Perfil DEVE ter acesso a uma tela que exibe todos os dados
  pessoais guardados sobre ele.
- **FR-002**: A tela DEVE exibir: nome, Apelido, Igreja de origem, telefone, gênero, idade e a
  data do consentimento LGPD.
- **FR-003**: Campo opcional em branco DEVE ser exibido como explicitamente vazio.
- **FR-004**: A tela NÃO DEVE exibir dado de nenhuma outra pessoa.
- **FR-005**: Visitante sem Perfil DEVE ser direcionado ao cadastro ao tentar alcançá-la.
- **FR-006**: A tela DEVE ser alcançável a partir da navegação do app, sem link decorado.

### Corrigir (US2)

- **FR-007**: O Usuário DEVE poder alterar nome, Apelido, Igreja de origem e telefone.
- **FR-008**: A moderação de nome DEVE valer na edição com a **mesma regra e a mesma mensagem**
  do cadastro.
- **FR-009**: A exigência de Apelido para menor de idade DEVE valer na edição.
- **FR-010**: Campos opcionais DEVEM poder voltar a ficar vazios.
- **FR-011**: Escolher Igreja de origem na edição DEVE exigir o consentimento destacado, como
  no cadastro.
- **FR-012**: Uma falha ao salvar NÃO DEVE deixar o Perfil alterado pela metade.
- **FR-013**: O Usuário NÃO DEVE conseguir alterar Perfil de outra pessoa — garantido no
  banco, não só na tela.

### Transparência (US3)

- **FR-014**: A Política de Privacidade DEVE deixar de dizer que a tela não existe, e passar a
  indicá-la.

## Key Entities

Nenhuma entidade nova. A tela lê e escreve o **Perfil** que já existe, usando a permissão
`perfis_update_own` que já está no banco e nunca foi consumida.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): **nenhum dado novo é coletado.** A feature dá ao titular
acesso e correção dos dados que já são dele — é exatamente o que os artigos 18, II e III da
LGPD pedem. A exposição **não aumenta**: cada pessoa vê só o próprio Perfil, e a regra de
exibir menor de idade por Apelido para terceiros não é tocada.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum. Alterar o nome muda o
que aparece nas listas de participantes e confirmados, porque o nome sempre veio do Perfil —
não há cópia guardada em outro lugar para divergir.

**Papéis** (Princípio V): nenhum papel novo.

## Success Criteria *(mandatory)*

- **SC-001**: 100% dos campos pessoais guardados aparecem na tela — nenhum dado sobre o
  Usuário fica invisível a ele.
- **SC-002**: Um Usuário corrige o próprio nome em menos de 1 minuto, sem sair do app.
- **SC-003**: 0 pedidos de acesso ou correção que ainda precisem de e-mail para dados que a
  tela cobre.
- **SC-004**: 0 tentativas bem-sucedidas de alterar Perfil alheio, inclusive por chamada
  direta que não passe pela tela.
- **SC-005**: 0 salvamentos parciais: depois de uma falha, o Perfil está exatamente como
  antes.
- **SC-006**: 0 afirmações falsas na Política — as duas frases que dizem "ainda não existe"
  deixam de existir.

## Assumptions

- **Idade e gênero fora do escopo de edição**: gênero valida composição de Dupla Missionária
  e idade decide a exigência de Apelido; alterá-los tem consequência em regra de domínio que
  esta feature não quer carregar. Continuam sendo corrigidos por e-mail. Se isso incomodar,
  vira feature própria.
- **Sem histórico de alterações**: o app não guarda o que o dado era antes. Corrigir
  sobrescreve.
- **Sem exportar os dados num arquivo**: portabilidade (LGPD art. 18, V) é outra feature,
  já identificada na varredura.
- **Nada muda no banco**: a permissão `perfis_update_own` já existe
  (`20260723191202_perfis_igrejas.sql:76-79`). Esta feature é cliente puro, o que a torna
  pequena — e explica por que a lacuna durou tanto sem ninguém perceber o custo.
- **Sem confirmação por segunda etapa**: corrigir o próprio nome não é destrutivo e não pede
  confirmação, diferente de excluir a conta.
- **Interação com a feature 015**: se a autorização de responsável existir, baixar a idade
  para a faixa de criança precisa exigi-la. Como idade não é editável aqui (ver primeira
  assumption), a interação não acontece nesta versão.
