## 1. Workflow

- [ ] 1.1 Trocar o gatilho de `deploy-web.yml` para `workflow_run` sobre a
      conclusão bem-sucedida do `ci.yml` em `main`
- [ ] 1.2 Conferir que o `workflow_dispatch` manual continua existindo — é o que
      permite republicar sem commit novo

## 2. Porta manual

- [ ] 2.1 Decidir e implementar o comportamento de `make deploy-web` diante de
      uma árvore não provada: recusar, ou exigir confirmação explícita. Medir
      quanto tempo a suíte inteira custaria dentro do alvo antes de escolher

## 3. Prova

- [ ] 3.1 Num branch de teste, quebrar um teste de propósito, empurrar, e
      verificar que o deploy **não** roda
- [ ] 3.2 Consertar, empurrar, e verificar que roda
- [ ] 3.3 Conferir que a mudança não deixou o deploy dependendo de um workflow
      que não roda em `main`

## 4. Registro

- [ ] 4.1 Atualizar `specs/020-deploy-gcs-cdn/contracts/deploy-web.yml` e a
      seção Deploy do `README.md`, onde a lacuna está escrita hoje
- [ ] 4.2 Fechar `PENDENCIAS.md` § 2.4 e a T031 da 020
