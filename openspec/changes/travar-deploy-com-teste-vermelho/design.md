## Context

`ci.yml` e `deploy-web.yml` são dois workflows independentes disparados pelo
mesmo evento. Rodam em paralelo, e nada liga o resultado de um ao outro.

## Goals / Non-Goals

**Goals:**
- Ligar a publicação ao resultado dos testes.
- Fechar também a porta manual, que hoje é a única em uso.

**Non-Goals:**
- Mudar o que os testes cobrem.
- Resolver a política do GCP que tornou a publicação manual — é a feature 020.

## Decisions

**`workflow_run` sobre `needs:`.** `needs:` exigiria fundir os dois workflows num
só, o que mistura duas coisas com públicos diferentes: `ci.yml` roda em toda
branch e em todo PR; deploy só interessa em `main`. `workflow_run` mantém os dois
separados e cria a dependência.

**Fechar a porta manual junto, e não depois.** Enquanto a publicação for
`make deploy-web`, travar só o workflow conserta a porta que ninguém usa e deixa
aberta a que todo mundo usa. Como rodar a suíte inteira dentro do `make` é lento,
a forma provável é exigir confirmação explícita — a decisão fica para quem
implementar, com o custo medido.

## Risks / Trade-offs

**Deploy fica mais lento**, porque espera o CI. É o ponto.

**Suíte instável vira bloqueio de deploy.** Isto tem endereço: existe uma falha
intermitente conhecida (`PENDENCIAS.md` § 2.6, e a change
`estabilizar-suite-de-integracao`). Travar o deploy numa suíte que falha 1 em 5
execuções transforma higiene em transtorno — **esta change deveria entrar depois
daquela**, e não antes.
