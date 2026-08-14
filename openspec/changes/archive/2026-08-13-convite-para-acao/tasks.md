## 0. Dependência declarada por outra change

- [x] 0.1 `acao-direcionada-a-grupo` foi aplicada primeiro e criou
      `acoes.restrita_ao_grupo`. Convidar para uma Ação restrita NÃO pode
      alcançar quem não participa do Grupo dono dela: um convite para algo que
      a pessoa não consegue abrir é convite morto, e ainda revela que a Ação
      existe. Portanto `convidar_para_acao` e `contatos_para_convite` DEVEM
      recusar/omitir esse caso, com teste de integração próprio. O requisito já
      está escrito em
      `openspec/changes/acao-direcionada-a-grupo/specs/visibilidade-de-acao/spec.md`,
      requisito "Convidar para Ação restrita só alcança quem participa do Grupo"
      - `acao-direcionada-a-grupo` foi arquivada em 2026-08-13, então a regra
        entrou desde o nascimento das duas funções, não como ajuste:
        `contatos_para_convite` só devolve a seção do Grupo dono quando a Ação
        é restrita, e `convidar_para_acao` recusa convite por Grupo diferente
        do dono nesse caso
- [x] 0.2 Ao escrever essas funções, lembrar que Ação de Grupo neste app é
      candidata de Rodada e a vencedora dela — `acoes_candidata_checar_regras`
      recusa `grupo_id` sem `rodada_id`. Não existe "Ação criada direto num
      Grupo"

## 1. Banco — tabela, privilégios e RLS
      - Confirmado no banco: `acoes_candidata_checar_regras` recusa `grupo_id`
        sem `rodada_id`. Nenhuma das funções cria Ação, então o efeito aqui é
        só de leitura — `acoes.grupo_id` de uma Ação de Grupo veio da Rodada
- [x] 1.1 Migration nova com `public.convites_acao` (`acao_id`, `convidado_id`,
      `grupo_id`, `convidante_id`, `created_at`, `recusado_em`), PK composta
      `(acao_id, convidado_id, grupo_id)`, `acao_id` e `grupo_id` com
      `on delete cascade`, `convidado_id` e `convidante_id` referenciando
      `perfis(id)` **sem cascade** (o Perfil é anonimizado, não apagado —
      `20260806140000_exclusao_de_conta.sql:14-16`)
- [x] 1.2 `grant select on public.convites_acao to authenticated` e **nada para
      `anon`**. Nenhum `grant insert` ou `delete` para ninguém — a ausência é o
      mecanismo, não esquecimento; escrever isso em comentário na migration
      - **Corrigido durante a implementação**: como estava, a task fechava
        também o `update`, e aí `recusado_em` não tinha caminho de escrita
        nenhum — a coluna existia, o design explicava por que ela existe, a task
        4.3 pedia `decline(...)` e a 5.3 pedia o botão, e nada dizia como
        escrever. Entrou `grant update (recusado_em)` + policy
        `convites_acao_update_convidado`, com recorte POR COLUNA pelo precedente
        de `20260811160000_grant_update_perfis_por_coluna.sql`
      - Criar convite continua sem grant e continua só pela RPC: ali a regra
        "quem convida tem Conta" exige ler `auth.users`, fora do alcance de
        policy. Recusar não exige nada disso — é a própria pessoa sobre a
        própria linha
- [x] 1.3 RLS ligada com uma policy só: `convites_acao_select_partes`, para
      `authenticated`, `using (auth.uid() in (convidado_id, convidante_id))`
- [x] 1.4 Índices `convites_acao_por_convidado (convidado_id, created_at desc)`
      e `convites_acao_por_acao (acao_id, convidante_id)`
- [x] 1.5 `comment on table` e `comment on column` explicando por que não existe
      coluna de aceite (aceite é `confirmacoes_acao`) e por que `recusado_em`
      existe

## 2. Banco — funções

