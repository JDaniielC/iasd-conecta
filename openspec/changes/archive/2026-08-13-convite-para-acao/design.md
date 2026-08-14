## Context

O que o banco já oferece e limita (ver `proposal.md - Why` para a motivação):

- `perfis_select_own` (`20260723191202_perfis_igrejas.sql:66-69`) impede ler o
  Perfil de outra pessoa. A única saída é `perfil_publico(uuid)`, `security
  definer`, **uma pessoa por chamada** (`:41-53`).
- `participacoes_grupo` é lida publicamente (`:121-124` de
  `20260723220703_grupos.sql`), então "quem participa de qual Grupo" já é
  público — o que não é público é o **nome** em lote.
- `confirmacoes_acao_decidir_status()` decide `confirmado`/`fila` sob
  `for update` na Ação (`20260723230639_acoes.sql:26-88`, substituída por
  `20260724110000_dupla_missionaria.sql`). Convite não pode encostar nisso.
- `acao_encerrada(uuid)` já existe e é `data_hora + 4h`
  (`20260809174740_acao_encerrada_bloqueia_presenca.sql:33-50`).
- `declarar_lideranca` é o precedente de "exige Conta": lê
  `auth.users.is_anonymous` de dentro de uma função `security definer`
  (`20260724100000_leadership.sql:20-38`). Policy sozinha não alcança
  `auth.users`.
- Não existe infraestrutura de notificação (push, e-mail ou in-app). O único
  lugar onde `notifica` aparece em `lib/` é `app.dart`.

## Goals / Non-Goals

**Goals:**
- A lista de contatos sai do banco em **uma** chamada, já agrupada e já sabendo
  quem foi convidado.
- As três regras de quem pode convidar (tem Conta, participa do Grupo,
  a pessoa convidada participa do mesmo Grupo) vivem num lugar só.
- Convidar cinco pessoas de uma vez sobrevive a uma delas falhar.

**Non-Goals:**
- Notificar. Sem push e sem e-mail nesta change; o convite aparece quando a
  pessoa abre a tela. Construir notificação aqui traria consentimento, opt-out
  e retenção junto — é change própria.
- Convite para quem não está em nenhum Grupo comum. Não há "buscar pessoa por
  nome" nesta change; a busca por nome no distrito inteiro é exatamente o que
  `perfis_select_own` foi escrito para impedir.
- Convite por link público.

## Decisions

### O convite é uma linha de `(acao_id, convidado_id, grupo_id)`, sem coluna de "aceito"

Tabela `convites_acao` com chave primária composta pelos três, mais
`convidante_id`, `created_at` e `recusado_em`.

**Não existe status de aceite** porque aceitar já tem tabela: aceitar é
confirmar presença, e isso é `confirmacoes_acao`. Uma coluna `status = 'aceito'`
seria uma segunda fonte de verdade sobre a mesma coisa, e as duas divergiriam
no primeiro `desistir`. "Em aberto" é derivado: existe a linha, `recusado_em is
null`, a pessoa não está em `confirmacoes_acao`, e a Ação não está cancelada
nem encerrada.

`recusado_em` existe porque recusar precisa de algum lugar — sem ele, o convite
ignorado e o convite recusado ficam indistinguíveis e a lista nunca esvazia.

_Alternativa recusada:_ `status text check (status in ('pendente','aceito',
'recusado'))`. Duplica o estado de presença e obriga a sincronizar duas tabelas
a cada confirmação e a cada desistência — o tipo de sincronização que este
projeto já pagou caro em outro lugar.

_Alternativa recusada:_ PK `(acao_id, convidado_id)` sem o Grupo. Torna
impossível o cenário "mesma pessoa convidada pelo Grupo Jovens e pelo Grupo
Música" e obriga a escolher um Grupo arbitrário para o filtro do item 2.

### Escrever convite é RPC `security definer`, não `insert` com policy

`authenticated` **não** recebe `grant insert` em `convites_acao`. A criação
passa por `convidar_para_acao(p_acao_id, p_grupo_id, p_convidados uuid[])`.

**Recusar é o caso oposto e leva tratamento oposto.** Quem recusa é a própria
pessoa convidada, sobre a própria linha, sem nenhuma regra que exija ler
`auth.users` — é o caso que uma policy resolve inteira. Então `recusado_em` sai
por `grant update (recusado_em)` mais `convites_acao_update_convidado`
(`using`/`with check` em `auth.uid() = convidado_id`), com recorte por coluna
pelo precedente de `20260811160000_grant_update_perfis_por_coluna.sql`: a linha
protegida e a coluna não era, e foi assim que dava para forjar `idade`. Com o
recorte, tentar escrever `convidante_id` ou `grupo_id` recusa por privilégio,
sem depender de a policy lembrar de proibir.

Quem convidou não retira o convite. Retirar em silêncio confundiria mais do que
ajudaria — mesmo raciocínio que a spec usa para sair do Grupo não apagar
convite.

Motivo: uma das três regras é "quem convida tem Conta", que exige ler
`auth.users.is_anonymous` — fora do alcance de qualquer policy. Se uma das
regras já precisa de `security definer`, colocar as outras duas numa policy
espalharia a mesma decisão por dois lugares com sintaxes diferentes. Ausência
de `grant insert` é o mecanismo, igual ao que a change `log-de-mudancas` faz
com a tabela dela — vale comentar isso na migration, senão parece esquecimento.

