# Quickstart: configurar e verificar o deploy em Cloud Storage + CDN

**Feature**: `020-deploy-gcs-cdn` | **Plano**: [plan.md](./plan.md) | **Pesquisa**: [research.md](./research.md)

Este documento é a US3 inteira: quem for configurar o deploy segue daqui, sem adivinhar
permissão e sem perguntar nada.

**Nomes de projeto, bucket e url map estão em `.tickets/IASD-CI-GCS-UPLOAD.md:9-13`.** Não são
repetidos aqui de propósito — duplicá-los criaria duas verdades. Onde este documento escreve
`<PROJETO>`, `<BUCKET>` e `<URL_MAP>`, copie do ticket.

**Nenhum valor de segredo aparece neste arquivo, e nenhum deve aparecer** (FR-013). Nomes de
chave, sim; valores, nunca.

---

## §1 — Conta de serviço e permissões (só o responsável faz)

No console do Google Cloud, projeto `<PROJETO>`:

1. **Criar a conta de serviço.** Nome sugerido: `github-actions-deploy-web`. Descrição: "Publica
   o build do Flutter Web no bucket e invalida o cache da CDN. Usada só pelo GitHub Actions."

2. **Conceder as duas permissões mínimas** — e **só** elas:

   | Papel | Onde conceder | Para quê | Fonte |
   |---|---|---|---|
   | `roles/storage.objectAdmin` | **no bucket `<BUCKET>`**, não no projeto | criar, sobrescrever, listar e apagar objetos — é o que as duas passadas de `rsync` e o ajuste do `index.html` fazem | "Grants full control of objects, including listing, creating, viewing, and deleting objects." — [IAM roles](https://docs.cloud.google.com/storage/docs/access-control/iam-roles) |
   | `roles/compute.loadBalancerAdmin` | no projeto | invalidar o cache da CDN (permissão `compute.urlMaps.invalidateCache`) | [Invalidating cached content](https://docs.cloud.google.com/cdn/docs/invalidating-cached-content) lista `roles/compute.networkAdmin` **ou** `roles/compute.loadBalancerAdmin`; usamos o menor dos dois |

   **O ticket pede `Storage Admin` + `Compute Network Admin`. Os dois são maiores que o
   necessário** e não devem ser usados: `roles/storage.admin` dá controle sobre o **bucket**
   (apagar o bucket inteiro, mudar política de acesso) que o deploy nunca exerce.

   **Se a publicação falhar com erro de permissão**, suba um degrau por vez, nunca vá direto ao
   topo: `roles/storage.objectAdmin` → acrescentar `roles/storage.legacyBucketReader` →
   só então `roles/storage.admin`. (Não está documentado se o `gcloud storage rsync` chama
   `storage.buckets.get`; research D-008 registra isso como não verificado, e este é o degrau
   que resolve se chamar.)

3. **Criar a chave JSON** da conta de serviço e **baixar uma vez**. O arquivo é uma senha:
   "Anyone with access to the JSON key can authenticate to Google Cloud as the underlying
   Service Account" ([google-github-actions/auth](https://github.com/google-github-actions/auth)).
   Depois de colar no GitHub (§3), apague o arquivo baixado.

   > O próprio fornecedor recomenda **Workload Identity Federation** no lugar da chave —
   > "obviates the need to export a long-lived credential". Ficamos na chave nesta feature
   > porque é o que o ticket pede e o que uma pessoa configura sozinha. Está registrado como
   > dívida em research D-007; a troca depois é mudar um bloco `with:` no workflow.

---

## §2 — Modo de cache do backend bucket (só o responsável faz) ⚠️

**Este passo é metade do FR-010, e nada no repositório denuncia se ele estiver errado.**

O workflow marca o `index.html` com `no-cache`. Isso só vale se a CDN respeitar o cabeçalho do
objeto. Confira o **modo de cache** do backend bucket de `<BUCKET>`:

| Modo | Serve? | Por quê |
|---|---|---|
| `CACHE_ALL_STATIC` (padrão) | ✅ sim | "Automatically caches successful responses with static content"; respeita as diretivas válidas da origem |
| `USE_ORIGIN_HEADERS` | ✅ sim | exige e segue as diretivas da origem |
| `FORCE_CACHE_ALL` | ❌ **não** | "Unconditionally caches successful responses, **overriding any cache directives set by the origin**" — o `no-cache` do `index.html` deixa de existir |

Fonte: [Cloud CDN caching overview](https://docs.cloud.google.com/cdn/docs/caching).

O TTL padrão é **3600 s** — o mesmo número registrado no ticket. É o limite superior de
defasagem quando a invalidação **não** roda; é por isso que a invalidação que falha derruba o
fluxo (FR-008).

---

## §3 — Segredos do repositório (GitHub → Settings → Secrets and variables → Actions)

| Segredo | O que é | Já existia? |
|---|---|---|
| `GCP_PROJECT_ID` | id do projeto no Google Cloud (`<PROJETO>`, ver ticket). Não é o nome de exibição | **novo** |
| `GCP_SERVICE_ACCOUNT_JSON` | conteúdo **inteiro** do arquivo JSON da chave criada em §1.3, colado como está | **novo** |
| `SUPABASE_URL` | URL do projeto Supabase de produção. Vai **dentro** do bundle público — é público por desenho | já existe (`deploy-web.yml:36`) |
| `SUPABASE_PUBLISHABLE_KEY` | chave publicável do Supabase, protegida por RLS. Vai **dentro** do bundle público — é público por desenho | já existe (`deploy-web.yml:37`) |

🔴 **Nunca cadastre `SUPABASE_SERVICE_ROLE_KEY` nem nenhum `ADMIN_*` neste workflow.** `.env` é
`assets:` no `pubspec.yaml:74-75`, então tudo que entra nele é publicado em
`https://<site>/assets/.env` e baixável por qualquer visitante. O comentário em
`deploy-web.yml:9-14` existe por causa disso e continua valendo.

Se um segredo faltar, o workflow falha no primeiro passo dizendo **qual** falta, sem imprimir
valor nenhum (FR-004).

---

## §4 — Ensaio antes do merge (a homologação que este projeto tem)

Não há ambiente de homologação. O que dá para provar antes de tocar em produção:

**Sem nuvem nenhuma:**

```bash
actionlint .github/workflows/deploy-web.yml   # sintaxe, expressões, nomes de input
flutter build web --release                   # o artefato existe (o ci.yml já roda isto)
grep -oE '^[A-Z_]+=' build/web/assets/.env    # tem que sair exatamente 2 linhas
```

**Com um bucket descartável (recomendado, custa centavos):**

1. Crie um bucket novo, **público, sem CDN na frente**, e conceda a mesma
   `roles/storage.objectAdmin` à conta de serviço.
2. No GitHub → Actions → `deploy-web` → **Run workflow**, escolha **o branch da feature** (não
   `main`), preencha `target_bucket` com o bucket de ensaio e marque `skip_invalidation`.
3. Confira, no bucket de ensaio:
   - os 40 arquivos do build chegaram, e `.last_build_id` **não** chegou;
   - `gcloud storage objects describe gs://<ensaio>/index.html --format='value(cacheControl)'`
     devolve `no-cache, max-age=0, must-revalidate`;
   - `gcloud storage objects describe gs://<ensaio>/main.dart.js --format='value(cacheControl)'`
     devolve `public, max-age=3600`;
   - **teste do FR-006**: apague um arquivo qualquer do bucket de ensaio, crie nele um
     `lixo.txt`, rode o workflow de novo — `lixo.txt` tem que sumir e o arquivo apagado tem que
     voltar.
4. Apague o bucket de ensaio.

**O que este ensaio NÃO prova, e só a produção responde:**

1. se `roles/storage.objectAdmin` basta no bucket **real** (ligação IAM diferente);
2. se o nome do url map está certo — falha ruidosa no primeiro deploy real, em segundos;
3. **toda a US2** — o bucket de ensaio não tem CDN. Invalidação valer, `no-cache` ser respeitado
   pelo modo do backend bucket, e um visitante antigo passar a ver a versão nova (SC-003) só
   existem em produção;
4. o tempo real de propagação (§6).

---

## §5 — Quando o deploy falha, o que aconteceu com a produção

**Falha antes de `flutter build web` terminar** → nada foi publicado. A produção está intacta.
(FR-002.)

**Falha no meio da publicação (passadas de `rsync`)** → o bucket pode estar **misturado**: parte
dos arquivos novos, parte dos antigos. Ninguém baixa arquivo pela metade (o Cloud Storage é
atômico por objeto), mas um visitante pode pegar código novo com asset antigo.
**Recuperação: rerodar o workflow.** As duas passadas são idempotentes.

**Falha na invalidação** → ⚠️ **os arquivos novos JÁ ESTÃO no bucket.** A produção está nova; o
cache da CDN é que continua servindo a anterior, por até 3600 s. O job fica vermelho de
propósito (FR-008), e o resumo da execução diz isto por escrito — não conclua "nada foi
publicado". Recuperação: rerodar o workflow, ou rodar só a invalidação:

```bash
gcloud compute url-maps invalidate-cdn-cache <URL_MAP> --path "/*"
```

**Rollback** (não é automatizado, e a spec já assume isso): reexecutar `deploy-web` a partir do
commit anterior — `workflow_dispatch` apontando para o commit bom, ou `git revert` + push. Isso
recompila (minutos) e invalida o cache de novo, que é o que o rollback precisa. **Não há build
anterior guardado no bucket**: a passada destrutiva apaga o que não é do build atual (FR-006), e
isso é a mesma decisão vista de dois lados.

---

## §6 — Quanto tempo esperar antes de achar que deu errado (FR-009)

| Etapa | Tempo | Fonte |
|---|---|---|
| Build + publicação | minutos (dominado por `flutter build web --release` e pelos 3,2 MB de `main.dart.js`) | observado |
| Comando de invalidação | o passo **só retorna quando termina** — não usamos `--async` | "By default, the Google Cloud CLI waits until the invalidation has completed." — [docs](https://docs.cloud.google.com/cdn/docs/invalidating-cached-content) |
| Propagação até um visitante antigo ver a versão nova | **`[A MEDIR]`** — preencher com o número observado no primeiro deploy real (tarefa T026) | — |
| **Se a invalidação não rodar** | até **3600 s** (TTL padrão do modo de cache, e o mesmo número do ticket) | [Cloud CDN caching](https://docs.cloud.google.com/cdn/docs/caching) |

O ticket estima "~1m" para propagar. **É estimativa do autor, sem fonte publicada** — está aqui
como referência, não como garantia. O número que vale é o medido, e o campo fica marcado
`[A MEDIR]` até alguém medir. Preencher com um número plausível seria pior do que deixar em
branco.

**Verificação de ponta a ponta, depois do primeiro deploy real** (é o SC-003):

```bash
# 1. cabeçalho do index.html na borda — tem que dizer no-cache
curl -sI https://<site>/index.html | grep -i cache-control

# 2. a versão nova está sendo servida?
curl -s https://<site>/version.json
```

Se o `Cache-Control` do `index.html` voltar `public, max-age=3600` em vez de `no-cache`, o
backend bucket provavelmente está em `FORCE_CACHE_ALL` — volte para §2.

---

## §7 — A branch `dist-web`

**Decisão registrada (FR-014): descontinuada.**

1. Ela **para de receber push** no mesmo commit em que a publicação no bucket entra. Manter os
   dois deixaria dois lugares dizendo "o que está no ar", divergindo no primeiro deploy em que
   um dos dois falhar.
2. Fica **congelada**, parada no último commit anterior à virada, enquanto o primeiro deploy no
   bucket não é confirmado — é o único artefato do último build sabidamente bom.
3. **Depois do primeiro deploy real confirmado, é apagada** (tarefa T027). A partir daí a fonte
   do que está no ar é o bucket, ponto.

Rejeitada a redação do ticket ("can be kept for backup"): backup que ninguém escreve e ninguém
restaura não é backup, é uma branch velha com aparência de garantia.
