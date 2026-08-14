## 0. Pré-requisito

- [x] 0.1 Confirmar que `convite-para-acao` já está aplicada e reler o schema
      **aplicado** de `convites_acao` (`\d public.convites_acao`), não o design
      dela. Os três gatilhos desta change dependem dos nomes reais das colunas
      - `convite-para-acao` arquivada em 2026-08-13. Schema aplicado conferido:
        `acao_id, convidado_id, grupo_id, convidante_id, created_at, recusado_em`
        — bate com o que o design desta change esperava
- [x] 0.2 Conferir que nenhuma tabela está na publicação `supabase_realtime`
      hoje (`select * from pg_publication_tables where pubname =
      'supabase_realtime'`) e colar a saída — é a linha de base

## 1. Banco — tabela, privilégios e RLS
      - `select * from pg_publication_tables where pubname='supabase_realtime'`
        → **0 linhas**. A publicação existe (`puballtables = f`) e está vazia.
        Linha de base confirmada: esta change estreia o Realtime no projeto
- [x] 1.1 Migration nova com `public.notificacoes` (`id`, `destinatario_id`,
      `tipo`, `ator_id`, `acao_id`, `grupo_id`, `lida_em`, `created_at`);
      `acao_id` e `grupo_id` com `on delete cascade`; `destinatario_id` e
      `ator_id` referenciando `perfis(id)` **sem cascade** (Perfil é
      anonimizado, não apagado — `20260806140000_exclusao_de_conta.sql:14-16`)
- [x] 1.2 `check (tipo in ('convite_recebido','convite_aceito',
      'convite_recusado'))`, no padrão de `confirmacoes_acao.status`
- [x] 1.3 `grant select on public.notificacoes to authenticated` e
      `grant update (lida_em) on public.notificacoes to authenticated`.
      **Nada para `anon`.** Nenhum `grant insert` nem `delete` para ninguém —
      comentar na migration que a ausência é o mecanismo
      - `authenticated`: `SELECT` na tabela e `UPDATE` só em `lida_em`,
        conferido em `information_schema.column_privileges`. `anon`: nada
- [x] 1.4 RLS ligada com duas policies: `notificacoes_select_propria`
      (`using (auth.uid() = destinatario_id)`) e
      `notificacoes_update_propria` (mesmo `using`, mais `with check` igual)
- [x] 1.5 Índices `notificacoes_nao_lidas (destinatario_id, created_at desc)
      where lida_em is null` e `notificacoes_por_destinatario (destinatario_id,
      created_at desc)`
- [x] 1.6 `comment on table` e `comment on column` explicando por que o cliente
      só escreve `lida_em`, e por que o aviso de aceite não guarda o status

## 2. Banco — gatilhos

- [x] 2.1 `after insert on convites_acao` gravando `convite_recebido` para
      `new.convidado_id`, com `ator_id = new.convidante_id` e `acao_id`/
      `grupo_id` copiados do convite
- [x] 2.2 `after update on convites_acao`, `when (old.recusado_em is null and
      new.recusado_em is not null)`, gravando `convite_recusado` para
      `new.convidante_id`
- [x] 2.3 `after insert on confirmacoes_acao` gravando um `convite_aceito` por
      convite existente para `(new.acao_id, new.usuario_id)`, cada um para o
      `convidante_id` daquele convite. `after`, nunca `before` — precisa rodar
      depois do gatilho que decide `confirmado`/`fila`
- [x] 2.4 Os três entram **ao lado** dos gatilhos existentes;
      `confirmacoes_acao_decidir_status()` e `promover_fila_acao()` não são
      tocadas. Confirmar com `\d public.confirmacoes_acao` que os antigos
      continuam lá

## 3. Banco — view, Realtime e retenção

- [x] 3.1 `create view public.notificacoes_ativas with (security_invoker =
      true)` filtrando fora aviso de Ação cancelada ou encerrada
      (`acao_encerrada(uuid)`), deixando passar aviso sem `acao_id`
- [x] 3.2 Verificar no `psql` que a view tem `security_invoker` ligado
      (`select reloptions from pg_class where relname =
      'notificacoes_ativas'`) e colar a saída. Sem isso a view entrega aviso
      alheio — é a linha mais perigosa desta change
      - `reloptions` → `{security_invoker=true}`
- [x] 3.3 `alter publication supabase_realtime add table public.notificacoes`
- [x] 3.4 Job de `pg_cron` diário apagando `where lida_em < now() - interval
      '90 days'`. Não lido nunca é apagado
