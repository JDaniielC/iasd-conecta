## 0. Decisões que bloqueiam a migration

- [ ] 0.1 **Escolher o prazo do motivo depois do desfecho**, com o dono do app.
      Recomendação do design: reusar um número que a Política já usa, para a
      titular não ter de aprender um segundo. Constante nomeada, no molde de
      `mensagem_teto_de_fixadas()`
- [ ] 0.2 **Contar as linhas de `denuncias_imagem` cujo motivo é só quebra de
      linha**, antes de refazer o `check`. Se houver, decidir o que fazer com
      elas — não subir `not valid` em silêncio
- [ ] 0.3 Conferir de novo, com `grep`, que nenhuma tela manda `motivo` ou
      `denunciante_id` num `update`. Medido hoje: `resolveReport` manda só
      `estado` e `resolvida_em`

## 1. Banco — a denúncia não se reescreve

- [ ] 1.1 **Reler `mensagens_so_remove`** antes de escrever o gatilho novo: ele
      é o molde, e o que se copia é a forma, não o `security definer`
- [ ] 1.2 `denuncias_mensagem_so_resolve()`, `before update`, `security
      invoker` — aqui não há contagem a fazer e privilégio que não é necessário
      não se pede. Recusa mudança em `id`, `mensagem_id`, `denunciante_id`,
      `motivo` e `created_at`, uma a uma, com frase que diz o que aconteceu
- [ ] 1.3 O nome importa: gatilhos `before` da mesma tabela disparam em ordem
      ALFABÉTICA, e já existe `denuncias_mensagem_filtro_de_palavra_trigger`.
      Decidir qual roda antes e escrever por quê
- [ ] 1.4 `comment on trigger` dizendo o que os Termos prometem e que este
      gatilho é quem cumpre

## 2. Banco — uma pendente por (mensagem, denunciante)

- [ ] 2.1 Índice único parcial sobre `estado = 'pendente'`
- [ ] 2.2 `comment on index` com o que o design registrou: parcial é o ponto, e
      `mensagem_id` nulo não colide com nulo
- [ ] 2.3 A recusa precisa chegar ao cliente distinguível — código de erro da
      família `PT`, como as três de `filtro-e-intervalo-de-mensagem`, e não
      violação de índice crua

## 3. Banco — prazo e exclusão de conta

- [ ] 3.1 `expurgar_motivos_de_denuncia()`, no molde de
      `expurgar_mensagens_de_acao`: apaga o `motivo` de denúncia **com
      desfecho** passada do prazo. Pendente não expira
- [ ] 3.2 Agendamento no `pg_cron` **e** segundo gatilho no app — um executor
      só não é promessa. Registrar em `INFRA-PRODUCAO.md` o que produção exige
      à mão
- [ ] 3.3 Uma linha em `excluir_minha_conta`, na mesma transação, esvaziando o
      `motivo` de quem é `denunciante_id`. **Sem anular `denunciante_id`** —
      anular quebraria o índice único parcial
- [ ] 3.4 `denuncias_imagem.motivo` passa a `btrim` com a lista explícita

## 4. Prova no banco (test/integration)

- [ ] 4.1 Reescrever `motivo` é recusado — por quem modera, e pelo próprio
      denunciante. Dois casos, e o segundo é o que o teste antigo não tinha
- [ ] 4.2 Trocar `denunciante_id` é recusado. É o achado medido de 2.24, e o
      teste tem de falhar sem o gatilho
- [ ] 4.3 Apontar a denúncia para outra mensagem é recusado; alterar
      `created_at` é recusado
- [ ] 4.4 Resolver a denúncia continua aceito, por quem tem autoridade —
      contraste sem o qual os de cima passariam com a tabela travada inteira
- [ ] 4.5 Segunda pendente da mesma pessoa sobre a mesma mensagem é recusada,
      **com o código de erro** que a tela lê
- [ ] 4.6 Depois do desfecho, a mesma pessoa denuncia de novo e é aceita
- [ ] 4.7 Pessoas DIFERENTES denunciando a mesma mensagem: as duas aceitas
- [ ] 4.8 Denúncias em sequência sobre mensagens diferentes: todas aceitas —
      não há limite de ritmo, e este teste é o que impede alguém acrescentar um
- [ ] 4.9 Expurgo: denúncia julgada passada do prazo perde o `motivo` e mantém
      `estado` e `resolvida_em`, com contagem antes e depois
- [ ] 4.10 Expurgo: denúncia PENDENTE passada do mesmo prazo mantém o motivo
- [ ] 4.11 `excluir_minha_conta` do denunciante esvazia o motivo dele na mesma
      transação, e NÃO esvazia o motivo que outra pessoa escreveu sobre
      mensagem dele
- [ ] 4.12 `denuncias_imagem` recusa motivo feito só de quebras de linha

## 5. Dart — tela

- [ ] 5.1 A recusa de denúncia repetida diz "já está aguardando desfecho", pelo
      código de erro e nunca por texto de mensagem do servidor
- [ ] 5.2 A tela de denúncias mostra o desfecho de caso cujo motivo já expirou
      sem parecer defeito — o registro do ato continua, o texto não
- [ ] 5.3 Prova de widget das duas frases

## 6. Legal e ledgers — bloqueia o fechamento

- [ ] 6.1 Política de Privacidade: o motivo passa a ter prazo e a sair com a
      conta de quem denunciou. Hoje ela declara que ele não expira — manter é
      torná-la falsa. Rodar o agente `advogado-digital`
- [ ] 6.2 Subir a versão do texto legal, pelo critério da 1.6 e da 1.7
- [ ] 6.3 `MAPA-DE-DADOS.md`: o `motivo` ganha prazo e ganha alcance de
      exclusão; as duas linhas mudam
- [ ] 6.4 `REVISAO-JURIDICA.md`: o trade-off de apagar o porquê da remoção, por
      escrito, com o que se conserva e o que se perde
- [ ] 6.5 Rodar o agente `promessa-vs-execucao` cruzando o que os Termos dizem
      sobre o motivo contra o gatilho e o expurgo reais
- [ ] 6.6 `PENDENCIAS.md`: 2.24, 2.23, 2.14 e 2.12 fecham, com os números de
      fechamento
- [ ] 6.7 Novidade em `news_item.dart` pelo `CRITERIO-DE-NOVIDADE.md` — é
      mudança sobre os dados dela: o que ela escreveu ao denunciar passa a ter
      prazo

## 7. Fechamento

- [ ] 7.1 Gates com números reais: `flutter analyze`, `flutter test test/unit
      test/widget`, `dart test test/integration` com `supabase start`,
      `flutter build web --release`
- [ ] 7.2 O commit registra que o rollback **não** devolve motivo já apagado
- [ ] 7.3 Rodar a skill `openspec-converge` e resolver o que ela achar
