# Feature Specification: Visibilidade das declarações de Líder/Diretor

**Feature Branch**: `018-visibilidade-de-liderancas`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado #4 da varredura de 2026-08-09 — trabalho pendente sem spec.

## Contexto: a tela esconde, o banco não

A tabela `liderancas` é legível por **qualquer pessoa, sem cadastro**
(`supabase/migrations/20260724100000_leadership.sql:73-76`):

```sql
create policy liderancas_select_public
  on public.liderancas for select
  to anon, authenticated
  using (true);
```

`using (true)` significa: sem filtro. Qualquer Visitante que consulte a API diretamente lê a
tabela inteira — incluindo **declarações pendentes** e **declarações rejeitadas**.

A interface esconde: a tela do Grupo só renderiza quem tem `confirmado_em` preenchido. Mas
esconder na tela não é proteger. Quem sabe montar uma requisição vê que Fulano se autodeclarou
Líder do Ministério Jovem e **foi rejeitado pelo Administrador do distrito** — um fato que o
app nunca quis tornar público, e que diz respeito a uma pessoa real numa comunidade pequena.

O glossário é explícito sobre o que deveria ser público: *"Identificação do Líder é pública na
página do Ministério"* (`CONTEXT.md`, entrada Ministério). **Identificação do Líder** — não a
lista de quem tentou e não conseguiu.

`MAPA-DE-DADOS.md:68,70-73` registra o fato como conhecido. Nenhum ticket, nenhuma spec.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Declaração rejeitada ou pendente para de ser pública (Priority: P1)

Alguém se autodeclara Líder de um Ministério e o Administrador do distrito não confirma. Esse
fato deixa de ser legível por qualquer pessoa da internet. Continua visível para quem tem
motivo: a própria pessoa e o Administrador.

**Why this priority**: é a feature. É o único item aqui que expõe dado de pessoa real sem
ninguém ter decidido isso.

**Independent Test**: consultar a API como Visitante sem cadastro e verificar que a resposta
traz apenas declarações confirmadas.

**Acceptance Scenarios**:

1. **Given** uma declaração **pendente**, **When** um Visitante consulta as declarações,
   **Then** não a recebe.
2. **Given** uma declaração **rejeitada**, **When** um Visitante consulta, **Then** não a
   recebe.
3. **Given** uma declaração **confirmada**, **When** um Visitante consulta, **Then** a recebe —
   é a identificação pública que o glossário promete.
4. **Given** um Usuário comum cadastrado, **When** consulta, **Then** vê o mesmo que o
   Visitante: só as confirmadas.
5. **Given** a pessoa que se declarou, **When** consulta, **Then** vê a **própria** declaração,
   em qualquer estado — ela precisa saber se foi confirmada, rejeitada ou se ainda espera.
6. **Given** o Administrador do distrito, **When** consulta, **Then** vê todas — é ele quem
   decide sobre elas.

---

### User Story 2 - Nada quebra no que já funciona (Priority: P2)

A página do Ministério continua mostrando quem é o Líder. A tela de declarações pendentes do
Administrador continua listando o que ele precisa decidir. A pessoa continua vendo o estado da
própria declaração.

**Why this priority**: apertar uma permissão é fácil; apertar sem quebrar o que dependia dela
é o trabalho. As três telas leem a mesma tabela.

**Acceptance Scenarios**:

1. **Given** um Ministério com Líder confirmado, **When** um Visitante abre a página, **Then**
   vê a identificação do Líder, como hoje.
2. **Given** o Administrador do distrito, **When** abre as declarações pendentes, **Then** vê
   todas as pendentes, como hoje.
3. **Given** um Usuário que se declarou, **When** abre o Grupo, **Then** vê o estado da própria
   declaração, como hoje.
4. **Given** a expiração anual do título em janeiro, **When** acontece, **Then** funciona como
   hoje — a regra de expiração não é tocada.

---

### Edge Cases

- **Declaração confirmada e depois expirada**: continua pública ou não? Ela foi pública
  legitimamente enquanto valia.
- **Declaração confirmada de um Grupo arquivado** (feature 014): a 014 já exige que ela suma
  da exibição. As duas features tocam a mesma consulta.
- **A pessoa que se declarou excluiu a conta**: o Perfil vira "Membro removido" e a declaração
  continua apontando para ele, como histórico da feature 009.
