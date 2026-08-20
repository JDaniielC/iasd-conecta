## Context

Ver `proposal.md` — Why, para os números medidos e o motivo.

Restrições que moldam a solução:

- **`lcov` e `genhtml` não existem nesta máquina** (`which lcov` → não
  encontrado). Existem no `ubuntu-latest` do CI, mas não no macOS de
  desenvolvimento. Um gate que só roda num dos dois lugares é um gate que se
  descobre quebrado no PR.
- `flutter test --coverage` já produz `coverage/lcov.info` sem dependência
  nenhuma. `coverage/` já está em `.gitignore` (linha 47).
- O `Makefile` deste repo carrega a explicação junto do alvo, em comentário
  longo — ver o cabeçalho de `deploy-web`. Decisão que mora fora do arquivo que
  a executa some.
- `ci.yml` tem três jobs: `fast` (analyze + unit/widget), `integration`
  (Supabase local) e `build-web`. O gate rápido é `fast`.
- A constituição (`Governance`) exige, para emenda: texto exato da mudança,
  Sync Impact Report atualizado no topo, e verificação de que
  `plan-template.md`, `spec-template.md` e `tasks-template.md` continuam
  consistentes.

## Goals / Non-Goals

**Goals:**

- O mesmo comando de cobertura roda igual no macOS de desenvolvimento e no
  `ubuntu-latest` do CI, sem instalar nada além do que o repo já exige.
- O piso é legível por humano, versionado, e com a data da medição.
- A regra de teste-primeiro fica onde os agentes a leem como inegociável
  (constituição), com o operacional onde eles procuram o *como* (`CLAUDE.md`).

**Non-Goals:**

- Trazer `test/integration` para a medição de cobertura. Exigiria ciclo de vida
  do Supabase local dentro do gate rápido — o mesmo motivo já medido e recusado
  em `travar-deploy-com-teste-vermelho` para o alvo `deploy-web`. Fica em
  `PENDENCIAS.md`.
- Cobertura de branch/função. Só linha.
- Relatório HTML navegável. Sai do escopo junto com a dependência de `genhtml`.
- Consertar defeito que um teste novo revele. Se aparecer, vira change própria
  e achado em `PENDENCIAS.md` — misturar conserto de comportamento com adição
  de cobertura torna o diff irrevisável.

## Decisions

### Decisão 1: o resumo do lcov sai de um script no repo, não do binário `lcov`

`scripts/coverage_summary.dart`, rodado com `dart run`, lê
`coverage/lcov.info`, aplica as exclusões e imprime o número e o veredito.

Alternativas recusadas:

- **`brew install lcov` + `lcov --remove` + `lcov --summary`**: obriga cada
  máquina de desenvolvimento a instalar um pacote que só serve para isto, e as
  versões de `lcov` divergem no formato do resumo — o parse do gate quebraria
  entre macOS e Ubuntu sem ninguém mexer no repo.
- **`dart pub global activate coverage`** (`format_coverage`): resolve o parse,
  mas é dependência global fora do `pubspec.lock`, então nada trava a versão e
  o CI e a máquina local podem divergir em silêncio.
- **`awk` inline no `Makefile`**: foi o que mediu os números do `proposal.md` e
  funciona, mas um `awk` de dez linhas dentro de uma receita de `make` — com o
  escape de `$` que `make` exige — não é código que alguém revisa nem testa.
  Sendo Dart, o script é testável pela própria suíte.

Consequência aceita: o script vira código de produção do gate, e por isso ele
mesmo nasce com teste (`test/unit/coverage_summary_test.dart`), escrito antes,
com lcov sintético — inclusive o caso de arquivo malformado e o de
`lcov.info` ausente.

### Decisão 2: o piso é um número no `Makefile`, com data

```
# Piso medido em 2026-08-20 sobre o denominador declarado abaixo.
# Sobe quando a cobertura sobe. Baixar exige motivo no corpo do commit.
COVERAGE_FLOOR := <número no fim desta change>
```

Alternativa recusada: arquivo `coverage_floor.txt` ou entrada em
`pubspec.yaml`. Mais um arquivo para explicar, e separa o número do comentário
que diz o que ele significa — que é justamente o que dá para ler depois.

