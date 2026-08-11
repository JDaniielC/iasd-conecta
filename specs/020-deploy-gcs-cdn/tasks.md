# Tasks: Deploy do app web em Cloud Storage com CDN

**Input**: `specs/020-deploy-gcs-cdn/` — [spec.md](./spec.md), [plan.md](./plan.md),
[research.md](./research.md), [contracts/deploy-web.yml](./contracts/deploy-web.yml),
[quickstart.md](./quickstart.md)

## Formato: `[ID] [P?] [H?] [Story] Descrição`

- **[P]** — pode rodar em paralelo (arquivo diferente, sem dependência)
- **[H]** — **tarefa humana**: só o responsável pelo app faz, na interface do provedor ou do
  GitHub. Não é opcional e não é "pré-requisito externo" — é tarefa desta feature, e a feature
  não fecha sem ela
- **[Story]** — a qual história de usuário a tarefa pertence

**Sem tarefas de teste automatizado**: esta feature não cria código Dart, e não há teste
automatizado a escrever. A verificação é o ensaio em bucket descartável (T026) e o
[quickstart.md](./quickstart.md) (T032). Nenhuma linha de `lib/`, `test/` ou `supabase/` é
tocada.

**Idioma** (Princípio I aplicado a CI): nome de job, step, input e variável de ambiente do
workflow em **inglês**; comentário e mensagem ao operador (`::error::`, `$GITHUB_STEP_SUMMARY`)
em **português**. Os dois steps hoje em português (`deploy-web.yml:34`, `:47`) são traduzidos
nesta virada.

**Nomes de recurso**: `<PROJETO>`, `<BUCKET>` e `<URL_MAP>` vêm de
`.tickets/IASD-CI-GCS-UPLOAD.md:9-13`. Não duplicar em spec, plan, research ou quickstart.

---

## Phase 1: Setup — configuração na nuvem e no GitHub

**Propósito**: sem isto o workflow não tem onde publicar nem com o que autenticar. Todas as
tarefas desta fase são humanas.

- [ ] T001 [H] [US3] Criar a conta de serviço `github-actions-deploy-web` no projeto
      `<PROJETO>` e conceder **exatamente** dois papéis: `roles/storage.objectAdmin`
      **no bucket `<BUCKET>`** (não no projeto) e `roles/compute.loadBalancerAdmin` no projeto.
      **Não** usar `roles/storage.admin` nem `roles/compute.networkAdmin` — os dois que o ticket
      pede são maiores que o necessário. Passo a passo em [quickstart.md](./quickstart.md) §1.
      — **FR-012**
- [ ] T002 [H] [P] [US1] Criar a chave JSON da conta de serviço, cadastrar
      `GCP_PROJECT_ID` e `GCP_SERVICE_ACCOUNT_JSON` em Settings → Secrets and variables →
      Actions, e **apagar o arquivo baixado** em seguida. Confirmar que `SUPABASE_URL` e
      `SUPABASE_PUBLISHABLE_KEY` continuam cadastrados. Nenhum valor vai para arquivo, commit ou
      mensagem. [quickstart.md](./quickstart.md) §3. — **FR-003, FR-013**
- [ ] T003 [H] [P] [US2] Conferir no console o **modo de cache** do backend bucket de
      `<BUCKET>`. Se estiver em `FORCE_CACHE_ALL`, mudar para `CACHE_ALL_STATIC` ou
      `USE_ORIGIN_HEADERS`. ⚠️ Em `FORCE_CACHE_ALL` a CDN ignora o `Cache-Control` do objeto e o
      `no-cache` do `index.html` deixa de existir — o FR-010 fica violado com o CI perfeito, e
      nada no repositório denuncia. [quickstart.md](./quickstart.md) §2. — **FR-010**
- [ ] T004 [H] [P] Criar um bucket descartável, público e **sem CDN**, e conceder a ele a
      mesma `roles/storage.objectAdmin` da conta de serviço. É a homologação que este projeto
      vai ter (T026); é destruído no fim.