- [x] 3.5 `supabase db reset` roda limpo; colar `\d public.notificacoes` e a
      linha do job em `cron.job`

## 4. Testes de integração — privacidade primeiro
      - `supabase db reset` limpo com 36 migrations. `cron.job` tem
        `expurgar-notificacoes-lidas` em `17 4 * * *`, ao lado dos dois da
        drenagem de capas. Publicação com exatamente `public.notificacoes`
- [x] 4.1 `notificacao_leitura_propria_test.dart`: duas sessões, cada uma lendo
      `notificacoes` e `notificacoes_ativas` e vendo **só** as próprias.
      Cobre a tabela e a view separadamente — a view é o caminho que pode
      ignorar RLS
      - 3 testes verdes — tabela e view separadas, mais a checagem do `reloptions`
- [x] 4.2 `notificacao_anon_test.dart`: sessão `anon` recebe conjunto vazio
      - 2 testes verdes; a recusa é por privilégio, e o comentário explica por que aqui não vale o argumento de canal lateral
- [x] 4.3 `notificacao_escrita_recusada_test.dart`: `insert` e `delete` pelo
      cliente são recusados, inclusive sobre linha própria; `update` de `tipo`,
      `ator_id` ou `destinatario_id` é recusado pelo `grant` de coluna;
      `update` de `lida_em` na própria linha funciona
      - 5 testes verdes, separando o que cai por policy do que cai por privilégio de coluna
- [x] 4.4 `notificacao_realtime_isolamento_test.dart`: duas sessões inscritas
      no canal, aviso gerado para uma, verificar que a **outra não recebe
      evento**. Se falhar, aplicar o recuo do design (não publicar a tabela)
      antes de seguir
      - **A afirmação central do design está PROVADA, não assumida**: o canal
        respeita a RLS — B nunca recebe o aviso de A. O recuo previsto não foi
        preciso
      - O teste fala com o servidor de Realtime de verdade (WebSocket na 54321),
        não com o Postgres na 54322. Precedente: `upgrade_conta_test.dart` já
        usa `package:supabase` contra a API real
      - **Foi preciso um aquecimento, e ele não é paciência com teste lento.**
        Medido: logo após `supabase db reset` o servidor ainda não pegou a
        publicação nova e o cliente já reporta `SUBSCRIBED` — o teste falhava
        de forma reproduzível nessa condição. Sem aquecer, "B não recebeu nada"
        passaria também com o canal morto: o teste diria "isolado" quando a
        verdade é "desligado". Agora ele insere para A até A receber, e só então
        a ausência em B vira evidência. Verde nas duas condições
- [x] 4.5 `notificacao_convite_recebido_test.dart`: convite gera um aviso não
      lido; convite em lote de cinco gera cinco avisos, um por pessoa; convite
      repetido não gera segundo aviso
      - 4 testes verdes, incluindo a idempotência que sai de graça do `on conflict do nothing`
- [x] 4.6 `notificacao_resposta_test.dart`: confirmar presença gera
      `convite_aceito` para quem convidou; recusar gera `convite_recusado`;
      confirmar sem ter sido convidado não gera nada; dois convidantes recebem
      cada um o seu; desistir depois de aceitar não gera aviso novo
      - 4 testes verdes. **Um deles mentia e foi corrigido**: eu tinha
        escrito "os DOIS que convidaram" e provava um só — pelo mesmo Grupo o
        segundo convite não cria linha, porque a PK é `(acao, convidado, grupo)`.
        Agora monta dois Grupos e prova os dois convidantes de verdade
- [x] 4.7 `notificacao_fila_test.dart`: convidada que cai na `fila` gera
      `convite_aceito`, e o aviso **não** guarda o status — promover a fila
      depois não deixa o aviso mentindo
      - 2 testes verdes; um deles trava a lista de colunas, que é a garantia estrutural de o status não ser gravado
- [x] 4.8 `notificacao_acao_cancelada_test.dart`: aviso de Ação cancelada
      some de `notificacoes_ativas`; Ação apagada leva o aviso junto (cascade)
      - 3 testes verdes, separando cancelada (a view filtra) de apagada (cascata leva junto)
- [x] 4.9 `notificacao_retencao_test.dart`: lida há mais que o prazo é apagada;
      não lida antiga permanece
      - 2 testes verdes, com a assimetria lida/não lida