O piso é **um número só**, sobre o denominador declarado. Piso por camada
(presentation, domain, providers) foi considerado e recusado por Princípio V:
três números para manter, e o modo de falha real que este projeto tem é
"página inteira sem teste nenhum", que um número só já pega.

### Decisão 3: o gate falha o comando inteiro se a suíte estiver vermelha

`make coverage` roda `flutter test --coverage` e só mede se ele sair 0. Suíte
vermelha produz `lcov.info` de execução parcial, cujo percentual não é
comparável com o piso — e é o pior modo de falha possível, porque o número sai
alto (o que não rodou não conta como não coberto) e o gate passa numa árvore
quebrada.

### Decisão 4: a exclusão é por prefixo de caminho, e cada uma carrega o motivo

Fora do denominador:

| caminho | motivo |
|---|---|
| `lib/features/*/data/` | provado por `dart test test/integration`, que não entra nesta medição |
| `lib/main.dart` | bootstrap; não aparece no lcov porque nenhum teste o importa |

`lib/features/chat/domain/chat_limits.dart` e `lib/features/legal/legal_metadata.dart`
também estão hoje fora do lcov por nunca serem importados por teste. Eles
**não** entram na lista de exclusão: são constantes que a regra usa, e o
caminho certo é um teste importá-los, não o gate ignorá-los.

### Decisão 5: os dez arquivos de teste desta change são a exceção declarada da própria regra que ela cria

Teste-primeiro pressupõe que o comportamento ainda não existe. As dez páginas
já existem e já funcionam; o teste que se escreve para elas nasce verde, e
fingir um vermelho ("comento a página, rodo, descomento") seria teatro.

A honestidade aqui importa mais que a simetria: a primeira coisa que a regra
nova faz, se isso não estiver escrito, é ser violada por quem a escreveu. A
requirement "O teste é escrito antes do código que ele prova" fala de
comportamento **novo ou alterado** — cobertura retroativa de código existente
não é nem uma coisa nem outra, e o `CLAUDE.md` diz isso com todas as letras.

O que **não** é exceção: o `scripts/coverage_summary.dart` é código novo, e
segue a regra (Decisão 1).

### Decisão 6: a emenda entra antes dos testes, no mesmo branch

Ordem dos commits: emenda + `CLAUDE.md` → script + gate → os dez arquivos de
teste, um commit por frente verificada. Assim o gate já existe quando os testes
chegam, e cada commit de teste move o número de forma visível no histórico da
branch.

Alternativa recusada: emenda por último, "depois que a cobertura provar que
funciona". Deixaria o commit mais importante da change dependente de a parte
mecânica dar certo.

## Risks / Trade-offs

- **[Piso vira teto]** — a equipe escreve teste até bater o número e para. →
  Mitigação: o piso é chão registrado, não meta; a regra que puxa para cima é
  teste-primeiro no Princípio IV, que é inegociável e não tem número. O gate só
  impede a queda.
- **[Um teste novo revela defeito e a change trava]** → Mitigação: Non-Goal
  explícito. Achado vai para `PENDENCIAS.md`, o teste do comportamento errado
  não entra verde nem entra vermelho — entra a cobertura do que está certo, e o
  defeito vira change própria.
- **[Cobertura de linha mede execução, não verificação]** — um `pumpWidget`
  que não afirma nada sobe o número sem provar coisa alguma. → Mitigação: não
  há gate automático contra isso. É revisão, e está escrito no `CLAUDE.md`:
  teste de widget que não faz asserção sobre o que a pessoa vê não conta como
  teste, mesmo que o lcov concorde.
- **[Emenda de constituição sem conferir os templates]** → Mitigação: task
  explícita, exigida pela seção Governance, com os três arquivos nomeados.
- **[Piso frágil entre versões de Flutter]** — atualização do SDK pode mexer no
  que o lcov instrumenta e derrubar o número sem ninguém mexer em código. →
  Mitigação aceita como risco residual: se acontecer, o gate reprova, alguém
  investiga, e a queda legítima é registrada no commit — que é exatamente o
  comportamento pedido pela requirement.
