# Feature Specification: Produção — confirmar região e resolver backup

**Feature Branch**: `019-producao-regiao-e-backup`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Achado #5 da varredura de 2026-08-09 — trabalho pendente sem spec.

## Contexto: produção existe, e duas afirmações sobre ela não foram verificadas

O app **está em produção**. `.env.prod` aponta para um projeto Supabase Cloud real, e
`.github/workflows/deploy-web.yml:34-42` já injeta os segredos de produção no build. Mas duas
coisas continuam como estavam antes de existir produção:

**1. A Política afirma que não há transferência internacional.** Isso depende de o projeto
Supabase estar mesmo em território brasileiro. O código registra a intenção
(`lib/features/legal/legal_metadata.dart:24-26`):

> "Região de hospedagem do Supabase em produção — escolhida para manter o dado em território
> brasileiro e evitar declarar transferência internacional. **Ainda não provisionada.** A
> infra que criar o projeto Supabase de produção DEVE usar esta região."

O comentário diz "ainda não provisionada" — mas o projeto **já existe**. Ou o comentário está
velho e a região está certa, ou o projeto foi criado fora da região e a Política afirma algo
falso. **Ninguém verificou**, e o repositório não tem como responder.

**2. Backup não foi decidido.** `.achados/20260724-devops-iasd.md:184-187` registra a decisão
D-3 como aberta: *"backup Supabase volta à mesa — Supabase Cloud free tier não tem backup
automático nem PITR"*. Há dado pessoal de uma comunidade real num banco sem estratégia de
recuperação declarada.

## User Scenarios & Testing *(mandatory)*

> Esta feature é de infraestrutura e conformidade. O beneficiário é a comunidade cujos dados
> estão lá, mas ninguém vai ver nada mudar na tela. Essa ausência é o resultado esperado.

### User Story 1 - A afirmação sobre transferência internacional passa a ser verificada (Priority: P1)

Alguém consegue responder, com evidência, em que região o projeto Supabase de produção roda —
e a Política de Privacidade passa a dizer o que é verdade, não o que se pretendia.

**Why this priority**: é a única das duas onde o app **afirma** algo. Backup é risco; região
não confirmada é possível afirmação falsa a titulares.

**Independent Test**: consultar a região do projeto de produção e comparar com o que a Política
e `legal_metadata.dart` afirmam.

**Acceptance Scenarios**:

1. **Given** o projeto Supabase de produção, **When** alguém verifica a região, **Then** obtém
   a resposta com evidência — não por suposição.
2. **Given** a região confirmada como brasileira, **When** os documentos são conferidos,
   **Then** o comentário deixa de dizer "ainda não provisionada" e passa a registrar a
   verificação, com data.
3. **Given** a região **fora** do Brasil, **When** isso for constatado, **Then** a Política de
   Privacidade DEVE ser corrigida para declarar a transferência internacional, **antes** de
   qualquer outra providência.
4. **Given** a decisão registrada, **When** alguém provisionar outro ambiente no futuro,
   **Then** encontra a região exigida escrita em lugar que ele vai ler.

---

### User Story 2 - Existe uma resposta escrita para "e se o banco morrer?" (Priority: P2)

O responsável pelo app sabe, sem precisar pesquisar, o que acontece se o banco de produção for
perdido: se há backup, de que tipo, com que frequência, quanto se perde no pior caso, e como se
restaura.

**Why this priority**: hoje a resposta é "não sei". Vale muito e não afirma nada falso ao
usuário — por isso vem depois da US1.

**Acceptance Scenarios**:

1. **Given** a decisão D-3 em aberto, **When** ela é fechada, **Then** existe uma decisão
   escrita: há backup, qual mecanismo, com que frequência, e quanto de dado se perde no pior
   caso.
2. **Given** a decisão de **não** ter backup automático, **When** for essa a escolha, **Then**
   ela é registrada como risco aceito, com quem aceitou e quando — e não fica implícita.
3. **Given** um backup existindo, **When** alguém precisa restaurar, **Then** encontra o
   procedimento escrito, e ele **já foi testado ao menos uma vez**.
4. **Given** a Política de Privacidade, **When** ela fala de retenção e segurança, **Then** não
   contradiz o que foi decidido.

---

### Edge Cases

- **Backup contém dado pessoal**: um backup é uma cópia de dado pessoal, e a Política precisa
  dizer que ela existe e por quanto tempo.
- **Exclusão de conta versus backup**: a feature 009 anonimiza o Perfil no banco vivo. Um
  backup anterior ainda contém o nome. Prazo de retenção do backup passa a ser prazo de
  retenção do dado apagado.