- [x] 4.10 `notificacao_anonimizacao_test.dart`: depois de `excluir_conta` de
      quem gerou o aviso, o nome anterior não sai em nenhuma leitura

- [x] 4.11 **Achado fora do escopo, consertado em `main` antes de seguir**: com
      os testes novos, `dart test test/integration` passou a falhar de forma
      DETERMINÍSTICA em 5 casos — 4 de `account_deletion_test` e 1 de
      `leadership_decide_test` —, todos passando isolados. Causa:
      `excluir_minha_conta` decide pela CONTAGEM de administradores, e
      `administradores_distrito` é estado global tocado por 17 arquivos que
      rodam em paralelo. Violava o requisito "A suíte é determinística em
      paralelo" de `openspec/specs/suite-de-integracao`, que é explícito sobre
      não alcançar contagem de outro arquivo
      - Conserto: lock consultivo de sessão dentro de `createTestDistrictAdmin`.
        Não é `skip` nem `retry`, que a change `estabilizar-suite-de-integracao`
        proíbe. `concurrency: 1` foi descartado — é configuração do runner, não
        aceita recorte por tag, e serializaria a suíte inteira
      - Verificado com o critério do próprio cenário do requisito: **20
        execuções seguidas, 335/335 nas 20, zero falha**
      - Foi para `main` direto, e não para esta branch: conserta requisito de
        outra capability e não deve se perder se esta change for abandonada

## 5. App — dados e tempo real
      - 2 testes verdes
- [x] 5.1 `lib/features/notification/domain/app_notification.dart` — modelo com
      `tipo` mapeado para enum Dart; chaves de mapa em português
      (`destinatario_id`, `lida_em`, `ator_id`), identificadores em inglês
      (CONTEXT.md — fronteira de idioma)
- [x] 5.2 `lib/features/notification/data/notification_repository.dart` —
      único ponto de acesso; lê **sempre** de `notificacoes_ativas`, nunca da
      tabela crua, senão contador e lista divergem
      - `fetch()` e `unreadCount()` leem os dois de `notificacoes_ativas`
- [x] 5.3 Inscrição Realtime como **sinal**: qualquer evento dispara
      reconsulta da contagem e da lista. O payload do evento não monta tela
      - O sinal é um `Stream` que emite a cada evento; a lista e a contagem o
        observam e reconsultam. O payload não monta tela — o filtro de "aviso
        ainda válido" depende de `acoes` e não cabe num payload de linha
- [x] 5.4 Ciclo de vida do canal fecha junto com o widget/provider — canal sem
      `dispose` vaza conexão, e o plano Free tem teto de conexões concorrentes
      - `ref.onDispose` remove o canal e fecha o `StreamController`
- [x] 5.5 Queda da conexão de tempo real não vira erro na tela; a contagem se
      corrige ao reabrir a tela ou ao app voltar ao primeiro plano
      - A lista não depende do canal para funcionar: são caminhos separados, e
        a consulta continua de pé se a conexão cair. `autoDispose` faz a
        próxima abertura reconsultar
- [x] 5.6 Testes de unidade do mapeamento e da derivação de "não lido"

## 6. App — telas
      - `test/unit/notificacao_model_test.dart`, 9 testes verdes
- [x] 6.1 Indicador de não lidas na barra do app, visível de qualquer tela,
      **ausente** quando o total é zero (não "0")
      - **O app não tem barra global** — são 28 telas com `AppBar` própria. O
        indicador vive nas **8 telas de leitura** (as duas listas, os dois
        detalhes, Novidades, Convites e as duas de Rodada) e **não** nas de
        formulário, onde seria distração no meio de um fluxo. A decisão está
        travada por teste, nas duas metades
      - Some quando o total é zero, e some enquanto carrega — número que pisca a
        cada abertura é pior que número nenhum
- [x] 6.2 `notifications_page.dart` em `/notificacoes`: lista em ordem de tempo,
      não lidas destacadas, cada aviso dizendo quem, o quê e por qual Grupo
- [x] 6.3 Abrir a tela marca como lidas as exibidas, num `update` só; elas
      continuam na lista, agora com aparência de lida
- [x] 6.4 Aviso que chega com a tela aberta entra na lista sem recarregar
- [x] 6.5 Tocar num aviso leva à Ação; se a Ação sumiu, cai em "não está mais
      disponível", sem erro e sem tela quebrada
- [x] 6.6 Rota `/notificacoes` em `lib/app.dart`
- [x] 6.7 Julgar as telas na **largura de celular**: o indicador não pode
      cobrir outro controle da barra, e o texto do aviso precisa caber sem
      rolagem horizontal

