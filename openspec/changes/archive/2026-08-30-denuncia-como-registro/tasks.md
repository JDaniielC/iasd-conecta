## 0. Decisões que bloqueiam a migration

- [x] 0.1 **Decidido com o dono do app, 2026-08-30: 30 dias.** Mesmo número
      que a Política já usa (mensagem de Ação, exceção de mensagem fixada) —
      a titular não aprende um segundo prazo. Constante nomeada, no molde de
      `mensagem_teto_de_fixadas()`, entra na migration da tarefa 3.x.
- [ ] 0.2 **Contar as linhas de `denuncias_imagem` cujo motivo é só quebra de
      linha**, antes de refazer o `check`. Se houver, decidir o que fazer com
      elas — não subir `not valid` em silêncio.

      **Não medido ainda**: exige consulta na base de PRODUÇÃO (a instância
      hospedada, `mbfcnebyxzoagwatjxuh.supabase.co`), e esta sessão só tem a
      chave pública do app (`SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` em
      `.env`), sem acesso de Administrador nem `service_role`. Quem tem
      acesso ao painel roda:
      `select count(*) from denuncias_imagem where btrim(motivo, E' \t\n\r') = ''`
      — e decide o que fazer com o que aparecer, antes da migration subir.
- [x] 0.3 Conferido de novo com `grep`: nenhuma tela manda `motivo` ou
      `denunciante_id` num `update`.
      `ChatRepository.resolveReport` (denuncias_mensagem) manda só `estado`
      e `resolvida_em`; `ImageReportRepository.dismiss` (denuncias_imagem)
      manda só `estado` e `resolvida_em` também. Confere com o medido no
      design.

## 1. Banco — a denúncia não se reescreve

- [x] 1.1 **Reler `mensagens_so_remove`** antes de escrever o gatilho novo: ele
      é o molde, e o que se copia é a forma, não o `security definer`
- [x] 1.2 `denuncias_mensagem_so_resolve()`, `before update`, `security
      invoker` — aqui não há contagem a fazer e privilégio que não é necessário
      não se pede. Recusa mudança em `id`, `mensagem_id`, `denunciante_id`,
      `motivo` e `created_at`, uma a uma, com frase que diz o que aconteceu.
      `mensagem_id` e `motivo` precisaram de uma exceção não prevista no design:
      só a transição para NULL é aceita nos dois — `mensagem_id` por causa do
      `on delete set null` do expurgo de mensagem (medido:
      `chat_expurgo_test.dart` quebrava sem a exceção), `motivo` por causa do
      prazo (seção 3) e da exclusão de conta
- [x] 1.3 O nome importa: gatilhos `before` da mesma tabela disparam em ordem
      ALFABÉTICA, e já existe `denuncias_mensagem_filtro_de_palavra_no_update`.
      Decidido: manter a ordem natural (filtro antes, "f" < "s") — depois
      desta migration toda reescrita de motivo é recusada de qualquer forma, e
      qual mensagem de erro vence no cruzamento raro (reescrever justamente
      para uma palavra bloqueada) não muda o resultado. Escrito no comentário
      da migration
- [x] 1.4 `comment on trigger` dizendo o que os Termos prometem e que este
      gatilho é quem cumpre

## 2. Banco — uma pendente por (mensagem, denunciante)

- [x] 2.1 Índice único parcial sobre `estado = 'pendente'`
- [x] 2.2 `comment on index` com o que o design registrou: parcial é o ponto, e
      `mensagem_id` nulo não colide com nulo
- [x] 2.3 A recusa precisa chegar ao cliente distinguível — código de erro da
      família `PT` (`PT423`), como as três de `filtro-e-intervalo-de-mensagem`,
      e não violação de índice crua. Gatilho `before insert`,
      `security definer` (precisa enxergar a pendente já existente mesmo
      quando quem denuncia não tem `select` por RLS); o índice continua sendo
      a garantia atômica contra a corrida rara

## 3. Banco — prazo e exclusão de conta

