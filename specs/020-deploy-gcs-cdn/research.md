# Research: Deploy do app web em Cloud Storage com CDN

**Feature**: `020-deploy-gcs-cdn` | **Data**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

Nomes de projeto, bucket e url map **não são repetidos aqui**. Fonte única:
`.tickets/IASD-CI-GCS-UPLOAD.md:9-13`.

Toda afirmação sobre comportamento do fornecedor carrega `[VERIFICADO — url]` com citação
literal, ou `[NÃO VERIFICADO]` com o motivo. Nenhuma frase sobre GCP saiu de memória.

---

## Levantamento: o que o build do Flutter Web realmente produz

Lido de `build/web` neste repositório (build de 2026-08-09, Flutter SDK `^3.12.2`). 40 arquivos.

| Caminho | Bytes | Nome versionado por hash? |
|---|---|---|
| `index.html` | 1 607 | não |
| `flutter_bootstrap.js` | 9 974 | não |
| `main.dart.js` | 3 212 924 | **não** |
| `flutter.js` | 9 553 | não |
| `flutter_service_worker.js` | 784 | não |
| `version.json`, `manifest.json`, `favicon.png` | — | não |
| `assets/**` (inclui `assets/.env`) | — | não |
| `canvaskit/**` (11 arquivos, `.wasm` + `.js`) | — | não |
| `icons/**` (4 PNG) | — | não |
| `.last_build_id` | 32 | metadado de build, não é do site |

A cadeia de carregamento é toda de nome fixo:
`index.html` → `<script src="flutter_bootstrap.js">` → `main.dart.js`. Uma busca por `?v=` ou
por sufixo hexadecimal em `flutter_bootstrap.js` retorna **zero**.

Dois efeitos colaterais registrados:

- `flutter_service_worker.js` desta versão do Flutter **não faz cache** — ele se
  desregistra no `activate` e recarrega os clientes. O comentário do próprio build diz
  `"Flutter's service worker is deprecated and will be removed in a future Flutter release."`
  Logo, o **único cache entre o usuário e o bucket é o HTTP/CDN** — não há uma segunda camada
  de cache no navegador para brigar com a invalidação. Boa notícia, e é o que torna a
  invalidação de CDN suficiente.
- `assets/.env` **vai dentro do bundle público** — é `assets:` no `pubspec.yaml:74-75`. É o
  desenho pretendido (spec, Edge Cases), e é exatamente o arquivo que o FR-013 protege.

---

## D-001 — `gcloud storage` em vez de `gsutil` (contraria o texto literal do ticket)

**Decisão**: usar `gcloud storage`. O ticket escreve `gsutil -m cp -r`; não vamos usar nem o
binário nem o comando.

