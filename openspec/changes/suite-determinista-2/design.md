## Context

Ver `proposal.md` — Why. O que vem pronto:

- `acao_restrita_helper.dart` com `asUser`, `asVisitor` e `asAnon` — a
  definição compartilhada, e ela **já está certa**: `asAnon` documenta que os
  claims saem antes de entrar, porque `reset role` não limpa GUC customizado.
- `db_test_helper.dart` com `createTestDistrictAdmin`, que **já toma lock
  consultivo de sessão** sobre `administradores_distrito`, com o comentário que
  explica por quê.
- `chat_helper.dart` e outros helpers por change.
- A capability `suite-de-integracao`, que já proíbe a 49ª cópia.

**O conserto é de varredura, não de invenção.** As três frentes têm solução
conhecida; o que falta é aplicá-la em 48 arquivos sem quebrar nada, e travar
para não voltar.

## Goals / Non-Goals

**Goals:**
- A suíte volta a ser prova: falha intermitente deixa de existir como
  categoria.
- A regra passa a ser conferível por máquina, não por atenção.

**Non-Goals:**
- **Reescrever teste que está certo.** A troca de prefixo e a troca de `asUser`
  são mecânicas; o corpo do teste não muda. Um diff que muda asserção nesta
  change é um erro.
- `concurrency: 1` no `dart_test.yaml`. Já recusado, e continua recusado:
  serializaria a suíte inteira para resolver disputa de poucos arquivos.
- `retry` ou `skip`. Proibidos pela change `estabilizar-suite-de-integracao`,
  com razão — apagam o sinal.
- Unificar os helpers por change (`chat_helper`, `convite_helper`,
  `mudancas_helper`). Eles são de domínio, não de papel, e não estão em causa.

## Decisions

### Prefixo de uid é propriedade do arquivo, e a verificação é a regra

Cada arquivo fica com um prefixo de 8 dígitos hexadecimais que só ele usa. Foi
o que se fez à mão em 2026-08-17 (`cc000000` para
`chat_denuncias_do_grupo_test`), e funcionou.

**O que faz isso durar não é a troca, é a verificação.** Ela é um teste da
própria suíte: varre os arquivos, extrai os identificadores no formato de UUID,
e falha quando um aparece em mais de um arquivo — dizendo quais dois.

Alternativa recusada: gerar o uid a partir do nome do arquivo em tempo de
execução. Resolveria a colisão de vez e tornaria os identificadores ilegíveis
no banco durante um diagnóstico — e diagnosticar com o banco na mão é
exatamente o que se faz quando a suíte falha.

**A verificação mora onde a suíte roda**, não num script que alguém lembra de
chamar. `test/` tem prioridade sobre `Makefile` aqui pela mesma razão de o
`CRITERIO-DE-NOVIDADE.md` morar na raiz: quem viola precisa tropeçar.

### As 48 cópias somem, e a verificação impede a 49ª

A definição compartilhada já existe e já está certa. A troca é mecânica: apagar
a cópia local e importar.

**O risco real é o `tearDown` de cada arquivo**, e é o que fez esta dívida ser
adiada duas vezes: as cópias divergem em mais coisas que o `reset`. A tarefa
manda ler cada uma antes de trocar, e tratar como achado toda diferença que não
seja o `reset` — é bem possível que alguma cópia esconda comportamento que o
arquivo depende.

Alternativa recusada: trocar todas de uma vez com `sed`. As 48 não são
idênticas — 32 fazem uma coisa e 16 fazem outra —, e uma varredura cega
transformaria uma dívida conhecida em defeito novo.

### A eleição de herdeiro toma o mesmo lock que a criação

`createTestDistrictAdmin` já serializa `administradores_distrito` com
`pg_advisory_lock` de sessão. O caso de herdeiro em `account_deletion_test`
lê a mesma tabela e não toma lock nenhum.

O conserto é tomar o mesmo lock, no mesmo lugar em que a contagem importa. Não
é lock novo, é o mesmo — e é por isso que ele funciona: quem já disputa aquele
recurso já está na fila.

**Isto é hipótese medida uma vez, não confirmada por desligamento do culpado**
(`PENDENCIAS.md` 2.7 diz isso com todas as letras). A tarefa manda **confirmar
antes de consertar**: reproduzir com o Administrador do outro arquivo vivo de
propósito. Consertar sem reproduzir é trocar uma falha intermitente por uma
crença.

### A prova é laço, e o número de execuções vem da janela conhecida

A falha de 2.7 apareceu na execução **29 de 30**. Uma prova de 3 execuções não
diz nada sobre uma janela dessas.

O laço é de 30, e o número está escrito porque foi medido — não porque é
redondo. Se alguém reduzir, precisa saber que está reduzindo abaixo da única
janela que este projeto já observou.

## Risks / Trade-offs

**Mexer em 48 arquivos de teste pode quebrar teste por motivo que não é o
dele.** É o risco central, e é o motivo de a dívida ter sobrevivido a duas
changes. → Arquivo a arquivo, com a suíte rodando entre um e outro, e commit
por frente verificada. Nunca `git add -A`.

**A verificação nova pode ficar frágil** — uma regex sobre código-fonte quebra
com formatação. → Ela varre formato de UUID, que é estável, e o que ela produz
quando erra é falso positivo barulhento, não falso negativo silencioso. Falso
positivo alguém conserta; falso negativo é a dívida de volta.

**Trocar prefixo pode deixar lixo no banco de desenvolvimento** — linhas com o
uid antigo que nenhum `tearDownAll` alcança mais. → A tarefa manda limpar o que
sobrar, e `supabase db reset` resolve o resto.

**Confirmar 2.7 pode mostrar que a hipótese está errada.** → Então o achado
muda, e é isso que confirmar serve para descobrir. A tarefa prevê o caso.

## Migration Plan

Não há migration. Nada de banco muda, nada de produção muda.

A ordem importa por risco decrescente: primeiro os uids (mecânico, e é o que já
mordeu), depois o lock de 2.7 (confirmar, então consertar), por último as 48
cópias (a mais longa, e a que mais pede leitura).

Rollback: `git revert`. Nenhum estado persistente é criado.
