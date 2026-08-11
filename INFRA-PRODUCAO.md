# Infraestrutura de produção — região

**Este arquivo é o registro canônico da região e do que produção precisa
configurar à mão.** `README.md`, `.env.example`,
`MAPA-DE-DADOS.md` e o comentário de `LegalMetadata.hostingRegion` apontam para
cá — nenhum deles repete o conteúdo. Quem for provisionar um ambiente novo lê
aqui.

Criado pela feature [019](specs/019-producao-regiao-e-backup/spec.md) em
2026-08-10.

⚠️ **Nunca escreva neste arquivo** `SUPABASE_SERVICE_ROLE_KEY` nem senha de
banco — o repositório é público. O `project-ref` **pode**: ele já vai público
dentro do build web (`.github/workflows/deploy-web.yml:33-42`).

---

## 1. Região exigida para qualquer ambiente

**`sa-east-1` — South America (São Paulo, Brasil).**

Isto é **requisito de provisionamento, não o default do fornecedor**. Quem criar
um projeto Supabase novo — produção, homologação, ambiente de teste com dado
real — DEVE escolher esta região explicitamente na criação. A região de um
projeto Supabase não é documentada como alterável depois: corrigir na prática
significa projeto novo e mover banco com gente usando.

**Por quê**: a Política de Privacidade afirma a titulares que o dado não sai do
Brasil, e por isso não declara transferência internacional (LGPD art. 33). Zerar
a transferência é mais barato e mais seguro do que justificá-la. A afirmação da
Política só é verdadeira enquanto esta região for cumprida.

---

## 2. Verificação da produção atual

✅ **Verificado em 2026-08-10. A região cumpre a exigência da seção 1.**

A partir desta data, a afirmação da Política de Privacidade de que o dado não sai
do Brasil descreve **um fato conferido**, e não mais uma decisão tomada. Foi por
falta desta linha que a feature 019 existiu: a mesma afirmação estava repetida em
quatro documentos sem que ninguém tivesse aberto o painel.

| Campo | Valor |
|---|---|
| Região lida no fornecedor | **South America (São Paulo)** — `sa-east-1` |
| Nome do projeto | `iasd-conecta-vsa` |
| `project-ref` | `mbfcnebyxzoagwatjxuh` |
| Projeto criado em (UTC) | 2026-08-07 00:57:15 |
| Plano do projeto (Free / Pro / Team / Enterprise) | `[NÃO COLHIDO]` — ver nota abaixo |
| Verificado em | **2026-08-10** |
| Quem verificou | O fundador, com a CLI autenticada na própria conta |

**Nota sobre o plano**: não foi colhido, e deixou de bloquear alguma coisa. Ele
existia como insumo de uma única decisão — se havia backup automático disponível —
e essa decisão foi fechada por outro caminho (seção 3). Fica registrado como não
colhido em vez de deduzido.

**Sobre a evidência abaixo**: é a saída literal de `supabase projects list`, com o
`ORG ID` mascarado. O `project-ref` fica, porque já vai público dentro do build
web; o identificador da organização não vai a lugar nenhum público e não
acrescenta nada à prova da região.

A CLI imprime o nome legível da região (`South America (São Paulo)`), não o slug
`sa-east-1`. São a mesma região na nomenclatura do fornecedor — a seção 1 usa o
slug porque é ele que se digita ao criar o projeto.

**Como obter** — um acesso só, dois caminhos:

```bash
supabase login
supabase projects list    # copiar a linha do projeto de produção, INTEIRA
```

ou Dashboard → projeto de produção → Project Settings → General, transcrevendo a
string de região exatamente como aparece. **Print de tela não serve**: não se
versiona nem se pesquisa por `grep`.

Saída literal (`supabase projects list`, 2026-08-10):

```text
   LINKED | ORG ID     | REFERENCE ID         | NAME             | REGION                    | CREATED AT (UTC)
  --------|------------|----------------------|------------------|---------------------------|---------------------
     ●    | [mascarado]| mbfcnebyxzoagwatjxuh | iasd-conecta-vsa | South America (São Paulo) | 2026-08-07 00:57:15
```

### O portão — resultado: **Ramo A**

A região é brasileira, então a Política de Privacidade **não muda**: continua
correto não declarar transferência internacional, e agora com evidência atrás.

Se um dia uma verificação destas der região **não** brasileira, a primeira
providência — antes de qualquer outra — é corrigir a Política para declarar a
transferência. Enquanto a Política diz que o dado não sai do Brasil e ele sai, o
app afirma algo falso a titulares. Migrar de região é trabalho separado e maior:
na prática, projeto novo e banco em produção movido com gente usando.

### Quando reverificar

