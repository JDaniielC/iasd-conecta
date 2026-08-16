# Pendências

**Atualizado**: 2026-08-10 | **Base**: `main`, commit `90c9bee`

O que falta, em quatro grupos: o que **implementar** (já tem spec, plan e tasks), o que
**especificar** (achado real, sem spec), o que **só gente mede** (verificação manual), e o
que **depende de decisão sua**.

As cinco decisões da seção 4 foram respondidas em 2026-08-09, e as três features que elas
travavam foram entregues (014, 015) ou destravadas (019). **Nada está bloqueado por decisão
hoje** — o que resta é trabalho, mais dois pedidos de acesso à nuvem.

---

## 1. Implementar — spec, plan e tasks prontos

Nada aqui precisa de trabalho de especificação. É só executar.

| Feature | Tarefas | O que entrega | Bloqueio |
|---|---|---|---|
| **013** foto-de-capa | 31 abertas de 35 | Foto de capa de Grupo e Ação, com aviso contra foto pessoal e de menor | — (branch `013-foto-de-capa`, fundação pronta) |
| **020** deploy-gcs-cdn | 32 (7 humanas) | Publicar em Cloud Storage + CDN, com invalidação de cache | 7 tarefas exigem conta GCP — só você |

**Entregues desde a última versão desta lista**: 014 (arquivar Grupo), 015 (autorização do
responsável), 016 (Meu Perfil), 017 (versão do consentimento), 018 (visibilidade de
lideranças), 019 (região e backup), 021 (visibilidade do voto) e 022 (Novidades).

**Sugestão de ordem**: **013**, que é a única de produto que sobrou — o que falta nela é o
app, não a infraestrutura. A 020 espera o acesso GCP e destrava as duas verificações que
exigem produção no ar.

---

## 2. Especificar — achado real, sem spec

Vieram de verificação durante a implementação, não de auditoria dedicada. Nenhum deve virar
código antes de ter spec.

> **Cinco destes viraram change OpenSpec em 2026-08-11** (`openspec/changes/`), com proposal,
> spec-delta, design e tasks: `endurecer-grant-update-perfis` (§ 2.1),
> `revogar-truncate-de-anon-e-authenticated` (§ 2.2), `destravar-cadastro-antigo-de-crianca`
> (§ 2.3), `travar-deploy-com-teste-vermelho` (§ 2.4) e `estabilizar-suite-de-integracao`
> (§ 2.6). As seções abaixo continuam sendo o registro do **achado**; a change é o plano.
> O § 2.5 não virou change de propósito — é dívida com custo já avaliado e decisão de não
> fazer, não trabalho pendente.

### 2.1 `grant update` em `perfis` sem recorte de coluna

Registrado em `SECURITY-AUDIT.md`, achado 5. `perfis_update_own` protege a **linha**, não a
**coluna**: por chamada direta à API, a pessoa consegue escrever a própria `idade` e o próprio
`genero`.

**Não é vazamento** — só o próprio dado. É contorno de regra de domínio: mudar a `idade` foge
da exigência de Apelido de menor, mudar o `genero` forja composição de Dupla Missionária.

O conserto está escrito no achado (`revoke update` + `grant update (colunas)`). Exige migration
e conferir coluna a coluna quem mais escreve em `perfis`.

**FECHADO em 2026-08-11** pela change `endurecer-grant-update-perfis`.
`supabase/migrations/20260811160000_grant_update_perfis_por_coluna.sql` aplica exatamente o
conserto do achado: `revoke update on public.perfis from authenticated`, seguido de `grant
update (nome, apelido, igreja_id, telefone, consentimento_lgpd_igreja_aceito_em)` — as cinco
colunas que `Profile.toUpdateMap()` já mandava, nenhuma outra. Levantamento em `lib/` e nas
migrations não achou ponto de escrita fora da lista; `excluir_minha_conta` é `security definer`
e não é afetada. Provado por `test/integration/perfil_edicao_rls_test.dart` (casos novos g/h:
`idade` e `genero` recusam com `permission denied`, 42501) e pela suíte inteira — **212/212**
testes de integração e **17/17** testes de widget das telas de Perfil, todos passando sem
nenhuma tela quebrar.

### 2.2 `anon` tem `TRUNCATE` em todas as tabelas — **FECHADO em 2026-08-11**

Descoberto ao verificar as premissas da 018. `anon` e `authenticated` têm `TRUNCATE`,
`REFERENCES` e `TRIGGER` nas 14 tabelas de `public` — herança do default do Supabase. **TRUNCATE
ignora RLS por completo.**

**Não é porta aberta hoje**: `anon` é `rolcanlogin = f`, só alcançável via PostgREST, que mapeia
verbos HTTP para SELECT/INSERT/UPDATE/DELETE e nunca emite TRUNCATE. É desvio de menor
privilégio, não vulnerabilidade viva — e é assim que deve ser descrito, sem dramatizar.

Vale spec porque o conserto (`revoke truncate, references, trigger`) toca todas as tabelas e
precisa de teste que prove que nada legítimo quebrou.

**Deixou de ser teórico em 2026-08-10.** A feature 013 mostrou o dano concreto: `TRUNCATE`
ignora RLS **e não dispara gatilho `after delete`**. Na 013, uma única instrução apagaria todas
as linhas de capa sem enfileirar nada, e **todos os arquivos do bucket virariam órfãos de uma
vez** — derrubando o desenho inteiro da feature por uma porta que ela nem abriu. A 013 fechou
para as suas duas tabelas; **as outras 14 continuam abertas**, e agora se sabe que a
consequência depende do que cada tabela sustenta.

**Conserto**, openspec `revogar-truncate-de-anon-e-authenticated`:
`supabase/migrations/20260811120000_revogar_truncate_de_anon_e_authenticated.sql` —
`revoke truncate, references, trigger on all tables in schema public from anon, authenticated`
(fecha o presente) + `alter default privileges for role postgres in schema public revoke ...`
(fecha o futuro; `for role postgres` porque é o papel que roda as migrations deste projeto, mesma
descoberta de `20260805090000_service_role_default_privileges.sql`).

**Antes**: `information_schema.role_table_grants` — 14 tabelas × 2 papéis = 28 linhas com
`REFERENCES, TRIGGER, TRUNCATE` pra `anon`/`authenticated`. **Depois**: 0 linhas; `pg_default_acl
FOR ROLE postgres` confirmado sem `D`/`x`/`t` pros dois papéis.

**Prova, não só "TRUNCATE falha"**: suíte de integração inteira antes e depois da migration.
Antes: `flutter analyze` 0 issues, `flutter test test/unit test/widget` 273 passando, `dart test
test/integration` 210 passando. Depois: mesmos números pras duas primeiras; integração foi 210 →
214 — delta de +4 é exatamente os 4 testes novos que provam a revogação
(`test/integration/privilegios_publicos_truncate_test.dart`: `truncate` recusado com `42501` em
`acoes` [RLS pública], `perfis` [gatilho] e `participacoes_grupo` [junção]; tabela criada numa
transação `begin`/`rollback` nasce sem os três privilégios). Nenhum teste pré-existente quebrou —
nenhum caminho legítimo do app dependia de `REFERENCES`/`TRIGGER`/`TRUNCATE` em `anon`/
`authenticated`.

Achado colateral durante a medição: o Postgres local estava com uma migration de outra worktree
aplicada (`grant update` em `perfis` por coluna) que não existe no histórico desta branch —
`supabase db reset` foi necessário antes da baseline pra alinhar o banco só com as migrations
desta worktree. Isso é característica do Supabase local ser compartilhado entre worktrees por
porta fixa, não bug desta change.

### 2.3 Cadastro antigo de criança ficou somente-leitura — **DECIDIDO em 2026-08-12**

Consequência conhecida e aceita da feature 015: um cadastro de criança anterior a ela não tem
os dados do responsável, e a check constraint recusa **qualquer** `update` naquela linha —
inclusive de campo sem relação, como telefone. Localmente são **0** cadastros assim.