- [x] 3.1 `expurgar_motivos_de_denuncia()`, no molde de
      `expurgar_mensagens_de_acao`: apaga o `motivo` de denúncia **com
      desfecho** passada do prazo. Pendente não expira
- [x] 3.2 Agendamento no `pg_cron` **e** segundo gatilho no app — um executor
      só não é promessa. Registrado em `INFRA-PRODUCAO.md` o que produção exige
      à mão
- [x] 3.3 Uma linha em `excluir_minha_conta`, na mesma transação, esvaziando o
      `motivo` de quem é `denunciante_id`. **Sem anular `denunciante_id`** —
      anular quebraria o índice único parcial. ACHADO ao escrever: a versão
      vigente de `excluir_minha_conta` não era a de `20260810000000` (que um
      primeiro `grep` sem distinguir maiúscula/minúscula deixou passar) e sim
      a de `20260810130000_capa_cancelamento_e_exclusao.sql` — a `create or
      replace` foi refeita a partir da versão certa, com o bloco de capa
      (FR-024) preservado
- [ ] 3.4 **PULADA — depende de 0.2, que está bloqueada** (exige acesso de
      produção que esta sessão não tem). `denuncias_imagem.motivo` continua
      com `trim`

## 4. Prova no banco (test/integration)

- [x] 4.1 Reescrever `motivo` é recusado — por quem modera, e pelo próprio
      denunciante. Dois casos, e o segundo é o que o teste antigo não tinha.
      `test/integration/chat_denuncia_imutavel_test.dart`
- [x] 4.2 Trocar `denunciante_id` é recusado. É o achado medido de 2.24, e o
      teste falhava sem o gatilho (update afetava 1 linha em vez de lançar)
- [x] 4.3 Apontar a denúncia para outra mensagem é recusado; alterar
      `created_at` é recusado
- [x] 4.4 Resolver a denúncia continua aceito, por quem tem autoridade —
      contraste sem o qual os de cima passariam com a tabela travada inteira
- [x] 4.5 Segunda pendente da mesma pessoa sobre a mesma mensagem é recusada,
      **com o código de erro** que a tela lê.
      `test/integration/chat_denuncia_unica_pendente_test.dart`
- [x] 4.6 Depois do desfecho, a mesma pessoa denuncia de novo e é aceita
- [x] 4.7 Pessoas DIFERENTES denunciando a mesma mensagem: as duas aceitas
- [x] 4.8 Denúncias em sequência sobre mensagens diferentes: todas aceitas —
      não há limite de ritmo, e este teste é o que impede alguém acrescentar um
- [x] 4.9 Expurgo: denúncia julgada passada do prazo perde o `motivo` e mantém
      `estado` e `resolvida_em`, com contagem antes e depois.
      `test/integration/chat_denuncia_expurgo_test.dart`
- [x] 4.10 Expurgo: denúncia PENDENTE passada do mesmo prazo mantém o motivo
- [x] 4.11 `excluir_minha_conta` do denunciante esvazia o motivo dele na mesma
      transação, e NÃO esvazia o motivo que outra pessoa escreveu sobre
      mensagem dele. `test/integration/chat_denuncia_exclusao_conta_test.dart`
- [ ] 4.12 **PULADA — depende de 3.4/0.2**, mesma razão

## 5. Dart — tela

- [x] 5.1 A recusa de denúncia repetida diz "já está aguardando desfecho", pelo
      código de erro (`PT423` → `SendRefusalKind.alreadyPending`) e nunca por
      texto de mensagem do servidor. Não reabre o diálogo de denúncia — a
      causa não é o texto, é `showSnackBar`
- [x] 5.2 A tela de denúncias mostra o desfecho de caso cujo motivo já expirou
      sem parecer defeito — o registro do ato continua (`_stateLine`), o texto
      não (`_reasonLine`, `MessageReport.reason` agora `String?`). Vale para as
      duas listas (do espaço e as órfãs `sem_mensagem`)
- [x] 5.3 Prova de widget das duas frases: `test/widget/conversa_recusa_test.dart`
      (grupo 6.3) e `test/widget/message_reports_page_test.dart` (novo arquivo)

