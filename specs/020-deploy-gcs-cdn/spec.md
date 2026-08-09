# Feature Specification: Deploy do app web em Cloud Storage com CDN

**Feature Branch**: `020-deploy-gcs-cdn`

**Created**: 2026-08-09

**Status**: Draft

**Input**: Ticket `.tickets/IASD-CI-GCS-UPLOAD.md`, apontado pelo responsável pelo app, mais o
achado #6 da varredura de 2026-08-09.

## Contexto

O ticket `IASD-CI-GCS-UPLOAD` está aberto desde que foi escrito — os três itens de aceite
continuam desmarcados (`.tickets/IASD-CI-GCS-UPLOAD.md:16-19`), e o deploy atual continua o
que ele queria substituir: `.github/workflows/deploy-web.yml:47-60` compila o Flutter Web e
**empurra o resultado para uma branch `dist-web`**, com `git push -f`. Uma busca por `gsutil`
ou `gcloud` em `.github/` retorna zero.

**Arquitetura confirmada pelo responsável em 2026-08-09**: o front (Flutter Web compilado) vai
para Cloud Storage com Cloud CDN na frente; o backend continua sendo o **Supabase Cloud
gerenciado**. São camadas diferentes — o ticket fala em "sair do EC2" e isso se refere ao
front, não ao banco. A camada de banco é a feature 019.

Publicar site por branch de git funciona, mas tem três problemas que o ticket já identificou:
não há CDN na frente, o histórico da branch cresce a cada deploy, e não existe invalidação de
cache — o que significa que uma correção publicada pode continuar não aparecendo para quem já
visitou.

## User Scenarios & Testing *(mandatory)*

> Ninguém no app vê nada mudar. O beneficiário é quem opera o deploy e quem carrega a página.

### User Story 1 - O build publicado chega ao Cloud Storage (Priority: P1)

Um commit entra na branch principal, o CI compila o Flutter Web e publica o resultado no bucket
de produção. Ninguém precisa rodar nada à mão.

**Why this priority**: é a feature. Sem publicar no destino certo, nada mais importa.

**Independent Test**: disparar o fluxo e verificar que os arquivos do build chegaram ao bucket,
com o mesmo conteúdo que o build local produz.

**Acceptance Scenarios**:

1. **Given** um commit na branch principal, **When** o fluxo roda, **Then** o conteúdo de
   `build/web` é publicado no bucket de produção.
2. **Given** um build que **falha**, **When** o fluxo roda, **Then** **nada** é publicado — um
   build quebrado não pode substituir um site que funciona.
3. **Given** o fluxo concluído, **When** alguém abre o endereço público, **Then** vê a versão
   recém-publicada.
4. **Given** os segredos de acesso à nuvem ausentes ou inválidos, **When** o fluxo roda,
   **Then** falha com mensagem que diz **o que** falta, sem vazar o valor de nenhum segredo.

---

### User Story 2 - A correção publicada aparece de verdade (Priority: P1)

Depois de publicar, o cache da CDN é invalidado, e quem já tinha visitado o site passa a
receber a versão nova em vez da antiga guardada.

**Why this priority**: **é P1 junto com a US1, não depois.** Publicar sem invalidar é pior do
que não publicar: cria a convicção de que a correção foi ao ar quando ela não chegou a
ninguém que já usou o app. O ticket registra TTL padrão de 3600s — uma hora de gente vendo
código velho, sem ninguém desconfiar.

**Independent Test**: publicar uma alteração visível, recarregar como um visitante que já
tinha o site em cache, e verificar que a alteração aparece.

**Acceptance Scenarios**:

1. **Given** uma publicação concluída, **When** o fluxo termina, **Then** o cache da CDN foi
   invalidado.
2. **Given** um visitante que já tinha a versão antiga, **When** recarrega depois da
   invalidação propagar, **Then** recebe a versão nova.
3. **Given** a invalidação **falhando**, **When** acontece, **Then** o fluxo é marcado como
   falho — publicar sem invalidar não pode ser reportado como sucesso.
4. **Given** o tempo de propagação, **When** alguém acompanha um deploy, **Then** encontra
   escrito quanto tempo esperar antes de concluir que algo deu errado.

---

### User Story 3 - Quem for configurar sabe exatamente o que precisa (Priority: P2)

O responsável pelo app consegue criar as credenciais e permissões necessárias seguindo um
documento, sem adivinhar quais permissões dar.

**Why this priority**: os segredos e a conta de serviço são configurados por uma pessoa, na
interface do provedor. Sem documentação, ou ela dá permissão de menos e o deploy falha, ou dá
permissão demais.

**Acceptance Scenarios**:

1. **Given** o repositório, **When** o responsável procura como configurar o deploy, **Then**
   encontra a lista de segredos necessários, cada um com o que é.
2. **Given** essa documentação, **When** ele cria a conta de serviço, **Then** encontra as
   permissões mínimas necessárias, e só elas.
3. **Given** a documentação, **When** alguém a lê, **Then** **nenhum valor de segredo** está
   escrito nela.

---

### Edge Cases

- **Arquivo removido entre um build e outro**: publicar por cópia não apaga o que sumiu. Um
  arquivo antigo pode ficar no bucket para sempre.
- **Publicação parcial**: se falhar no meio, o site fica com metade dos arquivos novos e
  metade dos velhos — pior do que qualquer um dos dois estados.
- **`index.html` e os demais arquivos com cache igual**: o `index.html` precisa ser sempre
  fresco; os arquivos com hash no nome podem ser cacheados longamente. Tratar todos igual
  causa o problema que a invalidação tenta resolver.
