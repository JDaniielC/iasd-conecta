## 0. Decisões que bloqueiam a migration

- [x] 0.1 **Decidido com o dono do app, 2026-08-30: 90 dias.** Mesmo prazo de
      `notificacoes`, a única tabela do app com prazo declarado hoje (90 dias
      após lida). Registrado em `REVISAO-JURIDICA.md` — pendente task 6.x
      colocar isso na íntegra, com o custo declarado.
- [x] 0.2 **Decidido, 2026-08-30: 30 dias.** Mesmo número já usado no app
      (mensagem de Ação) — menos uma constante nova pra aprender, ao custo de
      ser mais longo que o estritamente necessário para "os últimos dias".
- [x] 0.3 **Conferido: o `cron.schedule` NÃO existe em produção — e não pode
      existir.** `supabase migration list` mostra produção **15 migrations
      atrás de `main`**, de `20260811120000` até `20260817180000`. A migration
      que cria `expurgar_mensagens_de_acao` e o `cron.schedule`
      (`20260813200000_chat_de_grupo_e_acao.sql`) está nessa lista — nunca foi
      empurrada. `INFRA-PRODUCAO.md` dizia "pode não existir"; hoje é
      "não existe, porque a migration nem chegou lá". Isto vale para TODA
      feature dessas 15 migrations, não só o expurgo — chat, moderação,
      filtro de palavra, mensagem fixada, o endurecimento de RLS de
      `endurecer-grant-update-perfis`. Levado ao dono do app fora desta
      change; não é decisão de retenção e não bloqueia o design daqui.

## 1. Banco — a tabela e o registro

- [x] 1.1 `execucoes_de_faxina(faxina, quando, quantas, disparada_por)`. Sem
      dado pessoal: quando, quanto, qual, e quem disparou
- [x] 1.2 `faxina` como texto e não enum — faxina nova não deve exigir
      `alter type`, e `denuncia-como-registro` já traz a segunda
- [x] 1.3 `registrar_faxina(...)`, `security definer`, chamada pelas funções de
      expurgo
- [x] 1.4 RLS ligada, `grant select` só a `authenticated`, policy com o braço
      de Administrador do distrito e mais nada. Sem policy de escrita — quem
      escreve é a função
- [x] 1.5 `comment on table` dizendo o que a tabela responde e por que
      `disparada_por` existe: sem ela, o app disparando esconde a ausência do
      cron

## 2. Banco — as faxinas passam a se registrar

- [x] 2.1 `expurgar_mensagens_de_acao()` chama o registro **depois** do
      `delete`, dentro de `begin ... exception when others then null end`. A
      ordem e o `exception` são a decisão: a promessa é o descarte
- [x] 2.2 Parâmetro de quem disparou, com padrão, e o `cron.schedule` passando
      o dele explicitamente. **Não inferir por `current_user`** — cron e
      PostgREST podem chegar com o mesmo papel
- [x] 2.3 `expurgar_mudancas()`, com o prazo da tarefa 0.1, registrando-se do
      mesmo jeito
- [x] 2.4 `expurgar_rastro()`, preservando a **última execução de cada faxina**
      — sem ela, a limpeza apaga a informação que a change existe para dar
- [x] 2.5 Agendamento das duas novas no `pg_cron`, e `INFRA-PRODUCAO.md`
      atualizado com o que produção exige à mão

## 3. Prova no banco (test/integration)

- [x] 3.1 Faxina que apaga linhas registra instante, quantidade e faxina
- [x] 3.2 **Faxina que não apaga nada registra execução com zero.** É a metade
      que dá sentido à outra: "rodou e não havia nada" contra "não rodou"
- [x] 3.3 `disparada_por` distingue cron de app — as duas chamadas, dois
      valores
- [x] 3.4 **Registro que falha não desfaz o `delete`.** Provado passando
      `p_disparada_por` fora do CHECK (`'nem-cron-nem-app'`) pela superfície
      pública — quebra o `insert` de verdade, sem precisar revogar nem
      renomear nada, e confere que as linhas vencidas continuam apagadas
- [x] 3.5 Participante comum consultando as execuções recebe zero linhas;
      Administrador recebe as linhas