A pessoa não fica presa: a tela traduz a recusa numa frase pedindo que escreva para o e-mail
de contato, e a **exclusão de conta continua funcionando** (a anonimização zera `idade` e as
constraints passam), então o art. 18 VI está a salvo. Isso é **provado por teste**, não
suposto: `test/integration/autorizacao_responsavel_test.dart`, grupo "cadastro antigo,
anterior à feature", caso "LGPD art. 18 VI" — a linha é semeada com a constraint derrubada
dentro de uma transação (é o equivalente de uma linha que já estava lá quando a migration
entrou), e a exclusão conclui. **13/13** naquele arquivo em 2026-08-12.

**Decisão de 2026-08-12 (change `destravar-cadastro-antigo-de-crianca`): saída A — não fazer
nada, e registrar.** **Medido em produção**, não deduzido: a consulta abaixo rodou no SQL
Editor do painel, projeto `mbfcnebyxzoagwatjxuh` (`iasd-conecta-vsa`, branch `main`,
PRODUCTION), role `postgres`, em 2026-08-12 — **count = 0**.

```sql
select count(*) from public.perfis
where idade is not null
  and idade < public.limiar_crianca()
  and (responsavel_nome is null
    or responsavel_contato is null
    or autorizacao_responsavel_em is null
    or autorizacao_responsavel_versao is null);
```

O zero era o esperado pelas datas, e elas ficam registradas porque explicam **por que** zero:
produção nasceu em 2026-08-07, a constraint da 015 entrou lá no push de 2026-08-11, e o
lançamento ao distrito é 2026-10-06 — a única janela em que um cadastro assim poderia ter
nascido eram esses quatro dias, com produção fechada ao público. Mas o que fecha este item é a
medição, não o raciocínio.

Se o número deixar de ser zero depois do lançamento, o caminho é o e-mail de contato (saída B)
e, só se passar de um punhado, a spec própria de autorização retroativa (saída C) — que a 015
excluiu de propósito. As três saídas, com custo, estão em
`openspec/changes/.../destravar-cadastro-antigo-de-crianca/design.md`.

### 2.4 `deploy-web.yml` publica mesmo com teste vermelho

`.github/workflows/deploy-web.yml` dispara em `push: branches: [main]`, sem `needs:` e sem
`workflow_run:`. Não depende do `ci.yml` — um commit que quebra os testes vai para produção
assim mesmo.

É conserto de poucas linhas, mas muda quando o deploy acontece, então merece decisão escrita.
Está registrado como T031 dentro da 020; se a 020 demorar, vale spec própria antes.

**FECHADO em 2026-08-11** pela change `travar-deploy-com-teste-vermelho`. `deploy-web.yml`
passou a disparar por `workflow_run` sobre a conclusão bem-sucedida de `ci.yml` em `main` (não
mais por `push` direto), com `workflow_dispatch` mantido para republicar sem commit novo. A
porta manual fechou junto: `make deploy-web` recusa publicar com árvore não commitada ou sem
prova de `ci.yml` verde para o commit exato (checado via `gh run list`), a menos que
`CONFIRM_SEM_PROVA=sim` seja passado explicitamente. Rodar a suíte inteira dentro do `make` foi
medido (~20s de parede, suíte completa) e descartado — o custo não era o problema, e sim
gerenciar o ciclo de vida do Supabase local dentro de um alvo de publicação, e ainda assim não
provar o commit exato se a árvore estivesse suja; checar o veredito que o GitHub já registrou é
mais barato e é a mesma prova de que o workflow automático agora depende. Verificação de push
real (branch de teste, teste quebrado de propósito) fica pendente de autorização — não é
recusa: é ação de CI real em produção, fora do escopo de uma worktree isolada.

---

### 2.5 Envio de capa: a atribuição de etapa não tem teste automatizado

Da feature 013 (T059). O envio de capa tem três etapas — subir o arquivo, tirar a linha antiga,
gravar a linha nova — e cada falha produz uma frase diferente para a pessoa (FR-031). Os cinco
casos de `test/widget/cover_photo_falha_parcial_test.dart` provam o mapa **etapa → frase**, mas
injetam a exceção já montada. Quem decide a etapa e calcula `previousPhotoLost` é
`lib/features/cover_photo/data/cover_photo_repository.dart`, e **isso não é exercitado por
nenhum teste**.

**Verificado à mão em 2026-08-10**, em SQL, sob RLS e como dono: `DELETE ... RETURNING` devolve
1 linha quando havia capa e 0 quando não havia — que é a conta inteira de `previousPhotoLost`.

**Por que fica como dívida em vez de teste.** Cobrir exige exercitar o repositório contra o
Supabase local com um `SupabaseClient` de verdade — padrão que este repositório não tem, já que
`test/integration` fala com o Postgres direto. E não basta o padrão: forçar cada etapa a falhar
**de propósito** não é possível de fora. Falhar o upload exigiria um bucket inexistente, que é
constante; falhar só o `delete` exigiria uma policy contraditória; falhar só o `insert` exigiria
vencer uma corrida no índice único. Cada um deles precisaria de uma costura aberta no código de
produção só para o teste — mudar a forma do que funciona para cobrir três `try` e um
`isNotEmpty`.

**O que reabre isto**: se a atribuição de etapa ganhar regra (mais etapas, retentativa,
mensagens por tipo de erro), o cálculo deixa de ser trivial e a costura passa a se pagar.

### 2.6 `consentimentos_por_versao_test` falhava de forma intermitente na suíte — **FECHADO em 2026-08-11**

Achado enquanto se rodavam os gates da 013 — não era da 013, que não toca em consentimento,
Perfil nem versão de texto legal. Consertado pela change OpenSpec
`estabilizar-suite-de-integracao`.

**Sintoma original**, medido em 2026-08-10: `test/integration/consentimentos_por_versao_test.dart`,
caso *"(d) Perfil anonimizado sai da contagem"*, falha com `Expected: <1> Actual: <0>` na
contagem de **baldes**: `consentimentos_por_versao()` devolvia nenhuma linha para a versão
isolada `9.9-anon`.

**Causa real, confirmada por reprodução em 2026-08-11**: NÃO eram as duas hipóteses do design
(linha de `perfis` apagada, ou linha de `versoes_texto_legal` apagada). Era
`test/integration/versao_texto_legal_registro_test.dart`, caso *"FR-002: a FK existe e recusa
versão fora do catálogo — provado com o gatilho desligado"`, que rodava
`alter table public.perfis disable trigger perfis_carimbar_consentimento_trigger` **fora de
transação**. Em Postgres isso é DDL autocommitada: o gatilho ficava desligado, GLOBAL, para
todas as sessões, durante a janela até o `enable trigger` seguinte — e `dart test` roda os
arquivos em paralelo contra o mesmo banco. Qualquer `insert`/`update` em `public.perfis` de
OUTRO arquivo que caísse nessa janela gravava `consentimento_lgpd_versao` como `NULL` em vez do
valor esperado, porque o gatilho que carimba a versão (`perfis_carimbar_consentimento`) não
disparava.

O mesmo defeito tinha DOIS sintomas, confirmados por reprodução (30 execuções, concorrência 12,
antes do conserto): 6 falhas — 4×
`consentimento_versao_carimbada_test.dart` caso "(f) SC-005: publicar versão nova muda o
carimbo", `Expected: '1.2-teste' Actual: <null>`; e 2× o `(d)` original acima. Mesma causa, dois
arquivos-vítima.

**Conserto**: `versao_texto_legal_registro_test.dart` passou a rodar o `disable trigger`, o
`update`, e o `rollback` dentro de uma transação (`begin`/`rollback`, sem `enable trigger`
explícito — o `rollback` desfaz o `disable` junto). É o mesmo padrão que `db_test_helper.dart`,
`consentimentos_por_versao_test.dart` e `consentimento_versao_desconhecida_test.dart` já usavam
para o mesmo gatilho — só este arquivo não seguia.

**Prova**: 30 execuções seguidas da suíte inteira, concorrência 12 (a mesma condição que media
6 falhas em 30 antes do conserto) — **0 recorrências do defeito original** depois do conserto.