- [x] 2.1 `contatos_para_convite(p_acao_id uuid)` `security definer`,
      `set search_path = public, auth`, devolvendo `(grupo_id, grupo_nome,
      usuario_id, nome_exibido, ja_convidado)`; filtra por `auth.uid()` **por
      dentro**, sem parâmetro de Grupo vindo do cliente; exclui `auth.uid()` da
      própria lista; exclui Grupo com `arquivado_em not null`; `nome_exibido`
      usa `coalesce(apelido, nome)`, a mesma expressão de `perfil_publico`
      (`20260723191202_perfis_igrejas.sql:47`)
- [x] 2.2 `convidar_para_acao(p_acao_id uuid, p_grupo_id uuid, p_convidados
      uuid[])` `security definer`, devolvendo uma linha por pessoa pedida com
      `resultado in ('criado','ja_convidado','nao_participa')`; recusa se quem
      chama é anônimo (`auth.users.is_anonymous`, padrão de
      `20260724100000_leadership.sql:26-31`), se quem chama não participa de
      `p_grupo_id`, ou se a Ação está cancelada/encerrada
      (`acao_encerrada(uuid)`)
- [x] 2.3 `grant execute` das duas funções apenas para `authenticated`
- [x] 2.4 `supabase db reset` roda limpo e as duas funções aparecem em
      `\df public.*convite*` (colar a saída)

## 3. Testes de integração — o que a tela não prova
      - `\df public.*convite*` mostra **só** `contatos_para_convite` — o
        padrão não casa com `convidar_para_acao` ("convidar", não "convite").
        Conferido pelo catálogo, que é o que vale:
        - `contatos_para_convite(p_acao_id uuid)` — definer, `search_path=public, auth`
        - `convidar_para_acao(p_acao_id uuid, p_grupo_id uuid, p_convidados uuid[])`
          — definer, `search_path=public, auth`
      - `convites_acao`: PK `(acao_id, convidado_id, grupo_id)`; FK de `acoes` e
        `grupos` com `on delete cascade`, as duas de `perfis` sem cascade
      - Privilégios: `authenticated` só `SELECT`; `anon` **nada**. Satisfaz
        "Tabela nova nasce fechada" de `privilegios-de-banco`
      - `POLICY convites_acao_select_partes FOR SELECT TO authenticated`
      - `supabase db reset` aplicou as 35 migrations sem erro
- [x] 3.1 `contatos_para_convite_isolamento_test.dart`: sessão `anon` recebe
      **lista vazia**; sessão autenticada sem Grupo em comum recebe **lista
      vazia**. Sem estes dois, a change não fecha (design — Risks)
      - 5 testes verdes. **O spec foi corrigido antes de o teste passar**: ele
        descrevia uma API que o design não construiu. Dizia "sessão anônima
        recebe lista vazia", mas `anon` não tem `grant execute` (task 2.3), e a
        resposta real é recusa por permissão — o que não é canal lateral aqui,
        porque anon não participa de Grupo nenhum e não há quantidade a contar.
        E dizia "pedindo o id de um Grupo alheio", parâmetro que o design tirou
        de propósito: a defesa é justamente não haver por onde pedir. Os dois
        cenários passaram a descrever o que existe, e um dos testes fixa a
        assinatura `p_acao_id uuid` para o parâmetro não voltar por descuido
- [x] 3.2 `contatos_para_convite_agrupamento_test.dart`: pessoa em dois Grupos
      recebe as duas seções; quem participa dos mesmos dois Grupos aparece nos
      dois; quem chama não aparece na própria lista; Grupo arquivado não vem
      - 5 testes verdes, incluindo `ja_convidado` por Grupo e não por pessoa
- [x] 3.3 `convidar_exige_conta_test.dart`: sessão anônima é recusada; sessão
      com Conta cria o convite
      - 3 testes verdes, com o lado de receber sem Conta
- [x] 3.4 `convite_nao_reserva_vaga_test.dart`: Ação com `limite_vagas = 1`,
      pessoa convidada, outra confirma antes e ocupa a vaga, a convidada
      confirma depois e cai em `fila`; a contagem de confirmados não muda no
      momento do convite
      - 3 testes verdes. Capacidade 2, porque
        `acoes_criador_vira_confirmado` já ocupa uma vaga com quem criou —
        sobra exatamente uma para a corrida