[VERIFICADO — https://docs.cloud.google.com/storage/docs/gsutil]
> "gsutil is not the recommended CLI for Cloud Storage. Use `gcloud storage` commands in the
> Google Cloud CLI instead."
> "The gsutil tool is a legacy Cloud Storage CLI and minimally maintained."
> "After March 2027, gsutil will no longer be available as part of the Google Cloud CLI
> installation package."

Escrever hoje um deploy sobre uma ferramenta com data de remoção publicada é criar dívida no
mesmo commit que a resolve. O ticket é de antes desse aviso; o plano diverge dele **de
propósito**, e isso fica escrito no ticket quando ele for fechado (FR-015).

Efeito colateral: `-m` (paralelismo do gsutil) não existe em `gcloud storage` porque não
precisa —
[VERIFICADO — https://docs.cloud.google.com/storage/docs/gsutil]
> "gcloud storage commands require less manual optimization in order to achieve the fastest
> upload and download rates."

---

## D-002 — A premissa do FR-010 está errada: **nada** tem nome versionado por hash

**Achado que muda o desenho.** O FR-010 diz que `index.html` não pode ter "o mesmo cache dos
arquivos versionados por hash". No build deste app **não existe arquivo versionado por hash**
(tabela acima). `main.dart.js` — 3,2 MB, o arquivo que carrega o app inteiro — tem nome fixo e
é sobrescrito a cada deploy.

Três consequências:

1. **Cache longo (`max-age=31536000, immutable`) é proibido em todo o build**, não só no
   `index.html`. Um `main.dart.js` cacheado por um ano é um app congelado por um ano.
2. **A técnica clássica de deploy atômico não está disponível.** Ela consiste em subir os
   arquivos com hash primeiro (aditivos, não colidem com os antigos) e trocar o `index.html`
   por último. Aqui não há aditivo: o novo `main.dart.js` **sobrescreve** o antigo. Ver D-003.
3. **A invalidação de CDN deixa de ser higiene e vira o mecanismo de entrega.** É por isso que
   o FR-008 (falha de invalidação = falha do fluxo) não é rigor decorativo: sem invalidação, o
   deploy literalmente não chega a quem já visitou.

**Decisão de cache**, então:

| Objeto | `Cache-Control` | Por quê |
|---|---|---|
| `index.html` | `no-cache, max-age=0, must-revalidate` | 1,6 KB. Revalidar a cada carga custa um 304; é o preço mais barato do deploy |
| todo o resto | `public, max-age=3600` | Igual ao padrão do Cloud Storage (D-005), coerente com o TTL de 3600 s registrado no ticket, e a invalidação é quem corta esse TTL |

Isto **cumpre o FR-010 na letra** (o `index.html` não tem o mesmo cache do resto) e corrige a
premissa que o motivava. `canvaskit/**` seria o candidato natural a cache longo — mas o nome
também é fixo, então também não.

Alternativa rejeitada: renomear os artefatos com hash no CI e reescrever as referências. Quebra
o `flutter_bootstrap.js` (que resolve `main.dart.js` por URL construída em runtime), é
manutenção contra o SDK, e viola o Princípio V.

---

## D-003 — FR-005 e FR-006: publicação em duas passadas, aditiva antes da destrutiva

Esta é a decisão central da feature. As duas exigências brigam entre si:

- **FR-006** exige apagar o que sumiu do build → precisa de uma operação destrutiva.
- **FR-005** exige que o site nunca fique pela metade → a operação destrutiva é justamente a
  que pode deixar o site pela metade.

### O que é verdade sobre o Cloud Storage

[VERIFICADO — https://docs.cloud.google.com/storage/docs/consistency]
> "When you write an object to Cloud Storage, such as when you upload, compose, or copy an
> object, the object is immediately available for reading and metadata operations as soon as
> you receive a success response to your write request."
> "You never receive a `404 Not Found` response or stale data for an object read-after-write or
> object read-after-metadata-update operation, even for buckets located in dual-regions or
> multi-regions."

Ou seja: **cada objeto individualmente é atômico e forte**. Ninguém baixa meio `main.dart.js`.
Um leitor pega a versão antiga **ou** a nova, nunca um arquivo rasgado. O risco de "site pela
metade" não é por arquivo — é **entre** arquivos.

[VERIFICADO — https://docs.cloud.google.com/sdk/gcloud/reference/storage/rsync]
> "--delete-unmatched-destination-objects: Delete extra files under DESTINATION not found under
> SOURCE. By default extra files are not deleted."
> "Note: this option can delete data quickly if you specify the wrong source and destination
> combination."

[NÃO VERIFICADO] A referência do `gcloud storage rsync` **não diz nada** sobre atomicidade nem
sobre o que sobra quando a execução é interrompida no meio. Procurei; a página não trata do
assunto. Portanto: **assumo que não há atomicidade nenhuma no nível do conjunto** e desenho
para isso, em vez de esperar uma garantia que ninguém publicou.

### A decisão

**Duas passadas de `rsync`, nesta ordem, no mesmo job:**

```
1ª (aditiva)   gcloud storage rsync -r build/web gs://BUCKET   # SEM --delete-...
2ª (destrutiva) gcloud storage rsync -r --delete-unmatched-destination-objects build/web gs://BUCKET
```

Por que a ordem importa, e não é detalhe: numa passada única com `--delete-…`, a ferramenta
pode apagar um arquivo **antes** de subir o que o substitui. Enquanto essa janela dura, o
`index.html` antigo — que ainda está sendo servido — aponta para algo que **não existe mais**:
404, tela branca. Com duas passadas, **nenhuma remoção acontece antes de todo byte novo estar
no lugar**. A 2ª passada só remove arquivos que o build atual não tem, e que portanto nenhum
HTML novo referencia.

### O que sobra, dito na cara

A janela entre o primeiro e o último objeto da 1ª passada continua existindo. Nela, um visitante
pode receber `main.dart.js` novo com `assets/AssetManifest.bin` antigo. Três coisas a dizem
inteira:

1. **Duração**: só os objetos que mudaram são reescritos, e o job sobe em paralelo. Na prática,
   segundos. Não é zero.
2. **Se o job morrer no meio da 1ª passada**, o bucket fica misturado **até alguém agir** — e
   este é o furo real do FR-005. Não há como fechá-lo com operação por arquivo. Mitigações que
   entram: (a) `concurrency` sem cancelamento (D-004), que elimina a causa mais provável de
   interrupção — outro deploy atropelando; (b) o job falha ruidosamente, e o resumo de execução
   diz em que estado a produção ficou (D-006), para ninguém achar que deu certo; (c) a
   recuperação é **rerodar o mesmo job** — as duas passadas são idempotentes.
3. **O desenho que fecharia o furo de verdade está registrado e adiado**: publicar em prefixo
   versionado (`releases/<sha>/`) e virar um `pathPrefixRewrite` no url map — a virada passa a
   ser **uma chamada de API**, atômica, e o rollback vira virar de volta. Custa mexer no
   balanceador (que é do responsável, não do CI), uma regra de ciclo de vida para o bucket não
   crescer para sempre, e some com a simplicidade que o Princípio V pede. **Fora de escopo da
   020**, registrado aqui para quem voltar.

**Veredito honesto**: a 020 cumpre o FR-006 integralmente e o FR-005 **parcialmente** — garante
que nenhum arquivo é servido pela metade e que nenhuma remoção precede a publicação, mas não
garante troca atômica do conjunto. Isso está no Complexity Tracking do plano, não escondido.

---

## D-004 — `concurrency` sem cancelamento

**Decisão**: o workflow declara um grupo de concorrência com `cancel-in-progress: false`.

[VERIFICADO — https://docs.github.com/en/actions/reference/workflows-and-actions/workflow-syntax#concurrency]
> "only a single job or workflow using the same concurrency group will run at a time."
> Jobs process "in first-in-first-out (FIFO) order according to the time each one started
> waiting."

Resolve o edge case "deploy concorrente" da spec: dois commits em sequência rápida não escrevem
no mesmo bucket ao mesmo tempo, e a ordem passa a ser a de chegada.

**`cancel-in-progress: true` está proibido aqui, e o motivo é contraintuitivo**: cancelar um
deploy em andamento mata o job no meio da 1ª passada — ou seja, o recurso que "economiza CI"
é uma **fábrica de estado parcial** (D-003, item 2). Para um build o cancelamento é economia;
para uma publicação é dano.

---

## D-005 — `Cache-Control` se configura em dois lugares, e os dois importam

**Lugar 1 — metadado do objeto, no Cloud Storage** (fica no CI, versionado neste repositório):

[VERIFICADO — https://docs.cloud.google.com/sdk/gcloud/reference/storage/rsync]
> "--cache-control=CACHE_CONTROL: How caches should handle requests and responses."

[VERIFICADO — https://docs.cloud.google.com/storage/docs/metadata]
> "`Cache-Control` is also a header you can specify in your HTTP requests for an object;
> however, Cloud Storage ignores this header and sets response `Cache-Control` headers based on
> the stored metadata values."

E o padrão que herdaríamos sem fazer nada:
> Publicamente legível: `"public, max-age=3600"`.

`--cache-control` do `rsync` vale para **tudo** naquela passada. Como o `index.html` precisa de
um valor diferente (D-002), ele leva **uma terceira operação**, depois das duas passadas:
`gcloud storage objects update gs://BUCKET/index.html --cache-control=...`. Três operações, não
duas — e a do `index.html` vem **por último**, mantendo a regra de D-003 (nada que o site
antigo precise é mexido antes do conteúdo novo estar no lugar).

**Lugar 2 — modo de cache do backend bucket, no console do GCP** (é do responsável, não do CI):

[VERIFICADO — https://docs.cloud.google.com/cdn/docs/caching]
> `CACHE_ALL_STATIC`: "Automatically caches successful responses with static content that isn't
> otherwise non-cacheable." — é "the *default* for Cloud CDN-enabled backends created by using
> the Google Cloud CLI or the REST API."
> `FORCE_CACHE_ALL`: "Unconditionally caches successful responses, overriding any cache
> directives set by the origin."
> TTL padrão: 3600 s.

**O modo `FORCE_CACHE_ALL` anula o Lugar 1 inteiro** — ele ignora o `Cache-Control` do objeto,
e o `no-cache` do `index.html` deixa de existir. Se o backend bucket estiver nesse modo, o
FR-010 está violado por configuração de nuvem mesmo com o CI perfeito. Por isso conferir o modo
é **tarefa**, não nota de rodapé (quickstart §2). `CACHE_ALL_STATIC` (o padrão) e
`USE_ORIGIN_HEADERS` respeitam o objeto; qualquer um dos dois serve.

---

## D-006 — Invalidação síncrona, e o que dizer quando ela falhar

[VERIFICADO — https://docs.cloud.google.com/cdn/docs/invalidating-cached-content]
> `gcloud compute url-maps invalidate-cdn-cache URL_MAP_NAME --path "/images/file.jpg"`
> "By default, the Google Cloud CLI waits until the invalidation has completed."
> Padrões de caminho documentados: `/images/file.jpg`, `/images/*`, `/*`.

**Decisões**:

- `--path "/*"`, como o ticket. Nada aqui tem nome estável o bastante para invalidação
  seletiva valer a pena (D-002).
- **`--async` está proibido.** É a única linha que separa "o fluxo esperou a invalidação
  terminar" de "o fluxo disparou e foi embora". Com `--async` o FR-008 é impossível de cumprir:
  o comando volta 0 antes de saber o resultado.
- **FR-008 sai de graça se ninguém sabotar**: `run:` do GitHub Actions roda com `bash -e`, e o
  passo é o último do job. Basta **não** escrever `continue-on-error: true`, **não** encerrar a
  linha com `|| true`, e **não** canalizar a saída para outro comando (que trocaria o código de
  saída pelo do último da tubulação). São três armadilhas conhecidas; as três viram comentário
  no arquivo.
- **Falha de invalidação tem um estado próprio, e ele precisa ser dito.** Não é igual a falha de
  build. Quando a invalidação falha, **os arquivos novos já estão no bucket** — a produção está
  nova, o cache é que está velho, por até 3600 s (o TTL do ticket). Um passo
  `if: failure()` escreve isso em `$GITHUB_STEP_SUMMARY`, em português, com a ação de
  recuperação (rodar a invalidação à mão, ou rerodar o workflow). Sem isso, quem lê "job
  vermelho" conclui "nada foi publicado", que é o oposto da verdade.

[NÃO VERIFICADO] Tempo real de propagação global da invalidação. A página de invalidação não
publica número; o único número com fonte é o **TTL padrão de 3600 s** do modo de cache, que é o
limite superior se a invalidação **não** rodar. O ticket estima "~1m" para propagar — é
estimativa do autor do ticket, sem fonte, e assim está anotada. O FR-009 é cumprido registrando
**o que se sabe**: limite superior de 3600 s sem invalidação; com invalidação, o comando só
retorna quando termina, e o número observado no primeiro deploy real entra no quickstart
(tarefa T026). Não vou inventar um número para preencher o campo.

---

## D-007 — Autenticação: chave JSON agora, WIF registrado como dívida

Os nomes de segredo são os do ticket: `GCP_PROJECT_ID`, `GCP_SERVICE_ACCOUNT_JSON`.

[VERIFICADO — https://github.com/google-github-actions/auth]
> "Workload Identity Federation is recommended over Service Account Keys as it obviates the need
> to export a long-lived credential."
> "Service Account Key JSON credentials are long-lived credentials and must be treated like a
> password. Anyone with access to the JSON key can authenticate to Google Cloud as the
> underlying Service Account."

**Decisão**: ficar com a chave JSON nesta feature, como o ticket pede, e registrar WIF como o
upgrade recomendado pelo próprio fornecedor. Motivo: WIF exige criar pool e provider de
identidade e amarrar ao repositório — configuração de nuvem que só o responsável faz, e que
dobraria a US3 (a história cujo critério é "consegue seguir a documentação sem perguntar
nada"). Trocar depois é mudar o bloco `with:` de um passo. **Dívida declarada, não esquecida.**

**Armadilha que quase publica a chave privada num bucket público:**

[VERIFICADO — https://github.com/google-github-actions/auth]
> "The credentials file is exported into `$GITHUB_WORKSPACE`, which makes it available to all
> future steps and filesystems (including Docker-based GitHub Actions)."

O arquivo de credencial fica na **raiz do workspace**. A fonte do `rsync` é `build/web`, então
hoje ele não entra. Mas o dia em que alguém trocar a fonte para `.` — ou rodar o rsync da raiz
"para simplificar" — a chave da conta de serviço vai para um bucket **público**. Isso vira
comentário em caixa alta no workflow, ao lado do já existente sobre o `.env` (`deploy-web.yml:9-14`),
porque é a mesma classe de erro que aquele comentário já evitou uma vez.

**FR-004 — falhar sem vazar**: um passo de preflight confere que
`secrets.GCP_PROJECT_ID` e `secrets.GCP_SERVICE_ACCOUNT_JSON` não estão vazios e falha nomeando
**qual** falta. Nunca ecoa valor, nunca faz `echo "$KEY" | head -c 20`, nunca roda
`gcloud auth list` com saída completa. Segredo de repositório é mascarado nos logs do GitHub,
mas mascaramento é a segunda linha de defesa — a primeira é não imprimir.

---

## D-008 — Permissões mínimas da conta de serviço

O ticket pede `Storage Admin` + `Compute Network Admin`. Os dois são maiores do que o
necessário. O mínimo com fonte:

**Para publicar**
[VERIFICADO — https://docs.cloud.google.com/storage/docs/access-control/iam-roles]
> `roles/storage.objectAdmin`: "Grants full control of objects, including listing, creating,
> viewing, and deleting objects."
> `roles/storage.admin`: "Grants full control of objects **and buckets**."

`objectAdmin` cobre `storage.objects.create`, `.delete`, `.get`, `.list`, `.update` — que é
exatamente o conjunto que as duas passadas de `rsync` e o `objects update` do `index.html`
usam. `storage.admin` acrescenta poder sobre o **bucket** (apagar o bucket inteiro, mudar
política de acesso) que o deploy nunca exerce. **Recomendação: `roles/storage.objectAdmin`
concedida no bucket, não no projeto.**

**Para invalidar**
[VERIFICADO — https://docs.cloud.google.com/cdn/docs/invalidating-cached-content]
> Permissão: `compute.urlMaps.invalidateCache`. Papéis: `roles/compute.networkAdmin` **ou**
> `roles/compute.loadBalancerAdmin`.

**Recomendação: `roles/compute.loadBalancerAdmin`**, o menor dos dois publicados. Menor ainda
seria um papel personalizado com só `compute.urlMaps.invalidateCache`; fica registrado como
opção, mas papel personalizado é mais uma peça para o responsável manter, e o ganho sobre
`loadBalancerAdmin` é pequeno num projeto que não tem outro balanceador.

[NÃO VERIFICADO] Se `roles/storage.objectAdmin` **sozinha** basta para o `gcloud storage rsync`
resolver o bucket (algumas operações do CLI tocam `storage.buckets.get`, que não está em
`objectAdmin`). Não achei a lista de permissões que o `rsync` chama. **Isto só se descobre
executando** — e é o primeiro candidato a falhar no ensaio do bucket descartável (D-011).
Plano B, escrito antes de precisar: acrescentar `roles/storage.legacyBucketReader`, e só então
`roles/storage.admin`. Sempre subindo, nunca começando pelo topo.

---

## D-009 — `dist-web`: descontinuada, congelada, e depois removida

FR-014 exige uma decisão escrita. Aqui está.

**Decisão em três tempos:**

1. **Imediato — para de receber push.** O passo `Publica build/web na branch dist-web`
   (`deploy-web.yml:47-60`) sai no mesmo commit em que a publicação no bucket entra. Manter os
   dois é exatamente a "duas fontes de verdade" que a spec chama de confusão: dois lugares
   dizendo "o que está no ar", divergindo no primeiro deploy em que um dos dois falhar.
2. **Janela — a branch fica congelada.** Ela continua existindo, parada no último commit
   anterior à virada, porque é o único artefato do último build sabidamente bom se o primeiro
   deploy no bucket der errado. O README passa a dizer, em uma linha, que ela está congelada e
   **não** é mais a fonte.
3. **Depois do primeiro deploy real confirmado — é apagada.** Tarefa humana (T027), não
   automática. A partir daí a fonte do que está no ar é o bucket, ponto.

Rejeitado: "manter como backup" (redação do ticket). Backup que ninguém escreve e ninguém
restaura não é backup, é uma branch velha com aparência de garantia.

---

## D-010 — Achado: o deploy **não** depende dos gates do `ci.yml`

`ci.yml` e `deploy-web.yml` são workflows **separados**, os dois disparados por
`push: branches: [main]`. Não há `needs:` nem `workflow_run` entre eles. Consequência real:
**um commit que quebra `flutter analyze`, `flutter test` ou `dart test test/integration` é
publicado assim mesmo**, desde que `flutter build web --release` compile.

Confronto com a spec: o FR-002 e o SC-002 falam de "build que falha", e nesse sentido estrito o
fluxo já está correto — `bash -e` mais a ordem dos passos garantem que build quebrado não
publica. Mas a leitura natural de "0 publicações a partir de build que falhou" inclui teste
vermelho, e hoje não inclui.

**Decisão: fora do escopo da 020.** Amarrar deploy a gate é mudar o gatilho dos dois workflows
(ou fundi-los), tem efeito em todo PR e merece a sua própria spec. **Registrado como lacuna
conhecida** e escrito (T028), porque uma lacuna não escrita vira surpresa.

---

## D-011 — Como testar sem homologação

A spec declara: não há homologação, publica direto em produção. Isso não significa "não dá para
testar" — significa separar o que se prova antes do merge do que só a produção responde.

**Prova antes do merge, sem tocar em produção:**

| O quê | Como | Cobre |
|---|---|---|
| Sintaxe e expressões do workflow | `actionlint .github/workflows/deploy-web.yml` | erro de digitação em `secrets.`, `if:`, `needs:` |
| O artefato existe e compila | `flutter build web` — já roda no job `build-web` do `ci.yml:49-62` | FR-002 |
| O `.env` do bundle tem só as 2 chaves | ler `build/web/assets/.env` no runner e contar as linhas; falhar se aparecer terceira | FR-013 |
| O que o rsync faria | `gcloud storage rsync --dry-run` — [VERIFICADO — https://docs.cloud.google.com/sdk/gcloud/reference/storage/rsync] "Print what operations rsync would perform without actually executing them." | FR-006 |
| **O fluxo inteiro, de ponta a ponta** | **bucket descartável** (sem CDN) + `workflow_dispatch` a partir do branch da feature | FR-001, FR-005, FR-006, FR-010 |

A última linha é a resposta boa. `deploy-web.yml` já tem `workflow_dispatch` (`:19`), e
`workflow_dispatch` dispara **de qualquer branch**. Então: cria-se um bucket descartável, aponta-se
o destino para ele por um input do dispatch, e roda-se o workflow real, com o código real, antes
de qualquer merge. Custa centavos, dura o tempo do ensaio, e é destruído no fim. É homologação
suficiente para a metade que importa (publicação), e a única que este projeto vai ter.

**Só a produção responde** — e isto entra escrito, não fica implícito:

1. Se os papéis da conta de serviço bastam para o bucket **real** e o url map **real** (as
   ligações IAM são outras; ver D-008, `[NÃO VERIFICADO]`).
2. Se o nome do url map está certo. Falha ruidosa — `invalidate-cdn-cache` erra alto com nome
   inexistente. Descoberto no primeiro deploy, em segundos.
3. **A invalidação e a propagação (SC-003).** O bucket descartável não tem CDN na frente. Todo o
   comportamento de cache — a invalidação valer, o `no-cache` do `index.html` ser respeitado
   pelo modo do backend bucket (D-005, Lugar 2), o tempo até um visitante antigo ver a versão
   nova — **só existe em produção**. É a parte não testável desta feature, e é justamente a US2.
4. O tempo real de propagação, que preenche o `[NÃO VERIFICADO]` de D-006.

---

## D-012 — Rollback

A spec já assume "sem rollback automatizado". O que fica escrito no README, para não virar
pergunta às 23h: **voltar é reexecutar o `deploy-web` a partir do commit anterior**
(`workflow_dispatch` no commit bom, ou `git revert` + push). Isso roda o build de novo (minutos)
e invalida o cache de novo, o que é justamente o que o rollback precisa. Não há artefato guardado
do build anterior no bucket — a 2ª passada apaga o que não é do build atual (FR-006), e as duas
coisas são a mesma decisão vista de dois lados: **o preço de não servir arquivo fantasma é não
ter versão anterior à mão.** O desenho de prefixo versionado (D-003) resolveria os dois de uma
vez; está adiado, e é o argumento mais forte a favor dele.

---

## Nenhum `NEEDS CLARIFICATION` restante

Dois `[NÃO VERIFICADO]` permanecem de propósito, os dois com plano B escrito: o conjunto exato
de permissões que o `rsync` chama (D-008) e o tempo real de propagação da invalidação (D-006).
Os dois se resolvem executando, e as tarefas que os resolvem existem (T023, T026).
