## Context

Ver `proposal.md` — Why, para os números medidos e as quatro pendências.

Restrições que moldam a solução:

- A regra de conferir linhas afetadas já está escrita no `CLAUDE.md` desde a
  change `chat-de-grupo-e-acao`, que pagou três achados por ela. O que falta não
  é a regra — é aplicá-la onde ainda não foi.
- **`ProfileGuard.requireProfile` é síncrono e retorna `bool`**, e sete pontos
  de chamada dependem disso. Quatro deles são `if (...) return;` no começo de um
  método; três são dentro de `onPressed` de um botão.
- A suíte de integração fala com `package:postgres` direto, não com
  `supabase_flutter` — que arrasta o Flutter e não roda em `dart test`. Testes
  que precisam do PostgREST usam `package:supabase`, com precedente em
  `chat_fixada_api_test.dart`.
- `administradores_distrito` é estado global, e `excluir_minha_conta` transfere
  Grupo para o Administrador **mais antigo**. Um Administrador vivo num arquivo
  de teste vira herdeiro dos Grupos de `account_deletion_test` — medido em
  2026-08-20, quatro casos derrubados, duas vezes.
- `make coverage` é o gate e não pode ficar mais lento nem depender de Docker.

## Goals / Non-Goals

**Goals:**

- Nenhuma tela do app afirma que uma escrita aconteceu sem ter conferido.
- O gate de largura existe para toda tela, não só para as dez de
  `cobertura-e-tdd`.
- O projeto passa a ter um número de cobertura verdadeiro, medido pelo menos uma
  vez, sem exclusão de caminho.

**Non-Goals:**

- `PENDENCIAS.md` § 2.34, a variação de 0,24pp na cobertura. Fica aberta.
- Mudar qualquer policy, trigger ou função do banco. O banco já se comporta
  certo em todos os 12 casos; quem mente é o cliente.
- Subir `COVERAGE_FLOOR` por causa da medição completa. São números de
  denominadores diferentes e não se comparam.
- Redesenhar a tela de Ação para o caso de desistência recusada. A frase muda; o
  fluxo, não.

## Decisions

### Decisão 1: os 12 sites, classificados um a um, e a classificação é a entrega

A leitura dos 12 produziu uma regra que não estava escrita em lugar nenhum:
**zero linhas é legítimo quando o filtro já carrega a condição que a escrita vai
mudar, ou quando a operação remove o próprio vínculo de quem chamou.**

| escrita | zero significa | decisão |
|---|---|---|
| `action_repository.cancelAction` | recusa | lança |
| `cover_photo_repository.remove` | recusa | lança |
| `district_admin_repository.archiveChurch` | recusa | lança |
| `group_repository.updateGroup` | recusa | lança |
| `group_repository.removeMember` | recusa | lança |
| `group_repository.transferOwnership` | recusa | lança |
| `image_report_repository.resolveByRemovingImage` | recusa | lança |
| `profile_repository.updateMyProfile` | recusa ou Perfil inexistente | lança |
| `action_repository.withdraw` | **ambíguo** | lança, ver Decisão 2 |
| `group_repository.leave` | já não participa | não lança, motivo escrito |
| `image_report_repository.dismiss` | já resolvida | não lança, motivo escrito |
| `notification_repository.markRead` | já lidas | não lança, motivo escrito |

Alternativa recusada: **`.select()` nas 12 com `StateError` genérico**. Produz
doze telas com a mesma frase inútil, e transforma `markRead` repetido — que é
comportamento normal, acontece toda vez que a tela reabre — em erro visível. A
regra existe para separar recusa de repetição, e um patch uniforme apaga
justamente essa separação.

Alternativa recusada: **deixar as três seguras sem comentário**. Elas ficariam
indistinguíveis das doze de antes, e a próxima varredura as levantaria de novo.
O comentário é o que encerra o achado.

### Decisão 2: `withdraw` pergunta ao banco qual das duas causas foi

`confirmacoes_acao_delete_self` recusa quando `public.acao_encerrada(acao_id)`.
Zero linhas tem duas origens opostas, e a diferença importa para a pessoa: numa
ela não precisava fazer nada, na outra **continua contando como presente num
encontro que já aconteceu**.

Quando o `delete` volta vazio, `withdraw` lê o estado e decide:

- Ação encerrada → lança com a frase de encerramento; a tela diz que a presença
  continua registrada.
- Ação aberta → não lança; a pessoa não estava confirmada, e o estado que a tela
  recarrega já mostra isso.

Alternativas recusadas:

- **Conferir `acao_encerrada` ANTES do `delete`.** Duas viagens no caminho
  feliz, para um caso que quase nunca acontece — e ainda haveria a corrida entre
  a checagem e a escrita. A leitura extra só acontece quando o `delete` já
  falhou.
- **Deixar `withdraw` sem lançar, como `leave`.** É o que existe hoje, e é o
  defeito: a pessoa acha que saiu.
- **Uma RPC `desistir_da_acao` que devolva o motivo.** Resolve melhor, e é
  migration nova numa change que não toca o banco de propósito. Fica registrado
  como o caminho se este voltar a incomodar.

### Decisão 3: `ProfileGuard` vira assíncrono, e o `context` atravessa um await

