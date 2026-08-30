## 1. As oito escritas de recusa inequívoca

Uma frente. Cada método ganha `.select()`, confere vazio e lança com a frase que
a tela mostra. Teste primeiro em cada caso: o teste de integração que mede
`affectedRows` (nunca `throwsA`), e o teste de widget da tela que exercita a
recusa. Escopar por UUID próprio, conferido contra os prefixos em uso.

- [x] 1.1 Conferir, para cada um dos oito, quem chama e o que a tela faz hoje
      com exceção. Registrar aqui os que NÃO tratam — eles precisam de tratamento
      junto, senão a mudança troca mentira por erro não tratado.

      **Resultado: os oito têm `catch` alcançável. Nenhum vira erro não
      tratado.** `my_profile_page` filtra `on PostgrestException` primeiro, mas
      tem `catch (_)` depois, então o `StateError` cai lá.

      Dois mostram a frase errada para o caso novo, e entram na frente:
      `cover_photo_widget:229` e `pending_reports_page:94` dizem *"Não deu pra
      confirmar... a tela está mostrando o que vale agora"*. Essa frase existe
      para tempo esgotado de rede, onde o cliente de fato **não sabe** se
      aconteceu. Com `.select()` a recusa deixa de ser incerteza: sabemos que
      não aconteceu, e mandar a pessoa "conferir antes de tentar de novo"
      quando a resposta é "você não tem permissão" é desperdiçar a única
      informação que a mudança acabou de ganhar. As duas telas passam a ter um
      braço `on StateError` com frase definitiva.

      Decisão de forma, para os oito: o `StateError` carrega **a mesma frase que
      a tela mostra**. As telas continuam com o `catch` delas — quem lê o log
      vê a frase que a pessoa viu, sem ter que cruzar arquivo.
- [x] 1.2 `ActionRepository.cancelAction` — teste de integração com
      `affectedRows` para quem não é criador nem Administrador, depois o
      `.select()` e a frase.
- [x] 1.3 `CoverPhotoRepository.remove`.
- [x] 1.4 `DistrictAdminRepository.archiveChurch`.
- [x] 1.5 `GroupRepository.updateGroup`.
- [x] 1.6 `GroupRepository.removeMember`.
- [x] 1.7 `GroupRepository.transferOwnership`.
- [x] 1.8 `ImageReportRepository.resolveByRemovingImage`.
- [x] 1.9 `ProfileRepository.updateMyProfile`.
- [x] 1.10 **Verificar e commitar a frente**: `flutter analyze` (issues),
      `make coverage` (percentual e piso), `dart test test/integration`
      (contagem), rodado **duas vezes** — os arquivos novos tocam estado que
      outros arquivos leem, e uma execução não prova determinismo.

## 2. As três em que zero é resultado esperado

- [x] 2.1 `GroupRepository.leave`, `ImageReportRepository.dismiss` e
      `NotificationRepository.markRead` ganham, cada um, o comentário que diz
      por que zero linhas é aceitável ali — a condição está no filtro, ou a
      operação remove o próprio vínculo. Sem esse texto elas voltam na próxima
      varredura.
- [x] 2.2 Teste de integração que prova que zero acontece e É sucesso em pelo
      menos um dos três (`markRead` de linha já lida é o mais barato de montar).
- [x] 2.3 Teste de integração que prova o OUTRO lado do `leave`: o Dono que não
      transferiu é barrado pelo trigger e isso chega como **erro levantado**, não
      como zero linhas. É o que separa "já não participo" de "não posso sair".
- [x] 2.4 **Verificar e commitar a frente**, com os números.

## 3. `withdraw` — o zero ambíguo

- [x] 3.1 Teste de integração medindo as DUAS causas do zero, separadas: quem
      nunca confirmou numa Ação aberta, e quem está confirmada numa Ação
      encerrada. As duas dão `affectedRows == 0` hoje — a asserção é que dão, e
      é isso que justifica a desambiguação.
- [x] 3.2 Teste de widget: a tela de Ação encerrada mostra a frase de
      encerramento e NÃO diz que a desistência foi feita.