**Achado colateral, ainda ABERTO**: a mesma rodada de 30 execuções pós-conserto expôs uma
**segunda corrida, não relacionada**, entre `account_deletion_test.dart` (cenários 11–14,
eleição de herdeiro) e qualquer outro arquivo que crie Administrador de distrito de teste (ex.:
`arquivar_grupo_permissao_test.dart`) — ver item novo abaixo. Fora do escopo desta change, que
era só o defeito acima.

### 2.7 Eleição de herdeiro em `account_deletion_test` alcança Administrador de outro arquivo

Achado em 2026-08-11, no laço de prova de 30 execuções (concorrência 12) depois do conserto do
§ 2.6. Run 29 de 30 falhou com dois sintomas na mesma execução:

- `account_deletion_test.dart`, cenário 12 *"a única Administradora é recusada, mesmo com
  Grupo"*: esperava `throwsA(isA<ServerException>())` e recebeu sucesso.
- Logo em seguida, `arquivar_grupo_permissao_test.dart: (tearDownAll)` falhou com
  `Severity.error 23503: update or delete on table "perfis" violates foreign key constraint
  "grupos_dono_id_fkey"` — apagar o Perfil do `_uidAdmin` daquele arquivo (
  `91000000-0000-0000-0000-000000000003`) foi recusado porque um Grupo ainda referenciava esse
  `id` como `dono_id`.

**Hipótese, não confirmada por desligamento do culpado** (§ 2.3 do processo de diagnóstico não
foi feito para este achado — só a reprodução em laço, uma vez): o cenário 12 espera que "a única
Administradora" seja recusada porque é a **única** linha em `public.administradores_distrito`.
Essa contagem é global — correta em produção, onde só existe um distrito real — mas
`createTestDistrictAdmin` (em `db_test_helper.dart`) insere linhas nessa mesma tabela
compartilhada a partir de QUALQUER arquivo de teste, sem escopo por arquivo. Se
`arquivar_grupo_permissao_test.dart` (ou outro arquivo) tinha seu próprio Administrador de teste
vivo no exato instante em que o cenário 12 rodava, a contagem deixa de ser 1, a recusa não
dispara, e a lógica de herança do banco elege esse Administrador de outro arquivo como herdeiro
— transferindo `dono_id` do Grupo do cenário 12 para um `id` que não pertence a
`account_deletion_test.dart`. O arquivo dono desse `id` (`arquivar_grupo_permissao_test.dart`)
não sabe que ganhou um Grupo e não o inclui no próprio `delete from public.grupos where dono_id
= any(@u)` da `tearDownAll` — exceto que inclui, porque o `id` está no seu próprio `_allUids`;
a corrida real é de **tempo**, entre esse `delete` e o `cleanUpTestUser` do mesmo `tearDownAll`,
com a transferência acontecendo no meio.

**Por que não foi consertado agora**: fora do escopo da change `estabilizar-suite-de-integracao`,
que mirava só o § 2.6. É a mesma classe de bug (isolamento entre arquivos que rodam em
paralelo), mas mecanismo e arquivos diferentes — merece sua própria reprodução em laço antes de
qualquer conserto, pelo mesmo motivo que o § 2.6 exigiu.

**Frequência medida**: 1 em 30 execuções completas, concorrência 12 — não dá pra saber se é
alta ou baixa com uma amostra só.

**Hipótese CONFIRMADA em 2026-08-13, por desligamento do culpado — sem querer.** Na sessão da
change `destaque-de-acoes-distritais-e-de-grupo` foi criado um Administrador do distrito de
demonstração (`teste@local.dev`, via `scripts/bootstrap_admin.sh`) para testar o app no
navegador. Ele fez exatamente o papel que o parágrafo acima atribui ao "Administrador de outro
arquivo", e com uma diferença que tornou o efeito visível: por ser permanente, não dependia de
corrida de tempo nenhuma. Os sintomas passaram a ser determinísticos — os cenários 12 e 13 de
`account_deletion_test` falhavam **até rodando o arquivo sozinho**. Depois vieram 6 Grupos
chamados "Grupo da Única Admin" / "Grupo da Admin Mais Antiga" com `dono_id` apontando para o
usuário de demonstração: a herança elegeu-o e transferiu a posse, e o `tearDownAll` do arquivo
dono não os limpou porque o `id` não era dele. Um deles sobreviveu e quebrou o `tearDownAll` de
`leadership_decide_test` com o mesmo `23503 grupos_dono_id_fkey`.

Removendo só a linha de `administradores_distrito` do usuário de demonstração — sem tocar em
mais nada — os cenários voltaram a passar. Isso fecha a dúvida do parágrafo anterior: o
mecanismo é o descrito, e a contagem global de `administradores_distrito` é o ponto frágil.

**Medida que separa o defeito do ambiente**, e que vale guardar para o próximo diagnóstico:
`flutter test --concurrency=1` deu **535 de 535** com a mesma árvore em que a execução paralela
falhava. Antes de investigar um vermelho de integração, rode em série: se passar, é isolamento
entre arquivos, não código.

**O que isso acrescenta ao conserto**: o escopo não é só `account_deletion_test`. Enquanto
`createTestDistrictAdmin` escrever numa tabela cuja contagem é global, qualquer linha viva ali
— de outro arquivo de teste **ou de dado de desenvolvimento no banco local** — quebra os
cenários de "a única Administradora". O conserto precisa dar escopo à contagem ou ao dado, não
só espaçar os testes no tempo.

### 2.8 `anon` lê `participacoes_grupo` inteira — quem participa de qual Ministério é público

Achado em 2026-08-13, medindo a fronteira do destaque de Ações. Com a chave **publicável** —
que vai dentro do JavaScript publicado e é legível por qualquer pessoa que abra o site:

```
GET /rest/v1/participacoes_grupo?select=grupo_id,usuario_id   → HTTP 200
[{"grupo_id":"1111…","usuario_id":"5d5e…"}, {"grupo_id":"2222…","usuario_id":"584b…"}]
```

Sem sessão, sem filtro, linhas de todos os Usuários. Cruzando `usuario_id` com a RPC
`perfil_publico`, isso vira **nome da pessoa + Ministério de que ela participa**, para qualquer
um. Num app de igreja, associação a Ministério somada a nome é dado de filiação religiosa.

**Não é regressão desta change, e ela não piorou nada** — a RLS é aberta desde que
`fetchMemberIds` precisou listar os membros de um Grupo alheio, que é uma tela legítima do
produto (ver `GroupRepository.fetchMemberIds`). O que a change fez foi medir e escrever.

**Por que é o Princípio II e não acabamento**: a constituição diz que nenhum dado pessoal é
exibido além do que o glossário autoriza. O glossário autoriza mostrar os membros de um Grupo
**dentro do app**; não autoriza a lista completa de participações do distrito para quem não tem
Conta.

**O que decidir antes de consertar**: quem legitimamente precisa ler `participacoes_grupo`, e
com qual recorte. Fechar para `anon` e deixar `authenticated` é o corte óbvio, mas muda a tela
de Grupo para Visitante — que hoje vê membros sem cadastro (FR-010 da feature de Grupos). É
decisão de produto, não só de policy.

### 2.9 `NewsPage` tem o bug de ciclo de vida que `/acoes` acabou de corrigir

`lib/app.dart:171` constrói `const NewsPage()`. Sendo `const`, o widget é idêntico entre
navegações: o Flutter reusa o `State` e o `initState` só roda no arranque frio. `NewsPage`
grava o marcador de Novidades exatamente ali (`initState` → `_markAsSeen`).

É a mesma forma do defeito medido em `/acoes` em 2026-08-12, onde o marcador ficou parado em
`18:08:34` depois de duas idas e voltas pelo router. **Não foi medido em `NewsPage`** — a
inferência é por leitura, e é o tipo de coisa que este repositório já viu parecer certa na
página e estar errada.

O conserto usado em `/acoes` está em `lib/features/action/action_providers.dart`
(`lastSeenActionsProvider` + `markActionsSeenProvider`): o gatilho deixa de ser o ciclo de vida
do widget e passa a ser um provider `autoDispose`, que morre ao sair da tela e renasce ao
voltar. `NewsPage` também não tem a segunda metade da correção — só avançar o marcador quando a
tela teve o que mostrar.

### 2.10 Não existe recuperação de senha

