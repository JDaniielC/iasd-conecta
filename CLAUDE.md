# Instruções do repositório

## Fluxo de trabalho por change (OpenSpec)

Cada change do OpenSpec vira uma branch própria. Isso existe para a verificação
ficar focada: dá para olhar o diff de um ticket sem o ruído dos outros.

```
/opsx:apply <change>   →  git checkout -b change/<nome-da-change>
                          commits normais na branch
/opsx:archive <change> →  git checkout main
                          git merge --squash change/<nome-da-change>
                          git commit
                          git branch -D change/<nome-da-change>
```

`-D` e não `-d`: o squash não registra ancestralidade, então o `-d` recusa
dizendo que a branch "não está totalmente mesclada". Conferir antes com
`git diff change/<nome> main --stat` — vazio quer dizer que `main` já tem tudo.

- **Uma branch por change**, nomeada `change/<nome-da-change>`.
- **Squash no merge**: a change inteira vira um commit em `main`. O histórico
  detalhado fica na branch até ela ser apagada; o que permanece é o `tasks.md`
  arquivado, que é o registro que se lê depois.
- **Apagar a branch** logo após o merge.
- Trabalho que não é de change (correção pontual, ledger avulso) continua
  direto em `main`.

## Testes de integração

`dart test test/integration` roda os arquivos **em paralelo contra o mesmo
Postgres**. A capability `suite-de-integracao` exige determinismo, e o modo de
quebrar é sempre o mesmo: um arquivo alcança linha ou contagem de outro.

Estado global conhecido: `administradores_distrito`. `excluir_minha_conta`
decide pela contagem de administradores, então dois arquivos com Administrador
vivo ao mesmo tempo se atropelam. `createTestDistrictAdmin` toma um lock
consultivo de sessão por isso — não remover sem ler o comentário lá.

Ao escrever teste novo: escopar tudo por UUID próprio, e nunca apagar por
padrão que outro arquivo possa casar.