- [x] 3.3 Implementar a leitura de estado no caminho vazio, conforme a Decisão 2
      do design — só quando o `delete` volta vazio, nunca antes.
- [x] 3.4 **Verificar e commitar a frente**, com os números.

## 4. `ProfileGuard` espera a resposta

- [x] 4.1 Teste que exercita o guard **sem nenhuma outra parte ter lido
      `hasProfileProvider` antes** — é o estado que hoje decide errado, e o que
      `lib/app.dart:47` esconde. Ele precisa falhar antes da mudança; conferir a
      mensagem da falha.
- [x] 4.2 `requireProfile` vira `Future<bool>`, lendo com
      `ref.read(hasProfileProvider.future)`, com `context.mounted` conferido
      depois do await.
- [x] 4.3 Os sete pontos de chamada: `group_detail_page:29`,
      `group_list_page:121`, `voting_round_list_page:31`,
      `action_detail_page:30`, `voting_round_detail_page:23` e `:83`,
      `action_list_page:117`.
- [x] 4.4 Revisar os testes de widget que hoje usam override **síncrono** de
      `hasProfileProvider` (`rodada_detalhe_page_test`, `rodadas_lista_page_test`
      e os que copiaram o padrão). Com o guard assíncrono o override síncrono
      deixa de ser necessário — e um teste que continua precisando dele é sinal
      de que a mudança não pegou naquele caminho.
- [x] 4.5 **Verificar e commitar a frente**, com os números.

## 5. Largura de celular em toda tela

- [x] 5.1 Listar as telas de `lib/features/*/presentation/` e marcar quais já são
      julgadas a 360 pelos testes existentes. A diferença é o trabalho.

      **Medido: 37 telas, 21 já julgadas a 360, 16 não. E TODAS AS 37 TÊM
      TESTE** — nenhuma está sem arquivo.

- [x] 5.2 **A Decisão 4 do design foi revista aqui, e o motivo é essa medição.**
      Ela previa um `largura_de_celular_test.dart` dirigido por lista, porque
      supunha telas *sem arquivo nenhum*. Como todas têm, a resposta certa é
      mais barata e mais forte: `test/flutter_test_config.dart` fixa 360×800
      como ponto de partida de **todo** teste sob `test/`.

      Assim as telas passam a ser julgadas a 360 em todas as asserções que já
      têm, não só num teste de fumaça — e o próximo arquivo de teste nasce
      julgado sem ninguém lembrar. Um teste que precise de outra largura
      continua podendo mexer no `tester.view` dele.

- [x] 5.3 **Sete estouros, quatro causas, todos consertados.** A varredura a 360
      derrubou 55 testes de uma vez:

      | site | causa |
      |---|---|
      | `cover_photo_widget:285` | `Row` de "Trocar capa" + "Remover capa" com ícone |
      | `my_profile_page:315` | `Row(spaceBetween)` de rótulo + valor; **os dois** podem ser longos |
      | `group_list_page:214,227` | `DropdownButtonFormField` sem `isExpanded` dentro de `Expanded` |
      | `action_list_page:331,343` | idem |
      | `pending_reports_page:196` | `Row` de "Improcedente" + "Remover imagem" |
      | `message_reports_page:221` | `Row` de "Remover mensagem" + "Improcedente" |

      `Expanded` não conserta o dropdown: ele limita a largura externa, e quem
      estoura é o `Row` interno do próprio campo. É a terceira vez que esse
      mesmo engano aparece neste repo.

