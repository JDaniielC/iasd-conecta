## 1. Banco — tabela, privilégios e RLS

- [ ] 1.1 Migration nova com `public.convites_acao` (`acao_id`, `convidado_id`,
      `grupo_id`, `convidante_id`, `created_at`, `recusado_em`), PK composta
      `(acao_id, convidado_id, grupo_id)`, `acao_id` e `grupo_id` com
      `on delete cascade`, `convidado_id` e `convidante_id` referenciando
      `perfis(id)` **sem cascade** (o Perfil é anonimizado, não apagado —
      `20260806140000_exclusao_de_conta.sql:14-16`)
- [ ] 1.2 `grant select on public.convites_acao to authenticated` e **nada para
      `anon`**. Nenhum `grant insert`, `update` ou `delete` para ninguém — a
      ausência é o mecanismo, não esquecimento; escrever isso em comentário na
      migration
- [ ] 1.3 RLS ligada com uma policy só: `convites_acao_select_partes`, para
      `authenticated`, `using (auth.uid() in (convidado_id, convidante_id))`
- [ ] 1.4 Índices `convites_acao_por_convidado (convidado_id, created_at desc)`
      e `convites_acao_por_acao (acao_id, convidante_id)`
- [ ] 1.5 `comment on table` e `comment on column` explicando por que não existe
      coluna de aceite (aceite é `confirmacoes_acao`) e por que `recusado_em`
      existe

## 2. Banco — funções

- [ ] 2.1 `contatos_para_convite(p_acao_id uuid)` `security definer`,
      `set search_path = public, auth`, devolvendo `(grupo_id, grupo_nome,
      usuario_id, nome_exibido, ja_convidado)`; filtra por `auth.uid()` **por
      dentro**, sem parâmetro de Grupo vindo do cliente; exclui `auth.uid()` da
      própria lista; exclui Grupo com `arquivado_em not null`; `nome_exibido`
      usa `coalesce(apelido, nome)`, a mesma expressão de `perfil_publico`
      (`20260723191202_perfis_igrejas.sql:47`)
- [ ] 2.2 `convidar_para_acao(p_acao_id uuid, p_grupo_id uuid, p_convidados
      uuid[])` `security definer`, devolvendo uma linha por pessoa pedida com
      `resultado in ('criado','ja_convidado','nao_participa')`; recusa se quem
      chama é anônimo (`auth.users.is_anonymous`, padrão de
      `20260724100000_leadership.sql:26-31`), se quem chama não participa de
      `p_grupo_id`, ou se a Ação está cancelada/encerrada
      (`acao_encerrada(uuid)`)
- [ ] 2.3 `grant execute` das duas funções apenas para `authenticated`
- [ ] 2.4 `supabase db reset` roda limpo e as duas funções aparecem em
      `\df public.*convite*` (colar a saída)

## 3. Testes de integração — o que a tela não prova

- [ ] 3.1 `contatos_para_convite_isolamento_test.dart`: sessão `anon` recebe
      **lista vazia**; sessão autenticada sem Grupo em comum recebe **lista
      vazia**. Sem estes dois, a change não fecha (design — Risks)
- [ ] 3.2 `contatos_para_convite_agrupamento_test.dart`: pessoa em dois Grupos
      recebe as duas seções; quem participa dos mesmos dois Grupos aparece nos
      dois; quem chama não aparece na própria lista; Grupo arquivado não vem
- [ ] 3.3 `convidar_exige_conta_test.dart`: sessão anônima é recusada; sessão
      com Conta cria o convite
- [ ] 3.4 `convite_nao_reserva_vaga_test.dart`: Ação com `limite_vagas = 1`,
      pessoa convidada, outra confirma antes e ocupa a vaga, a convidada
      confirma depois e cai em `fila`; a contagem de confirmados não muda no
      momento do convite
- [ ] 3.5 `convite_leitura_restrita_test.dart`: terceiro autenticado pedindo
      `convites_acao` de uma Ação recebe **conjunto vazio**, não erro
- [ ] 3.6 `convidar_em_lote_test.dart`: array com uma pessoa válida, uma já
      convidada e uma que não participa devolve as três classificações certas,
      e a válida fica gravada
