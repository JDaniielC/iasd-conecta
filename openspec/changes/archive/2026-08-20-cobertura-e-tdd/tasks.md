## 1. Emenda à constituição e o operacional

- [x] 1.1 Reescrever o Princípio IV de `.specify/memory/constitution.md` para
      teste-primeiro, mantendo a lista de regras de domínio que ele já enumera
      (fila de espera, desempate por sorteio, revogabilidade, descarte,
      composição de Dupla Missionária) e acrescentando: o teste do comportamento
      novo ou alterado DEVE existir e falhar antes do código; o vermelho DEVE
      ser pelo motivo do requisito; exceções declaradas (texto de tela,
      tradução de identificador, movimentação sem efeito observável).
- [x] 1.2 Atualizar o Sync Impact Report no topo do mesmo arquivo: versão
      1.1.0 → 1.2.0 (MINOR, expansão material do Princípio IV), o que mudou,
      e o resultado da conferência da task 1.3. Atualizar o rodapé
      `**Version**` e `**Last Amended**` para 2026-08-20.
- [x] 1.3 Conferir, um por um, se `.specify/templates/plan-template.md`,
      `spec-template.md` e `tasks-template.md` continuam consistentes com o
      Princípio IV reescrito — a seção Governance exige isso em toda emenda.
      Registrar no Sync Impact Report o veredito de cada um (✅ sem edição, ou
      o que foi editado).
