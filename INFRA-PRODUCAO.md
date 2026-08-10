# Infraestrutura de produção — região

**Este arquivo é o registro canônico da região.** `README.md`, `.env.example`,
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

## 3. Backup

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
