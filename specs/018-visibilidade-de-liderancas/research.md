# Research: visibilidade das declarações de Líder/Diretor

**Feature**: `018-visibilidade-de-liderancas` | **Data**: 2026-08-09

Este arquivo registra o que foi lido no código antes de desenhar a política, e as decisões
que o plano toma. Cada afirmação tem `arquivo:linha` — o resto é palpite.

---

## D-001 — Quais estados uma declaração pode ter, de verdade

**Pergunta**: "confirmada" é `confirmado_em is not null`, ou `confirmado_em is not null AND
rejeitado_em is null`? Uma linha pode ter os dois preenchidos?

**O que o código faz** (`supabase/migrations/20260724100000_leadership.sql`):

| Caminho | Efeito em `confirmado_em` | Efeito em `rejeitado_em` |
|---|---|---|
| `declarar_lideranca` — insert novo | fica `null` (default) | fica `null` (default) |
| `declarar_lideranca` — `on conflict do update` | intocado (só roda `where confirmado_em is null`) | zerado (`rejeitado_em = null`) |
| `decidir_lideranca(p_aprovar => true)` | `now()` | `null` (explicitamente zerado) |
| `decidir_lideranca(p_aprovar => false)` | `null` (explicitamente zerado) | `now()` |

Ou seja: **as duas funções zeram o campo oposto**. Os três estados são mutuamente exclusivos
por construção, e é isso que `LeadershipStatus` no Dart assume
(`lib/features/leadership/domain/leadership_declaration.dart:26-30`, que checa `confirmedAt`
primeiro e nem olha `rejectedAt` depois).

**Mas não há `check` constraint.** A tabela (`leadership.sql:3-13`) não impede a combinação
`confirmado_em is not null AND rejeitado_em is not null`. O que impede hoje é o **grant**:

```
grant select on public.liderancas to anon, authenticated;   -- linha 65: SÓ select
```

Não existe `grant insert`/`grant update` na tabela para `anon`/`authenticated` — toda escrita
passa pelas duas funções `security definer`
(`lib/features/leadership/data/leadership_repository.dart:5-7` documenta isso). Quem escreve
direto é `service_role`, seed manual, ou um teste rodando como `postgres`.

**Decisão**: a política escreve o predicado **completo** —
`confirmado_em is not null and rejeitado_em is null`. Não porque a combinação seja alcançável
hoje, mas porque:

1. O custo é uma conjunção a mais, e o custo de errar é o dado que a feature existe pra
   proteger.
2. Se um dia alguém der `grant update`, ou uma migration criar uma linha estranha, a política
   nega **por default** em vez de vazar.
3. `fetchCurrentLeaders` (`leadership_repository.dart:31-37`) hoje filtra só
   `confirmado_em is not null` — a política mais apertada é a rede embaixo, não a duplicata.

**Consequência declarada**: com o predicado completo na política e incompleto no cliente, uma
linha com os dois campos preenchidos sumiria da tela sem erro. Por isso T012 alinha o cliente
ao mesmo predicado — os dois lados dizem a mesma coisa, no estilo da "duplicação declarada"
da feature 011 (`specs/011-acoes-titulo-e-encerramento/contracts/schema.sql:27-31`).

---

## D-002 — A política: um `or` de três disjuntos, um por leitor

Três leitores, necessidades diferentes, **uma** tabela e **uma** política de select:

| Leitor | O que precisa ler | Disjunto que o atende |
|---|---|---|
| Visitante (`anon`) e Usuário comum | só confirmadas | `confirmado_em is not null and rejeitado_em is null` |
| A própria pessoa | a **sua**, em qualquer estado | `usuario_id = auth.uid()` |
| Administrador do distrito | todas | `exists (select 1 from administradores_distrito ...)` |

**Precedente exato no repo**: `igrejas_select_ativas_publico`
(`supabase/migrations/20260724092132_district_admin.sql:66-75`) já usa a forma
"condição pública `or` exists-admin", com `to anon, authenticated`, e funciona em produção.
Não estamos inventando padrão.

**`auth.uid()` com role `anon`**: retorna `null` (não existe claim `sub`). `usuario_id = null`
é `null` → não é `true` → o disjunto não dispara; `usuario_id = auth.uid()` nunca vira `true`
por acidente. Mesmo para o `exists`. Confirmado pelo comportamento já testado de
`igrejas_select_ativas_publico` em `test/integration/church_archive_visibility_test.dart:57+`.

**A subconsulta em `administradores_distrito` não recursa**: é outra tabela, cuja policy
(`district_admin.sql:52-55`) é `using (true)` para `anon, authenticated` — a subconsulta não é
bloqueada por RLS.