`requireProfile` passa a `Future<bool>` e lê com `ref.read(hasProfileProvider
.future)` — o padrão que `report_image_sheet.dart:62` já usa neste repo.

Isso põe um `await` antes do `context.push('/cadastro')`, então o guard passa a
checar `context.mounted` depois de esperar. Sem isso o `flutter analyze`
reprova, e com razão: a tela pode ter saído durante a espera.

Os sete pontos de chamada acompanham. Quatro são `if (!...) return;` no começo
de um método já assíncrono — viram `if (!await ...) return;`. Três estão em
`onPressed`, que é `void Function()`; viram `onPressed: () async { ... }`.

Alternativa recusada: **manter o síncrono e fazer `app.dart` garantir o
aquecimento por contrato**, com comentário nos dois lados. Mais barato, e é
exatamente o que já existe — a correção continuaria morando em outro arquivo, e
a próxima pessoa que mexer no router não tem como saber. A requirement "Decisão
sobre resposta que ainda não chegou é explícita" recusa isso por escrito.

Alternativa recusada: **`hasProfileProvider` virar `Provider<bool>` síncrono com
valor semeado no arranque.** Empurra o problema para o arranque e cria uma janela
em que o valor semeado está velho depois de um login.

### Decisão 4: a varredura de largura é um arquivo só, dirigido por lista

Um `test/widget/largura_de_celular_test.dart` que monta cada tela a 360 e afirma
apenas que ela renderiza sem estouro. Não substitui teste de comportamento —
prova uma coisa só, para todas.

Alternativa recusada: **acrescentar a asserção de largura em cada arquivo de
teste existente**. Espalha a mesma verificação por ~25 arquivos, e a tela que
não tem arquivo nenhum continua sem julgamento — que é exatamente o buraco.

Consequência aceita: cada tela precisa dos seus provedores fingidos para montar,
e a lista vira o lugar onde isso mora. Telas que exigem montagem cara demais
ficam de fora **com o nome escrito na lista e o motivo**, nunca em silêncio.

### Decisão 5: `make coverage-full` é um alvo separado, e não roda no CI

Sobe o Supabase local se preciso, roda `flutter test --coverage test/unit
test/widget` e `dart test test/integration --coverage`, funde os dois `lcov` e
reporta sobre **todo** o `lib/`, sem exclusão.

`scripts/coverage_summary.dart` ganha `--no-exclusions` em vez de um script
segundo — o parser, o formato e os testes são os mesmos, e duplicá-los é como as
duas metades passam a divergir.

Fora do `ci.yml` de propósito: o gate rápido não sobe banco. A medição completa
é para rodar de vez em quando e registrar o número, não para reprovar PR.

Alternativa recusada: **acrescentar cobertura ao job `integration` que já existe
no CI**. O job já sobe Supabase, então seria barato — mas aí o número completo
vira gate, e um gate sobre um número que ninguém mediu ainda é como se começa a
baixar piso para fazer PR passar.

## Risks / Trade-offs

- **[Nove métodos passam a lançar onde antes retornavam]** — uma tela que não
  trate a exceção passa a mostrar erro não tratado. → Mitigação: conferir os
  chamadores de cada um dos nove antes de mudar, e o teste de widget de cada tela
  afetada cobre o caminho de recusa. As telas das dez de `cobertura-e-tdd` já
  tratam.
- **[`ProfileGuard` assíncrono muda sete pontos de chamada]** — é a mudança de
  maior alcance da change, e `onPressed` assíncrono abre janela para toque duplo.
  → Mitigação: a janela já existia (o `push` era síncrono, mas a navegação não);
  o que muda é o tamanho. Não se acrescenta trava de duplo toque aqui — seria
  escopo novo, e o sintoma nunca foi relatado. Fica dito.
- **[A varredura de largura pode achar muitos estouros de uma vez]** → Mitigação:
  a change conserta os que achar. Se o volume passar do razoável, a lista de
  telas é a unidade de corte — o achado fica registrado em `PENDENCIAS.md` com a
  contagem, e o teste da tela não consertada entra listado como fora, com motivo.
  Nunca em silêncio.
- **[O número completo vai ser feio]** — `lib/main.dart` e 695 linhas de `data/`
  entram no denominador. → Mitigação aceita: é o ponto. Um número honesto e baixo
  informa mais que um número alto sobre um recorte. Ele não vira gate e não mexe
  no piso.
- **[Fundir dois `lcov` de runners diferentes]** — `flutter test` e `dart test`
  produzem `lcov` com o mesmo formato mas caminhos possivelmente diferentes. →
  Mitigação: normalizar caminho na fusão, e o teste de unidade do script cobre
  o caso de o mesmo arquivo aparecer nos dois com contagens diferentes.

## Open Questions

- `dart test --coverage` emite formato JSON do pacote `coverage`, não `lcov`
  direto. Se a conversão exigir `dart pub global activate coverage` — dependência
  global fora do `pubspec.lock`, recusada na change anterior pela Decisão 1 de
  lá — a fusão passa a ser feita pelo próprio `coverage_summary.dart`, que já lê
  formato e sabe somar. A escolha não muda spec, design nem tarefas: muda só o
  meio dentro da tarefa da medição completa.
