## 0. Pré-requisito

- [ ] 0.1 Confirmar que `convite-para-acao` já está aplicada e reler o schema
      **aplicado** de `convites_acao` (`\d public.convites_acao`), não o design
      dela. Os três gatilhos desta change dependem dos nomes reais das colunas
- [ ] 0.2 Conferir que nenhuma tabela está na publicação `supabase_realtime`
      hoje (`select * from pg_publication_tables where pubname =
      'supabase_realtime'`) e colar a saída — é a linha de base

## 1. Banco — tabela, privilégios e RLS

- [ ] 1.1 Migration nova com `public.notificacoes` (`id`, `destinatario_id`,
      `tipo`, `ator_id`, `acao_id`, `grupo_id`, `lida_em`, `created_at`);
      `acao_id` e `grupo_id` com `on delete cascade`; `destinatario_id` e
      `ator_id` referenciando `perfis(id)` **sem cascade** (Perfil é
      anonimizado, não apagado — `20260806140000_exclusao_de_conta.sql:14-16`)
- [ ] 1.2 `check (tipo in ('convite_recebido','convite_aceito',
      'convite_recusado'))`, no padrão de `confirmacoes_acao.status`
- [ ] 1.3 `grant select on public.notificacoes to authenticated` e
      `grant update (lida_em) on public.notificacoes to authenticated`.
      **Nada para `anon`.** Nenhum `grant insert` nem `delete` para ninguém —
      comentar na migration que a ausência é o mecanismo
- [ ] 1.4 RLS ligada com duas policies: `notificacoes_select_propria`
      (`using (auth.uid() = destinatario_id)`) e
      `notificacoes_update_propria` (mesmo `using`, mais `with check` igual)
- [ ] 1.5 Índices `notificacoes_nao_lidas (destinatario_id, created_at desc)
      where lida_em is null` e `notificacoes_por_destinatario (destinatario_id,
      created_at desc)`
- [ ] 1.6 `comment on table` e `comment on column` explicando por que o cliente
      só escreve `lida_em`, e por que o aviso de aceite não guarda o status

## 2. Banco — gatilhos

- [ ] 2.1 `after insert on convites_acao` gravando `convite_recebido` para
      `new.convidado_id`, com `ator_id = new.convidante_id` e `acao_id`/
      `grupo_id` copiados do convite
- [ ] 2.2 `after update on convites_acao`, `when (old.recusado_em is null and
      new.recusado_em is not null)`, gravando `convite_recusado` para
      `new.convidante_id`
- [ ] 2.3 `after insert on confirmacoes_acao` gravando um `convite_aceito` por
      convite existente para `(new.acao_id, new.usuario_id)`, cada um para o
      `convidante_id` daquele convite. `after`, nunca `before` — precisa rodar
      depois do gatilho que decide `confirmado`/`fila`
- [ ] 2.4 Os três entram **ao lado** dos gatilhos existentes;
      `confirmacoes_acao_decidir_status()` e `promover_fila_acao()` não são
      tocadas. Confirmar com `\d public.confirmacoes_acao` que os antigos
      continuam lá

## 3. Banco — view, Realtime e retenção

- [ ] 3.1 `create view public.notificacoes_ativas with (security_invoker =
      true)` filtrando fora aviso de Ação cancelada ou encerrada
      (`acao_encerrada(uuid)`), deixando passar aviso sem `acao_id`
- [ ] 3.2 Verificar no `psql` que a view tem `security_invoker` ligado
      (`select reloptions from pg_class where relname =
      'notificacoes_ativas'`) e colar a saída. Sem isso a view entrega aviso
      alheio — é a linha mais perigosa desta change
- [ ] 3.3 `alter publication supabase_realtime add table public.notificacoes`
- [ ] 3.4 Job de `pg_cron` diário apagando `where lida_em < now() - interval
      '90 days'`. Não lido nunca é apagado
- [ ] 3.5 `supabase db reset` roda limpo; colar `\d public.notificacoes` e a
      linha do job em `cron.job`

## 4. Testes de integração — privacidade primeiro

- [ ] 4.1 `notificacao_leitura_propria_test.dart`: duas sessões, cada uma lendo
      `notificacoes` e `notificacoes_ativas` e vendo **só** as próprias.
      Cobre a tabela e a view separadamente — a view é o caminho que pode
      ignorar RLS
- [ ] 4.2 `notificacao_anon_test.dart`: sessão `anon` recebe conjunto vazio
- [ ] 4.3 `notificacao_escrita_recusada_test.dart`: `insert` e `delete` pelo
      cliente são recusados, inclusive sobre linha própria; `update` de `tipo`,
      `ator_id` ou `destinatario_id` é recusado pelo `grant` de coluna;
      `update` de `lida_em` na própria linha funciona