- [x] 3.5 `convite_leitura_restrita_test.dart`: terceiro autenticado pedindo
      `convites_acao` de uma Ação recebe **conjunto vazio**, não erro
      - 4 testes verdes, incluindo `anon` sem `grant select` na tabela
- [x] 3.6 `convidar_em_lote_test.dart`: array com uma pessoa válida, uma já
      convidada e uma que não participa devolve as três classificações certas,
      e a válida fica gravada
      - 3 testes verdes, as três classificações na mesma chamada
- [x] 3.7 `convite_idempotente_test.dart`: convidar duas vezes pelo mesmo Grupo
      dá uma linha; convidar pela mesma Ação por dois Grupos dá duas
      - 2 testes verdes
- [x] 3.8 `convite_anonimizacao_test.dart`: depois de `excluir_conta` de quem
      convidou, a leitura do convite não devolve o nome anterior

- [x] 3.9 `convite_acao_restrita_test.dart` (exigido pela 0.1, não estava na
      lista original): a Ação avulsa segue oferecendo os dois Grupos; a Ação
      restrita só oferece a seção do Grupo dono; convidar por outro Grupo é
      recusado e nada fica gravado; convidar pelo Grupo dela funciona. 4 testes
      verdes

## 4. Domínio e dados no app
      - 2 testes verdes. Um deles trava a lista de colunas de
        `convites_acao` — é o que impede alguém de "otimizar" a leitura
        guardando o nome junto, que sobreviveria à anonimização
      - Montagem: o Grupo é da pessoa convidada, não de quem convida.
        `excluir_minha_conta` recusa Dono de Grupo sem Administrador do
        distrito para herdar
- [x] 4.1 `lib/features/invite/domain/action_invite.dart` — modelo do convite
      com o Grupo de origem; chaves de mapa em português (`acao_id`,
      `grupo_id`, `convidado_id`, `recusado_em`), identificadores em inglês
      (CONTEXT.md — fronteira de idioma)
      - `ActionInvite` (a linha) e `ReceivedInvite` (linha + Ação + nome do
        Grupo + se já confirmou), mais `InviteOutcome`/`InviteResult` para o
        lote. `ReceivedInvite.action` é anulável de propósito: Ação restrita
        deixa de ser legível quando a pessoa sai do Grupo, e o embed vem nulo
- [x] 4.2 `lib/features/invite/domain/invite_contact.dart` e
      `invite_contact_group.dart` — contato e seção por Grupo
- [x] 4.3 `lib/features/invite/data/invite_repository.dart` — único ponto de
      acesso a `convites_acao` e às duas funções; `fetchContacts(actionId)`,
      `invite(actionId, groupId, userIds)`, `fetchReceivedInvites()`,
      `decline(...)`. **Uma** chamada de rede por operação — nada de laço de
      `perfil_publico` (o N+1 de `group_repository.dart:151-161` é justamente o
      que esta change existe para não repetir)
      - `fetchContacts` e `invite`: **uma** chamada cada, via RPC.
      - `fetchReceivedInvites`: **duas** chamadas constantes, não N+1 — os
        convites com `grupos(nome)` e `acoes(*)` embutidos, e as confirmações
        **da própria pessoa** para aquelas Ações. Embutir as confirmações na
        primeira puxaria o par nominal de todo mundo que confirmou em cada Ação
        convidada, só para desenhar um booleano sobre si mesma
      - `decline` lê o retorno com `.select()`: recusa por RLS de `update`
        devolve zero linha, não erro — mesma lição da convergência de
        `acao-direcionada-a-grupo`
- [x] 4.4 `lib/features/invite/invite_providers.dart` — providers Riverpod, no
      padrão dos existentes em `action_providers.dart`
      - Mais `openInvitesCountProvider`, que é a mitigação registrada no
        design para esta change não ter notificação
- [x] 4.5 Testes de unidade do mapeamento de/para as chaves em português e da
      derivação de "convite em aberto" (existe, `recusado_em` nulo, não
      confirmado, Ação viva)

## 5. Telas
      - `test/unit/convite_model_test.dart`, 11 testes verdes. Um caso por
        motivo de saída de "em aberto" (recusado, confirmado, cancelada,
        encerrada, ilegível): são cinco condições e é fácil implementar quatro