Nenhum `resetPasswordForEmail` em `lib/`. Quem faz upgrade de Perfil para Conta e depois esquece
a senha perde o acesso, e não há caminho de volta pelo app: o Perfil só é recuperável entre
aparelhos por meio da Conta (ver `contracts/auth-flow.md`).

Achado em 2026-08-13 ao melhorar as mensagens de erro do login. Não foi posto link de "Esqueci
minha senha" na tela justamente porque ele não levaria a lugar nenhum.

### 2.11 Entrar num Grupo não mostra as Ações que ele já tinha — decisão, não defeito

O marcador de "última vez que vi `/acoes`" é único e global (decisão registrada no design da
change `destaque-de-acoes-distritais-e-de-grupo`). Consequência medida em 2026-08-13: quem entra
num Grupo hoje não vê **nenhuma** Ação dele em destaque, porque o marcador já passou por todas
enquanto essa pessoa ainda não participava. Só Ação criada depois da entrada aparece.

O `design.md` arquivado registra a limitação do marcador único como aceita, mas o caso que ele
descreve é "a pessoa não reparou". Este é diferente: **a pessoa não podia reparar**, não
participava do Grupo. E é o caso de uso mais óbvio de "novidade no meu Grupo" — acabei de entrar
no Coral, quero ver o que tem.

**O que o conserto exigiria**: comparar contra a data de entrada no Grupo em vez do marcador
global — ou seja, guardar quando cada participação começou. É o marcador por Grupo que o design
considerou e descartou, por outro caminho.

### 2.8 Candidata perde a marca de Dupla Missionária no caminho

Achado em 2026-08-13, pela passagem de convergência da change
`acao-direcionada-a-grupo`. Não é dela: é anterior, e apareceu porque foi essa a linha que
ganhou `restrictedToGroup`.

`VotingRoundRepository.proposeCandidate` (`lib/features/action/data/voting_round_repository.dart:53-64`)
remonta o `NewAction` campo a campo antes de mandar ao repositório de Ação, e **não copia
`isMissionaryPair` nem `visitedGender`**. Quem propõe uma candidata marcada como Dupla
Missionária tem a marca descartada antes do banco: a Ação nasce comum, sem as 2 vagas fixas nem
a regra de composição por gênero da feature 007.

O que ainda não foi verificado, e decide o tamanho: se `create_candidate_page.dart` chega a
oferecer o controle de Dupla Missionária (ele oferece — o `SwitchListTile` está lá), então a
tela promete uma coisa e o banco grava outra, calado. Se alguma candidata já foi proposta assim,
há dado em produção com a marca faltando.

**Não virar código antes de spec.** Duas leituras possíveis, e elas mudam o conserto: ou
candidata pode ser Dupla Missionária e o repositório está errado, ou não pode e é a tela que
está oferecendo o que não deveria.

### 2.9 Grafo do graphify desatualizado nos documentos

Registrado em 2026-08-13, pela change `acao-direcionada-a-grupo` (task 7.8, ver o
arquivo dela).

`graphify-out/graph.json` está atualizado para o **código** (5640 nós) e parado em
05/08 para os **documentos**. A rodada de 13/08 extraiu os 276 documentos alterados
por 13 subagentes, a 1.868.352 tokens, e o resultado foi **descartado**: `build_merge`
substitui os nós de todo arquivo re-extraído, a extração nova saiu muito mais magra
que a antiga (`specs/` cairia de 1937 para 571 nós) e a mescla completa daria 3566
nós contra os 5536 já existentes. O guarda anti-encolhimento do graphify recusaria a
escrita.

O cache semântico daquela rodada foi apagado e o manifesto **omite 311 arquivos de
propósito**, para eles voltarem como pendentes no próximo `--update` em vez de
contarem como processados sem terem sido.

**O que fazer**: `/graphify . --update` numa sessão própria, com chunks de 8–10
arquivos por agente (~30 agentes) em vez de 22, para bater ou passar a densidade de
05/08 antes de mesclar. Enquanto isso, consulta ao grafo sobre documento responde com
o estado de 05/08 — o que inclui não conhecer nenhuma das sete changes propostas em
12–13/08.

Enquanto está assim, vale saber de duas perdas do extrator, que não dependem desta
pendência: 11 arquivos de manifesto/configuração produzem zero nós, e 13 nós Swift de
iOS/macOS são descartados por colisão de id (`Package.swift`,
`AppDelegate.swift`/`SceneDelegate.swift` repetem nome em diretórios diferentes). O
graphify sugere `extract` por subpasta + `merge-graphs` para o segundo caso.

### 2.10 `mudancas` cresce sem retenção

Registrado em 2026-08-13 pela change `log-de-mudancas-em-grupo-e-acao`, que já a
declarou como dívida no próprio design (Risks).

`public.mudancas` é a única tabela do app que **só cresce**: nada nela é
atualizado nem apagado, exceto por cascata quando o Grupo ou a Ação somem. Não há
política de retenção, e nenhum job a limpa.

**Por que foi aceito assim**: o volume por evento é pequeno — cinco colunas, sem
texto livre — e os dois índices são parciais e já ordenados por `created_at
desc`, então a leitura da tela não degrada com o total acumulado; só o
armazenamento cresce.

**O que decidir quando incomodar**: prazo de retenção e quem o executa. Vale
lembrar que a decisão tem efeito legal — o registro é dado pessoal (`autor_id`),
e a Política de Privacidade fala de prazos. Se um prazo for adotado, ele entra em
`REVISAO-JURIDICA.md` junto.

### 2.11 Quatro dívidas recusadas na limpeza de 2026-08-13

Vieram da passagem de `/simplify` sobre `notificacoes-in-app`, com quatro
revisores. Foram **recusadas com motivo**, não esquecidas — cada uma tem custo
concreto e um conserto que passa do escopo de uma change de notificação.

**(a) `perfil_publico` em lote.** `NotificationRepository` e
`ChangeLogRepository` resolvem nome com um RPC por ator distinto. Hoje as
chamadas vão concorrentes e a lista tem teto de 50, então a conta é limitada —
mas o padrão é o mesmo que `contatos_para_convite` existiu para matar. O
conserto é `perfil_publico(p_ids uuid[])` com `where p.id = any(p_ids)`: a
função atual tem cinco linhas, e a versão em lote é a mesma com `= any`. Serve
às duas leituras e a mais três cópias privadas em `group_repository.dart:177`,
`action_repository.dart:136` e `profile_repository.dart`.

**(b) A regra "tela de leitura tem indicador, formulário não" não tem casa no
código — e já é falsa.** O indicador de avisos foi acrescentado a 8 `AppBar`
uma a uma. Existem **30** telas com `AppBar` em `lib/features/*/presentation/`;
o teste que "trava a decisão" classifica 16 e não diz nada sobre as outras 14 —
e entre elas há telas de leitura pelo próprio critério da decisão
(`archived_groups_page`, `pending_reports_page`, `pending_declarations_page`,
`my_profile_page`). Além disso o teste lê o TEXTO do arquivo com `contains()`,
então quebra num rename e cala numa tela nova.

O conserto certo é o **`ShellRoute`** já registrado como change própria de
navegação — que serviria também ao chat. Uma fábrica de `AppBar` agora seria uma
terceira camada a desfazer depois. Enquanto isso, **quem criar tela de leitura
nova precisa lembrar de três edições**: o import, o `actions:` e a lista do
teste.

**(c) `isOpen` de convite discorda da view de avisos.** `ActionInvite.isOpen`
decide "Ação ainda vale" no Dart, com o relógio do aparelho (`clockProvider`);
`notificacoes_ativas` decide o mesmo no servidor, com `now()`. As duas telas
falam do mesmo convite. Com relógio adiantado, um convite some da tela de
Convites enquanto o aviso correspondente continua contado no indicador — dois
números sobre o mesmo fato, discordando pela camada em que cada um foi decidido.
O conserto é um `convites_acao_ativos` no mesmo espírito. Dívida anterior a esta
change; esta apenas criou o lugar canônico e passou ao lado dele.