- [ ] 3.7 `convite_idempotente_test.dart`: convidar duas vezes pelo mesmo Grupo
      dá uma linha; convidar pela mesma Ação por dois Grupos dá duas
- [ ] 3.8 `convite_anonimizacao_test.dart`: depois de `excluir_conta` de quem
      convidou, a leitura do convite não devolve o nome anterior

## 4. Domínio e dados no app

- [ ] 4.1 `lib/features/invite/domain/action_invite.dart` — modelo do convite
      com o Grupo de origem; chaves de mapa em português (`acao_id`,
      `grupo_id`, `convidado_id`, `recusado_em`), identificadores em inglês
      (CONTEXT.md — fronteira de idioma)
- [ ] 4.2 `lib/features/invite/domain/invite_contact.dart` e
      `invite_contact_group.dart` — contato e seção por Grupo
- [ ] 4.3 `lib/features/invite/data/invite_repository.dart` — único ponto de
      acesso a `convites_acao` e às duas funções; `fetchContacts(actionId)`,
      `invite(actionId, groupId, userIds)`, `fetchReceivedInvites()`,
      `decline(...)`. **Uma** chamada de rede por operação — nada de laço de
      `perfil_publico` (o N+1 de `group_repository.dart:151-161` é justamente o
      que esta change existe para não repetir)
- [ ] 4.4 `lib/features/invite/invite_providers.dart` — providers Riverpod, no
      padrão dos existentes em `action_providers.dart`
- [ ] 4.5 Testes de unidade do mapeamento de/para as chaves em português e da
      derivação de "convite em aberto" (existe, `recusado_em` nulo, não
      confirmado, Ação viva)

## 5. Telas

- [ ] 5.1 `invite_to_action_page.dart` em `/acoes/:id/convidar`: seções por
      Grupo, seleção múltipla, quem já foi convidado aparece marcado e não
      selecionável; estado vazio ("a lista vem dos seus Grupos") com caminho
      para `/grupos`
- [ ] 5.2 Resultado do lote na tela: quantos foram, e **quem** ficou de fora,
      nominalmente, com botão de tentar de novo só para quem falhou. Nunca
      afirmar sucesso quando a chamada falhou
- [ ] 5.3 `received_invites_page.dart` em `/convites`: lista de convites em
      aberto, cada um dizendo por qual Grupo veio; filtro por Grupo cujas
      opções são só os Grupos em que a pessoa participa hoje; recusar; abrir a
      Ação
- [ ] 5.4 Convite de Ação cancelada ou encerrada não entra na lista; abrir um
      por link mostra "Ação cancelada", sem opção de confirmar presença e sem
      tela quebrada
- [ ] 5.5 Entrada em `action_detail_page.dart`: botão "Convidar" para quem tem
      Conta, e o caminho de `/upgrade-conta` no lugar dele para Perfil anônimo
- [ ] 5.6 Contador de convites em aberto na tela inicial (mitigação registrada
      no design para a ausência de notificação)
- [ ] 5.7 Rotas `/acoes/:id/convidar` e `/convites` em `lib/app.dart`
- [ ] 5.8 Julgar as duas telas na **largura de celular**, não no desktop:
      seções por Grupo, seleção múltipla e o resumo de falha parcial precisam
      caber ali sem rolagem horizontal

## 6. Testes de widget

- [ ] 6.1 Estado vazio de contatos (sem Grupo) mostra o caminho para `/grupos`
- [ ] 6.2 Falha parcial do lote nomeia quem ficou de fora e oferece repetir
- [ ] 6.3 Filtro por Grupo reduz a lista e a contagem exibida corresponde ao que
      está na tela
- [ ] 6.4 Perfil anônimo vê o caminho de Conta no lugar de "Convidar"

## 7. Gates e ledger

- [ ] 7.1 `flutter analyze` — zero issue (colar a linha final)
- [ ] 7.2 `flutter test test/unit test/widget` — colar a contagem real de testes
- [ ] 7.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os oito testes novos identificados
- [ ] 7.4 `flutter build web --release` conclui
- [ ] 7.5 `MAPA-DE-DADOS.md`: `convites_acao` e `contatos_para_convite` com
      `arquivo:linha`, dizendo qual dado pessoal cada uma toca
- [ ] 7.6 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
- [ ] 7.7 `graphify --update` antes de considerar a change fechada
