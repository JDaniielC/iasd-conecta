## 0. Decisões que bloqueiam a migration

- [ ] 0.1 **Prazo de retenção de `mudancas`**, com o dono do app. Não é decisão
      técnica: apagar cedo demais tira o contexto de por que um Grupo mudou.
      A decisão entra em `REVISAO-JURIDICA.md` — o registro é dado pessoal
- [ ] 0.2 **Prazo do próprio rastro.** Recomendação do design: curto, porque a
      pergunta que ele responde é sobre os últimos dias
- [ ] 0.3 Conferir em produção se o `cron.schedule` de
      `expurgar-mensagens-de-acao` existe de verdade. `INFRA-PRODUCAO.md` diz
      que pode não existir, e esta change é o que torna isso visível — mas o
      estado de hoje merece ser sabido antes

## 1. Banco — a tabela e o registro

- [ ] 1.1 `execucoes_de_faxina(faxina, quando, quantas, disparada_por)`. Sem
      dado pessoal: quando, quanto, qual, e quem disparou
- [ ] 1.2 `faxina` como texto e não enum — faxina nova não deve exigir
      `alter type`, e `denuncia-como-registro` já traz a segunda
- [ ] 1.3 `registrar_faxina(...)`, `security definer`, chamada pelas funções de
      expurgo
- [ ] 1.4 RLS ligada, `grant select` só a `authenticated`, policy com o braço
      de Administrador do distrito e mais nada. Sem policy de escrita — quem
      escreve é a função
- [ ] 1.5 `comment on table` dizendo o que a tabela responde e por que
      `disparada_por` existe: sem ela, o app disparando esconde a ausência do
      cron

## 2. Banco — as faxinas passam a se registrar

- [ ] 2.1 `expurgar_mensagens_de_acao()` chama o registro **depois** do
      `delete`, dentro de `begin ... exception when others then null end`. A
      ordem e o `exception` são a decisão: a promessa é o descarte
- [ ] 2.2 Parâmetro de quem disparou, com padrão, e o `cron.schedule` passando
      o dele explicitamente. **Não inferir por `current_user`** — cron e
      PostgREST podem chegar com o mesmo papel
- [ ] 2.3 `expurgar_mudancas()`, com o prazo da tarefa 0.1, registrando-se do
      mesmo jeito
- [ ] 2.4 `expurgar_rastro()`, preservando a **última execução de cada faxina**
      — sem ela, a limpeza apaga a informação que a change existe para dar
- [ ] 2.5 Agendamento das duas novas no `pg_cron`, e `INFRA-PRODUCAO.md`
      atualizado com o que produção exige à mão

## 3. Prova no banco (test/integration)

- [ ] 3.1 Faxina que apaga linhas registra instante, quantidade e faxina
- [ ] 3.2 **Faxina que não apaga nada registra execução com zero.** É a metade
      que dá sentido à outra: "rodou e não havia nada" contra "não rodou"
- [ ] 3.3 `disparada_por` distingue cron de app — as duas chamadas, dois
      valores
- [ ] 3.4 **Registro que falha não desfaz o `delete`.** Provar de verdade:
      quebrar o registro de propósito (revogar, renomear, ou uma linha que
      viole constraint) e conferir que as linhas vencidas continuam apagadas.
      Sem este caso, o `exception` é decoração
- [ ] 3.5 Participante comum consultando as execuções recebe zero linhas;
      Administrador recebe as linhas
- [ ] 3.6 Sem sessão, a consulta é recusada — molde de
      `superficie_sem_sessao_test.dart`
- [ ] 3.7 Expurgo do rastro apaga o velho e **preserva a última de cada
      faxina**, com contagem antes e depois
- [ ] 3.8 `expurgar_mudancas()` apaga o vencido e mantém o recente
- [ ] 3.9 O expurgo de mensagens continua apagando exatamente o que apagava —
      o teste de `chat_expurgo_test.dart` estendido, não substituído. Esta
      change não pode mudar o que é apagado

## 4. Dart — tela do Administrador

- [ ] 4.1 Limiar de "atrasada" como constante num lugar só, no molde de
      `ChatLimits`, com teste de integração comparando com o agendamento real
- [ ] 4.2 Lista das execuções, mais recentes primeiro, por faxina
- [ ] 4.3 "Nunca rodou" dito com todas as letras — lista vazia não pode parecer
      que está tudo bem, e no primeiro dia depois da subida é o estado normal
- [ ] 4.4 A tela diz "não há registro desde X", e **não** afirma que a faxina
      não rodou: o `exception` do registro torna as duas coisas distintas
- [ ] 4.5 Julgar o layout **na largura de celular**

## 5. Prova no cliente (test/widget)

- [ ] 5.1 Widget: faxina em dia não mostra alerta
- [ ] 5.2 Widget: faxina atrasada diz desde quando
- [ ] 5.3 Widget: nenhuma execução registrada diz isso, e não desenha lista
      vazia silenciosa

## 6. Legal e ledgers

- [ ] 6.1 Se `mudancas` ganhou prazo, a Política de Privacidade ganha esse
      prazo e a versão do texto legal sobe. Rodar o agente `advogado-digital`
- [ ] 6.2 `MAPA-DE-DADOS.md`: o prazo de `mudancas`, e a tabela nova declarada
      como **sem dado pessoal**, com o porquê
- [ ] 6.3 `REVISAO-JURIDICA.md`: a decisão de prazo de `mudancas`
- [ ] 6.4 `INFRA-PRODUCAO.md`: os agendamentos novos, e como conferir pela tela
      em vez de pelo banco
- [ ] 6.5 `PENDENCIAS.md`: 2.17 e 2.10 fecham; registrar que o segundo gatilho
      do app **continua** escondendo a ausência do cron — o que mudou é que
      agora dá para ver
- [ ] 6.6 Rodar o agente `promessa-vs-execucao` cruzando o prazo declarado
      contra o que o rastro mostra
- [ ] 6.7 Novidade: só se `mudancas` ganhar prazo — aí é mudança sobre os dados
      dela. A tela de Administrador não vira Novidade pelo
      `CRITERIO-DE-NOVIDADE.md`

## 7. Fechamento

- [ ] 7.1 Gates com números reais: `flutter analyze`, `flutter test test/unit
      test/widget`, `dart test test/integration` com `supabase start`,
      `flutter build web --release`
- [ ] 7.2 Rodar a skill `openspec-converge` e resolver o que ela achar