**(d) `notificacoes.acao_id` e `grupo_id` têm `on delete cascade` sem índice de
apoio.** Apagar uma Ação ou um Grupo varre `notificacoes` inteira. Hoje é barato
e a operação é rara — mas esta é a tabela declarada como a que **vai** crescer
(chat e log entram como tipos novos). Vale o índice quando o segundo tipo entrar.

**Também avaliada e mantida como está**: o índice parcial
`notificacoes_nao_lidas` foi apontado como redundante por ser prefixo do
completo. Fica: ele serve exatamente a consulta do contador, que roda na abertura
de oito telas, e o custo de escrita numa tabela pequena não justifica remover sem
medir.

### 2.12 `denuncias_imagem.motivo` aceita motivo feito só de quebras de linha

Achado em 2026-08-14, escrevendo a denúncia de mensagem da change
`chat-de-grupo-e-acao`. A constraint de `denuncias_imagem`
(`20260810120000_denuncia_de_imagem.sql:23`) é:

```sql
motivo text not null check (length(trim(motivo)) > 0)
```

O `trim` padrão do Postgres remove **apenas espaços**. Medido:
`length(trim(E'\n\t'))` é `2`, então um motivo de quebras de linha e tabulações
passa como se dissesse alguma coisa — e o campo existe justamente para ser o
registro do caso quando a imagem denunciada já não estiver lá.

`denuncias_mensagem` nasceu com a versão correta,
`length(btrim(motivo, E' \t\n\r')) > 0`, e `mensagens.texto` também. Ficaram
**duas constraints com regras diferentes para a mesma ideia**, e a de imagem é a
frouxa.

Não consertado aqui por escopo: mexer em `denuncias_imagem` é migration de outra
feature, e a change do chat não deve carregar o conserto de uma vizinha. O
conserto é de uma linha (`alter table ... drop constraint ... add constraint`) e
não tem risco de dado existente — nenhum motivo em produção é feito só de
espaço em branco, porque não há produção com denúncia ainda.

### 2.13 ~~As duas funções de acesso do chat não têm teste de unidade próprio~~ — FECHADO em 2026-08-16

Estava registrado como **dispensado por decisão em 2026-08-14**: as duas funções
de acesso só eram exercitadas através das policies, e o custo era de
diagnóstico — quando um teste de acesso ficasse vermelho, ele não diria se quem
errou foi a função ou a policy que a chama.

**Reaberto e feito ao fechar a change**, porque a dispensa não sobreviveu ao
próprio motivo: durante a change, três achados diferentes tiveram o mesmo
sintoma (a operação afeta zero linha e a tela diz que deu certo), e distinguir
função de policy deixou de ser conforto de diagnóstico.

`test/integration/chat_funcoes_de_acesso_test.dart`, medido em 2026-08-16:
**7 papéis × 3 idades = 21 credenciais × 3 funções = 63 casos**, mais 1
asserção de montagem. As funções são chamadas direto
(`select public.pode_ver_chat_grupo(@g)`), sem uma linha em `mensagens` — que é
o ponto: `count(*)` em `mensagens` devolve o mesmo zero quando a função disse
"não" e quando a policy nem chegou a chamá-la.

Os papéis cobrem os braços um a um: estranho (controle negativo), participante,
dono do Grupo da Ação, criador, confirmado, fila, e Administrador do distrito. A
idade multiplica tudo porque `maior_de_idade()` está do lado de FORA do `or` das
outras duas — é a asserção que pega quem uniformizar as funções e mover o corte
para dentro de um braço só.

Provado que discrimina por mutação: trocar o esperado de `na fila da Ação` para
`false` deixa vermelho (`Expected: <false> Actual: <true>`).

### 2.14 `denuncias_mensagem.motivo` é texto livre do titular, sem prazo e fora da exclusão de conta

Achado em 2026-08-14 pelo `advogado-digital`, conferindo a Política contra o
código. Não consertado.

O `motivo` é escrito por quem denuncia, em campo aberto, e a Política agora
declara que ele é o registro do caso — é ele que sobrevive ao expurgo da
mensagem, de propósito, para denúncia pendente não sumir sem desfecho.

Duas consequências que ninguém decidiu:

- **`excluir_minha_conta` não toca nele** (`20260810130000:17-147`). Quem
  denunciou e depois excluiu a conta continua com um texto seu no banco,
  ligado a `denunciante_id`, enquanto as mensagens dele perderam o texto. As
  duas metades da exclusão discordam.
- **Não tem prazo nenhum.** `mensagens` de Ação some em 30 dias; a denúncia
  sobre ela fica para sempre.

Declarar na Política que o motivo fica não é o mesmo que minimizar o dado.
O conserto provável é prazo após `resolvida_em` e apagar o motivo na
anonimização do denunciante — mas isso é decisão, não conserto óbvio: apagar o
motivo de uma denúncia julgada apaga o registro de por que uma mensagem foi
removida.

### 2.15 A decisão de não ter backup foi tomada antes de existir texto livre

`REVISAO-JURIDICA.md` §4-B fechou "backup: nada, risco aceito" e listou um
gatilho explícito para reabrir: **o app passar a guardar dado que a pessoa não
saiba de cor**. A conversa de Grupo satisfaz o gatilho — não expira, e o que
foi combinado ali não está em lugar nenhum além do banco.

Não é defeito e não bloqueia a change. É uma decisão cuja premissa mudou, e
quem a tomou precisa saber disso antes de ela virar padrão por inércia.

### 2.16 Base legal do texto livre — o que ainda bloqueia publicar o texto 1.5

**A parte da tela FECHOU em 2026-08-14** e este item foi reescrito por isso. O
caminho da denúncia está completo e provado ponta a ponta: botão
(`chat_page.dart`), diálogo com motivo obrigatório, `insert`, leitura por
autoridade (`message_reports_page.dart`, rotas em `lib/app.dart`) e desfecho.
A redação anterior dizia que a tela não existia e, do jeito que estava escrita,
bloqueava publicar a versão 1.5 por um motivo que já não existe — foi o próprio
agente `promessa-vs-execucao` quem apontou que o ledger estava mentindo para a
equipe.

**O que continua aberto, e este sim bloqueia:** a conversa pode conter dado
sensível do art. 5º, II — saúde, religião, opinião — de **terceiro que nem usa
o app**. Não há como detectar nem impedir. A Política do projeto não tem seção
de base legal, e ninguém disse se o consentimento genérico do cadastro cobre
isto. Precisa de advogado inscrito, não de código.

Também aberto no mesmo texto: **base legal do texto livre**. A conversa pode
conter dado sensível de terceiro — saúde, religião — que o app não impede nem
detecta. A Política do projeto não tem seção de base legal, e um advogado
inscrito precisa dizer se o consentimento do cadastro cobre isso.

### 2.17 O prazo de 30 dias tem dois executores e nenhum observador

Achado pelo agente `promessa-vs-execucao` no fechamento de
`chat-de-grupo-e-acao`, em 2026-08-14. **Não é promessa quebrada** — o expurgo
funciona e está provado nos dois lados da fronteira
(`chat_expurgo_test.dart`). É que ninguém no sistema sabe dizer se ele rodou.

Os dois executores falham calados, cada um do seu jeito:

- `ChatRepository.purgeExpiredActionMessages` engole toda exceção e devolve
  `0`, e é chamada com `unawaited`. Isso é deliberado e continua certo: faxina
  que falha não pode estragar a leitura da conversa. Mas a função devolve a
  contagem de linhas apagadas e o app a joga fora.
- O `pg_cron` em produção pode simplesmente não existir — `INFRA-PRODUCAO.md`
  já declara que, se o `cron.schedule` não tiver rodado no projeto hospedado,
  a consulta devolve zero linhas e **não há erro em lugar nenhum**, porque o
  segundo gatilho continua funcionando e escondendo a ausência do primeiro.

Somando: não há tabela de última execução, nem `/health`, nem alerta. A
Política promete 30 dias, e a única forma de conferir se a promessa foi
cumprida ontem é ir ao banco à mão.

O conserto barato é uma linha por execução (`quando`, `quantas`), lida por uma
tela de Administrador — mas isso é change própria, com retenção própria, e não
entra no fechamento desta.