- [x] 5.1 `invite_to_action_page.dart` em `/acoes/:id/convidar`: seções por
      Grupo, seleção múltipla, quem já foi convidado aparece marcado e não
      selecionável; estado vazio ("a lista vem dos seus Grupos") com caminho
      para `/grupos`
- [x] 5.2 Resultado do lote na tela: quantos foram, e **quem** ficou de fora,
      nominalmente, com botão de tentar de novo só para quem falhou. Nunca
      afirmar sucesso quando a chamada falhou
      - O resumo diz quantos foram e nomeia quem ficou de fora; o botão vira
        "Tentar de novo (N)" já com a seleção reduzida a quem falhou. Rede
        caindo num Grupo não desfaz os Grupos já enviados e não afirma sucesso
- [x] 5.3 `received_invites_page.dart` em `/convites`: lista de convites em
      aberto, cada um dizendo por qual Grupo veio; filtro por Grupo cujas
      opções são só os Grupos em que a pessoa participa hoje; recusar; abrir a
      Ação
      - Filtro por chips, com as opções interseccionadas com
        `myGroupIdsProvider` — convite de Grupo que a pessoa deixou fica na
        lista e some das opções
- [x] 5.4 Convite de Ação cancelada ou encerrada não entra na lista; abrir um
      por link mostra "Ação cancelada", sem opção de confirmar presença e sem
      tela quebrada
      - Resolvido na derivação, não numa tela de erro: `isOpen` exclui Ação
        cancelada, encerrada **e ilegível**. Abrir a Ação por link cai no
        `error:` que já existe em `action_detail_page.dart` ("Ação não
        encontrada") ou na marca "Cancelada", ambos sem opção de confirmar
- [x] 5.5 Entrada em `action_detail_page.dart`: botão "Convidar" para quem tem
      Conta, e o caminho de `/upgrade-conta` no lugar dele para Perfil anônimo
      - `OutlinedButton` "Convidar" para quem tem Conta, "Criar Conta para
        convidar" apontando para `/upgrade-conta` para Perfil anônimo. Some em
        Ação cancelada ou encerrada — o banco também recusaria
- [x] 5.6 Contador de convites em aberto na tela inicial (mitigação registrada
      no design para a ausência de notificação)
- [x] 5.7 Rotas `/acoes/:id/convidar` e `/convites` em `lib/app.dart`
      - `/acoes/:id/convidar` e `/convites` em `lib/app.dart`
- [x] 5.8 Julgar as duas telas na **largura de celular**, não no desktop:
      seções por Grupo, seleção múltipla e o resumo de falha parcial precisam
      caber ali sem rolagem horizontal

## 6. Testes de widget
      - **Feito, e é menos do que a task pede.** Os dois arquivos de teste de
        widget renderizam em 360x800, e o Flutter transforma estouro de layout
        em falha — então isso prova que nada escapa na horizontal. As seções por
        Grupo usam `ListView`, o resumo de falha quebra em várias linhas, e os
        chips de filtro usam `Wrap`
      - **NÃO feito: julgar olhando.** "Julgar" é ver a tela, e medição por
        script já mentiu duas vezes neste projeto (`PENDENCIAS.md` § 3, aviso de
        método). Registrado em `PENDENCIAS.md` § 3, separado no que dá para
        automatizar com navegador (render em 375 px, captura de tela, fluxo
        ponta a ponta com duas contas) e no que exige gente (o texto comunica?
        alvo de toque de 48 px, leitura por gente do distrito)
      - **Buraco maior, registrado junto**: nenhuma linha desta change passou
        pelo PostgREST. Os testes de integração falam com o Postgres direto e os
        de widget falam com mock, então as chamadas `rpc(...)` e os *embeds*
        `grupos(nome), acoes(*)` nunca foram executados de verdade
- [x] 6.1 Estado vazio de contatos (sem Grupo) mostra o caminho para `/grupos`
      - Em `convidar_para_acao_page_test.dart`
- [x] 6.2 Falha parcial do lote nomeia quem ficou de fora e oferece repetir
      - Dois casos: falha classificada pelo banco e rede caindo
- [x] 6.3 Filtro por Grupo reduz a lista e a contagem exibida corresponde ao que
      está na tela
      - Em `convites_recebidos_page_test.dart`, com a contagem conferida
- [x] 6.4 Perfil anônimo vê o caminho de Conta no lugar de "Convidar"

## 7. Gates e ledger
      - Em `convite_entrada_detalhe_test.dart`, 3 testes verdes
- [x] 7.1 `flutter analyze` — zero issue (colar a linha final)
      - `No issues found! (ran in 2.1s)`
- [x] 7.2 `flutter test test/unit test/widget` — colar a contagem real de testes
      - `00:08 +359: All tests passed!` — 359 testes, 0 falhas (contagem final)
      - **Duas quebras minhas, consertadas**: `ActionDetailPage` passou a ler
        `isAnonymousProvider`, e `acao_restrita_tela_test.dart` e
        `detalhe_acao_page_test.dart` renderizam aquela tela sem cliente
        Supabase. Os dois ganharam o override, com o porquê no comentário
- [x] 7.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os oito testes novos identificados
      - `00:13 +285: All tests passed!` — 285 testes, 0 falhas (contagem final), depois de
        `supabase db reset` limpo. Dez arquivos novos desta change:
        `contatos_para_convite_isolamento` (5), `_agrupamento` (5),
        `convidar_exige_conta` (3), `convite_nao_reserva_vaga` (3),
        `convite_leitura_restrita` (4), `convidar_em_lote` (3),
        `convite_idempotente` (2), `convite_anonimizacao` (2),
        `convite_acao_restrita` (4), `convite_recusa` (4) — 35 no total
- [x] 7.4 `flutter build web --release` conclui
      - `✓ Built build/web`
- [x] 7.5 `MAPA-DE-DADOS.md`: `convites_acao` e `contatos_para_convite` com
      `arquivo:linha`, dizendo qual dado pessoal cada uma toca
      - `MAPA-DE-DADOS.md`: linha nova na tabela "Quem vê o quê" para
        `convites_acao`, e três parágrafos com `arquivo:linha` dizendo o que
        cada peça toca — `contatos_para_convite` (`:118`) toca nome, apelido e
        participação em Grupo, e não toca idade, telefone, gênero nem Igreja;
        `convidar_para_acao` (`:177`) não devolve nome nenhum
- [x] 7.6 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
      - 10 requisitos e 29 cenários verificados. **Um achado, HIGH, resolvido
        nesta entrega**: o cenário "Quem convidou acompanha os próprios
        convites" pede que ele veja "quem já convidou por ali **e quem daquela
        lista já confirmou presença**", e a segunda metade não existia —
        `contatos_para_convite` devolvia só `ja_convidado`. Entrou
        `ja_confirmou`, e a tela passou a distinguir "Já convidado — sem
        resposta" de "Confirmou presença"
      - O lugar não podia ser a tela da Ação: o cenário vizinho proíbe lista de
        convidados ali para **qualquer pessoa**, inclusive quem convidou
      - Cinco hipóteses verificadas e derrubadas, no relatório da passagem
- [x] 7.7 `graphify --update` antes de considerar a change fechada
      - **Código: entrou.** AST sobre os 30 arquivos alterados, mesclado com
        `build_merge`. `graph.json` foi de 5640 para **5833 nós** e de 6596 para
        **6910 arestas**, 697 comunidades. Diagnóstico de saúde limpo: 0 ponta
        solta, 0 ponta ausente, 0 self-loop, 0 aresta colapsada. Custo: **zero
        token de LLM** — AST é determinístico
      - **Documentos: seguem pendentes**, pelo mesmo motivo registrado em
        `PENDENCIAS.md` § 2.9 e na task 7.8 de `acao-direcionada-a-grupo`. Os
        276 documentos alterados continuam fora do manifesto de propósito, para
        voltarem como pendentes no próximo `--update` em vez de contarem como
        processados
      - **Efeito colateral conhecido**: a mescla podou 61 nós de 7 arquivos que
        sumiram do caminho antigo — são os da change `acao-direcionada-a-grupo`,
        que mudou de lugar ao ser arquivada. Os caminhos novos são documentos e
        entram na próxima extração semântica; até lá, aquela change está no
        grafo só pelo código dela