Esta verificação vale para **este** projeto (`mbfcnebyxzoagwatjxuh`). Ela não se
herda: qualquer projeto Supabase novo — homologação, ambiente de teste com dado
real, ou uma recriação deste — começa com a região indefinida do ponto de vista
deste documento, e a tabela acima precisa ser refeita para ele.

---

## 3. Drenagem das fotos de capa — **um passo obrigatório no primeiro deploy**

A feature 013 guarda imagens de capa num bucket público. Quando alguém remove
uma imagem, o banco só **enfileira** o arquivo em `public.capas_a_remover`; quem
apaga de verdade é uma Edge Function, chamada pelo `pg_cron` e pelo app.

**Essa chamada precisa saber o endereço da função, e ele não vem configurado.**
De propósito: a primeira versão trazia o endereço do Docker de quem desenvolve
semeado na migration, o que faria produção disparar de minuto em minuto contra
um endereço que não resolve — **a fila nunca drenaria, e toda imagem removida
ficaria no bucket para sempre**, em silêncio. Hoje a função **recusa em voz
alta** enquanto o ambiente não estiver configurado.

Rodar **uma vez**, contra o banco de produção, trocando `<project-ref>`:

```sql
insert into public.configuracao_drenagem (url_funcao)
values ('https://<project-ref>.supabase.co/functions/v1/drenar-capas')
on conflict (id) do update set url_funcao = excluded.url_funcao,
                               atualizado_em = now();
```

O `project-ref` está na seção 2. A Edge Function precisa estar publicada
(`supabase functions deploy drenar-capas`) — ela recebe a chave de serviço do
próprio ambiente do Supabase, e **nenhum segredo é guardado aqui nem no banco**.

### Como saber que a fila parou

Se esta consulta devolver algo além de zero por mais de uma hora, há imagem
removida que **continua acessível**:

```sql
select count(*) from public.capas_a_remover
where removido_em is null
  and enfileirado_em < now() - interval '1 hour';
```

Vale conferir depois do primeiro deploy e sempre que alguém relatar que uma
imagem removida continua aparecendo. É a única forma de o problema dar sinal: a
fila parada não aparece em tela nenhuma.

E olhe a coluna `tentativas` das linhas pendentes: **contagem alta e parada
quer dizer que aquele caminho não sai** — bucket errado, ou objeto que já não
existe. `ultimo_erro` diz qual dos dois.

> **Por que a confirmação é positiva, e não "não deu erro".** Medido em
> 2026-08-10: com um nome de bucket errado, a API de armazenamento devolve
> **sucesso** para a remoção. A versão anterior da drenagem acreditava nisso e
> carimbava a linha como drenada — o arquivo continuava público, a fila ficava
> vazia e esta consulta mostrava zero. Hoje só sai da fila o caminho que a API
> devolve **na lista dos removidos**.

### O que fazer quando um caminho não sai

Detectar não basta. Um caminho que **nunca** vai confirmar — objeto apagado à
mão, resíduo de teste, prefixo inválido — fica pendente para sempre, e a
consulta acima alarma para sempre. Alarme sem conduta é alarme que se aprende a
ignorar, e aí a fila deixa de ser a rede de segurança que ela existe para ser.

**Passo 1 — leia o motivo.**

```sql
select caminho, tentativas, enfileirado_em, ultimo_erro
from public.capas_a_remover
where removido_em is null
order by tentativas desc, enfileirado_em;
```

**Passo 2 — confirme se o objeto ainda existe.** Esta consulta é a autoridade;
abrir o endereço no navegador **não** é, porque a borda pode servir cache por
até 60 segundos depois da remoção:

```sql
select count(*) from storage.objects
where bucket_id = 'fotos-capa' and name = '<o caminho da linha>';
```

**Passo 3, se o objeto EXISTE (`1`):** a remoção está falhando de verdade. Não
encerre a linha. Confira o nome do bucket na Edge Function contra
`select id from storage.buckets`, confira que a função está publicada, e olhe o
log dela. A linha continua pendente **de propósito** — é o arquivo que ainda
está público.

**Passo 3, se o objeto NÃO existe (`0`):** o arquivo já saiu, e a linha só está
segurando o alarme. Encerre-a dizendo por quê:

```sql
update public.capas_a_remover
set removido_em = now(),
    ultimo_erro = 'confirmado inexistente em <data>'
where caminho = '<o caminho da linha>';
```

> **Encerrar sem fazer o passo 2 é reintroduzir o problema que a fila resolve.**
> A linha some do alarme, o arquivo continua público, e nada mais no sistema
> sabe dele. É o órfão invisível voltando pela porta da manutenção.

### A varredura — o arquivo que nunca teve linha

