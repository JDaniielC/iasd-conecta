## 1. Workflow

- [x] 1.1 Trocar o gatilho de `deploy-web.yml` para `workflow_run` sobre a
      conclusão bem-sucedida do `ci.yml` em `main`
- [x] 1.2 Conferir que o `workflow_dispatch` manual continua existindo — é o que
      permite republicar sem commit novo

## 2. Porta manual

- [x] 2.1 Decidir e implementar o comportamento de `make deploy-web` diante de
      uma árvore não provada: recusar, ou exigir confirmação explícita. Medir
      quanto tempo a suíte inteira custaria dentro do alvo antes de escolher

## 3. Prova

- [x] 3.1 Num branch de teste, quebrar um teste de propósito, empurrar, e
      verificar que o deploy **não** roda. Commit `7ed3620` direto em `main`
      (branch sem proteção). `CI` (run 31524736507) → `failure` em 4m. `deploy-web`
      (run 31525081800, `workflow_run`) → `skipped` em 1s, sem publicar
- [x] 3.2 Consertar, empurrar, e verificar que roda. Commit `05227e8` — remove o
      teste proposital. `CI` (run 31525536705) → `success`. `deploy-web`
      (run 31525871554) → `success`, job `build` `success`, artifact publicado
- [x] 3.3 Conferir que a mudança não deixou o deploy dependendo de um workflow
      que não roda em `main`. `ci.yml` tem `push: branches: [main]` — confirmado
      por `gh workflow view ci.yml --yaml`, e os dois runs de 3.1/3.2 são prova
      viva de que ele roda lá

## 4. Registro

- [x] 4.1 Atualizar `specs/020-deploy-gcs-cdn/contracts/deploy-web.yml` e a
      seção Deploy do `README.md`, onde a lacuna está escrita hoje
- [x] 4.2 Fechar `PENDENCIAS.md` § 2.4 e a T031 da 020