**Também aceito nesta rodada, e menor:** `expurgar_mensagens_de_acao()` tem
`grant execute ... to authenticated`, então qualquer sessão autenticada —
inclusive Visitante anônimo sem Perfil — invoca uma varredura global que roda
`security definer`. Não viola promessa nenhuma (só apaga o que já venceu) e o
grant existe porque o app É o segundo gatilho. Fica registrado porque é uma
função de escrita global exposta na REST, e quem for endurecer isso precisa
saber que o cliente depende dela.

### 2.18 Seis funções `security definer` anteriores continuam chamáveis por `anon`

Achado ao consertar o mesmo defeito dentro de `chat-de-grupo-e-acao`, em
2026-08-14. **Não é da change do chat — as do chat foram corrigidas.** É o
precedente que o agente `pentest-etico` mandou procurar, e ele existe.

A armadilha: **função nova no Postgres nasce com `execute` para `PUBLIC`**.
`grant execute ... to authenticated` acrescenta um privilégio, não substitui o
que já estava lá. Sem `revoke ... from public`, a role `anon` — que o PostgREST
usa em requisição sem `Authorization` — herda o direito de chamar. E a chave
publicável está no bundle público do app.

Consultadas no banco local, estas seis são `security definer`, não são função
de gatilho, e `has_function_privilege('anon', ..., 'execute')` devolve `true`:

| Função | O que faz | Tem checagem de `auth.uid()`? |
|---|---|---|
| `fechar_rodada_se_devido` | **escreve** — fecha Rodada de votação | **Só no caminho `p_forcar`.** Fechar Rodada vencida não checa nada |
| `declarar_lideranca` | **escreve** | Sim |
| `decidir_lideranca` | **escreve** | Sim |
| `autor_de_mudanca` | lê | — |
| `nome_valido` | lê/valida | — |
| `perfil_publico` | lê | — (é pública por desenho) |

A pior é `fechar_rodada_se_devido`: qualquer pessoa com `curl` e a chave
publicável fecha Rodada vencida de qualquer Grupo, sem login. O efeito é o
mesmo que o segundo gatilho do app produziria de qualquer jeito — como no
expurgo do chat, o dano de dado é limitado —, mas é escrita disparável por não
autenticado, e o padrão se repete a cada função nova.

**Não consertado aqui por escopo**: são migrations de três features diferentes,
cada uma com a sua suíte. O conserto é mecânico (`revoke execute on function
... from public;` antes de cada `grant`) e o teste já existe como modelo em
`test/integration/chat_privilegio_funcao_test.dart`, que olha o PRIVILÉGIO e
não o resultado — um teste que só conferisse "anon não lê" continuaria verde
com a RPC aberta.

Para procurar em qualquer migration: `proacl` com uma entrada que começa em `=`
(nada antes do sinal) é o grant a `PUBLIC`.

### 2.21 Dezessete uids repetidos entre arquivos da suíte

Achado em 2026-08-16, pela convergência da change `separar-visitante-de-anon`.
Não consertado: cada par precisa de alguém decidindo qual dos dois arquivos
muda, e a change que os achou é sobre outro assunto.

A suíte declara **283 uids** e **17 deles aparecem em dois arquivos**. Os
arquivos rodam em PARALELO contra o mesmo banco — a capability
`suite-de-integracao` cobra determinismo justamente por isso —, e uid repetido
faz o `cleanUpTestUser` de um apagar o Perfil que o outro está usando no meio
do teste.

**Não está mordendo hoje**, e vale dizer por quê: os inserts de Perfil são
`on conflict (id) do nothing`, e as limpezas moram em `tearDownAll`. A janela
existe mesmo assim — dois `tearDownAll` concorrentes, ou um arquivo que passe a
limpar em `tearDown` —, e é do tipo que aparece uma vez em trinta execuções e é
descartada como "flaky". Foi assim com o § 2.6 e com o § 2.7.

| uid | arquivo A | arquivo B |
|---|---|---|
| `90000000…0020` | `church_manage_authorization:_uidNaoAdmin` | `leadership_requires_account:_uidSemConta` |
| `90000000…0021` | `church_archive_visibility:_uidAdmin` | `leadership_declare_idempotent:_uidLider` |
| `90000000…0030` | `district_admin_cancel_any_action:_uidAdmin` | `leadership_decide_authorization:_uidOwner` |
| `90000000…0031` | `district_admin_cancel_any_action:_uidCreator` | `leadership_decide_authorization:_uidComum` |
| `90000000…0032` | `district_admin_cancel_any_action:_uidGroupOwner` | `leadership_decide_authorization:_uidLider` |
| `95000000…0001` | `consentimentos_por_versao:_adminUid` | `security_signup_grant:_uid` |
| `95000000…0002` | `consentimentos_por_versao:_plainUserUid` | `security_nome_valido_rls:_uid` |
| `96000000…0001` | `consentimento_versao_carimbada:_uidPlain` | `meus_grupos_so_os_meus:_eu` |
| `96000000…0002` | `consentimento_versao_carimbada:_uidForged` | `meus_grupos_so_os_meus:_outra` |
| `c3000000…0001` | `chat_admin_menor:_uidOwner` | `convidar_exige_conta:_uidComConta` |
| `c3000000…0002` | `chat_admin_menor:_uidMember` | `convidar_exige_conta:_uidAnonimo` |
| `c4000000…0001` | `chat_denuncias_do_grupo:_uidOwner` | `convite_nao_reserva_vaga:_uidCriadora` |
| `c4000000…0002` | `chat_denuncias_do_grupo:_uidMember` | `convite_nao_reserva_vaga:_uidRapida` |
| `c4000000…0003` | `chat_denuncias_do_grupo:_uidOtherOwner` | `convite_nao_reserva_vaga:_uidConvidada` |
| `c5000000…0001` | `chat_acao_cancelada:_uidCreator` | `convite_leitura_restrita:_uidConvidante` |
| `c5000000…0002` | `chat_acao_cancelada:_uidConfirmed` | `convite_leitura_restrita:_uidConvidada` |
| `d2000000…0001` | `chat_denuncia_desfecho:_uidOwner` | `mudancas_gatilhos_acao:_uidDona` |

A consulta que os encontra, para a varredura não redescobrir:

```
grep -h "const _\w* = '[0-9a-f]\{8}-" test/integration/*.dart
```
lendo o valor e o arquivo, e agrupando por valor. Havia 60 prefixos de oito
dígitos em uso quando isto foi medido; escolher um uid novo de olho é como as
colisões nasceram.

### 2.20 Dezesseis cópias locais de `asUser` não devolvem o `jwt.claims`

Achado em 2026-08-16, pela convergência da change `separar-visitante-de-anon`.
Não consertado: é varredura de risco próprio, e a change que o achou é sobre
outro papel.

A suíte tem **48 definições locais de "usuário autenticado"**, uma por arquivo,
além da compartilhada em `acao_restrita_helper.dart`. Elas já divergiram:
**32 fazem `reset request.jwt.claims` no `finally`, 16 não fazem.**

Os 16: `account_deletion`, `apenas_criador_cancela`, `apenas_dono_administra`,
`apuracao_empate`, `apuracao_presenca`, `apuracao_sem_candidata`,
`apuracao_vencedora`, `cancelar_acao_grupo`, `candidata_confirmar_presenca`,
`candidata_propor`, `fechamento_preguicoso`, `forcar_fechamento_dono`,
`foto_capa_orfao`, `rodada_abrir_participante`, `votar_participante`,
`voto_revogavel`.

**Por que isso morde.** `reset role` NÃO limpa GUC customizado. Sem o segundo
reset, o `sub` da identidade anterior sobrevive, e o próximo `set role` no
mesmo arquivo — ou o próximo teste, na mesma conexão — roda enxergando alguém
que não é ele. O achado é antigo e está documentado dentro de UMA das 32:
`church_archive_visibility_test.dart:27-29`, "achado durante a validação manual
desta feature". As outras 47 não leem aquele comentário.

**Por que não explodiu ainda.** Quase todos os 16 usam uma identidade só, ou
terminam o arquivo logo depois. O risco é o teste que alguém acrescentar
amanhã, num desses arquivos, esperando papel limpo.

