# Implementation Plan: Deploy do app web em Cloud Storage com CDN

**Branch**: `020-deploy-gcs-cdn` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/020-deploy-gcs-cdn/spec.md`

## Summary

Substituir a publicação por branch de git (`deploy-web.yml:47-60`, `git push -f` para
`dist-web`) por publicação no bucket de Cloud Storage com invalidação de Cloud CDN, mantendo o
banco onde está — Supabase Cloud gerenciado, camada da feature 019, não tocada aqui.

O eixo técnico é um só, e vem de um levantamento que mudou o desenho: **nenhum arquivo do build
do Flutter Web tem nome versionado por hash**. `main.dart.js`, `flutter_bootstrap.js`,
`assets/**`, `canvaskit/**` — todos de nome fixo, todos sobrescritos a cada deploy (research
D-002). Isso tem duas consequências que atravessam o plano inteiro:

1. **Cache longo é proibido em todo o build**, não só no `index.html`. A invalidação de CDN
   deixa de ser higiene e passa a ser **o mecanismo de entrega** — é por isso que o FR-008
   (falha de invalidação derruba o fluxo) não é rigor decorativo.
2. **A técnica clássica de deploy atômico não está disponível** — ela depende de os arquivos
   novos terem nome diferente dos velhos. Aqui não têm. O que dá para fazer é **ordenar**: uma
   passada aditiva que sobe tudo sem apagar nada, depois uma passada destrutiva que remove o que
   sumiu. Assim nenhuma remoção acontece antes de todo byte novo estar no lugar.

Esta feature **não cria nenhuma linha de código Dart** — nenhum arquivo de `lib/` ou `test/` é
tocado. A regra de idioma do Princípio I é aplicada ao que ela de fato cria: **nomes de job,
step, input e variável do workflow em inglês; comentários em português.** Os steps do arquivo
atual que estavam em português ("Monta .env de produção…", "Publica build/web na branch
dist-web") são traduzidos nesta virada.

## Technical Context

**Language/Version**: YAML de GitHub Actions + `bash`. Nenhum Dart novo. Flutter SDK `^3.12.2`
continua sendo o que compila o artefato.

**Primary Dependencies** (todas novas, todas no CI):

- `google-github-actions/auth@v2` — autenticação por chave JSON de conta de serviço
- `google-github-actions/setup-gcloud@v2` — instala a Google Cloud CLI no runner
- `gcloud storage rsync` e `gcloud compute url-maps invalidate-cdn-cache` — **não `gsutil`**
  (research D-001: o fornecedor o marcou como legado, com remoção prevista para março/2027)

**Storage**: Cloud Storage (o site compilado). Postgres/Supabase **não tocado** — nenhuma
migration criada ou alterada.

**Testing**: não há teste automatizado desta feature — não há código para testar. Os gates de
`.github/workflows/ci.yml` continuam iguais (`flutter analyze`, `flutter test test/unit
test/widget`, `dart test test/integration`, `flutter build web`). A verificação real é o ensaio
em bucket descartável via `workflow_dispatch` (research D-011) e o `quickstart.md`.

**Target Platform**: Flutter Web servido por Cloud Storage atrás de Cloud CDN.

**Project Type**: mudança de infraestrutura de entrega. Zero mudança observável no app.

**Performance Goals**: nenhum alvo novo. O TTL padrão de 3600 s registrado no ticket é o limite
superior de defasagem **se a invalidação não rodar**; com invalidação, é o tempo que o comando
levar (número real medido no primeiro deploy, T026).

**Constraints**:

- Nenhum valor de segredo em documento, log ou histórico (FR-013).
- Publicar sem invalidar **não** pode terminar em verde (FR-008).
- Sem homologação — publica direto em produção (spec, Assumptions).
- Nomes de recurso não são duplicados nesta feature; fonte única é
  `.tickets/IASD-CI-GCS-UPLOAD.md:9-13`.

**Scale/Scope**: 1 arquivo de workflow reescrito, 1 README atualizado, 1 ticket fechado.
40 arquivos e ~3,3 MB por publicação, dominados por `main.dart.js` (3,2 MB).

### Levantamento do fluxo atual

| Evidência | O que diz |
|---|---|
| `deploy-web.yml:16-19` | Dispara em `push` para `main` e em `workflow_dispatch` |
| `deploy-web.yml:34-42` | Monta `.env` de produção com **duas** chaves públicas; o comentário de segurança em `:9-14` explica por quê. Este bloco **sobrevive inteiro** |
| `deploy-web.yml:44-45` | `flutter pub get` + `flutter build web --release` — sobrevive |
| `deploy-web.yml:47-60` | `git init` + `git push -f` para `dist-web` — **é o que sai** |
| `deploy-web.yml:21-22` | `permissions: contents: write` — deixa de ser necessário; vira `contents: read` |
| `ci.yml:3-6` | Mesmo gatilho (`push` para `main`), **workflow separado** |
| `ci.yml:9-62` | Três jobs: `fast`, `integration`, `build-web` |
| `README.md:15-51, 148-162` | Descreve a arquitetura e a convenção de idioma; **não descreve o deploy em lugar nenhum** — a atualização do FR-016 é acréscimo, não correção |

**Achado**: `deploy-web.yml` **não depende** de `ci.yml`. Não há `needs:` nem `workflow_run`
entre eles. Um commit que quebra `flutter analyze` ou os testes **é publicado assim mesmo**,
desde que `flutter build web --release` compile. Isso não viola o FR-002 na letra (que fala de
build), mas contraria a leitura natural do SC-002. **Fora do escopo da 020** — amarrar deploy a
gate muda o gatilho dos dois workflows e afeta todo PR. Registrado como lacuna escrita (T028,
research D-010), não corrigido em silêncio nem esquecido.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência |
|---|---|---|
| **I. Linguagem Ubíqua** | ✅ PASS — **não se aplica ao glossário**, aplica-se à fronteira de idioma | Nenhum termo de domínio entra ou muda; `CONTEXT.md` não é tocado. Conta de serviço é credencial de máquina, não papel de domínio (a spec já declara isto). A parte do princípio que **se aplica** é a fronteira de idioma, estendida ao artefato que esta feature cria: job/step/input/variável do workflow em inglês, comentário em português — e os dois steps hoje em português (`deploy-web.yml:34`, `:47`) são traduzidos na virada. As strings visíveis ao operador (`::error::`, `$GITHUB_STEP_SUMMARY`) ficam em **português**, pela mesma regra que mantém string de UI em português |
| **II. Privacidade e LGPD** | ✅ PASS — **não se aplica**, com uma ressalva que virou verificação | Nenhum dado pessoal é lido, movido ou publicado: o que sobe é o app compilado. A ressalva é concreta e foi confirmada lendo o build: `.env` é `assets:` no `pubspec.yaml:74-75`, então **`build/web/assets/.env` está dentro do bundle público** e é baixável por qualquer visitante. É o desenho pretendido (só as duas chaves protegidas por RLS), e o FR-013 é o que garante que continue sendo só elas — por isso virou um passo do workflow que conta as chaves, não uma promessa (contrato, `Verify bundled .env carries only the two public keys`) |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita, checklist de qualidade preenchido (`checklists/requirements.md`). `/speckit-clarify` **pulado**: a única ambiguidade real (front no GCS vs. "sair do EC2" do ticket vs. `.env.prod` apontando para Supabase) foi resolvida direto com o responsável em 2026-08-09 e está registrada em Assumptions da spec e nas Notes do checklist. Mesma ressalva da feature 012 |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS — **não se aplica** | Nenhuma regra de domínio existe nesta feature. Fila de espera, empate por sorteio, revogação de voto, descarte de candidatas e composição de Dupla Missionária **não são tocados** — nenhuma linha de `lib/`, `test/` ou `supabase/` muda. A prova é negativa e verificável: o diff da feature não inclui esses diretórios. Os testes existentes continuam rodando em `ci.yml`, inalterados |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel de domínio novo. Nenhuma generalização especulativa: o desenho atômico de verdade (prefixo versionado + virada de `pathPrefixRewrite`, research D-003) foi **considerado e adiado** exatamente por este princípio — resolveria FR-005 e rollback de uma vez, mas custa configuração de balanceador, regra de ciclo de vida e um conceito a mais. Nas permissões, o princípio virou decisão concreta: o ticket pede `Storage Admin` + `Compute Network Admin`; o plano usa `roles/storage.objectAdmin` e `roles/compute.loadBalancerAdmin`, os menores com fonte publicada (research D-008) |

**Reavaliação pós-Fase 1**: sem mudança. O design não introduziu papel, dependência de app,
arquivo Dart nem qualquer alteração de dado. A única violação está no Complexity Tracking, e é
de requisito, não de princípio.

## Project Structure

### Documentation (this feature)

```text
specs/020-deploy-gcs-cdn/
├── spec.md
├── plan.md                  # Este arquivo
├── research.md              # Fase 0 — 12 decisões, com citação literal da fonte primária
├── quickstart.md            # Fase 1 — o que o responsável configura, e como se verifica
├── contracts/
│   └── deploy-web.yml       # Fase 1 — esqueleto comentado do workflow pretendido (NÃO roda)
├── checklists/
│   └── requirements.md
└── tasks.md                 # Fase 2 (/speckit-tasks)
```

**`data-model.md` não é gerado**: não há entidade. Nenhuma tabela, coluna ou migration nasce
desta feature.

**O que `contracts/` é aqui**: não há API. O contrato desta feature é **o workflow de CI** — o
acordo entre o repositório e a nuvem. `contracts/deploy-web.yml` é o esqueleto comentado, com os
comentários que precisam sobreviver à implementação (as três armadilhas do FR-008, a ordem das
duas passadas, e o aviso da credencial em `$GITHUB_WORKSPACE`). Ele **não roda** e não deve ser
copiado para `.github/` sem revisão — os nomes de bucket e url map estão como `<BUCKET>` e
`<URL_MAP>` de propósito, e vêm do ticket.

### Repositório — o antes e o depois

```text
.github/workflows/
├── ci.yml                   # INALTERADO (3 jobs, os mesmos gates)
└── deploy-web.yml           # REESCRITO — ver contracts/deploy-web.yml
                             #   sai:   git init / git push -f dist-web  (:47-60)
                             #   sai:   permissions: contents: write     (:21-22)
                             #   fica:  .env de produção com as 2 chaves (:34-42)
                             #   fica:  flutter pub get / build web      (:44-45)
                             #   entra: concurrency (cancel-in-progress: false)
                             #   entra: preflight de segredos, auth, setup-gcloud
                             #   entra: rsync aditivo → rsync destrutivo → index.html
                             #   entra: invalidate-cdn-cache (síncrono)
                             #   entra: resumo do estado de produção em caso de falha

README.md                    # ganha a seção "Deploy" (FR-016) + nota sobre dist-web (FR-014)
.tickets/IASD-CI-GCS-UPLOAD.md  # 3 itens de aceite marcados + divergências anotadas (FR-015)

lib/  test/  supabase/       # INTOCADOS — nenhuma linha
```

**Structure Decision**: nada muda de lugar. A feature reescreve um arquivo de workflow,
acrescenta uma seção a um README e fecha um ticket. A branch `dist-web` para de receber push no
mesmo commit em que a publicação no bucket entra (research D-009).

## Os seis pontos que este plano precisava resolver

### 1. Arquitetura — front no GCS+CDN, banco no Supabase

Confirmado pelo responsável em 2026-08-09. O "sair do EC2" do ticket se refere ao **front**. O
banco continua em Supabase Cloud gerenciado (`README.md:47-51`, decisão de `.tickets/IASD-03.md`)
e é a camada da feature 019. **Este plano não toca em nada de banco** — nem migration, nem
região, nem backup. Onde a 019 e a 020 se encostam é só no `.env` de produção, que já existe e
já está resolvido, e sobrevive inalterado.

### 2. FR-005 e FR-006 — arquivo removido, e publicação parcial

Os dois requisitos brigam: o FR-006 exige uma operação destrutiva, e a operação destrutiva é
justamente a que pode deixar o site pela metade.

**A solução tem três camadas** (research D-003, contrato):

**(a) Duas passadas, aditiva antes da destrutiva.** A primeira `gcloud storage rsync` sobe tudo
**sem** `--delete-unmatched-destination-objects`; a segunda repete **com** a flag. Numa passada
única, a ferramenta pode apagar um arquivo **antes** de subir o que o substitui — e nessa janela
o `index.html` antigo, ainda sendo servido, aponta para um 404. Com duas passadas, **nenhuma
remoção acontece antes de todo byte novo estar no lugar**, e a remoção que acontece só atinge
arquivos que o build novo não referencia. FR-006 fica cumprido integralmente.

**(b) Atomicidade por objeto vem de graça, e cobre o pior medo.** O Cloud Storage garante que
uma escrita só fica visível quando termina — "the object is immediately available for reading
… as soon as you receive a success response". Ninguém baixa meio `main.dart.js`. O risco não é
**dentro** de um arquivo, é **entre** arquivos.

**(c) `concurrency` sem cancelamento** elimina a causa mais provável de interrupção: outro
deploy atropelando. E `cancel-in-progress: true` fica proibido — o recurso que economiza CI é,
numa publicação, uma fábrica de estado parcial.

**O que fica em aberto, dito na cara**: se o job morrer no meio da passada aditiva, o bucket
fica misturado **até alguém agir**. Não há como fechar isso com operação por arquivo. Mitigação:
as duas passadas são **idempotentes** — a recuperação é rerodar o mesmo job — e o passo
`if: failure()` escreve em `$GITHUB_STEP_SUMMARY` o estado real da produção, para ninguém
concluir "nada foi publicado" quando metade foi.

**Veredito**: FR-006 cumprido; **FR-005 cumprido parcialmente** — ver Complexity Tracking.

### 3. FR-010 — cache do `index.html`

O requisito parte de uma premissa falsa, e a correção está no centro do plano: **não existe
arquivo versionado por hash neste build** (research D-002). Cumprimos a letra do FR-010 e
corrigimos a premissa:

| Objeto | `Cache-Control` | Onde se configura |
|---|---|---|
| `index.html` | `no-cache, max-age=0, must-revalidate` | `gcloud storage objects update`, terceiro comando do job, **depois** das duas passadas |
| todo o resto | `public, max-age=3600` | flag `--cache-control` nas duas passadas de `rsync` |

**São dois lugares, e o segundo não está neste repositório.** O metadado do objeto só vale se a
CDN o respeitar: `CACHE_ALL_STATIC` (o padrão) e `USE_ORIGIN_HEADERS` respeitam;
**`FORCE_CACHE_ALL` "unconditionally caches successful responses, overriding any cache
directives set by the origin"** — nesse modo o `no-cache` do `index.html` simplesmente não
existe, e o FR-010 está violado por configuração de nuvem, com o CI perfeito. Por isso conferir
o modo de cache do backend bucket é **tarefa humana** (T003), com verificação em
`quickstart.md` §2, e não uma nota de rodapé.

### 4. FR-008 — invalidação que falha derruba o fluxo

Três decisões, e todas viram comentário no arquivo porque as três são fáceis de desfazer sem
perceber:

1. **Sem `--async`.** "By default, the Google Cloud CLI waits until the invalidation has
   completed." Com `--async`, o comando retorna 0 antes de saber o resultado, e o FR-008 vira
   impossível.
2. **Sem `continue-on-error`, sem `|| true`, sem canalizar a saída.** `run:` já roda com
   `bash -e`; o requisito se cumpre por não sabotar. Canalizar (`| tee`) trocaria o código de
   saída pelo do último comando da tubulação — é a armadilha menos óbvia das três.
3. **O estado de falha é dito, não deduzido.** Invalidação que falha **não** significa "nada foi
   publicado": os arquivos novos já estão no bucket, e é o cache que está velho, por até 3600 s
   (TTL do ticket). O passo `if: failure()` escreve isso em português no resumo da execução, com
   a recuperação. Sem essa linha, o job vermelho comunica o oposto da verdade.

### 5. Testar sem homologação

Não há homologação. Isso não é o mesmo que não dar para testar — é separar o que se prova antes
do merge do que só a produção responde (research D-011).

**Antes do merge, sem tocar em produção:**

- `actionlint` no workflow — erro de digitação em `secrets.`, `if:`, `inputs.`
- `flutter build web` — já roda no job `build-web` do `ci.yml:49-62`
- contagem de chaves em `build/web/assets/.env` — passo do próprio workflow (FR-013)
- `gcloud storage rsync --dry-run` — "Print what operations rsync would perform without
  actually executing them"
- **o fluxo inteiro, num bucket descartável.** `deploy-web.yml` já tem `workflow_dispatch`
  (`:19`), e `workflow_dispatch` dispara **de qualquer branch**. Um input `target_bucket` aponta
  o deploy para um bucket de ensaio, sem CDN, e o workflow **real** roda com o código **real**
  antes de qualquer merge. Custa centavos e é a homologação que este projeto vai ter.

**Só a produção responde** — escrito, não implícito:

1. Se `roles/storage.objectAdmin` basta para o bucket real (as ligações IAM são outras; é o
   primeiro candidato a falhar, com plano B em research D-008).
2. Se o nome do url map está certo — falha ruidosa, descoberta em segundos.
3. **Toda a US2.** O bucket de ensaio não tem CDN. A invalidação valer, o `no-cache` ser
   respeitado pelo modo do backend bucket, e o tempo até um visitante antigo ver a versão nova
   (SC-003) **só existem em produção**. A parte não testável desta feature é exatamente a
   história P1 que mais importa — e é por isso que o passo de falha do item 4 tem que ser bom.
4. O tempo real de propagação, que preenche o `[NÃO VERIFICADO]` de research D-006.

### 6. `dist-web` fica ou sai? — **sai** (FR-014)

Decisão em três tempos (research D-009):

1. **Imediato**: para de receber push. O passo `deploy-web.yml:47-60` sai no mesmo commit em que
   a publicação no bucket entra. Manter os dois é exatamente a "duas fontes de verdade" que a
   spec chama de confusão — e elas divergem no primeiro deploy em que uma das duas falhar.
2. **Janela**: a branch fica **congelada**, parada no último commit anterior à virada, porque é
   o único artefato do último build sabidamente bom se o primeiro deploy no bucket der errado. O
   README diz isso em uma linha.
3. **Depois do primeiro deploy real confirmado**: é apagada (T027, tarefa humana). A fonte do
   que está no ar passa a ser o bucket, ponto.

Rejeitado: "manter como backup", a redação do ticket. Backup que ninguém escreve e ninguém
restaura não é backup — é uma branch velha com aparência de garantia.

## Riscos e decisões que precisam de olho

1. **A chave privada da conta de serviço fica na raiz do workspace.** "The credentials file is
   exported into `$GITHUB_WORKSPACE`". A fonte do `rsync` é `build/web`, então hoje ela não
   entra. No dia em que alguém trocar a fonte por `.` — "para simplificar" — a chave vai para um
   bucket **público**. É a mesma classe de erro que o comentário de `deploy-web.yml:9-14` já
   evitou uma vez com o `SUPABASE_SERVICE_ROLE_KEY`; ganha um comentário no mesmo tom.
2. **`--delete-unmatched-destination-objects` com destino errado apaga produção.** "this option
   can delete data quickly if you specify the wrong source and destination combination." O
   `target_bucket` do dispatch, criado para o ensaio, é também o jeito mais fácil de apontar o
   deploy para o lugar errado. Mitigação: o input só existe em `workflow_dispatch` (push para
   `main` usa sempre o bucket de produção) e o comentário fica ao lado da flag.
3. **Chave JSON de longa duração.** O próprio fornecedor recomenda Workload Identity Federation
   — "obviates the need to export a long-lived credential". Ficamos na chave porque é o que o
   ticket pede e o que uma pessoa só configura sem montar pool de identidade. **Dívida
   declarada**, trocável mudando um bloco `with:`.
4. **`FORCE_CACHE_ALL` no backend bucket anula o FR-010 inteiro**, sem que nada no repositório
   denuncie. Só se descobre olhando o console ou medindo o cabeçalho em produção. Por isso a
   verificação está no quickstart §2 e §6.
5. **Sem rollback de um comando.** Voltar é reexecutar o `deploy-web` no commit anterior — o que
   funciona, custa alguns minutos de build, e invalida o cache de novo. Não há build anterior
   guardado no bucket, porque a segunda passada apaga o que não é do build atual. **Não ter
   arquivo fantasma e não ter versão anterior à mão são a mesma decisão vista de dois lados**, e
   é o argumento mais forte a favor do desenho de prefixo versionado que ficou adiado.
6. **Dois `[NÃO VERIFICADO]` sobreviveram de propósito**, os dois com plano B escrito: o conjunto
   exato de permissões que o `rsync` chama (D-008) e o tempo real de propagação (D-006). Os dois
   se resolvem executando — T023 e T026. Preencher qualquer um dos dois com um número plausível
   seria pior do que deixá-los marcados.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 12 decisões (D-001 a D-012), com citação literal da
documentação primária do fornecedor em cada afirmação sobre comportamento de nuvem, e dois
`[NÃO VERIFICADO]` explícitos.

A decisão que mais mudou o desenho é a **D-002** — nada tem nome versionado por hash — porque
ela corrige a premissa do FR-010 e elimina a técnica de deploy atômico que seria a resposta
óbvia ao FR-005.

Nenhum `NEEDS CLARIFICATION` restante.

## Fase 1 — Design

Concluída.

- [contracts/deploy-web.yml](./contracts/deploy-web.yml) — o esqueleto comentado do workflow. Os
  comentários **fazem parte do contrato**: as três armadilhas do FR-008, a razão da ordem das
  duas passadas e o aviso da credencial em `$GITHUB_WORKSPACE` precisam sobreviver à
  implementação.
- [quickstart.md](./quickstart.md) — o que o responsável configura na nuvem (US3, FR-011/FR-012),
  o que se verifica antes do merge, e o que só a produção responde.

`data-model.md` não se aplica (justificado em Project Structure).

**Constitution Check pós-design**: reavaliado, sem mudança. Registrada no Complexity Tracking
uma violação **de requisito** (FR-005 parcial), não de princípio.

## Complexity Tracking

| Violação | Por que é necessária | Alternativa mais simples rejeitada porque |
|---|---|---|
| **FR-005 cumprido parcialmente** — a publicação garante que nenhum arquivo é servido pela metade e que nenhuma remoção precede a publicação, mas **não** garante troca atômica do conjunto: um job interrompido no meio da passada aditiva deixa o bucket misturado até alguém rerodar | Não existe operação de troca atômica de conjunto no Cloud Storage por arquivo, e **nenhum arquivo do build do Flutter Web tem nome versionado por hash** (research D-002), o que elimina a técnica padrão de "subir o novo, virar o ponteiro por último" | A alternativa que **cumpre** o FR-005 é publicar em prefixo versionado (`releases/<sha>/`) e virar um `pathPrefixRewrite` no url map — uma chamada de API, atômica, com rollback de graça. Foi **rejeitada nesta feature**, não descartada: exige configuração no balanceador (que é do responsável, não do CI), uma regra de ciclo de vida para o bucket não crescer sem fim, e acrescenta um conceito que o Princípio V manda evitar antes de a necessidade aparecer. **Registrada em research D-003 como o próximo passo**, com o argumento pronto — ela também resolveria o risco 5 (rollback) |
| **Chave JSON de conta de serviço em vez de Workload Identity Federation**, contra a recomendação escrita do fornecedor | É o que o ticket especifica, e o que uma pessoa só configura na interface sem montar pool e provider de identidade — a US3 exige que a documentação baste sem perguntar nada | WIF é a alternativa **melhor**, não a mais simples: dobraria a superfície de configuração manual da US3. Dívida declarada em research D-007; a troca é um bloco `with:` |