- [ ] 4.4 `notificacao_realtime_isolamento_test.dart`: duas sessões inscritas
      no canal, aviso gerado para uma, verificar que a **outra não recebe
      evento**. Se falhar, aplicar o recuo do design (não publicar a tabela)
      antes de seguir
- [ ] 4.5 `notificacao_convite_recebido_test.dart`: convite gera um aviso não
      lido; convite em lote de cinco gera cinco avisos, um por pessoa; convite
      repetido não gera segundo aviso
- [ ] 4.6 `notificacao_resposta_test.dart`: confirmar presença gera
      `convite_aceito` para quem convidou; recusar gera `convite_recusado`;
      confirmar sem ter sido convidado não gera nada; dois convidantes recebem
      cada um o seu; desistir depois de aceitar não gera aviso novo
- [ ] 4.7 `notificacao_fila_test.dart`: convidada que cai na `fila` gera
      `convite_aceito`, e o aviso **não** guarda o status — promover a fila
      depois não deixa o aviso mentindo
- [ ] 4.8 `notificacao_acao_cancelada_test.dart`: aviso de Ação cancelada
      some de `notificacoes_ativas`; Ação apagada leva o aviso junto (cascade)
- [ ] 4.9 `notificacao_retencao_test.dart`: lida há mais que o prazo é apagada;
      não lida antiga permanece
- [ ] 4.10 `notificacao_anonimizacao_test.dart`: depois de `excluir_conta` de
      quem gerou o aviso, o nome anterior não sai em nenhuma leitura

## 5. App — dados e tempo real

- [ ] 5.1 `lib/features/notification/domain/app_notification.dart` — modelo com
      `tipo` mapeado para enum Dart; chaves de mapa em português
      (`destinatario_id`, `lida_em`, `ator_id`), identificadores em inglês
      (CONTEXT.md — fronteira de idioma)
- [ ] 5.2 `lib/features/notification/data/notification_repository.dart` —
      único ponto de acesso; lê **sempre** de `notificacoes_ativas`, nunca da
      tabela crua, senão contador e lista divergem
- [ ] 5.3 Inscrição Realtime como **sinal**: qualquer evento dispara
      reconsulta da contagem e da lista. O payload do evento não monta tela
- [ ] 5.4 Ciclo de vida do canal fecha junto com o widget/provider — canal sem
      `dispose` vaza conexão, e o plano Free tem teto de conexões concorrentes
- [ ] 5.5 Queda da conexão de tempo real não vira erro na tela; a contagem se
      corrige ao reabrir a tela ou ao app voltar ao primeiro plano
- [ ] 5.6 Testes de unidade do mapeamento e da derivação de "não lido"

## 6. App — telas

- [ ] 6.1 Indicador de não lidas na barra do app, visível de qualquer tela,
      **ausente** quando o total é zero (não "0")
- [ ] 6.2 `notifications_page.dart` em `/notificacoes`: lista em ordem de tempo,
      não lidas destacadas, cada aviso dizendo quem, o quê e por qual Grupo
- [ ] 6.3 Abrir a tela marca como lidas as exibidas, num `update` só; elas
      continuam na lista, agora com aparência de lida
- [ ] 6.4 Aviso que chega com a tela aberta entra na lista sem recarregar
- [ ] 6.5 Tocar num aviso leva à Ação; se a Ação sumiu, cai em "não está mais
      disponível", sem erro e sem tela quebrada
- [ ] 6.6 Rota `/notificacoes` em `lib/app.dart`
- [ ] 6.7 Julgar as telas na **largura de celular**: o indicador não pode
      cobrir outro controle da barra, e o texto do aviso precisa caber sem
      rolagem horizontal

## 7. Testes de widget

- [ ] 7.1 Indicador some quando não há não lidas
- [ ] 7.2 Contagem do indicador é a mesma da lista, inclusive com aviso de Ação
      cancelada presente na tabela
- [ ] 7.3 Abrir a tela zera o indicador e mantém os avisos na lista
- [ ] 7.4 Aviso cujo assunto sumiu mostra "não está mais disponível"

## 8. Gates e ledger

- [ ] 8.1 `flutter analyze` — zero issue (colar a linha final)
- [ ] 8.2 `flutter test test/unit test/widget` — colar a contagem real
- [ ] 8.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os dez testes novos identificados
- [ ] 8.4 `flutter build web --release` conclui
- [ ] 8.5 `MAPA-DE-DADOS.md`: `notificacoes` com `arquivo:linha` e **o prazo de
      90 dias declarado** — o requisito de retenção exige que esteja lá
- [ ] 8.6 `INFRA-PRODUCAO.md`: a publicação `supabase_realtime` e o job de
      `pg_cron` como configuração que produção precisa ter, no mesmo formato
      que a drenagem de capas já usa
- [ ] 8.7 `SECURITY-AUDIT.md`: a estreia do Realtime como superfície de leitura,
      com o resultado do teste 4.4
- [ ] 8.8 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
- [ ] 8.9 `graphify --update` antes de considerar a change fechada