**Não é canal lateral nem defeito de produção** — é defeito de prova. O banco
está certo; o que fica errado é o que a suíte afirma estar medindo.

O conserto é trocar as 48 pela compartilhada, arquivo por arquivo, e cada um
tem `tearDown` próprio para conferir. A requirement "cada papel de teste tem
uma definição só" entra em `specs/suite-de-integracao` pela change
`separar-visitante-de-anon`, com este débito declarado: ela proíbe a 49ª cópia,
não apaga as 48.

### 2.19 O canal de Realtime entrega envelope de atividade a `anon`

Achado pelo `pentest-etico` em 2026-08-14. Severidade baixa, registrado porque
é observável de fora e ninguém decidiu que fosse assim.

Assinando `postgres_changes` em `public.mensagens` **sem `access_token`**, o
`anon` recebe um evento por escrita:

```json
{"table":"mensagens","type":"INSERT","record":{},"columns":[],
 "errors":["Error 401: Unauthorized"],"commit_timestamp":null}
```

Sem `texto`, sem `id` de linha, sem `grupo_id`/`acao_id`/`autor_id`. O conteúdo
**não vaza** — assinantes autenticados-mas-negados (menor de 18, não
participante) recebem **zero** eventos, e isso está provado em
`chat_realtime_test.dart`. O que vaza é volume e horário de atividade do app
inteiro, e a distinção entre criação e remoção.

É comportamento padrão do Realtime do Supabase (envelope 401 quando a RLS nega
ao `anon`), não algo que a migration controle além de publicar a tabela. A
mitigação a investigar é canal privado; **[NÃO VERIFICADO]** se elimina o
envelope.

## 3. Verificação manual — só gente mede

Nenhuma destas é "esqueci". Todas exigem rodar o app, olhar a tela, cronometrar alguém ou
esperar o tempo passar. Estão marcadas como abertas nos respectivos `tasks.md`.

### Exigem rodar o app e olhar

| Onde | O quê |
|---|---|
| 016 T039 | Quickstart, 16 itens. Três obrigatórios: `/perfil` sem Perfil, nome corrigido propagando na página do Grupo, e a data do consentimento não mudando ao corrigir o nome |
| 017 T021 | O corpo do `insert` no DevTools não pode ter chave de versão; e a tela de cadastro não ganhou campo nem passo |
| 018 T015 | Quatro telas: Líder visível a Visitante, estado da própria declaração, pendências do Administrador, e Usuário comum em `/leadership/pending` vendo lista vazia sem erro |
| 013 T033 | Quickstart Parte 2, 21 itens. **O item 18 é o que importa**: rodar em Android ou iOS de verdade, porque o seletor de imagem é a parte que se comporta diferente fora da web — e a web é o único ambiente em que isto foi exercitado |
| 021 T025 | Item 3.3: a tela da Rodada continua marcando sua candidata e não mostra contagem de votos |
| 010 T019–T021 | Paisagem a ~375px, contraste dos pares texto/fundo, alvos de toque e leitor de tela |

### Changes de 2026-08-13 — o que dá para automatizar com o navegador

As duas changes de 13/08 (`acao-direcionada-a-grupo` e `convite-para-acao`) foram entregues
com 359 testes de widget/unidade e 285 de integração, **e nenhuma execução do app**. A prova
de banco fala com o Postgres direto na 54322; a de widget fala com repositório mockado.
**O PostgREST nunca foi exercitado.** O que só aparece rodando o app de verdade:

| Onde | O quê |
|---|---|
| convite T5.8 | Fluxo ponta a ponta com **duas contas**: criar Ação, convidar, o convite chegar na outra conta, recusar, e o contador da Home mexer. É o único caminho que executa `rpc('convidar_para_acao')` e `rpc('contatos_para_convite')` pelo cliente Supabase — nome dos parâmetros, serialização do `uuid[]` saindo do Dart e formato do retorno de uma função `returns table` nunca foram verificados fora do SQL |
| convite T5.8 | Os *embeds* de `fetchReceivedInvites`: `select('*, grupos(nome), acoes(*)')`. Foram escritos de cabeça e o PostgREST os resolve por FK — se o nome do relacionamento não bater, a tela de convites quebra e nenhum teste atual percebe |
| convite T5.8 | `decline`: o `.select('id')` depois do `update` é o que faz zero linha virar aviso em vez de sucesso calado. Só o PostgREST diz se o retorno vem como esperado |
| restrita T5.5 | Ação restrita numa **aba anônima**: confirmar que ela não aparece em `/acoes` e que abrir a rota por id cai em "Ação não encontrada" |
| restrita T5.5 | Abrir a tela de uma Ação e confirmar que **não há lista de convidados** em lugar nenhum — a spec proíbe para qualquer pessoa, inclusive quem convidou |
| ambas | Renderização real em 375 px das três telas novas (propor candidata com o controle de restrição, convidar, convites recebidos) e captura de tela. **Teste de widget em 360 px não substitui isto** — é o aviso de método logo abaixo, e eu o repeti |

### Changes de 2026-08-13 — o que exige gente de verdade

Nada aqui é automatizável: são julgamentos de compreensão, não de layout.

| Onde | O quê |
|---|---|
| restrita T5.5 | "Só para quem participa do Grupo" comunica que a Ação **some do feed dos outros**? Ou lê como "é sobre o Grupo"? O texto secundário explica, mas ninguém de fora leu |
| restrita T5.5 | O cadeado no cartão da lista lê como "restrita" ou como "trancada/cancelada"? Ícone sem rótulo é adivinhação, e na faixa de destaque ele está sozinho |
| convite T5.8 | "Ficaram de fora: Bruno." diz à pessoa **o que fazer em seguida**? O botão vira "Tentar de novo (1)" — isso é óbvio ou parece que o convite todo falhou? |
| convite T5.8 | "Já convidado — sem resposta" vs "Confirmou presença": alguém que abriu a tela para chamar gente entende a diferença sem explicação? |
| convite T5.8 | Alvo de toque de 48 px nas duas telas novas. Este projeto já mediu isso errado uma vez, em 10/08, e só a captura de tela mostrou |
| ambas | Leitura por 2–3 pessoas do distrito, como foi feito na 022. É o que pega jargão que parece claro para quem escreveu |

### Exigem cronômetro ou tempo

| Onde | O quê |
|---|---|
| 016 T043 | Cronometrar 3 pessoas corrigindo o nome, do abrir o app até salvar. Meta: menos de 1 minuto |
| 016 T044 | Conferir `jdaniielc@gmail.com` 30 dias depois do lançamento: chegou pedido de acesso ou correção que a tela já cobre? |
| 011 T026a | Dar 5 Ações a alguém e cronometrar se identifica a mais confirmada em menos de 10s |
| 001 T039 | Tempos de cadastro (<2min) e reabertura (<5s) — bloqueado desde o começo por falta de ambiente |
| 013 T034 | Guardar o endereço de uma imagem de capa, removê-la, e **cronometrar** quanto tempo o endereço ainda responde. A Política de Privacidade promete até 60 segundos; se der mais, é a Política que está errada, não a medição |

### Exige produção no ar

Fechado em 2026-08-11, depois do deploy e do push das migrations de 018/021: `curl -s https://mbfcnebyxzoagwatjxuh.supabase.co/rest/v1/votos?select=* -H "apikey: <publishable-key>"` e o mesmo para `liderancas` — ambos `[]`, `HTTP 200`, anônimo. Nada pendente nesta seção.

---

## 4. Decisões — respondidas em 2026-08-09 pelo dono do app

### 4.1 Limiar de idade — **abaixo de 13** ✅ (destrava a 015)

Autorização do responsável passa a ser exigida para **menor de 13 anos**, alinhado ao art. 14
da LGPD (criança até 12; adolescente de 13 a 17 não exige consentimento de um dos pais).
A 015 já previu o número numa função (`public.limiar_crianca()`), então é uma linha.

### 4.2 Região do Supabase — **a documentação está correta** ✅ (destrava parte da 019)

O dono do app confirma `sa-east-1 (São Paulo, Brasil)`.