- **Backup fora do Brasil**: se o mecanismo escolhido guardar a cópia em outra região, a
  transferência internacional volta pela porta dos fundos.
- **Restauração nunca testada**: backup não testado é hipótese, não garantia.
- **Migrar de região**: se a região estiver errada, corrigir significa mover um banco em
  produção com gente usando.

## Requirements *(mandatory)*

### Região (US1)

- **FR-001**: A região do projeto Supabase de produção DEVE ser verificada com evidência.
- **FR-002**: O resultado DEVE ser registrado no repositório, com data, em lugar que quem
  provisiona ambiente vai ler.
- **FR-003**: `lib/features/legal/legal_metadata.dart` DEVE deixar de dizer "ainda não
  provisionada".
- **FR-004**: Se a região **não** for brasileira, a Política de Privacidade DEVE declarar a
  transferência internacional, e essa correção tem precedência sobre qualquer plano de
  migração.
- **FR-005**: A exigência de região DEVE ficar escrita como requisito para **futuros**
  ambientes, não só para o atual.

### Backup (US2)

- **FR-006**: A decisão sobre backup DEVE ser fechada por escrito: existe ou não, qual
  mecanismo, com que frequência, e quanto de dado se perde no pior caso.
- **FR-007**: Se a decisão for não ter backup automático, ela DEVE ser registrada como **risco
  aceito**, com quem aceitou e quando.
- **FR-008**: Existindo backup, o procedimento de restauração DEVE estar escrito **e ter sido
  executado ao menos uma vez**.
- **FR-009**: Existindo backup, a Política de Privacidade DEVE dizer que ele existe, por
  quanto tempo é guardado, e o que isso significa para quem pediu exclusão de conta.
- **FR-010**: A região onde o backup é guardado DEVE ser verificada com o mesmo rigor de
  FR-001.

### Documentação

- **FR-011**: `MAPA-DE-DADOS.md` DEVE registrar o backup como destino de dado pessoal, se ele
  existir.
- **FR-012**: `REVISAO-JURIDICA.md` DEVE ter o item de região marcado como resolvido, com a
  evidência.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): **nenhum dado novo é coletado**, mas a feature trata de onde
o dado **já existente** mora e para onde ele é copiado. As duas perguntas são de dado pessoal:
região é base para declarar transferência internacional, e backup é uma cópia integral do banco
— inclusive dos dados de quem pediu exclusão, se a cópia for anterior ao pedido.

FR-009 existe por causa disso: prometer exclusão e manter um backup indefinido com o nome da
pessoa é a mesma classe de divergência entre promessa e execução que a constituição proíbe.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum. Nenhuma regra de
domínio é tocada.

**Papéis** (Princípio V): nenhum papel novo. Nenhuma mudança no app.

## Success Criteria *(mandatory)*

- **SC-001**: A região do projeto de produção está registrada no repositório com evidência e
  data — 0 afirmações baseadas em suposição.
- **SC-002**: 0 ocorrências de "ainda não provisionada" nos documentos, quando o ambiente está
  provisionado.
- **SC-003**: A pergunta "quanto de dado se perde no pior caso?" tem resposta escrita, em
  unidade de tempo.
- **SC-004**: Se há backup, a restauração foi executada ao menos uma vez, com o resultado
  anotado.
- **SC-005**: 0 contradições entre o que a Política diz sobre retenção e segurança e o que foi
  decidido.
- **SC-006**: 0 itens de região e backup em aberto nos documentos de achados.

## Assumptions

- **Front no GCS+CDN, banco no Supabase Cloud**: decisão confirmada pelo responsável em
  2026-08-09. São camadas diferentes, e esta feature trata só da camada de banco. O front é a
  feature 020.
- **Nada muda no app**: nenhuma tela, nenhum código Dart, nenhuma migration. É infraestrutura e
  documento. Se a região estiver errada e exigir migração, isso é trabalho separado e maior.
- **Verificação exige acesso ao painel do fornecedor**, que o repositório não tem. Parte desta
  feature só pode ser feita por quem tem esse acesso — e isso está dito, em vez de fingir que
  dá para automatizar.
- **A decisão de backup é do responsável pelo app**, não técnica. As opções têm custo, e
  escolher é dele. Esta feature garante que a escolha seja **feita e registrada**, não que seja
  uma específica.
- **Sem retenção de log de acesso**: o Marco Civil art. 15 continua em aberto e depende de
  parecer jurídico (`REVISAO-JURIDICA.md:210-220`). Fora do escopo.