- [x] 1.4 Escrever a seção de fluxo TDD no `CLAUDE.md`, com: o ciclo
      vermelho-verde e a exigência de conferir a mensagem da falha; que em
      escrita do cliente contra o Supabase o vermelho de recusa de RLS é
      `affectedRows == 0` e não exceção (ligando à seção "Recusa de RLS é
      ausência, não erro" que já existe); que cobertura retroativa de código
      existente não é comportamento novo e por isso nasce verde; e que teste de
      widget sem asserção sobre o que a pessoa vê não conta como teste, mesmo
      que o lcov concorde.
- [x] 1.5 **Verificar e commitar a frente**: `flutter analyze` com 0 issues,
      `flutter test test/unit test/widget` com a contagem atual (469 no momento
      da proposta) ainda verde. Números reais no corpo do commit.

## 2. Script de resumo de cobertura (teste primeiro — Decisão 1)

- [x] 2.1 Escrever `test/unit/coverage_summary_test.dart` **antes** do script,
      com lcov sintético em memória, cobrindo: soma de `DA:` com hit e sem hit;
      exclusão por prefixo de caminho; percentual sobre o denominador já
      excluído; veredito acima, igual e abaixo do piso; `lcov.info` ausente;
      linha malformada no meio do arquivo. Rodar e confirmar que falha por
      asserção do requisito, não por compilação (registrar a mensagem).
- [x] 2.2 Escrever `scripts/coverage_summary.dart` até os testes de 2.1
      passarem. Ele lê `coverage/lcov.info`, aplica as exclusões, imprime
      `cobertas/total = X,X%` mais o piso, e sai 1 se ficar abaixo.
- [x] 2.3 Rodar `dart run scripts/coverage_summary.dart` contra o
      `coverage/lcov.info` da árvore atual e conferir que o número bate com o
      medido à mão na proposta (2980/4131 = 72,1% para o denominador sem
      `data/`). Divergência aqui é defeito do script, não do lcov.
- [x] 2.4 **Verificar e commitar a frente**: contagem de teste de unidade nova,
      `flutter analyze` 0 issues, e o número que 2.3 imprimiu.

## 3. Alvo `make coverage` e o gate no CI

- [x] 3.1 Adicionar o alvo `coverage` ao `Makefile`: roda
      `flutter test --coverage test/unit test/widget`, **aborta se ele sair
      diferente de 0** (Decisão 3), e só então chama
      `dart run scripts/coverage_summary.dart`.
- [x] 3.2 Escrever, em comentário no alvo, as exclusões e o motivo de cada uma
      (`lib/features/*/data/` provado pela integração; `lib/main.dart`
      bootstrap), e por que `chat_limits.dart` e `legal_metadata.dart`
      deliberadamente **não** são excluídos.
- [x] 3.3 Declarar `COVERAGE_FLOOR` no `Makefile` com o comentário da Decisão 2
      (data da medição, sobe quando sobe, baixar exige motivo no commit).
      Travar provisoriamente no número medido hoje; o valor final entra na
      task 5.2.
- [x] 3.4 Provar as duas direções do gate à mão: rodar com o piso no número
      medido (deve sair 0) e rodar com o piso um ponto acima (deve sair 1 e
      imprimir medido e piso). Registrar as duas saídas.
- [x] 3.5 Acrescentar `make coverage` ao job `fast` de
      `.github/workflows/ci.yml`, depois de `flutter analyze`. O passo
      `flutter test test/unit test/widget` que já existe sai — `make coverage`
      roda a mesma suíte e rodá-la duas vezes só dobra o tempo do job.
- [x] 3.6 **Verificar e commitar a frente**: as duas saídas de 3.4 no corpo do
      commit.

## 4. Cobertura das páginas em ~0%

Cada arquivo abaixo é um teste de widget novo em `test/widget/`. Regra que vale
para todos: asserção sobre o que a pessoa vê na tela (texto, estado do botão,
mensagem de erro), nunca só `pumpWidget`. Nome de arquivo de teste é a exceção
declarada da fronteira de idioma; identificador Dart dentro dele é inglês.

Ordem: primeiro o que o Princípio IV chama de inegociável.

- [x] 4.1 `voting_round_detail_page` (0/66) — inclusive o caminho de falha:
      votar quando a Rodada já fechou, e revogar voto.
- [x] 4.2 `create_voting_round_page` (0/44) — inclusive recusa de criação
      inválida e o que a tela mostra quando a escrita falha.
- [x] 4.3 `voting_round_list_page` (0/24).
- [x] 4.4 `declare_leadership_page` (0/40) — inclusive FR-002, que exige Conta
      e não só Perfil. (A tarefa dizia "composição de Dupla Missionária"; era
      erro de planejamento — Dupla Missionária é regra de Ação, e esta tela não
      a toca.)
- [x] 4.5 `pending_declarations_page` (2/51) — aprovar e recusar, e o que a
      tela mostra quando a escrita não alcança linha nenhuma.
- [x] 4.6 **Verificar e commitar a frente** (Rodada de votação e liderança):
      contagem de teste antes e depois, e o número de `make coverage`.
- [x] 4.7 `create_group_page` (1/74) — inclusive validação de campo e falha de
      rede.
- [x] 4.8 `manage_suggested_actions_page` (1/67).
- [x] 4.9 `archived_groups_page` (1/38).
- [x] 4.10 `promote_admin_page` (1/36) — inclusive o caminho em que a promoção
      é recusada.
- [x] 4.11 `login_page` (1/36).
- [x] 4.12 Teste que importa `lib/features/chat/domain/chat_limits.dart` e
      `lib/features/legal/legal_metadata.dart`, afirmando os valores que a
      regra usa — hoje nenhum teste os importa, e por isso eles nem aparecem no
      lcov (Decisão 4).
- [x] 4.13 **Verificar e commitar a frente** (páginas restantes): contagem de
      teste antes e depois, e o número de `make coverage`.

## 5. Fechamento

- [x] 5.1 Se algum teste da seção 4 revelar defeito de comportamento: **não
      consertar aqui**. Registrar em `PENDENCIAS.md` com arquivo:linha e o que
      se observou, e deixar o teste cobrindo o que está correto. Se nada
      aparecer, escrever isso explicitamente no relatório.
- [x] 5.2 Travar `COVERAGE_FLOOR` no número final medido, e conferir contra o
      alvo da proposta (≥ 85% no denominador sem `data/`). Se ficar abaixo,
      dizer no relatório qual página segurou o número e por quê — não baixar o
      alvo em silêncio.
- [x] 5.3 Gate final completo, com os números: `flutter analyze` (issues),
      `flutter test test/unit test/widget` (contagem), `make coverage`
      (percentual e piso), `dart test test/integration` (contagem, com Supabase
      local de pé) — a integração precisa continuar verde porque a seção 1
      mexeu em documento, não em código, e a seção 4 não deveria tocá-la.
- [x] 5.4 `openspec validate --changes cobertura-e-tdd` sem `--strict` (o
      `--strict` reprova por RFC 2119 em todo change deste repo, que escreve
      DEVE/NÃO DEVE em português).

## Convergence 1

- [x] C1.1 **CRITICAL** — `SuggestedActionRepository.delete`
      (`lib/features/suggested_action/data/suggested_action_repository.dart:50`)
      manda `.delete().eq('id', id)` **sem `.select()`**, e por isso reporta
      sucesso sobre zero linhas. Medido em 2026-08-20 contra o Postgres local,
      sob o papel `authenticated` que o app realmente usa, com um `sub` que não
      está em `administradores_distrito`:

      ```
      DELETE 0
      ainda_existe = 1
      ```

      Sem exceção. A policy `acoes_sugeridas_delete_admin` recusa fazendo a
      linha não existir para aquela sessão — é a regra do `CLAUDE.md`, seção
      "Recusa de RLS é ausência, não erro". A tela chama
      `ref.invalidate(allSuggestedActionsProvider)`, a lista recarrega, a
      sugestão continua lá, e quem tocou na lixeira não vê erro nenhum.

      **Isto contradiz a requirement "O vermelho prova o que o teste diz
      provar" desta própria change**: o teste
      `test/widget/acoes_sugeridas_page_test.dart`, caso "remoção recusada
      avisa e a sugestão continua na lista", faz o mock lançar `StateError` e
      afirma o aviso na tela. Em produção esse aviso nunca aparece, porque o
      repositório nunca lança. O teste passa pelo motivo errado.

      Conserto: `.select()` no `delete`, `throw StateError` quando vier vazio, e
      a asserção do teste de integração correspondente contando linhas
      afetadas — não `throwsA`. (`contradicts`)

- [x] C1.2 **HIGH** — a lista de exceções do teste-primeiro diverge entre a
      delta spec e a constituição, e a delta spec diz **"e são só estas"**.

      `specs/disciplina-de-teste/spec.md`, requirement "O teste é escrito antes
      do código que ele prova": três exceções — texto de tela, tradução de
      identificador, movimentação de código.

      `.specify/memory/constitution.md` Princípio IV e `CLAUDE.md`: quatro — as
      três acima **mais cobertura retroativa de código que já existe**.

      A quarta não é detalhe: é a exceção sob a qual os dez arquivos de teste
      da frente 4 foram escritos. Do jeito que está, a spec que esta change
      publica proíbe o que a change fez. Acrescentar a quarta exceção à delta
      spec, com a mesma redação da constituição. (`contradicts`)

- [x] C1.3 **MEDIUM** — `lib/main.dart` está excluído do denominador e não é
      coberto por suíte nenhuma, o que o cenário "Código sem teste em nenhuma
      suíte" da requirement "O denominador da cobertura é declarado" diz
      explicitamente que **não é aceito**.

      Na prática a exclusão não muda o número: `main.dart` nem aparece no
      `lcov.info`, porque nenhum teste o importa. É exclusão morta que só serve
      para contradizer a própria spec. Remover `_bootstrap` de
      `scripts/coverage_summary.dart` (e o teste de unidade correspondente, e a
      menção no comentário do `Makefile` e do `CLAUDE.md`), deixando
      `lib/features/*/data/` como a única exclusão — essa sim satisfaz o
      cenário, porque a integração prova aquela camada. (`contradicts`)

- [x] C1.4 **MEDIUM** — registrar em `PENDENCIAS.md` a classe que o C1.1
      revelou, com o número medido: **das 20 escritas `update`/`delete` que o
      cliente manda ao Supabase, 13 não conferem linhas afetadas.**

      ```
      action_repository.dart:93,112      group_repository.dart:140,197,206,216
      cover_photo_repository.dart:198    image_report_repository.dart:82,88
      district_admin_repository.dart:42  notification_repository.dart:90
      profile_repository.dart:50         suggested_action_repository.dart:50
      ```

      Só a última está no alcance desta change (é a que um teste desta change
      afirma erradamente). As outras 12 são varredura de risco próprio — cada
      uma precisa saber o que a tela deve dizer quando a recusa acontecer — e
      viram change própria. Aqui é só o registro do achado, com data e
      contagem, para não se perder. (`missing`)

## Convergence 2

- [x] C2.1 **MEDIUM** — o motivo escrito da exclusão dizia que a camada
      `lib/features/*/data/` é provada por `dart test test/integration`, e para
      um arquivo isso é falso: `action/data/actions_seen_repository.dart` cai no
      padrão mas não fala com o Supabase — é SharedPreferences, provado por
      `test/unit/actions_seen_repository_test.dart`, que roda DENTRO desta
      medição. O padrão descarta linhas que estão cobertas, então o número sai
      levemente menor que a realidade.

      A requirement "O denominador da cobertura é declarado" exige que o motivo
      diga **onde aquele código é provado**; dizer "integração" para um arquivo
      provado por unidade não cumpre. Corrigido no comentário do `Makefile` e no
      `CLAUDE.md`, sem estreitar o padrão: errar para baixo é o lado certo de
      errar num piso, e recortar a regex para salvar um arquivo de 20 linhas
      custaria mais do que rende. (`partial`)