A fila é alimentada pelo gatilho que dispara quando uma **linha** de capa é
apagada. Existe um arquivo que ele não vê: o que subiu e cuja linha nunca chegou
a ser gravada — o app sobe o arquivo primeiro e grava a linha depois, e uma
falha entre as duas coisas (rede caindo, ou duas pessoas que administram o mesmo
Grupo enviando ao mesmo tempo) deixa o arquivo no bucket sem linha nenhuma.
Medido em 2026-08-10: um objeto nesse estado **não move a consulta acima**.

`public.varrer_capas_orfas()` cobre isso. Enfileira todo objeto do bucket sem
linha em `fotos_capa` e sem linha na fila, e **ignora objetos com menos de uma
hora** — essa carência é o que impede a varredura de apagar um envio em
andamento. Migration `20260810160000_varredura_capas_orfas.sql`.

**Dois gatilhos, pelo mesmo motivo da drenagem.** O `pg_cron` acorda a varredura
de hora em hora, e `drenar_capas_a_remover()` — que o app chama a cada remoção e
a cada troca de capa — varre **antes** de olhar a fila
(`20260810170000_varredura_segundo_gatilho.sql`). O "antes" é o detalhe: a
drenagem sai cedo quando a fila está vazia, e fila vazia é justamente o estado
do arquivo que nunca teve linha. Com o cron de pé, o pior caso é ~2 horas
(1 de carência + 1 de espera); com o projeto pausado no plano gratuito, quem
acorda o banco é quem usa o app, e a varredura vai junto. **SC-010 declara o
prazo: no máximo 24 horas.**

Para ver o que ela veria, sem esperar a hora cheia:

```sql
select count(*) from storage.objects o
where o.bucket_id = 'fotos-capa'
  and o.created_at < now() - interval '1 hour'
  and not exists (select 1 from public.fotos_capa f where f.caminho = o.name)
  and not exists (select 1 from public.capas_a_remover q where q.caminho = o.name);
```

Zero é o esperado. Diferente de zero **fora** do horário da varredura quer dizer
que envios estão falhando no meio — vale olhar antes de simplesmente varrer.

**E esta é a consulta que confere o prazo declarado.** A de cima responde "o que
a varredura enfileiraria agora", que é diagnóstico. SC-010 promete outra coisa —
*arquivo sem nenhum registro que o referencie deixa de existir em no máximo 24
horas* —, e promessa que ninguém consegue conferir não vale nada:

```sql
select count(*) from storage.objects o
where o.bucket_id = 'fotos-capa'
  and o.created_at < now() - interval '24 hours'
  and not exists (select 1 from public.fotos_capa f where f.caminho = o.name)
  and not exists (select 1 from public.capas_a_remover q where q.caminho = o.name);
```

Aqui zero é o esperado **sempre**, sem ressalva de horário: qualquer resultado
diferente de zero é o prazo de SC-010 estourado, e quer dizer que nem o cron nem
o app acordaram a varredura em 24 horas — projeto pausado por mais de um dia, ou
a varredura quebrada.

Linhas já drenadas **não são expurgadas**, por decisão registrada na migration
`20260810150000_fila_capas_retencao.sql`: o volume é desprezível, o índice de
pendentes é parcial (crescimento não afeta esta consulta) e não há dado pessoal
nos caminhos.

**Uma limitação conhecida, que não é defeito**: `pg_cron` roda dentro do
Postgres, e projeto no plano gratuito é pausado depois de uma semana sem
atividade — com o banco pausado, o cron para junto. Por isso o app também pede a
drenagem depois de remover ou trocar uma capa: quem acorda o banco é quem usa o
app.

**Verificação ponta a ponta** (local, com a Edge Function de pé):
`specs/013-foto-de-capa/scripts/verificar-drenagem.sh`. Executada em 2026-08-10:
objeto no bucket **1 → 0**, `removido_em` preenchido em **1 segundo**, nenhuma
tentativa com erro.

---

## 4. Backup

**A decisão sobre backup existe, está fechada e assinada, e não mora aqui.** Ela
está em `REVISAO-JURIDICA.md`, que não é versionado — é levantamento de risco
interno, e publicá-lo seria entregar o mapa de onde ainda não se cumpre (ver o
comentário no `.gitignore`).

O que fica dito aqui, porque é requisito de provisionamento e não risco: **se um
dia existir cópia de segurança, a região dela é verificada com o mesmo rigor da
seção 1, e ela precisa de prazo de expiração automática escrito.** O motivo é a
Política: a feature 009 anonimiza o banco vivo e não alcança cópia nenhuma, logo
**prazo de retenção do backup é prazo de retenção do dado de quem pediu
exclusão**.