- [X] T005 Copiar `<PROJETO>`, `<BUCKET>` e `<URL_MAP>` de
      `.tickets/IASD-CI-GCS-UPLOAD.md:9-13` para `.github/workflows/deploy-web.yml`. **Só o
      workflow recebe os valores** — spec, plan, research e quickstart continuam com os
      marcadores, porque o ticket é a fonte única.
  ✅ `iasd-505120` / `gs://conecta-iasd-site` / `conecta-iasd-site-url-map`, recebidos do
  responsável em 2026-08-10 e registrados primeiro no ticket. **`iasd-images` ficou fora**: o
  ticket pedia publicar `build/assets/images/*` lá, mas este app não gera esse diretório
  (`pubspec.yaml` só declara `.env` como asset) — confirmado com o responsável que é destino
  futuro da migração das capas (feature 013), não desta feature.

**Checkpoint**: existe conta de serviço, existem segredos, existe destino, o modo de cache está
certo. **Pendente** — T001-T004 são humanas, ninguém rodou ainda.

---

## Phase 2: Foundational — o esqueleto do workflow

**Purpose**: estrutura que as três histórias usam. Bloqueia US1 e US2.

- [X] T006 Reescrever o cabeçalho de `.github/workflows/deploy-web.yml`:
      `permissions: contents: read` (era `write` em `:21-22`, e deixa de ser necessário quando o
      push para `dist-web` sai); bloco `concurrency` com `group: deploy-web` e
      **`cancel-in-progress: false`**; `workflow_dispatch` ganha os inputs `target_bucket` e
      `skip_invalidation`. ⚠️ `cancel-in-progress: true` está **proibido**: cancelar um deploy no
      meio da passada aditiva é a forma mais fácil de deixar o bucket pela metade (research
      D-004). — **FR-005**
- [X] T007 Escrever o step `Verify deploy secrets are present`, **antes** do build: falha
      nomeando qual segredo falta, com `::error::` em português, apontando para
      `quickstart.md`. Nunca ecoa valor, nunca faz `head -c` no segredo, nunca roda
      `gcloud auth list` com saída completa. Vir antes do build faz falhar em segundos em vez de
      depois de compilar o app inteiro. — **FR-003, FR-004**
- [X] T008 Preservar intacto o bloco que monta o `.env` de produção (`:34-42`) e o comentário
      de segurança de `:9-14` — traduzindo só o **nome** do step para inglês. Acrescentar o
      segundo aviso, da mesma família: `google-github-actions/auth` grava a chave privada na
      **raiz do workspace** ("The credentials file is exported into `$GITHUB_WORKSPACE`"); a
      fonte do `rsync` é `build/web` e por isso ela não entra, mas trocar essa fonte por `.`
      publica a chave num bucket **público**. — **FR-013**
  ✅ T006-T008: cabeçalho reescrito (`permissions: contents: read`, `concurrency` com
  `cancel-in-progress: false`, inputs `target_bucket`/`skip_invalidation`), step de preflight de
  segredos, bloco `.env` preservado com os dois avisos de segurança lado a lado.

**Checkpoint**: o workflow tem cabeçalho, preflight e build; ainda não publica nada.

---

## Phase 3: User Story 1 — O build publicado chega ao Cloud Storage (P1) 🎯 MVP

**Goal**: o conteúdo de `build/web` chega ao bucket, completo, sem sobra e sem estado parcial.

**Independent Test**: disparar o fluxo contra o bucket de ensaio e conferir que os 40 arquivos do
build chegaram, com o mesmo conteúdo do build local.

- [X] T009 Acrescentar os steps `Authenticate to Google Cloud`
      (`google-github-actions/auth@v2`, `credentials_json: ${{ secrets.GCP_SERVICE_ACCOUNT_JSON }}`)
      e `Set up gcloud` (`google-github-actions/setup-gcloud@v2`). Comentar no arquivo que WIF é
      a recomendação do fornecedor e ficou como dívida (research D-007). — **FR-003**