- [x] 3.6 Sem sessão, a consulta é recusada — `execucoes_de_faxina` entrou na
      lista de `superficie_sem_sessao_test.dart`
- [x] 3.7 Expurgo do rastro apaga o velho e **preserva a última de cada
      faxina**, com contagem antes e depois
- [x] 3.8 `expurgar_mudancas()` apaga o vencido e mantém o recente
- [x] 3.9 O expurgo de mensagens continua apagando exatamente o que apagava —
      o teste de `chat_expurgo_test.dart` estendido, não substituído. Esta
      change não pode mudar o que é apagado

## 4. Dart — tela do Administrador

- [x] 4.1 Limiar de "atrasada" como constante num lugar só, no molde de
      `ChatLimits`, com teste de integração comparando com o agendamento real
- [x] 4.2 Lista das execuções, mais recentes primeiro, por faxina
- [x] 4.3 "Nunca rodou" dito com todas as letras — lista vazia não pode parecer
      que está tudo bem, e no primeiro dia depois da subida é o estado normal
- [x] 4.4 A tela diz "não há registro desde X", e **não** afirma que a faxina
      não rodou: o `exception` do registro torna as duas coisas distintas
- [x] 4.5 Julgar o layout **na largura de celular** — teste de widget a 360px
      comprova sem overflow

## 5. Prova no cliente (test/widget)

- [x] 5.1 Widget: faxina em dia não mostra alerta
- [x] 5.2 Widget: faxina atrasada diz desde quando
- [x] 5.3 Widget: nenhuma execução registrada diz isso, e não desenha lista
      vazia silenciosa

## 6. Legal e ledgers

- [x] 6.1 Política de Privacidade ganhou o prazo de `mudancas` e a versão
      subiu para 1.8 (`LegalMetadata`, `20260830130000_versao_texto_legal_1_8.sql`).
      Texto escrito por mim, sem o agente `advogado-digital` (indisponível
      nesta sessão) — no estilo dos parágrafos vizinhos, conferido linha a
      linha contra o mecanismo antes de seguir
- [x] 6.2 `MAPA-DE-DADOS.md`: o prazo de `mudancas`, e `execucoes_de_faxina`
      declarada **sem dado pessoal**, com o porquê
- [x] 6.3 `REVISAO-JURIDICA.md` § 4-F: fechado o "ainda não feito", com o que
      cada migration/versão aplicou
- [x] 6.4 `INFRA-PRODUCAO.md`: os dois agendamentos novos, os dois números
      esperados, e como conferir pela tela em vez de pelo banco
- [x] 6.5 `PENDENCIAS.md`: 2.17 e 2.10 fechados; registrado que o segundo
      gatilho do app **continua** podendo esconder a ausência do cron — o que
      mudou é que agora dá para ver
- [x] 6.6 Verificação promessa-vs-execução feita por mim, achado por achado
      (agente indisponível nesta sessão). Um achado real, corrigido: o texto
      da tela dizia "pelo próprio app, ao abrir a tela" para as três faxinas,
      mas só `expurgar_mensagens_de_acao` tem esse segundo gatilho de
      verdade — `expurgar_mudancas`/`expurgar_rastro` nunca são chamadas pelo
      cliente. Corrigido para "pelo próprio app", sem prometer um caminho que
      só existe para uma das três
- [x] 6.7 Novidade escrita em `news_item.dart` (2026-08-30): o prazo de 90 dias
      de "Mudanças recentes". A tela de Administrador não virou Novidade,
      como o `CRITERIO-DE-NOVIDADE.md` manda

## 7. Fechamento

- [x] 7.1 Gates com números reais — ver o corpo do commit/relatório final:
      `flutter analyze` 0 issues, `flutter test test/unit test/widget` 638/638,
      `dart test test/integration --concurrency=4` 534/534 (2x, sob o lock,
      sem reset entre as duas), `flutter build web --release` OK
- [x] 7.2 A instrução desta sessão substituiu esta tarefa por
      `openspec validate observador-de-retencao` (sem `--strict`): **válido**,
      sem achado estrutural. A skill `openspec-converge` em si não rodou nesta
      sessão — fica para quem revisar decidir se ainda vale a pena, com o
      trabalho já em `main`