- **Deploy concorrente**: dois commits em sequência rápida podem publicar fora de ordem.
- **Rollback**: como voltar à versão anterior se a nova estiver quebrada?
- **A branch `dist-web` continua existindo**: o ticket diz que pode ficar como backup. Duas
  fontes de verdade sobre "o que está no ar" confundem.
- **`.env` de produção montado no CI**: hoje `deploy-web.yml:34-42` escreve as duas chaves
  públicas num arquivo durante o build. Elas terminam **dentro do bundle publicado**, que é
  público — é o desenho pretendido, mas precisa continuar sendo só as chaves públicas.

## Requirements *(mandatory)*

### Publicar (US1)

- **FR-001**: O fluxo de deploy DEVE publicar o conteúdo de `build/web` no bucket de produção.
- **FR-002**: Um build que falha NÃO DEVE publicar nada.
- **FR-003**: O fluxo DEVE autenticar na nuvem usando credencial guardada como segredo do
  repositório, nunca escrita no código.
- **FR-004**: Falha de autenticação DEVE dizer o que falta, **sem** revelar valor de segredo.
- **FR-005**: O fluxo NÃO DEVE deixar o site em estado parcial — ou a versão nova está
  completa, ou a anterior continua servindo.
- **FR-006**: Arquivos que deixaram de existir no build NÃO DEVEM continuar sendo servidos.

### Invalidar (US2)

- **FR-007**: Após publicar, o fluxo DEVE invalidar o cache da CDN.
- **FR-008**: Falha na invalidação DEVE marcar o fluxo como falho.
- **FR-009**: A documentação DEVE registrar o tempo esperado de propagação.
- **FR-010**: O `index.html` NÃO DEVE ser cacheado com a mesma duração dos arquivos versionados
  por hash.

### Configurar (US3)

- **FR-011**: O repositório DEVE documentar cada segredo necessário e o que ele é.
- **FR-012**: O repositório DEVE documentar as permissões mínimas da conta de serviço.
- **FR-013**: Nenhum valor de segredo DEVE aparecer em documento, log ou histórico do
  repositório.
- **FR-014**: A documentação DEVE dizer o que fazer com a branch `dist-web` — mantida como
  backup ou descontinuada — para não restarem duas fontes de verdade.

### Fechar o ticket

- **FR-015**: `.tickets/IASD-CI-GCS-UPLOAD.md` DEVE ser marcado como feito, ou apontar para
  esta feature.
- **FR-016**: `README.md` DEVE descrever o deploy que passou a existir. Ele hoje descreve o
  anterior, e já está desatualizado em outros pontos.

## Declarações exigidas pela Constituição

**Dado pessoal** (Princípio II): **nenhum dado pessoal é tocado.** O que é publicado é o app
compilado — código, não dado de gente. As duas chaves que o CI injeta no build já são públicas
por natureza (vão dentro do bundle que qualquer visitante baixa), e o requisito FR-013 existe
para garantir que **só** elas continuem indo.

O banco, onde o dado pessoal mora, não é tocado por esta feature — é a 019.

**Comportamento de borda de Ação/Grupo/Rodada** (Princípio IV): nenhum. Nenhuma linha de código
do app muda.

**Papéis** (Princípio V): nenhum papel novo no app. A conta de serviço é credencial de máquina
para o CI, não papel de domínio, e não entra em `CONTEXT.md`.

## Success Criteria *(mandatory)*

- **SC-001**: 100% dos commits na branch principal com build bem-sucedido resultam em site
  publicado, sem intervenção manual.
- **SC-002**: 0 publicações a partir de build que falhou.
- **SC-003**: Uma alteração visível aparece para um visitante que já tinha o site em cache,
  dentro do tempo de propagação documentado.
- **SC-004**: 0 valores de segredo em documento, log ou histórico.
- **SC-005**: 0 arquivos servidos que não existem mais no build atual.
- **SC-006**: Alguém que nunca configurou este deploy consegue fazê-lo seguindo a documentação,
  sem perguntar nada.
- **SC-007**: 0 itens de aceite em aberto em `.tickets/IASD-CI-GCS-UPLOAD.md`.

## Assumptions

- **Front no GCS+CDN, banco no Supabase Cloud** — confirmado pelo responsável em 2026-08-09. O
  ticket fala em "sair do EC2" referindo-se ao front. A camada de banco é a feature 019.
- **Provedor e nomes de recurso vêm do ticket**: projeto, bucket e mapa de URL estão escritos
  em `.tickets/IASD-CI-GCS-UPLOAD.md:9-13`. Esta spec não os repete — o ticket é a fonte, e
  duplicá-los criaria duas verdades.
- **Quem cria as credenciais é o responsável pelo app**, na interface do provedor. O CI só as
  consome. Parte desta feature não pode ser feita por quem só tem o repositório, e isso está
  dito em vez de fingir o contrário.
- **Sem rollback automatizado** nesta versão. Voltar à versão anterior é republicar um commit
  anterior. Rollback de um comando é outra feature.
- **Sem ambiente de homologação**: publica direto em produção, como hoje.
- **Sem verificação de disponibilidade após o deploy**: o fluxo não confere se o site
  responde depois de publicar. Fica como lacuna conhecida.
- **A branch `dist-web` continua existindo** até alguém decidir o contrário — FR-014 obriga a
  decisão a ser escrita, não tomada por esta spec.