- **Vários anos de declarações da mesma pessoa no mesmo Ministério**: as antigas confirmadas
  continuam públicas.
- **Contagem**: uma resposta vazia para um Visitante não pode revelar, por diferença de
  tamanho, que existem declarações escondidas.

## Requirements *(mandatory)*

### Fechar a exposição (US1)

- **FR-001**: Visitante sem cadastro DEVE receber apenas declarações **confirmadas**.
- **FR-002**: Usuário comum cadastrado DEVE receber apenas declarações confirmadas, mais a
  **própria**, em qualquer estado.
- **FR-003**: O Administrador do distrito DEVE receber todas as declarações, em qualquer
  estado.
- **FR-004**: A restrição DEVE ser garantida **no banco**, não na tela — é justamente a
  diferença entre esconder e proteger que motiva esta feature.
- **FR-005**: Declaração **pendente** e declaração **rejeitada** NÃO DEVEM ser legíveis por
  quem não é a própria pessoa nem o Administrador do distrito.

### Não quebrar o que existe (US2)

- **FR-006**: A identificação pública do Líder/Diretor na página do Ministério DEVE continuar
  visível a Visitante, como o glossário promete.
- **FR-007**: A tela de declarações pendentes do Administrador do distrito DEVE continuar
  funcionando.
- **FR-008**: A pessoa que se declarou DEVE continuar vendo o estado da própria declaração.
- **FR-009**: A regra de expiração anual do título NÃO DEVE ser alterada.

### Documentação

- **FR-010**: `MAPA-DE-DADOS.md` DEVE deixar de registrar a leitura irrestrita como fato
  vigente, e passar a descrever a regra que existe.

## Key Entities

Nenhuma entidade nova. **Declaração de Líder/Diretor** já existe, com os estados que já existem
— pendente, confirmada, rejeitada. O que muda é **quem consegue lê-la**.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II — e esta feature existe por causa dele): **a feature só reduz
exposição.** Nenhum dado novo é coletado. O que muda é que a informação "esta pessoa tentou ser
Líder e não foi confirmada" deixa de ser legível por qualquer um.

Vale nomear o dano concreto: numa comunidade de 15+ igrejas onde as pessoas se conhecem, saber
quem foi rejeitado para um papel de liderança é constrangimento real, e nunca foi decisão de
ninguém torná-lo público — foi consequência de uma política escrita com `using (true)`.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum. Nem fila de espera, nem
apuração, nem descarte, nem revogação, nem Dupla Missionária.

**Papéis** (Princípio V): nenhum papel novo. Usa Visitante, Usuário, a própria pessoa e
Administrador do distrito, que já existem.

## Success Criteria *(mandatory)*

- **SC-001**: 0 declarações pendentes ou rejeitadas retornadas a Visitante ou a Usuário que não
  seja o autor — verificado por **consulta direta à API**, não por inspeção de tela.
- **SC-002**: 100% das declarações confirmadas continuam retornadas a Visitante.
- **SC-003**: 0 regressões nas três telas que leem a tabela: página do Ministério, pendências
  do Administrador, e o estado da própria declaração.
- **SC-004**: 0 afirmações desatualizadas em `MAPA-DE-DADOS.md` sobre a visibilidade.

## Assumptions

- **Declaração confirmada é pública, mesmo depois de expirar.** Ela foi pública legitimamente
  enquanto valia, e esconder o histórico de quem foi Líder em 2026 não foi pedido. Se isso
  incomodar, é decisão de produto separada.
- **A restrição vale para leitura, não para escrita.** As regras de quem declara e de quem
  confirma não mudam — são da feature 006.
- **Sem correção retroativa**: nada é apagado. As declarações rejeitadas continuam gravadas, só
  deixam de ser legíveis por quem não tem motivo.
- **Sem aviso a quem foi rejeitado** de que o fato esteve exposto. Não há canal de
  notificação, e a spec não inventa um.
- **Interação com a feature 014**: a 014 exige que Ministério arquivado deixe de exibir o
  Líder. As duas mexem na mesma consulta — quem entrar depois lê o arquivo já modificado.
- **Esta feature não foi encontrada por auditoria de segurança**: `SECURITY-AUDIT.md` está
  limpo, com os três achados anteriores corrigidos. Este passou porque a tela esconde — e é
  exatamente por isso que ele merece spec.