## 6. Legal e ledgers — bloqueia o fechamento

- [x] 6.1 Política de Privacidade: o motivo passa a ter prazo e a sair com a
      conta de quem denunciou. Hoje ela declara que ele não expira — manter é
      torná-la falsa. Sem acesso ao agente `advogado-digital` nesta sessão —
      texto escrito à mão, no estilo dos parágrafos vizinhos
- [x] 6.2 Subiu a versão do texto legal para **1.8**, pelo critério da 1.6 e
      da 1.7 (mudança mais restritiva sobre dado que já existia)
- [x] 6.3 `MAPA-DE-DADOS.md`: o `motivo` ganha prazo e ganha alcance de
      exclusão; as duas linhas mudam. Acrescentadas também as seções de
      imutabilidade e unicidade, novas nesta change
- [x] 6.4 `REVISAO-JURIDICA.md` § 4-G: o trade-off de apagar o porquê da
      remoção, por escrito, com o que se conserva (estado, resolvida_em) e o
      que se perde (o texto). Arquivo é gitignored e não existia neste
      worktree isolado — copiado do diretório principal antes de editar
- [x] 6.5 Sem acesso ao agente `promessa-vs-execucao` nesta sessão — releitura
      manual, achado a achado, do texto da Política contra o gatilho e o
      expurgo reais (feita ao escrever a 6.1/6.4). Nenhuma divergência
      encontrada
- [x] 6.6 `PENDENCIAS.md`: 2.24, 2.23 e 2.14 fecham, com os números de
      fechamento. **2.12 CONTINUA ABERTA** — depende de 3.4/0.2, bloqueada por
      falta de acesso de produção; anotado o motivo e o que falta
- [x] 6.7 Novidade em `news_item.dart` pelo `CRITERIO-DE-NOVIDADE.md` — é
      mudança sobre os dados dela: o que ela escreveu ao denunciar passa a ter
      prazo

## 7. Fechamento

- [x] 7.1 Gates com números reais: `flutter analyze`, `flutter test test/unit
      test/widget`, `dart test test/integration` com `supabase start`,
      `flutter build web --release`
- [x] 7.2 O commit registra que o rollback **não** devolve motivo já apagado
      (escrito no corpo da migration e vai repetido no commit)
- [x] 7.3 Rodar a skill `openspec-converge` e resolver o que ela achar

## Convergence 1

- [x] Acrescentar `public.expurgar_motivos_de_denuncia()` à lista `functions`
      de `test/integration/chat_privilegio_funcao_test.dart` e ao teste "anon
      chamando o expurgo é recusado de verdade" — per o próprio propósito
      declarado daquele arquivo ("função nova... esquecida na lista passa
      batida"). A migration TEM `revoke execute ... from public` + `grant
      ... to authenticated` (correto, lido), mas nada na suíte automatizada
      provava que `anon` está mesmo bloqueado — é exatamente a classe de
      defeito que aquele arquivo existe para pegar. (missing, HIGH) — FEITO:
      as duas provas passam (nasce verde, é cobertura retroativa de grant já
      correto)

Achado à parte, medido ao rodar a suíte duas vezes seguidas sem reset entre
elas (o cenário real do gate final): `chat_denuncia_exclusao_conta_test.dart`
excluía `_uidReporter` do `tearDownAll` de propósito (comentário dizia que a
conta já tinha sido excluída dentro do teste), mas `excluir_minha_conta()`
anonimiza o Perfil e NÃO o apaga — só `auth.users` some. Sem o
`cleanUpTestUser` daquele uid, o Perfil anonimizado (idade NULA) sobrevivia
para a segunda rodada, `on conflict do nothing` mantinha o Perfil velho, e
`maior_de_idade()` passava a negar — quebrando um teste sem nenhuma relação
com este, por RLS. Corrigido para o padrão já estabelecido em
`chat_exclusao_conta_test.dart`: `cleanUpTestUser` para TODOS os uids,
sempre, mesmo o que já excluiu a própria conta (a função tolera `auth.users`
já ausente).