`select` continua por policy: `using (auth.uid() in (convidado_id,
convidante_id))`. Leitura não precisa de definer e policy é mais fácil de
auditar.

### Convidar em lote classifica cada pessoa, em vez de estourar na primeira

`convidar_para_acao` recebe um array e devolve uma linha por pessoa pedida:
`(usuario_id, resultado)` com `resultado in ('criado','ja_convidado',
'nao_participa')`. Uma única `insert ... select ... from unnest(...)` com
`on conflict do nothing`, e uma CTE classificando o resto.

`RETURNING` sozinho não serve: com `on conflict do nothing`, quem já tinha sido
convidado não volta no `RETURNING` e a tela leria isso como falha — mostrando
erro para uma operação que deu certo.

_Alternativa recusada:_ um `insert` por pessoa a partir do Dart. Cinco pessoas
= cinco round-trips, e a classificação de erro teria que ser adivinhada da
mensagem do Postgres.

_Alternativa recusada:_ loop plpgsql com `exception when others` por pessoa.
Mesmo resultado, mais código, e engole erro que deveria estourar.

### A lista de contatos é uma função `security definer` que filtra por `auth.uid()`

`contatos_para_convite(p_acao_id uuid)` devolve
`(grupo_id, grupo_nome, usuario_id, nome_exibido, ja_convidado)` para todos os
Grupos ativos em que `auth.uid()` participa, de uma vez.

Ela é `security definer` porque `perfis` é fechado; ela é **filtrada por
`auth.uid()` por dentro**, nunca por parâmetro de Grupo vindo do cliente.
Aceitar `p_grupo_id` do cliente numa função definer seria entregar a lista de
nomes de qualquer Grupo do distrito a qualquer sessão — inclusive `anon`. Como
`auth.uid()` é `null` em sessão anônima, o filtro devolve vazio sozinho, sem
`if` especial.

`nome_exibido` usa a mesma expressão de `perfil_publico`
(`coalesce(apelido, nome)`), e não outra: duas definições de "nome que aparece"
divergiriam, e a que protege menor de idade é essa.

`set search_path = public, auth` obrigatório, como em toda função definer deste
projeto.

_Alternativa recusada:_ manter o caminho de `fetchMembers` e chamar
`perfil_publico` N vezes. É o N+1 de hoje (`group_repository.dart:151-161`)
multiplicado pelo número de Grupos.

_Alternativa recusada:_ afrouxar `perfis_select_own` para "quem divide Grupo
comigo lê meu Perfil". Abriria `telefone`, `idade` e `igreja_id` junto — a
policy é por linha, não por coluna.

### Ação cancelada ou encerrada filtra na leitura; nada é apagado

O convite continua na tabela; a consulta de "convites em aberto" exclui Ação com
`cancelada_em not null` ou `acao_encerrada(acao_id)`. Reaproveita a função que
já existe e é gêmea de `defaultActionDuration` no Dart.

Apagar exigiria gatilho em `acoes` e destruiria o rastro de que o convite
existiu. Sair do Grupo, por sua vez, não filtra nada — decisão de produto já
registrada na spec.

### Filtro por Grupo acontece no cliente

A lista de convites de uma pessoa é curta e já vem inteira. As opções de filtro
são os Grupos presentes nos convites **interseccionados com os Grupos em que a
pessoa participa hoje** — por isso o convite de um Grupo que ela deixou
continua na lista sem filtro, mas some das opções.

## Risks / Trade-offs

- **Função definer mal filtrada vira dump de nomes do distrito** → o filtro é
  por `auth.uid()` de dentro, o parâmetro de Grupo não existe, e o teste de
  integração inclui uma sessão `anon` e uma sessão autenticada sem Grupo
  comum, ambas esperando resultado **vazio**. Sem esses dois testes, esta
  change não fecha.
- **Convite sem notificação pode não ser visto** → aceito nesta change. O
  contador de convites em aberto entra na tela inicial para reduzir o problema
  sem construir infraestrutura de push.
- **Convite vira vetor de incômodo** (convidar a mesma pessoa para tudo) → não
  há bloqueio nesta change. `recusado_em` dá o dado para uma regra futura de
  "não me convide mais"; construir bloqueio agora é especular sobre um abuso
  que ainda não aconteceu num app de distrito.
- **Interação com `acao-direcionada-a-grupo`** → aquela change acrescenta que
  convite para Ação restrita não alcança quem é de fora do Grupo. Se ela entrar
  depois desta, o ajuste é em `convidar_para_acao` e na função de contatos, e
  as tarefas dela dizem isso. Se entrar antes, esta já nasce com a regra.

## Migration Plan

Uma migration, puramente aditiva: tabela, índices
(`(convidado_id, created_at desc)` e `(acao_id, convidante_id)`), RLS ligada com
a policy de `select`, a policy de `update` só do convidado, `grant select` e
`grant update (recusado_em)` para `authenticated` (nada para `anon` — convite
não é público), e as duas funções.

Nenhuma tabela existente muda; nenhum gatilho existente é tocado. Rollback é
`drop` da tabela e das duas funções, sem efeito sobre Ação, Grupo ou presença.