**Não usamos `(select auth.uid())`** (o truque de initplan do PostgREST): nenhuma policy do
repo usa, `auth.uid()` já é `stable`, e `administradores_distrito` tem unidades de linha, não
milhares. Consistência de estilo > micro-otimização não medida. Se um dia a tabela crescer,
o lugar de mudar é este parágrafo.

---

## D-003 — Por que a política, e não um filtro no repositório

FR-004 responde: "a restrição DEVE ser garantida no banco, não na tela". Filtrar no Dart é
exatamente o que já acontece (`leadership_repository.dart:36`) e é exatamente o que **não
protege** — o cliente Supabase fala PostgREST, e qualquer um monta a mesma requisição sem o
filtro. Só a RLS vale.

Também não é trigger nem view: não há escrita a bloquear (a feature é sobre leitura), e uma
view exigiria mudar os três pontos de leitura do Dart sem ganhar nada.

---

## D-004 — As três telas continuam funcionando (prova por consulta)

| Tela | Consulta | Predicado do cliente | Por que a política deixa passar |
|---|---|---|---|
| Página do Ministério (`group_detail_page.dart:137` → `currentLeadersProvider`) | `fetchCurrentLeaders` (`leadership_repository.dart:31-37`) | `grupo_id`, `ano`, `confirmado_em is not null` | 1º disjunto — confirmada é pública para `anon` |
| Estado da própria declaração (`declare_leadership_page.dart:51` → `myDeclarationProvider`) | `fetchMyDeclaration` (`leadership_repository.dart:45-51`) | `grupo_id`, `usuario_id = uid`, `ano` | 2º disjunto — `usuario_id = auth.uid()`, qualquer estado |
| Pendências do Administrador (`pending_declarations_page.dart:37` → `pendingDeclarationsProvider`) | `fetchPendingDeclarations` (`leadership_repository.dart:59-64`) | `confirmado_em is null and rejeitado_em is null` | 3º disjunto — `exists` na `administradores_distrito` |

**Detalhe do 2º caso**: `fetchMyDeclaration` usa `.maybeSingle()`, que estoura se vier mais de
uma linha. Os filtros são exatamente a chave única `(grupo_id, usuario_id, ano)`
(`leadership.sql:12`), então no máximo uma linha — a política só **remove** linhas, nunca
adiciona. Nenhum risco novo.

**Detalhe do 3º caso**: a rota `/leadership/pending` (`lib/app.dart:150-152`) **não é gateada
por `isDistrictAdminProvider`** — qualquer um que digite a URL abre a tela. Hoje, com
`using (true)`, esse alguém vê as pendências do distrito inteiro. Depois desta feature, vê no
máximo a **própria** declaração pendente, ou a tela vazia com "Nenhuma declaração pendente."
(`pending_declarations_page.dart:44`). Não é regressão — é a segunda coisa que esta feature
conserta de graça. Sem `catch` novo: a consulta não falha, só volta menos linha.

---

## D-005 — Expiração anual: a política é cega para `ano`, e isso está certo

A spec assume que uma declaração confirmada de 2025 continua pública em 2026. **O código
concorda, e a política não muda nada disso**:

- A expiração **não é um estado no banco**. Não há job, não há coluna, não há
  `expirado_em`. É comparação preguiçosa: `currentLeadersProvider` monta a consulta com
  `DateTime.now().year` (`lib/features/leadership/leadership_providers.dart:13-14`) e
  `LeadershipDeclaration.isCurrentFor` compara `year` no cliente
  (`leadership_declaration.dart:34-36`).
- `test/integration/leadership_yearly_expiry_test.dart:60-70` fixa isso: uma confirmação do ano
  anterior "não conta como atual" — mas a linha continua **existindo e legível**.
- `test/integration/leadership_public_current_test.dart:66-79` já lê **duas** confirmadas
  (ano corrente e ano anterior) como `anon` e espera as duas.