→ **FECHADO em 2026-08-10 pela feature 019, e a evidência subiu de nível.** Este item pedia
que se gravasse com honestidade que a fonte era *afirmação do controlador*, e não leitura do
painel. Deixou de ser: a saída literal de `supabase projects list` está colada em
`INFRA-PRODUCAO.md` § 2 e em `REVISAO-JURIDICA.md` item 4 — projeto `iasd-conecta-vsa`,
`mbfcnebyxzoagwatjxuh`, região **South America (São Paulo)**, criado em 2026-08-07.
A palavra do controlador estava certa.

O comentário `Ainda não provisionada` em `legal_metadata.dart` saiu, substituído pelo
registro da verificação com data. Ele esteve errado por exatamente três dias — de 07/08,
quando o projeto foi criado, a 10/08.

### 4.3 Backup — ~~só os usuários; o resto é descartável~~ → **nada, risco aceito** ✅

**Decisão de 2026-08-09 (superada)**: não contratar backup automático, mas manter vivo o
cadastro das pessoas (`auth.users` + `public.perfis`); Grupos, Ações, Rodadas, votos,
confirmações e declarações de liderança seriam descartáveis e recriáveis pela comunidade.

**Decisão de 2026-08-10, que prevalece**: **opção C — não há backup nenhum.** Nem do
cadastro. O dono do app escolheu assim ao ver as opções com custo e RPO na mesa.

A diferença entre as duas não é de grau: em 09/08, o cadastro das pessoas *precisava
sobreviver* a um incidente; a partir de 10/08, ele não sobrevive. Num incidente de perda do
banco, **perde-se tudo desde o início** — nome, apelido, telefone, igreja, além dos Grupos e
das Ações. A comunidade recomeça do zero, cadastro incluído.

Registrado como risco aceito, com quem aceitou e quando, em `REVISAO-JURIDICA.md` item 4-B
(arquivo não versionado — o repositório é público). `INFRA-PRODUCAO.md` § 3 diz, na parte
pública, que a decisão existe e onde ela mora, sem revelar qual foi.

**A consequência que este item mandava tratar deixou de existir, e é o único ganho da
escolha**: sem cópia nenhuma, não há dado pessoal esquecido fora do banco vivo. A promessa da
Política — *"Não há como desfazer nem recuperar"* — passa a ser literalmente verdadeira, e a
anonimização da feature 009 alcança o único lugar onde o dado existe. Por isso nenhuma frase
da Política mudou e `LegalMetadata.version` segue em `1.3`.

### 4.4 Alcance da visibilidade do voto — **de acordo** ✅

Fica "só a própria pessoa lê o próprio voto", como implementado na feature 021. Nada a mudar.

### 4.5 Ordem das features de produto

Respondida na prática: **014 primeiro** (arquivar Grupo), por escolha do dono do app.

## 5. Conferido e fechado — não reinvestigar

Registrado para ninguém gastar tempo de novo.

- **`README.md`**: conferido, só uma linha desatualizada (a lista de rotas em `README.md:140`
  não cita `/perfil`, `/home`, `/district-admin/grupos-arquivados` nem
  `/district-admin/consentimentos`). Não é dívida grande.
- **Higiene da suíte de integração**: quatro arquivos faziam `delete from public.acoes` e
  afins **sem filtro**, e `dart test` roda os arquivos em paralelo. Era causa raiz de falha
  intermitente que aparecia em arquivos que não tinham feito nada errado. Escopados por UUID
  na feature 014; suíte estável em execuções repetidas.
- **Tickets fora do Spec Kit**: `IASD-01` e `IASD-02` estão **feitos**, `IASD-03` foi
  **descartado**, e `IASD-CI-GCS-UPLOAD` virou a feature 020. Nenhum ticket órfão.
- **As nove policies que ainda são `using (true)`** (`acoes`, `grupos`,
  `participacoes_grupo`, `confirmacoes_acao`, `rodadas_votacao`, `acoes_sugeridas`,
  `categorias_grupo`, `administradores_distrito`, `versoes_texto_legal`) foram conferidas uma a
  uma: **todas correspondem a algo que a Política de Privacidade declara público**. As duas que
  não correspondiam eram `votos` e `liderancas`, e as duas foram fechadas (features 021 e 018).
- **Identificadores em português**: 0 em `lib/` e 0 em `test/`. O verificador considera
  identificador que *começa* com a palavra portuguesa (`acaoId`, `grupoAsync`), que era o furo
  do scan da feature 012.
- **`CONTEXT.md`**: nenhum termo novo de domínio entrou nas features 016–021.
- **Verificações de tela feitas no navegador em 10/08** (vieram de
  `PARA-VOCE-FINALIZAR.md`, que agora só guarda o que está pendente): `/perfil` sem Perfil cai
  no cadastro; cadastro de adulto sem passo a mais, e o passo de criança aparecendo com idade 9
  e sumindo com 30; Líder confirmado visível; estado da própria declaração; Administrador vendo
  as pendentes; Rodada com "Seu voto" e **nenhuma contagem**; ordem de leitura terminando em "A
  Deus seja a glória"; Ministério arquivado mostrando o aviso e sumindo o Líder da tela com a
  linha ainda no banco.
- **Verificações fora da tela, no banco, em 10/08**: arquivar Grupo (presenças 5→5, participações
  2→2, Rodadas abertas 1→0, duas Ações futuras canceladas, a passada intacta, Rodada fechando com
  `vencedora_id` nulo); corrigir telefone sem mexer em `consentimento_lgpd_aceito_em` nem na
  versão; Líder de Ministério arquivado devolvendo 1 linha sem o filtro do cliente e 0 com ele —
  o que confirma que a barreira funciona **e** que ela é só do cliente; caixa de autorização
  contra a Política, sem contradição.
- **Dois consertos que passaram no `analyze` e continuaram errados na tela**, em 10/08: os alvos
  de toque da Home (o `visualDensity` adaptativo subtraía 8 px em desktop, então um mínimo de 48
  virava 40 reais — remedido em **48 px** nos seis alvos) e a tela de pendências de liderança
  (Usuário comum via a própria declaração com botões que o banco recusava, sem retorno nenhum na
  tela). **A lição é o registro**: nos dois casos só a medição no navegador mostrou.
- **Uma reprovação que era erro meu**: a doxologia em paisagem foi reprovada contra um texto de
  tarefa velho. SC-002 foi reescrita quando a doxologia foi para o rodapé e hoje pede "alcançável
  rolando até o fim" em 375 px de **largura**, não de altura. Contra o critério certo, passou.
- **Aviso de método**: medição por `getBoundingClientRect` **mentiu duas vezes** em 10/08 — um
  `top: 0` e um `33 px` de nó ainda não posicionado, os dois desmentidos pela captura de tela.
  Quem repetir medição por script confira contra a tela.

---

## 6. Estado das features

| Feature | Situação |
|---|---|
| 001–009 | Entregues |
| 010 pagina-home | Entregue; alvos de toque corrigidos e remedidos (48 px) em 10/08 |
| 011 acoes-titulo-e-encerramento | Entregue; 1 medição com gente aberta |
| 012 identificadores-em-ingles | Entregue |
| 013 foto-de-capa | **Entregue, mergeada e no ar** — schema e drenagem verificados em produção em 11/08; restam 2 verificações manuais (§ 3) |
| 014 arquivar-grupo | Entregue; 16 itens do quickstart esperam produção no ar |
| 015 consentimento-responsavel | Entregue; 1 medição com gente aberta |
| 016 meu-perfil | Entregue; 1 verificação de tela e 2 com gente abertas |
| 017 versao-do-consentimento | Entregue; 1 verificação de tela aberta |
| 018 visibilidade-de-liderancas | **Entregue, sem pendência** |
| 019 producao-regiao-e-backup | **Entregue, sem pendência** — região verificada em 10/08, backup decidido |
| 020 deploy-gcs-cdn | **Implementada e mergeada** — 24 de 32; as 8 abertas exigem acesso ao GCP (§ 3) |
| 021 visibilidade-do-voto | **Entregue, sem pendência** |
| 022 novidades | Entregue; a leitura por 3 pessoas do distrito continua aberta |