- [X] T010 Escrever a **passada aditiva**: `gcloud storage rsync --recursive`
      `--cache-control="public, max-age=3600"` de `build/web` para `$TARGET_BUCKET`,
      **sem** `--delete-unmatched-destination-objects`. Usar `gcloud storage`, **não `gsutil`** —
      o fornecedor marcou o gsutil como legado com remoção prevista para março/2027, e a
      divergência com o texto do ticket é deliberada (research D-001). — **FR-001, FR-005**
- [X] T011 Escrever a **passada destrutiva**, logo depois: o mesmo `rsync` **com**
      `--delete-unmatched-destination-objects`. ⚠️ A ordem é a feature, não estilo: numa passada
      única a ferramenta pode apagar um arquivo **antes** de subir o que o substitui, e nessa
      janela o `index.html` antigo aponta para um 404. Comentar isso no arquivo, junto do aviso
      da própria documentação ("this option can delete data quickly if you specify the wrong
      source and destination combination"). — **FR-006, SC-005**
- [X] T012 Garantir que build quebrado não publica: `flutter build web --release` vem
      **antes** de todos os steps de publicação, e daí para baixo **não existe**
      `continue-on-error`, `|| true` nem canalização de saída. Já vale por construção
      (`run:` roda com `bash -e`); a tarefa é confirmar e comentar, porque é fácil de desfazer
      sem perceber. — **FR-002, SC-002**
- [X] T013 Escrever o step `Verify bundled .env carries only the two public keys`: extrai os
      **nomes** de chave de `build/web/assets/.env`, compara com o conjunto esperado
      (`SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_URL`) e falha se houver uma terceira. Nunca imprime
      valor. Este arquivo vai **dentro** do bundle público (`pubspec.yaml:74-75`), baixável em
      `https://<site>/assets/.env` — é exatamente o que o FR-013 protege. — **FR-013, SC-004**

  > **Superada em 2026-08-11.** O step existe, mas com outra pergunta: `Verify no .env was
  > bundled`. `.env` deixou de ser `assets:` no `pubspec.yaml` depois que um `flutter build web`
  > **local**, com o `.env` de trabalho de um desenvolvedor, publicou a senha do Administrador no
  > bundle público — achado em pentest. Conferir **o conteúdo** do que vaza pressupõe aceitar que
  > algo vaze; hoje a garantia é que o arquivo não exista. As chaves entram por `--dart-define`.
  > FR-013 continua valendo; mudou o que o satisfaz.
- [X] T014 Excluir `.last_build_id` das duas passadas (`--exclude='^\.last_build_id$'`). É
      metadado de build, não faz parte do site.
  ✅ T009-T014: auth + setup-gcloud, passada aditiva sem `--delete-…`, passada destrutiva com
  `--delete-unmatched-destination-objects`, `.last_build_id` excluído das duas.
  `actionlint .github/workflows/deploy-web.yml` — **0 avisos**.

**Checkpoint**: o fluxo publica no bucket de ensaio, completo e sem sobra. US1 escrita; **não
ensaiada** — T026 exige bucket real (humana).

---

## Phase 4: User Story 2 — A correção publicada aparece de verdade (P1)

**Goal**: depois de publicar, o cache é invalidado; publicar sem invalidar termina em vermelho.

**Independent Test**: publicar uma alteração visível, recarregar como visitante que já tinha o
site em cache, e ver a alteração.

> **Contexto que torna esta história P1**: **nenhum** arquivo do build tem nome versionado por
> hash — `main.dart.js` é sobrescrito a cada deploy (research D-002). Cache longo é impossível, e
> a invalidação deixa de ser higiene e vira o mecanismo de entrega.

- [X] T015 Acrescentar, **depois** das duas passadas, o step `Set no-cache on index.html`:
      `gcloud storage objects update "$TARGET_BUCKET/index.html" --cache-control="no-cache, max-age=0, must-revalidate"`.
      Vem por último pela mesma regra das duas passadas: nada que o site antigo precise é mexido
      antes do conteúdo novo estar inteiro. Comentar que **a outra metade do FR-010 está fora do
      repositório** (modo de cache do backend bucket, T003). — **FR-010**
- [X] T016 Acrescentar o step `Invalidate CDN cache`:
      `gcloud compute url-maps invalidate-cdn-cache "$URL_MAP_NAME" --path "/*"`, condicionado a
      `if: ${{ !inputs.skip_invalidation }}` (o bucket de ensaio não tem CDN). — **FR-007**
- [X] T017 Garantir que a falha de invalidação derruba o job. Três armadilhas, as três
      proibidas e as três comentadas no arquivo: (1) **`--async`** — o comando voltaria 0 antes
      de saber o resultado, e sem ele "the Google Cloud CLI waits until the invalidation has
      completed"; (2) `continue-on-error: true` ou `|| true`; (3) canalizar a saída
      (`| tee`, `| grep`), que trocaria o código de saída pelo do último comando da tubulação —
      a menos óbvia das três. — **FR-008**
- [X] T018 Acrescentar o step `Report production state on failure` (`if: failure()`), que
      escreve em `$GITHUB_STEP_SUMMARY`, em português: se a falha foi na invalidação, **os
      arquivos novos já estão no bucket** — a produção está nova, o cache é que está velho, por
      até 3600 s — e a recuperação é rerodar o workflow ou invalidar à mão. Sem esta linha, um
      job vermelho comunica "nada foi publicado", que é o oposto da verdade. — **FR-008**
  ✅ T015-T018: `index.html` com `Cache-Control` próprio depois das duas passadas, invalidação
  síncrona (sem `--async`, sem `continue-on-error`, sem `| tee`), passo `if: failure()` escrevendo
  o estado real da produção em `$GITHUB_STEP_SUMMARY`.

**Checkpoint**: publicar sem invalidar é impossível de reportar como sucesso, **na letra do
workflow** — só a produção prova de verdade (T029, humana).

---

## Phase 5: User Story 3 — Quem for configurar sabe exatamente o que precisa (P2)

**Goal**: o responsável configura tudo seguindo um documento, sem adivinhar permissão e sem
perguntar nada.

**Independent Test**: alguém que nunca configurou este deploy consegue fazê-lo só com os
documentos (SC-006).

- [X] T019 [P] [US3] Conferir que [quickstart.md](./quickstart.md) §1 e §3 listam **cada**
      segredo com o que ele é — `GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT_JSON`, `SUPABASE_URL`,
      `SUPABASE_PUBLISHABLE_KEY` — e o aviso de nunca cadastrar `SUPABASE_SERVICE_ROLE_KEY` nem
      `ADMIN_*`. — **FR-011**
- [X] T020 [P] [US3] Conferir que [quickstart.md](./quickstart.md) §1 registra as permissões
      **mínimas** com a fonte de cada uma, diz por que o que o ticket pede é maior que o
      necessário, e traz o plano de escalada (`objectAdmin` → `+legacyBucketReader` →
      `storage.admin`) para o caso não documentado de o `rsync` precisar de
      `storage.buckets.get`. — **FR-012**
- [X] T021 [P] [US3] Conferir que [quickstart.md](./quickstart.md) §6 registra o tempo
      esperado: comando síncrono, limite superior de **3600 s** se a invalidação não rodar (com
      fonte), e o campo `[A MEDIR]` da propagação real. **Não preencher `[A MEDIR]` com
      estimativa** — o "~1m" do ticket é chute do autor, sem fonte, e está marcado como tal.
      T029 preenche com o número observado. — **FR-009, SC-003**
  ✅ T019-T021: `quickstart.md` já cumpria as três na escrita da spec (2026-08-09) — conferido,
  nada mudou. `[A MEDIR]` de §6 continua em branco, propositalmente, até T029.
- [X] T022 [US3] Escrever a decisão sobre `dist-web` em
      [quickstart.md](./quickstart.md) §7 **e** no `README.md`: descontinuada — para de receber
      push agora, fica congelada até o primeiro deploy real ser confirmado, depois é apagada.
      Rejeitar por escrito a redação "keep for backup" do ticket. — **FR-014**
  ✅ `quickstart.md` §7 já trazia a decisão. `README.md` ganhou a mesma decisão na seção Deploy
  (T023).
- [X] T023 [US3] Acrescentar a seção **Deploy** ao `README.md`. Hoje o README **não descreve
      deploy em lugar nenhum** (é acréscimo, não correção). Deve dizer: o que publica (CI em
      push para `main`), onde (bucket + CDN, apontando o ticket como fonte dos nomes), que o
      banco continua em Supabase Cloud e é outra camada, como voltar atrás (reexecutar no commit
      anterior), e apontar para `specs/020-deploy-gcs-cdn/quickstart.md`. — **FR-016**
  ✅ Seção **Deploy** nova, entre "Testes" e "Estrutura": o que publica, onde, banco intocado,
  rollback, `dist-web` descontinuada, e as quatro lacunas conhecidas de T031.
- [X] T024 Varrer os artefatos criados e o diff da feature atrás de **valor** de segredo:
      `plan.md`, `research.md`, `quickstart.md`, `contracts/deploy-web.yml`,
      `.github/workflows/deploy-web.yml`, `README.md` e o ticket. Nenhum deve conter chave, JSON
      de conta de serviço ou URL de projeto Supabase — só **nomes** de chave. Conferir também que
      nenhum step do workflow imprime segredo. — **FR-013, SC-004**
  ✅ `grep` por padrão de valor de segredo (URL Supabase real, `BEGIN PRIVATE KEY`,
  `"private_key"`) nos artefatos tocados — **0 ocorrências**.

**Checkpoint**: as três histórias estão completas e documentadas.

---

## Phase 6: Verificação e fechamento

- [X] T025 Rodar `actionlint .github/workflows/deploy-web.yml`. Registrar a saída real
      (número de avisos), não "passou".
  ✅ **0 avisos.** `actionlint` instalado via `brew install actionlint` (1.7.12) para rodar
  local — não fazia parte do runner antes.
- [ ] T026 [H] **Ensaio de ponta a ponta no bucket descartável.** GitHub → Actions →
      `deploy-web` → Run workflow, **a partir do branch da feature** (não `main`), com
      `target_bucket` = bucket de T004 e `skip_invalidation` marcado. Conferir, conforme
      [quickstart.md](./quickstart.md) §4: os 40 arquivos chegaram e `.last_build_id` não;
      `cacheControl` do `index.html` é `no-cache, max-age=0, must-revalidate` e o do
      `main.dart.js` é `public, max-age=3600`; e o teste do FR-006 — criar um `lixo.txt` no
      bucket, rodar de novo, ele some. Anotar se `roles/storage.objectAdmin` bastou (é o
      `[NÃO VERIFICADO]` de research D-008). Apagar o bucket no fim.
      — valida **FR-001, FR-005, FR-006, FR-010**; **SC-006**
- [X] T027 Remover o step `Publica build/web na branch dist-web`
      (`deploy-web.yml:47-60`, o `git init` + `git push -f`) **no mesmo commit** em que a
      publicação no bucket entra. Manter os dois deixaria duas fontes de verdade sobre o que
      está no ar. — **FR-014**
  ✅ Removido junto da reescrita — `.github/workflows/deploy-web.yml` não tem mais `git init`
  nem `git push -f`. `permissions: contents: write` também saiu (T006).
- [X] T028 Marcar os três itens de aceite de `.tickets/IASD-CI-GCS-UPLOAD.md:16-19` e
      acrescentar, no próprio ticket, as **três divergências deliberadas** do plano em relação ao
      texto dele: `gcloud storage` em vez de `gsutil` (D-001), papéis menores que
      `Storage Admin`/`Compute Network Admin` (D-008), e `dist-web` descontinuada em vez de
      "kept for backup" (D-009). Apontar para `specs/020-deploy-gcs-cdn/`.
      — **FR-015, SC-007**
  ✅ Três itens marcados `[x]` no ticket, com as três divergências escritas.
- [ ] T029 [H] **Primeiro deploy real**: merge em `main`, acompanhar a execução e verificar
      em produção — `curl -sI https://<site>/index.html | grep -i cache-control` tem que devolver
      `no-cache` (se vier `max-age=3600`, o backend bucket está em `FORCE_CACHE_ALL`, volte a
      T003), e `curl -s https://<site>/version.json` tem que ser a versão nova. **Medir** quanto
      tempo levou até um navegador que já tinha o site em cache receber a versão nova, e
      preencher o `[A MEDIR]` de [quickstart.md](./quickstart.md) §6 com o número observado.
      — **SC-001, SC-003**
- [ ] T030 [H] Depois de T029 confirmado, **apagar a branch `dist-web`**. Até aqui ela era o
      único artefato do último build sabidamente bom; a partir daqui é a segunda fonte de verdade
      que a spec manda não deixar existir. — **FR-014**
- [X] T031 Registrar as lacunas conhecidas onde elas serão lidas depois (README ou
      `DEFERRED.md`, se existir), com o porquê de cada uma:
      (a) **`deploy-web.yml` não depende de `ci.yml`** — os dois disparam em `push` para `main`
      sem `needs:` nem `workflow_run`, então um commit com `flutter analyze` ou teste vermelho é
      publicado assim mesmo, desde que compile (research D-010);
      (b) **FR-005 é parcial** — job interrompido no meio da passada aditiva deixa o bucket
      misturado até alguém rerodar; o desenho que fecharia isso (prefixo versionado + virada de
      `pathPrefixRewrite`) está em research D-003 e resolveria o rollback junto;
      (c) **chave JSON em vez de WIF**, contra a recomendação escrita do fornecedor (D-007);
      (d) **sem verificação de disponibilidade depois de publicar** (a spec já declara).
  ✅ `DEFERRED.md` não existe neste repo — as quatro foram para o README, seção Deploy,
  "Lacunas conhecidas".
  ✅ **(a) fechada em 2026-08-11** pela change `travar-deploy-com-teste-vermelho`:
  `deploy-web.yml` passou a depender de `ci.yml` via `workflow_run`, e `make deploy-web` passou
  a exigir prova de CI verde. (b), (c) e (d) continuam abertas — ver PENDENCIAS.md § 2.4.
- [ ] T032 Rodar [quickstart.md](./quickstart.md) inteiro, do §1 ao §7, como se fosse a
      primeira vez, e corrigir o que travar. É a prova do SC-006, e é a única tarefa que mede a
      US3 de verdade.

---

## Cobertura — cada FR e cada SC em ao menos uma tarefa

| Requisito | Tarefas |
|---|---|
| FR-001 publica `build/web` no bucket | T010, T026 |
| FR-002 build que falha não publica | T012 |
| FR-003 credencial vem de segredo | T002, T007, T009 |
| FR-004 falha de auth diz o que falta, sem vazar | T007 |
| FR-005 sem estado parcial | T006, T010, T026 *(parcial — Complexity Tracking)* |
| FR-006 arquivo removido para de ser servido | T011, T026 |
| FR-007 invalida o cache após publicar | T016 |
| FR-008 falha na invalidação derruba o fluxo | T017, T018 |
| FR-009 tempo de propagação documentado | T021, T029 |
| FR-010 `index.html` com cache próprio | T003, T015, T026 |
| FR-011 cada segredo documentado | T019 |
| FR-012 permissões mínimas documentadas | T001, T020 |
| FR-013 nenhum valor de segredo em doc/log/histórico | T002, T008, T013, T024 |
| FR-014 decisão sobre `dist-web` escrita | T022, T027, T030 |
| FR-015 ticket fechado ou apontando para a feature | T028 |
| FR-016 README descreve o deploy | T023 |
| SC-001 100% dos commits com build ok publicam | T029 |
| SC-002 0 publicações de build que falhou | T012 |
| SC-003 alteração aparece dentro do tempo documentado | T021, T029 |
| SC-004 0 valores de segredo | T013, T024 |
| SC-005 0 arquivos servidos que não existem mais | T011, T026 |
| SC-006 configura seguindo a documentação, sem perguntar | T026, T032 |
| SC-007 0 itens de aceite em aberto no ticket | T028 |

**32 tarefas. 7 humanas** (T001, T002, T003, T004, T026, T029, T030) — todas de painel de
provedor ou de GitHub, nenhuma delegável ao repositório, e nenhuma omitida por isso.

**Estado em 2026-08-10**: **24/25 tarefas de repositório feitas** (falta só T032, que depende
das humanas). Nenhuma das 7 humanas foi feita — exigem acesso ao console GCP e ao GitHub que
quem está implementando não tem. `.github/workflows/deploy-web.yml` está escrito, passa
`actionlint` (0 avisos) e **não foi ensaiado nem publicado** — sem T001-T004 não há credencial
nem bucket real para testar, e sem T002 os segredos nem existem no GitHub. Branch
`020-deploy-gcs-cdn`, não mesclada em `main`.

**CORREÇÃO 2026-08-10, mesma tarde — T001 está BLOQUEADA por política de organização, não só
pendente.** O projeto GCP tem `iam.disableServiceAccountKeyCreation` ("Secure by Default"),
aplicada automaticamente — criar a chave JSON da conta de serviço é recusado, no projeto e na
organização. Sem chave, T002 não existe e o desenho inteiro de "CI autentica sozinho" (T006,
T007, T009, T017, T018 — cabeçalho de segredo, preflight, `Authenticate to Google Cloud`,
tratamento de falha de invalidação) fica **sem como rodar** até o Google Cloud Support resolver
(pedido, resposta pendente — `.tickets/IASD-CI-GCS-UPLOAD.md`).

**O que existe hoje em vez disso**: `.github/workflows/deploy-web.yml` foi **reescrito de novo**
— builda e sobe `build/web` como artifact do GitHub Actions, sem `gcloud`, sem secret de GCP.
A lógica de publicação (T010 passada aditiva, T011 passada destrutiva, T014 exclusão de
`.last_build_id`, T015 cache do `index.html`, T016 invalidação de CDN) **não foi perdida** — ela
está no `Makefile` novo, alvo `deploy-web`, rodado à mão por quem tiver `gcloud auth login` com
permissão. As tarefas marcadas `[X]` acima continuam verdadeiras **como desenho documentado**
(é o que volta quando o bloqueio sair); **não são mais o que roda em produção hoje** — isso é
o `Makefile` + `.tickets/IASD-CI-GCS-UPLOAD.md`, que tem a explicação completa. `quickstart.md`
não foi reescrito: ainda descreve o fluxo automático original.

---

## Dependências e ordem

```
Phase 1 (Setup, humana) ─┬─> Phase 2 (Foundational) ─┬─> Phase 3 (US1) ─> Phase 4 (US2)
                         │                            └─> Phase 5 (US3, documentação) [P]
                         └─> T004 (bucket de ensaio) ─────────────> T026
```

- **T001 → T002**: não há chave sem conta de serviço.
- **T006/T007/T008 → T009..T018**: o esqueleto vem antes dos steps.
- **T010 → T011 → T015**: **a ordem é a feature**, não estilo. Aditiva, destrutiva, `index.html`.
  Inverter qualquer par reintroduz o estado parcial que o FR-005 proíbe.
- **T016 → T017 → T018**: invalidar, garantir que a falha derruba, dizer em que estado a produção
  ficou.
- **Phase 5 é paralela à Phase 3/4** — mexe em `quickstart.md`, `README.md` e no ticket, não no
  workflow. Só T022 e T023 tocam o mesmo arquivo (`README.md`) e por isso não são `[P]` entre si.
- **T026 antes de T027/T029**: ensaiar antes de tirar a rede (`dist-web`) e antes de publicar em
  produção.
- **T029 → T030**: a branch só é apagada depois de o deploy real ser confirmado.

## Estratégia de entrega

**US1 e US2 não se separam.** A spec já diz por quê: publicar sem invalidar é pior do que não
publicar, porque cria a convicção de que a correção foi ao ar. E o levantamento reforça — sem
arquivo versionado por hash, a invalidação **é** a entrega, não um polimento (research D-002).
O MVP desta feature é `Phase 1 → 2 → 3 → 4`, e o primeiro merge em `main` já leva as duas.

A Phase 5 pode ser escrita em paralelo, mas **T032 é o último passo de todos**: é a única tarefa
que mede se a US3 funciona, e ela só faz sentido depois que tudo o que ela documenta existe.