- [x] 5.3b Retomado depois do merge com `main` (redesenho de navegação e
      visual). O merge trouxe DOIS estouros novos de RenderFlex em
      `home_page.dart` (linhas 103 e 257, herói e `_ConceptCard` — layout
      novo nunca julgado a 360px), consertados com `Flexible` + ellipsis.

      Dos 24 (agora 26, com os dois do merge) testes que falhavam sem
      overflow: **22 eram mesmo scroll** (`delete_account_page_test`,
      `home_page_test`, `router_visitante_test`) — `ensureVisible` antes do
      toque resolveu, sem tocar produção. Depois de consertar os dois
      estouros do merge, `home_page_test` e `router_visitante_test`
      passaram a zero sem precisar de `ensureVisible` (eram os RenderFlex,
      não scroll de verdade).

      **1 era falso-negativo, não scroll nem estouro**:
      `lista_acoes_page_test: "sem o banner de CTA quando já tem Perfil"`.
      `Acampamento` é avulsa — `actionHighlight` já documenta que ela entra
      na faixa de destaque E continua na lista por período, "com ou sem
      Perfil", sempre. As duas aparições sempre existiram; `findsOneWidget`
      mascarava a segunda por ela cair fora do cache do Sliver a 360px
      quando o banner de Perfil ocupa altura acima. Corrigido para
      `findsNWidgets(2)`, com `skipOffstage: false` no caso (`FR-010`) em
      que a segunda aparição fica fora do cache. Nenhum defeito de produto
      escondido aqui — a checagem que a tarefa pedia.

      `novidades`/`perfil` "sem arquivo identificado" da estimativa original
      não existiam mais depois do merge — resolvidos junto dos estouros de
      `home_page.dart`, que era a causa real.
- [x] 5.4 **Verificado e commitado.** `flutter analyze`: 0 issues.
      `test/unit` + `test/widget`: 635/635 (26 vermelhos antes, 0 depois — 2
      estouros de RenderFlex consertados, 23 testes com `ensureVisible`/já
      resolvidos pelo conserto dos estouros, 1 assertion corrigida para o
      comportamento real). Commit `825c5af`.

## 6. A medição completa

- [x] 6.1 `scripts/coverage_summary.dart` ganha `--no-exclusions`, com teste de
      unidade escrito antes: com a bandeira, `lib/features/*/data/` conta.
- [x] 6.2 Fundir os dois `lcov` (unidade/widget e integração). Teste de unidade
      antes, cobrindo o caso do mesmo arquivo aparecer nos dois com contagens
      diferentes — a linha coberta em uma e não na outra conta como coberta.
      Se `dart test --coverage` não der `lcov` direto, resolver dentro do próprio
      script (Open Question do design).

      **Open Question resolvida: `dart test --coverage-path=<arquivo>` dá
      `lcov` direto**, sem passar pelo formato JSON do pacote `coverage` —
      medido rodando um teste de prova (`dart test ... --coverage-path=...`)
      antes de decidir. `mergeLcov` existe mesmo assim, porque concatenar os
      dois textos (sem fundir) faria a mesma linha entrar duas vezes no
      denominador quando o mesmo arquivo aparece nos dois relatórios.

      **Achado ao montar o teste de prova**: `flutter test --coverage` grava
      `SF:` relativo (`lib/app.dart`); `dart test --coverage-path` grava o
      caminho ABSOLUTO do arquivo neste disco. Sem normalizar (`normalizePath`)
      os dois formatos, o mesmo arquivo viraria duas chaves na fusão, e a
      exclusão por prefixo nunca bateria no caminho absoluto.
- [x] 6.3 Alvo `make coverage-full` no `Makefile`, com o comentário dizendo que
      ele NÃO é gate, por que não entra no `ci.yml`, e que o número dele não se
      compara com `COVERAGE_FLOOR` — denominadores diferentes.
- [x] 6.4 Rodar e **registrar o número real do projeto** no corpo do commit e em
      `PENDENCIAS.md`. É a primeira vez que ele existe.

      **3845/5174 = 74,3%** (`PENDENCIAS.md` § 2.33, medido 2026-08-30). Achado
      ao medir, não hipótese: o `lcov` de `dart test test/integration` só
      instrumenta 3 arquivos de domínio (`message.dart`, `send_refusal.dart`,
      `profile.dart`) — NENHUM de `lib/features/*/data/`. A suíte de
      integração fala com o Postgres direto (`package:postgres`/
      `package:supabase`), sem executar as classes `*Repository`, que usam
      `supabase_flutter` e não carregam sob `dart test`. Ela prova o contrato
      (RLS, trigger), não a linha. O `hit` subiu só 3824→3845 (+21, a exceção
      de `actions_seen_repository.dart`) apesar do denominador ganhar 730
      linhas — a camada de dados continua, na prática, sem cobertura de linha
      nenhuma suíte.