## 7. Testes de widget
      - Os testes de widget renderizam em 360x800. **Como nas changes de
        hoje, isso prova que nada estoura, não que a tela foi julgada** — o
        julgamento com olho está em `PENDENCIAS.md` § 3
- [x] 7.1 Indicador some quando não há não lidas
- [x] 7.2 Contagem do indicador é a mesma da lista, inclusive com aviso de Ação
      cancelada presente na tabela
- [x] 7.3 Abrir a tela zera o indicador e mantém os avisos na lista
- [x] 7.4 Aviso cujo assunto sumiu mostra "não está mais disponível"

## 8. Gates e ledger

- [x] 8.1 `flutter analyze` — zero issue (colar a linha final)
      - `No issues found`
- [x] 8.2 `flutter test test/unit test/widget` — colar a contagem real
      - `00:09 +384: All tests passed!` — 384 testes, 0 falhas (contagem final)
- [x] 8.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os dez testes novos identificados
      - `00:09 +335: All tests passed!` — 335 testes, 0 falhas. Onze arquivos
        novos desta change (10 de banco + 1 de Realtime), 33 testes
- [x] 8.4 `flutter build web --release` conclui
      - `✓ Built build/web`
- [x] 8.5 `MAPA-DE-DADOS.md`: `notificacoes` com `arquivo:linha` e **o prazo de
      90 dias declarado** — o requisito de retenção exige que esteja lá
      - `MAPA-DE-DADOS.md`: linha nova na tabela "Quem vê o quê" e três
        parágrafos — o prazo de 90 dias declarado, a referência em vez de cópia
        do nome, e a estreia do Realtime como superfície de leitura
- [x] 8.6 `INFRA-PRODUCAO.md`: a publicação `supabase_realtime` e o job de
      `pg_cron` como configuração que produção precisa ter, no mesmo formato
      que a drenagem de capas já usa
      - `INFRA-PRODUCAO.md` § 3b: a publicação e o job, com a consulta de
        conferência de cada um e o que significa vir vazio
- [x] 8.7 `SECURITY-AUDIT.md`: a estreia do Realtime como superfície de leitura,
      com o resultado do teste 4.4
      - `SECURITY-AUDIT.md`: a estreia do Realtime, o resultado medido (o
        canal respeita RLS, recuo não foi preciso) e — o que vale mais que o
        resultado — a armadilha de o teste passar pelo motivo errado logo após
        `db reset`, com `SUBSCRIBED` reportado sobre canal ainda mudo
- [x] 8.8 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
      - 9 requisitos e 28 cenários (30 depois dos dois novos). **Dois achados,
        os dois resolvidos.**
      - **C1, HIGH** — o requisito pedia contador "em lugar visível de qualquer
        tela", e ele estava em duas. Isso devolvia metade do problema que a
        change existe para resolver: o convite era invisível. O app não tem
        barra global e são 28 telas com `AppBar` própria, metade delas
        formulários. Resolvido pela **opção 2**: indicador nas 8 telas de
        leitura, ausente nos formulários — e o spec passou a descrever essa
        decisão em vez de uma que o app não cumpre. `ShellRoute` foi avaliado e
        fica como change própria de navegação, que serviria também ao chat
      - **C2, MEDIUM** — `_marcou` era interruptor de uma vez só, então aviso
        que chegasse com a tela aberta aparecia na lista e o contador continuava
        subindo com o aviso à vista. Virou conjunto de ids já marcados
      - Quatro hipóteses verificadas e derrubadas, no relatório da passagem
- [x] 8.9 `graphify --update` antes de considerar a change fechada
      - **Código: entrou.** AST sobre os 42 arquivos alterados, mesclado com
        `build_merge`. `graph.json` foi de 5833 para **5963 nós** e de 6910 para
        **7164 arestas**, 703 comunidades. Saúde limpa: 0 ponta solta, 0 ponta
        ausente, 0 self-loop, 0 aresta colapsada. Custo: **zero token de LLM**
      - **Documentos: seguem pendentes**, pelo motivo de `PENDENCIAS.md` § 2.9.
        314 arquivos ficaram fora do manifesto de propósito, para voltarem como
        pendentes no próximo `--update` em vez de contarem como processados
      - Podou 146 nós de 12 arquivos que sumiram do caminho antigo — as duas
        changes arquivadas hoje, que mudaram de lugar. Voltam na próxima
        extração semântica