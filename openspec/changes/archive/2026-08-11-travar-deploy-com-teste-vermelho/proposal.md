## Why

`.github/workflows/deploy-web.yml` dispara em `push: branches: [main]`, sem
`needs:` e sem `workflow_run:`. Ele não depende do `ci.yml` — **um commit que
quebra os testes constrói e publica assim mesmo**.

Hoje o dano é menor do que parece, porque a publicação virou manual
(`make deploy-web`) enquanto a política do GCP bloqueia a chave de conta de
serviço. Mas o workflow já produz o artefato que alguém pode publicar, e quando
o CI voltar a publicar sozinho — que é o plano registrado — a porta fica
escancarada sem ninguém mexer numa linha.

`PENDENCIAS.md` § 2.4, e T031 dentro da feature 020.

## What Changes

O deploy passa a depender do resultado dos testes. Commit com suíte vermelha não
gera artefato publicável e não publica.

## Capabilities

### New Capabilities
- `publicacao-do-site`: quando o app compilado pode ir ao ar, e o que precisa
  estar verdadeiro antes.

## Impact

- `.github/workflows/deploy-web.yml`.
- `specs/020-deploy-gcs-cdn/contracts/deploy-web.yml` — o contrato da 020
  descreve este workflow e precisa acompanhar.
- `Makefile`: decidir se `make deploy-web` também recusa publicar de uma árvore
  com teste vermelho. Hoje ele não roda teste nenhum.