A política proposta não menciona `ano`. Logo: confirmada de 2025 continua legível por `anon`
em 2026, `leadership_public_current_test` continua passando, e FR-009 ("a regra de expiração
NÃO DEVE ser alterada") é satisfeito por omissão deliberada.

---

## D-006 — Interação com a feature 014 (arquivar Grupo)

`specs/014-arquivar-grupo/data-model.md:82,105` e `contracts/schema.sql:182` são explícitos:
**a 014 não toca `liderancas` no banco, de propósito** — a declaração é histórico de quem foi
responsável perante a igreja. O que a 014 quer é que o Ministério arquivado pare de
**exibir** o Líder, e ela resolve isso na consulta (`specs/014-arquivar-grupo/tasks.md:101`,
T018, que aponta para `leadership_repository.dart` e `currentLeadersProvider`).

**As duas features escrevem no mesmo arquivo Dart** (`leadership_repository.dart`,
`fetchCurrentLeaders`). Nenhuma escreve na política da outra: a 018 mexe na RLS, a 014 mexe na
consulta. Quem implementar por último lê o arquivo já modificado — merge textual, não conflito
de regra.

**Residual declarado**: depois das duas, uma declaração **confirmada** de um Grupo arquivado
continua legível por `anon` via API direta, porque a 014 escolheu esconder na exibição, não no
banco. Isso é decisão da 014, registrada na data-model dela, e a 018 **não** a altera —
apertar aqui seria decidir por outra feature. Fica anotado no cabeçalho da migration para
quem for auditar depois não achar que é descuido desta.

**Ordem**: a 014 ainda não tem migration em `supabase/migrations/` (última é
`20260809174740_acao_encerrada_bloqueia_presenca.sql`). A 018 pode entrar antes, sem esperar.

---

## D-007 — O teste tem que consultar como `anon`, não olhar a tela

SC-001 exige verificação por **consulta direta à API**. O motivo é literal: a tela é o que
esconde o problema hoje (`group_detail_page.dart:126-140` só renderiza confirmado), então um
teste de widget que passa não prova nada — ele reproduz a mesma ilusão que criou o vazamento.

**Método**: `dart test test/integration`, conexão direta ao Postgres local
(`test/integration/db_test_helper.dart:6-17`), com `set role anon` / `set role authenticated`
+ `set request.jwt.claims`.

**Por que isso equivale a "consulta à API"**: PostgREST não tem lógica de autorização própria —
ele abre a conexão com o role (`anon` ou `authenticated`), injeta o JWT em
`request.jwt.claims`, e **a RLS é a única coisa que filtra**. O teste faz exatamente essas duas
coisas. É o método já usado por `test/integration/acoes_select_publico_test.dart:35-56`,
`grupos_select_publico_test.dart` e `church_archive_visibility_test.dart:12-25` — e o próprio
`leadership_public_current_test.dart:66-79` já testa `anon` nesta tabela. Não estamos inventando
harness.

**Armadilha herdada, obrigatória de copiar**: `reset role` **não** limpa GUC customizado. Sem
`reset request.jwt.claims`, um `set role anon` posterior ainda enxerga o `sub` antigo e o teste
mente. Está documentado em `church_archive_visibility_test.dart:18-22`, descoberto na validação
manual da 005. O novo teste repete os dois `reset`.

**Contagem (edge case da spec)**: a preocupação de "resposta vazia revelar por diferença de
tamanho" não se aplica — RLS filtra **antes** da agregação, então `count(*)` como `anon` já
retorna o número pós-filtro. O teste verifica isso explicitamente, e não existe nenhuma tela
pública que mostre "N pendentes".

---

## D-008 — Correção de fato: a spec erra num edge case (conta excluída)

A spec diz (Edge Cases, item 3): *"A pessoa que se declarou excluiu a conta: o Perfil vira
'Membro removido' e a declaração continua apontando para ele, como histórico da feature 009."*

**Isso não é o que o código faz.**
`supabase/migrations/20260806140000_exclusao_de_conta.sql:137` executa:

```sql
delete from public.liderancas where usuario_id = v_uid;
```

A declaração **dela é apagada**. O que sobrevive é `liderancas.confirmado_por` — o registro do
ato de confirmar de **outra** pessoa (comentário em `exclusao_de_conta.sql:125-127`, e o
cenário 10 de `test/integration/account_deletion_test.dart:436-453` fixa os dois lados: 0 linhas
com `usuario_id`, 1 linha com `confirmado_por`).

**Impacto nesta feature**: nenhum, e é por isso que não vira tarefa nem `/speckit-clarify`. Linha
apagada não é linha vazada. A correção fica registrada aqui porque a spec afirma um fato falso
sobre o banco, e a próxima pessoa que ler o edge case vai procurar uma linha que não existe.

---

## D-009 — Premissas a verificar antes de aplicar a migration

1. `public.liderancas` **não** está com `force row level security` (senão o `security definer`
   de `excluir_minha_conta` passaria a ser filtrado pela política nova e o delete da conta
   pararia de apagar a declaração — a mesma classe de bug que a 011 evitou em
   `specs/011-.../contracts/schema.sql:15-26`).
2. Não existe `grant insert`/`grant update`/`grant delete` em `public.liderancas` para
   `anon`/`authenticated` — a política nova é só de `select`, e escrita continua exclusivamente
   pelas funções `security definer`.
3. `public.administradores_distrito` continua com `select` liberado a `anon, authenticated`
   (`district_admin.sql:44,52-55`) — se isso apertar, o 3º disjunto para de enxergar a linha do
   admin e a tela de pendências esvazia.

Se qualquer uma cair, **parar** e revisar o contrato antes de aplicar. Comandos em
`quickstart.md`.
