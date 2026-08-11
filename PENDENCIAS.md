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

### 2.2 `anon` tem `TRUNCATE` em todas as tabelas

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

### 2.3 Cadastro antigo de criança ficou somente-leitura

Consequência conhecida e aceita da feature 015: um cadastro de criança anterior a ela não tem
os dados do responsável, e a check constraint recusa **qualquer** `update` naquela linha —
inclusive de campo sem relação, como telefone. Localmente são **0** cadastros assim; em
produção, desconhecido.

A pessoa não fica presa: a tela traduz a recusa numa frase pedindo que escreva para o e-mail
de contato, e a **exclusão de conta continua funcionando** (a anonimização zera `idade` e as
constraints passam), então o art. 18 VI está a salvo.

O que falta decidir: corrigir retroativamente esses cadastros, ou deixar como está. Se
corrigir, é spec própria — envolve pedir a autorização a quem já está cadastrado, e a spec da
015 excluiu isso de propósito.

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

### 2.6 `consentimentos_por_versao_test` falha de forma intermitente na suíte

Achado enquanto se rodavam os gates da 013 — **não é da 013**, que não toca em consentimento,
Perfil nem versão de texto legal.

**Sintoma medido**, em 2026-08-10: `test/integration/consentimentos_por_versao_test.dart`, caso
*"(d) Perfil anonimizado sai da contagem"*, falha com `Expected: <1> Actual: <0>` — e a falha é
na contagem de **baldes**, não na de pessoas: `consentimentos_por_versao()` devolve **nenhuma
linha** para a versão isolada `9.9-anon`, quando o teste espera uma.

**Frequência**: 2 falhas em cerca de 8 execuções da suíte completa. Rodado sozinho, o arquivo
passa sempre. Três suítes completas seguidas, logo depois de uma falha, passaram todas.

**Uma hipótese já descartada**: `versao_texto_legal_registro_test.dart` executa `delete from
public.versoes_texto_legal`, mas como `authenticated` e **esperando que falhe** — não é ele que
apaga o catálogo.

**Onde procurar**: o balde some, então ou as duas linhas de `perfis` criadas pelo caso (d)
deixaram de existir no meio do teste, ou a linha de `versoes_texto_legal` com `9.9-anon` saiu.
`dart test` roda os arquivos em paralelo contra o mesmo banco, e este projeto já teve esta
mesma classe de falha antes (feature 014, limpeza sem escopo em `tearDownAll`). O caminho é
procurar qual outro arquivo alcança essas linhas — por `uid` fixo repetido, por limpeza sem
filtro, ou por versão de texto legal compartilhada.

**Por que não foi consertado agora**: é a superfície da 009/017, não da 013, e consertar teste
alheio no meio da entrega de outra feature é como se introduz o defeito seguinte. Merece spec
curta própria, com a reprodução em laço (`for i in $(seq 1 20)`) como primeiro passo — sem laço
que falhe de propósito, qualquer conserto aqui é adivinhação.

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
