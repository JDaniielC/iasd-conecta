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

Produção **existe** (`.env.prod`, e os secrets `SUPABASE_URL` /
`SUPABASE_PUBLISHABLE_KEY` injetados por `.github/workflows/deploy-web.yml`).
A região que ela de fato usa **ainda não foi lida no painel do fornecedor**.

Enquanto esta tabela tiver `[PENDENTE]`, a afirmação da Política sobre
transferência internacional descreve **uma decisão tomada, não um fato
conferido**. Não preencha por suposição: a feature 019 existe porque essa mesma
afirmação foi repetida em quatro documentos sem que ninguém a tivesse verificado.

| Campo | Valor |
|---|---|
| Região lida no fornecedor | `[PENDENTE]` |
| `project-ref` | `[PENDENTE]` |
| Plano do projeto (Free / Pro / Team / Enterprise) | `[PENDENTE]` |
| Verificado em (AAAA-MM-DD) | `[PENDENTE]` |
| Quem verificou | `[PENDENTE]` |

**Como obter** — um acesso só, dois caminhos:

```bash
supabase login
supabase projects list    # copiar a linha do projeto de produção, INTEIRA
```

ou Dashboard → projeto de produção → Project Settings → General, transcrevendo a
string de região exatamente como aparece. **Print de tela não serve**: não se
versiona nem se pesquisa por `grep`.

Cole a saída literal aqui:

```text
[PENDENTE]
```

### O portão

Se a região lida **não** for brasileira, a primeira providência — antes de
qualquer outra — é corrigir a Política de Privacidade para declarar a
transferência internacional. Enquanto a Política diz que o dado não sai do
Brasil e ele sai, o app afirma algo falso a titulares. Migrar de região é
trabalho separado e maior: na prática, projeto novo e banco em produção movido
com gente usando.

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