- [x] 6.5 `CLAUDE.md`: os dois comandos, o que cada número significa, e qual
      deles é o gate.
- [x] 6.6 **Verificar e commitar a frente**, com os dois números lado a lado.

      `flutter analyze`: 0 issues. `test/unit`+`test/widget`: 645/645 (9 testes
      novos de `coverage_summary_test.dart`). `make coverage`: 3824/4444 =
      86,0% (piso 84,5%, PASSOU). `dart test test/integration`: 538/538, duas
      execuções seguidas pós-`db reset` (determinismo). `make coverage-full`:
      3845/5174 = 74,3% (não é gate).

## 7. Fechamento

- [x] 7.1 Fechar § 2.31, § 2.32, § 2.33 e § 2.35 em `PENDENCIAS.md`, cada um com
      o que foi feito e a data. § 2.34 continua aberta — dizer isso
      explicitamente, para não parecer esquecimento.

      Feito. § 2.34 ganhou uma linha explícita dizendo que continua aberta e
      por quê (Non-Goal do design, causa não perseguida nesta change).
- [x] 7.2 Se a frente 1 ou a 5 revelar defeito fora do escopo: registrar em
      `PENDENCIAS.md` com arquivo:linha, não consertar aqui. Se nada aparecer,
      escrever isso no relatório.

      **Nada fora do escopo apareceu nas frentes 1 e 5.** Confirmado relendo o
      código contra `tasks.md`: os 12 achados da frente 1 foram tratados dentro
      dela (8 lançam, 3 documentam zero como sucesso, 1 desambigua); a frente 5
      achou 2 estouros de RenderFlex trazidos pelo merge com `main` e 1
      falso-negativo de asserção (`findsOneWidget` → `findsNWidgets(2)`),
      ambos consertados dentro da própria frente (commit `cb32bb9`). O único
      achado fora do escopo desta change foi de infraestrutura, não de
      produto: o Postgres local compartilhado estava sem a migration
      `20260817160000_mensagem_fixada.sql` aplicada (função
      `expurgar_mensagens_de_acao()` ausente, 2 testes de
      `chat_privilegio_funcao_test.dart` vermelhos) — resolvido com
      `supabase db reset --local` sob o lock, antes de medir `coverage-full`;
      não é dívida do código, não entra em `PENDENCIAS.md`.
- [x] 7.3 Gate final com os números: `flutter analyze`,
      `flutter test test/unit test/widget`, `make coverage`,
      `dart test test/integration` (duas execuções), `make coverage-full`,
      `flutter build web --release`, `openspec validate --changes`.

      `flutter analyze`: 0 issues. `flutter test test/unit test/widget`:
      645/645. `make coverage`: 3823/4444 = 86,0% (piso 84,5% — a variação de
      1 linha contra a execução anterior é a mesma classe da § 2.34, não nova).
      `dart test test/integration`: 538/538, duas execuções seguidas (rodadas
      na verificação da frente 6, sob o lock, pós `supabase db reset`; nenhum
      arquivo de produção mudou desde então, então o número continua valendo).
      `make coverage-full`: 3845/5174 = 74,3%. `flutter build web --release`:
      compilou (`Built build/web`). `openspec validate --changes`: 5 passed,
      0 failed.
- [x] 7.4 Passada de convergência sobre a change, e resolver o que ela achar
      antes de arquivar.

      Reli `proposal.md`, `design.md` e este `tasks.md` contra o código —
      seção a seção, decisão a decisão (as 8 escritas, as 3 de zero-esperado,
      o `withdraw` ambíguo, `ProfileGuard`, a largura a 360, o
      `--no-exclusions`/`mergeLcov`, `coverage-full`). Tudo bate: nenhuma
      decisão do design ficou sem código correspondente, nenhum teste ficou
      sem a asserção que a tarefa pedia (`affectedRows`, nunca `throwsA`, nos
      12 casos de escrita). **Nada ficou para trás.** A change está pronta
      para `openspec archive`.
