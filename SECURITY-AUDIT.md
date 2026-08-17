# Auditoria de segurança — RLS/autorização (2026-07-24)

Auditoria ponta a ponta de RLS, `SECURITY DEFINER` e regras de negócio
across as 8 features (001-008), pedida depois do domínio central estar
completo. 3 bugs críticos confirmados por reprodução direta via
`docker exec -i supabase_db_iasd psql` (não só leitura de código) e
corrigidos em `supabase/migrations/20260724130000_fix_rls_security_bugs.sql`.

## Bug 1 — cadastro real quebrado desde a feature 001

`nome_valido()` (`20260723191202_perfis_igrejas.sql`) lê
`palavras_bloqueadas` sem ser `SECURITY DEFINER`, e a tabela nunca
recebeu `GRANT SELECT` pra `anon`/`authenticated`. Todo `INSERT` real em
`perfis` (cadastro de Perfil) — que dispara o `CHECK (nome_valido(nome))`
como parte da transação do próprio usuário — falhava com `permission
denied for table palavras_bloqueadas`.

**Por que passou despercebido**: todo teste de integração que semeia
`perfis` (`criarPerfilDeTeste` em `db_test_helper.dart`, e o teste
dedicado de `nome_valido`) insere direto como superusuário Postgres, que
ignora `GRANT` — nenhum teste jamais exercitou o caminho real de
cadastro como role `authenticated`. 7 features inteiras (002-008) foram
implementadas e testadas em cima de uma feature 001 cujo cadastro nunca
funcionaria de verdade fora dos testes.

**Reprodução** (antes do fix): `insert into perfis (...)` como
`authenticated` → `ERROR: permission denied for table
palavras_bloqueadas`.

**Fix**: `grant select on public.palavras_bloqueadas to anon,
authenticated;`

**Teste de regressão**: `test/integration/security_signup_grant_test.dart`

## Bug 2 — Ação de Grupo forjada sem participação nem votação

`acoes_candidata_checar_regras()` (`20260724084300_rodada_votacao.sql`)
só valida participação/rodada quando `new.rodada_id is not null` —
retorna cedo (`return new`) sem tocar em `grupo_id` quando `rodada_id` é
nulo. A policy `acoes_insert_criador` só checa `auth.uid() =
criador_id`, nunca restringe `grupo_id`. Como `confirmada` nasce `true`
por default, qualquer `authenticated` conseguia inserir uma Ação de
Grupo já "confirmada" em **qualquer** Grupo do distrito, sem nunca ter
participado dele nem existir voto algum — violando a definição do
próprio domínio (`CONTEXT.md`: "Ação de Grupo nasce como Ação
candidata").

**Reprodução** (antes do fix): usuário sem nenhuma linha em
`participacoes_grupo` do Grupo alvo insere `acoes (nome, ..., criador_id,
grupo_id)` com `rodada_id` omitido → sucesso, `confirmada = true`.

**Fix**: `grupo_id` só é permitido junto de `rodada_id` — Ação de Grupo
sempre nasce candidata; tentativa de `grupo_id` sem `rodada_id` levanta
exceção.

**Teste de regressão**: `test/integration/security_acao_grupo_sem_rodada_test.dart`

## Bug 3 — candidata auto-confirmada pelo criador, sem votação

As 3 versões sucessivas da policy de `UPDATE` de `acoes`
(003→004→005) nunca tiveram `WITH CHECK` explícito — Postgres reusa
`USING` (que só verifica identidade, não os valores da linha nova).
Qualquer criador de uma candidata ainda em votação conseguia rodar
`update acoes set confirmada = true where id = <minha_candidata>`
direto via PostgREST, bypassando inteiramente `fechar_rodada_se_devido`
(apuração, desempate por sorteio, descarte das perdedoras).

**Reprodução** (antes do fix): criador de uma candidata com `rodada_id`
ainda aberta roda `UPDATE ... SET confirmada = true` na própria linha →
sucesso imediato, sem nenhum voto.

**Fix**: trigger `BEFORE UPDATE` (`acoes_protege_campos_internos`)
bloqueia mudança direta em `confirmada`/`grupo_id`/`rodada_id`/
`criador_id`, a menos que a GUC de transação `app.bypass_acoes_protecao`
esteja setada como `'true'` — só `fechar_rodada_se_devido` (o único
caminho legítimo) seta essa flag antes do seu próprio `UPDATE` interno.

**Teste de regressão**: `test/integration/security_acoes_protege_campos_test.dart`
(cobre tanto a rejeição do criador quanto a confirmação de que o
caminho interno legítimo continua funcionando).

## Verificação

- Todos os 3 bugs reproduzidos empiricamente via psql ANTES do fix, e
  reconfirmados como corrigidos DEPOIS, na mesma sessão.
- Regressão checada manualmente: Ação avulsa (sem grupo/rodada) continua
  funcionando; cancelar Ação (`cancelada_em`) continua funcionando;
  `fechar_rodada_se_devido` continua apurando e confirmando a vencedora.
- `flutter test`: 171/171 passando (4 novos testes de regressão).
- `flutter analyze`: sem apontamentos.

## O que a auditoria NÃO encontrou (verificado e descartado)

- Nenhum outro `CHECK constraint` com comparação contra `NULL` sem guarda
  explícita (além dos 2 já corrigidos nas features 006/007 durante o
  desenvolvimento normal).
- Nenhuma função `SECURITY DEFINER` sem `search_path` fixado.
- Nenhum vazamento de `idade` ou nome real de menor de idade —
  `perfil_publico()` e a RLS de `perfis` seguram isso corretamente.
- `grupos_update_dono`'s `WITH CHECK (true)` é seguro porque o trigger
  `checar_dono_participa` independentemente bloqueia a troca de dono pra
  quem não participa — padrão já correto desde a feature 002.

---

# Achado 4 — voto legível por qualquer pessoa sem cadastro (feature 021)

**Data**: 2026-08-09 | **Corrigido em**: `20260809200000_votos_visibilidade.sql`

`votos_select_public ... using (true)` (`20260724084300_rodada_votacao.sql:207-210`),
somado ao `grant select ... to anon` da linha 190, deixava a tabela `public.votos`
inteira legível por qualquer pessoa da internet. E a tabela é o par nominal
`(usuario_id, candidata_id)`, não um agregado.

**Reproduzido antes do fix**, no ambiente local, com três requisições e só a
chave pública — nenhuma conta, nenhum login:

```
GET  /rest/v1/votos?select=*        -> os três pares (usuario_id, candidata_id)
POST /rest/v1/rpc/perfil_publico    -> {"nome_exibido":"Clara Demo"}
GET  /rest/v1/acoes?select=id,nome  -> {"nome":"Entrega de cestas"}
```

Resultado montável por qualquer um: **"Clara Demo votou em Entrega de cestas"** —
frase inteira, não UUID. Reconfirmado depois do fix: o `GET` devolve `[]` com
HTTP 200, e a cadeia quebra no primeiro elo.

**Por que passou pelas auditorias anteriores**: a tela nunca mostrou voto alheio.
`voting_round_repository.dart:78-86` sempre filtrou pelo próprio `uid`, então a
inspeção da interface não revelava nada. Esconder na tela não é proteger, e este
achado é o exemplo.

**Divergência entre promessa e execução**: a Política de Privacidade afirmava que
"o voto não é anônimo **entre os participantes do Grupo**" — um círculo menor do
que a internet. Quem aceitou os termos aceitou outra coisa. Corrigido junto
(`privacy_policy_page.dart`), inclusive removendo "vota numa Rodada de votação"
da lista do que torna o nome público, que também deixou de ser verdade.

**Regra adotada**: só a própria pessoa lê o próprio voto. Não "os participantes do
Grupo", porque nenhuma tela consome voto alheio — abrir para o Grupo entregaria
acesso que nada usa.

**Teste de regressão**: `test/integration/votos_visibilidade_test.dart`, 9 casos.
Provados vermelhos antes de serem aceitos: com `using (true)` restaurado, os
quatro casos de privacidade falham e só eles.

## O risco que este fix CRIA, e que não existia antes

Fechar a leitura arma uma dependência que era inofensiva. Enquanto valia
`using (true)`, tanto fazia `fechar_rodada_se_devido` ser `security definer` ou
`invoker` — todos enxergavam todos os votos e a contagem saía igual. Agora,
convertê-la para `invoker` faz a apuração contar **só os votos de quem chamou**.

Medido, com 2 votos numa candidata e 1 noutra: como `invoker` chamada pela
minoria, a candidata majoritária **some da consulta** e a minoria vence. A Rodada
fecha, grava a vencedora errada e apaga as perdedoras — sem erro, sem rastro,
irreversível.

Coberto pelo caso `(f)` do teste, montado com quem fecha a Rodada tendo votado na
**perdedora** — montado ao contrário, ele passaria verde numa apuração quebrada.
Verificado vermelho: com a função convertida para `invoker`, `(f)` falha.
O aviso está dentro da migration, no ponto onde alguém quebraria.

## O que fica em aberto

- **Verificação em produção**: tudo acima foi medido no ambiente local. O `curl`
  anônimo contra o ambiente publicado ainda não foi feito — depende do deploy.
- **Não há como saber se a exposição foi explorada.** Não existe log de acesso
  (`REVISAO-JURIDICA.md`, Marco Civil art. 15, pendente de parecer). Por isso
  ninguém foi notificado: não há fato conhecido a notificar, nem canal.
- **`liderancas_select_public` continua `using (true)`** — mesma classe, outra
  tabela, já especificada como feature 018 e ainda não implementada.

---

# Achado 5 — `grant update` em `perfis` é de tabela inteira, sem recorte de coluna

**Data**: 2026-08-09 | **Status**: **FECHADO em 2026-08-11** pela change `endurecer-grant-update-perfis`

`20260723191202_perfis_igrejas.sql:56` concede `update` na tabela `public.perfis`
inteira a `authenticated`. A policy `perfis_update_own` protege a **linha** —
ninguém altera Perfil alheio, provado em
`test/integration/perfil_edicao_rls_test.dart` casos (a) e (b) — mas **não
protege a coluna**.

Consequência: por chamada direta à API, o próprio Usuário consegue escrever
`idade`, `genero` e `consentimento_lgpd_aceito_em` do próprio Perfil. A tela
"Meu Perfil" (feature 016) não oferece isso, e `toUpdateMap()` tem exatamente
cinco chaves, nenhuma delas essas — mas a tela não é a barreira.

**Gravidade real, sem exagero**: só afeta o próprio dado da pessoa, não o de
terceiro. O dano concreto é ela conseguir mudar a própria `idade` para escapar
da exigência de Apelido de menor, ou o `genero` para forjar composição de Dupla
Missionária. Não é vazamento; é contorno de regra de domínio.

**Nota da feature 017**: `consentimento_lgpd_aceito_em` ficou mais protegido do
que estava, sem que essa fosse a intenção — o gatilho
`perfis_carimbar_consentimento` restaura o valor antigo quando o aceite não
mudou, então reescrever a data por chamada direta não funciona mais. `idade` e
`genero` continuam expostos.

**É anterior à feature 016** e nenhum FR dela pede o conserto; consertar exige
migration, o que a spec da 016 exclui explicitamente.

**Conserto identificado**:

```sql
revoke update on public.perfis from authenticated;
grant update (nome, apelido, igreja_id, telefone,
              consentimento_lgpd_igreja_aceito_em)
  on public.perfis to authenticated;
```

Antes de aplicar, verificar quem mais escreve em `perfis`: `excluir_minha_conta`
é `security definer` e não é afetada, mas o cadastro (`insert`) e qualquer
caminho futuro precisam ser conferidos coluna a coluna.

**Aplicado em 2026-08-11**, `supabase/migrations/20260811160000_grant_update_perfis_por_coluna.sql`
— exatamente o SQL acima, com `apelido` e `telefone` no lugar de `nome` já
incluídos (a lista final é `nome, apelido, igreja_id, telefone,
consentimento_lgpd_igreja_aceito_em`, as mesmas cinco colunas que
`Profile.toUpdateMap()` já mandava). Levantamento de quem mais escreve em
`perfis` (`lib/` inteiro + migrations) não achou nenhum ponto fora da lista;
`excluir_minha_conta` confirmado `security definer`, não afetado. Confirmado
por consulta a `information_schema.column_privileges` no banco local: as
únicas colunas com `UPDATE` para `authenticated` são as cinco da lista.
`idade` e `genero` recusam com `permission denied` (SQLSTATE `42501`), provado
por teste de integração novo em `test/integration/perfil_edicao_rls_test.dart`
(casos g/h). Suíte de integração completa — **212/212 passaram**, 0 falhas —
e os testes de widget das telas de cadastro e edição de Perfil — **17/17
passaram**, 0 falhas — confirmam que nenhuma tela quebrou.

---

# Incidente — `.env` publicado no bundle web (2026-08-10)

Diferente do resto deste arquivo: não é achado de auditoria de RLS, é **um
vazamento que aconteceu**. Registrado aqui porque não estava registrado em lugar
nenhum — vivia só num comentário do workflow de deploy.

## O que aconteceu

`.env` era o **único** asset declarado em `pubspec.yaml`, então todo o conteúdo
do arquivo ia para dentro de `build/web/assets/.env`, que o site serve
publicamente. Um `flutter build web` **local**, rodado por quem tinha o `.env`
de trabalho completo no diretório, publicou junto **a senha do Administrador**.

O vetor mais provável é o alvo `deploy-web` do `Makefile` como ele existia até
aqui: ele fazia `flutter build web --release` e subia `build/web` para o bucket
público, sem nada entre uma coisa e outra. Achado em pentest.

## O que foi feito (2026-08-10 e 11)

Não se passou a filtrar o que entra no arquivo: **passou a não existir arquivo**.

- `.env` saiu de `assets:` no `pubspec.yaml`, e `flutter_dotenv` saiu das
  dependências;
- `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` viraram `String.fromEnvironment`,
  preenchidas por `--dart-define` no `run` e no `build`. Sem elas o app falha na
  inicialização dizendo o que fazer, em vez de subir apontando para lugar nenhum;
- o passo de verificação do workflow foi **invertido**: era "o `.env` do bundle
  só tem as duas chaves públicas", virou "nenhum `.env` foi embutido". Conferir o
  conteúdo do que vaza pressupõe aceitar que algo vaze;
- o `Makefile` ganhou a mesma recusa, porque foi por ele que passou o vazamento;
- os artefatos da feature 020 (quickstart, tasks, plan, research) descreviam o
  desenho antigo como "pretendido" e foram corrigidos ou revogados.

Verificado depois do build: `build/web/assets/.env` não existe, e nenhum arquivo
do bundle contém nome de chave nem token.

## Contenção — 2026-08-11

- **Senha do Administrador trocada.**
- **O arquivo saiu do ar**, conferido na origem e não só na borda:
  `https://storage.googleapis.com/conecta-iasd-site/assets/.env` → **404**, com
  `index.html` do mesmo bucket → **200**. O objeto não existe mais no bucket; não
  é o CDN escondendo.
- **A causa foi removida do código**: `.env` não é mais asset, e tanto o workflow
  quanto o `make deploy-web` recusam publicar se um `.env` reaparecer no bundle.

## O que continua em aberto — e só o dono do app resolve

O conserto fecha o **caminho**. Ele não desfaz o que já foi publicado.

1. ~~**Trocar a senha do Administrador que foi ao ar.**~~ **Feito em 2026-08-11.**
2. **Conferir o que mais estava naquele `.env`.** O `.env.example` deste
   repositório lista `SUPABASE_SERVICE_ROLE_KEY` e variáveis `ADMIN_*` ao lado
   das chaves públicas. Se a chave de serviço estava no arquivo publicado, ela
   **ignora RLS** e precisa ser rotacionada no painel do Supabase — é a chave
   mais perigosa do projeto.
3. **Estimar a janela de exposição**: de quando foi o build que publicou até o
   deploy que o substituiu. O bucket e o CDN têm histórico de objetos; o CDN pode
   ter servido cópia por mais tempo que o bucket.
4. **Decidir se houve incidente com dado pessoal.** Se apenas credencial vazou e
   não há indício de acesso, não há comunicação à ANPD a fazer; se a chave de
   serviço vazou, o alcance passa a ser todo o banco, e a decisão muda. Vale
   registrar a conclusão em `REVISAO-JURIDICA.md` com data, qualquer que seja.

Os quatro dependem de informação que só quem publicou tem. Nenhum deles é código.

---

# Mudança de policy de leitura — `acoes` e `confirmacoes_acao` (2026-08-13)

Change `acao-direcionada-a-grupo`, migration
`supabase/migrations/20260813120000_acao_restrita_ao_grupo.sql`.

Não é achado nem incidente: é uma **mudança deliberada de quem vê o quê**, numa
tabela com dado pessoal, e por isso é registrada aqui com o que passou a ser
escondido, com o que **não** passou, e com a dívida que a decisão aceita.

## O que mudou

Duas policies de `select` que eram `using (true)` saíram, com o nome junto —
mesmo motivo da feature 021: policy com nome que mente é pior que nome nenhum.

- `acoes_select_public` → `acoes_select_visivel`: devolve a Ação quando
  `restrita_ao_grupo = false` **ou** quem lê participa do Grupo dela.
- `confirmacoes_acao_select_public` → `confirmacoes_acao_select_conforme_acao`:
  devolve a confirmação só quando a Ação correspondente é legível. A condição
  **não** repete a regra de participação — a subconsulta roda sob a RLS de
  `acoes`, então a regra de visibilidade existe num lugar só.

Esconder a Ação e deixar a lista de presença aberta seria vazamento por porta
lateral: `confirmacoes_acao` é o par nominal `(acao_id, usuario_id)`, e revela
de uma vez a existência da Ação e quem estará lá.

## O que NÃO mudou, de propósito

- **O padrão continua público.** A coluna nasceu `default false`. Nenhuma Ação
  existente mudou de visibilidade no dia da migration.
- **Os `grant select` de `anon` ficaram como estavam** nas duas tabelas.
  Revogá-los faria a API responder erro de permissão em vez de lista vazia, e a
  diferença entre "não existe" e "não posso ver" viraria canal lateral. Ação
  escondida é **linha ausente**, nunca erro.
- **`rodadas_votacao` e `grupos` continuam `using (true)`.** Some a candidata
  restrita da Rodada; a existência da Rodada, não.
- **O Administrador do distrito não ganhou `bypass` de leitura.** Ação restrita
  é invisível para ele como para qualquer um de fora do Grupo. Não existe
  `bypass` de RLS de leitura em lugar nenhum deste app, e criar o primeiro aqui
  abriria acesso amplo sem que ninguém tenha pedido moderação de Ação de Grupo.

## Dívida aceita — escrita sem filtro reabre a Ação restrita

A escrita em `acoes` é de `acoes_update_criador_dono_grupo_ou_admin`
(`20260724092132_district_admin.sql`): criador, Dono do Grupo **ou**
Administrador do distrito. A change decidiu **não** dividir essa policy nem pôr
`restrita_ao_grupo` na lista protegida de `acoes_protege_campos_internos` — a
restrição é configuração da Ação como qualquer outra, e partir a permissão em
duas cria a segunda regra que diverge da primeira.

Medido contra o Postgres local, com tabela de brinquedo e com o banco real:

```
-- fechar o que se deixaria de enxergar: o próprio Postgres barra
update acoes set restrita_ao_grupo = true  where id = <de Grupo alheio>
  -> ERROR: new row violates row-level security policy for table "acoes"

-- reabrir pelo id o que não se enxerga: não alcança
update acoes set restrita_ao_grupo = false where id = <invisível>   -> 0 linhas

-- reabrir SEM FILTRO: alcança
update acoes set restrita_ao_grupo = false                          -> alcança
```

A policy de `select` vale também como `with check` implícito do `update`, então
**ninguém consegue esconder uma Ação de si mesmo** — o lado de fechar está
coberto sem código nenhum. O lado de **abrir** não: desmarcar deixa a linha mais
visível, o `with check` implícito não tem o que barrar, e a policy de `update`
do Administrador não recorta por linha.

**Consequência:** um Administrador do distrito reabre ao público **toda** Ação
restrita do distrito com uma única escrita sem filtro (`PATCH /rest/v1/acoes`
sem parâmetro de filtro), inclusive as que nunca pôde ler. Com o Dono do Grupo o
mesmo caminho existe e é inofensivo — a policy dele já recorta pelos Grupos
dele.

**Por que foi aceito:** o alcance é o de quem já é Administrador do distrito,
um papel de confiança do app; o efeito é exposição de agenda interna, não de
dado sensível novo (a lista nominal volta a ser legível, como era antes desta
change para toda Ação); e o recuo é barato.

**Recuo pronto, se um dia incomodar:** acrescentar `restrita_ao_grupo` à lista
de `acoes_protege_campos_internos` com condição de criador. O preço é a
restrição passar a ter dona diferente do resto da Ação — o Dono do Grupo
editaria nome, data e local do que é dele, mas não a visibilidade.

**Marcador:** `test/integration/acao_restrita_admin_assimetria_test.dart` afirma
o comportamento **real**, não o desejado. Se o recuo for aplicado, é ele que
fica vermelho — e aí a dívida foi paga, não quebrada.

## Verificação

Gates rodados em 2026-08-13, com os números:

- `flutter analyze` — **No issues found**
- `flutter test test/unit test/widget` — **335/335 passaram**, 0 falhas
- `dart test test/integration` — **249/249 passaram**, 0 falhas, depois de
  `supabase db reset` limpo
- `flutter build web --release` — **✓ Built build/web**

Oito arquivos de teste de integração cobrem os dois sentidos desta mudança —
Ação pública continua pública para `anon` e para autenticado de fora
(`acoes_select_publico_test.dart`), e Ação restrita não vaza por nenhuma das
portas conhecidas: leitura direta, lista de presença, Rodada de votação, faixa
de destaque, saída do Grupo e Grupo arquivado. Só o lado de esconder não prova
nada: uma policy escrita errado esconde Ação pública de todo mundo, e é o outro
lado que pega isso.

**Custo medido**, com volume sintético de 5000 Ações / 500 Grupos, policy nova e
antiga na mesma transação sobre a mesma base: para uma leitora realista
(participa de 3 Grupos entre 500), o feed foi de **1.296 ms** para **0.971 ms** —
mais rápido, porque a policy descarta metade das linhas antes do `Sort`. No pior
caso (participar de todos os 500 Grupos, o que ninguém faz), 1.296 → 1.875 ms. O
`exists` vira `hashed SubPlan`: `participacoes_grupo` é lida uma vez por
consulta, não por linha.

---

# Estreia do Realtime como superfície de leitura (2026-08-13)

Change `notificacoes-in-app`, migration
`supabase/migrations/20260813180000_notificacoes_in_app.sql:214`.

Até esta change **nenhuma tabela estava na publicação `supabase_realtime`** —
`select * from pg_publication_tables where pubname = 'supabase_realtime'`
devolvia zero linhas, conferido antes de começar. `public.notificacoes` é a
primeira.

## Por que isso é registro de segurança e não nota de release

Uma tabela publicada emite evento para quem estiver inscrito no canal. O canal é
**um caminho de código diferente do da consulta**: quem filtra ali não é a mesma
policy sendo avaliada pelo PostgREST, é o servidor de Realtime avaliando a RLS
por assinante. Configurar errado transforma a inscrição num feed de eventos
alheios — e falha **calada**, porque a tela de quem recebe demais não precisa
mostrar nada para o dado ter saído.

`notificacoes` carrega o par nominal `(destinatario_id, ator_id)`. É o mesmo
formato de vazamento que a feature 021 fechou em `votos`, onde três requisições
com a chave pública montavam "Clara Demo votou em Entrega de cestas".

## O que foi medido

O design afirmava que o `postgres_changes` do Supabase avalia as policies de
`select` por assinante. **Isso deixou de ser confiança na documentação.**
`test/integration/notificacao_realtime_isolamento_test.dart` abre duas sessões
reais (WebSocket na 54321, não o Postgres na 54322), inscreve as duas no canal,
gera um aviso para uma delas e verifica que a outra **não recebe evento nenhum**.

Resultado: **o canal respeita a RLS.** A outra sessão não recebe. O recuo
previsto no design — não publicar a tabela e atualizar o contador por consulta —
não foi preciso.

### Uma armadilha do próprio teste, que vale mais que o resultado

A primeira versão do teste passava pelo motivo errado. Logo depois de
`supabase db reset` o servidor de Realtime ainda não pegou a publicação nova, e
**o cliente já reporta `SUBSCRIBED` mesmo assim**. Nessa condição "a outra sessão
não recebeu nada" é verdade por o canal estar desligado, não por ele estar
isolado — e o teste diria "seguro" sobre um sistema que não foi exercitado.

O teste agora **aquece**: insere para a primeira sessão até ela receber, e só
então a ausência na segunda vira evidência. Verde nas duas condições (logo após
reset e com o banco quente).

## Defesa em profundidade, registrada de propósito

O app usa o canal como **sinal, nunca como fonte de dado**: ao receber qualquer
evento ele reconsulta a lista e a contagem, e o payload não monta tela. Isso
reduz o estrago se um dia a configuração do canal mudar — mas **não substitui** o
teste acima, e não é o que garante a privacidade. O que garante é a RLS.

## Verificação

Gates de 2026-08-13, com os números:

- `flutter analyze` — **No issues found**
- `flutter test test/unit test/widget` — **382/382**, 0 falhas
- `dart test test/integration` — **335/335**, 0 falhas
- `flutter build web --release` — **✓ Built build/web**

Suíte de integração conferida com o critério que o requisito
"A suíte é determinística em paralelo" pede: **20 execuções seguidas, 335/335 nas
20, zero falha** — depois do conserto do lock consultivo em
`createTestDistrictAdmin`, que corrigiu uma violação daquele requisito
encontrada por esta change.

---

# Chat de Grupo e de Ação — 2026-08-14

A primeira tabela de texto livre do projeto. O que segue é o que a construção
dela ensinou, e o achado principal não veio da suíte.

## O achado: policy que recusa em silêncio, e uma tela que diz que deu certo

`pode_ver_chat_acao` não tinha o braço de `administradores_distrito`.
`pode_ver_chat_grupo` tinha. O comentário da própria função e o `design.md`
afirmavam, longamente, que o Administrador estava incluído — e explicavam
corretamente **por que** ele precisa estar: no Postgres, remover uma linha
exige alcançá-la, e alcançar é ler.

O efeito não era erro. Era ausência:

```
 pode_ver_chat_acao  | false
 mensagens_visiveis  | 0
 UPDATE 0            <-- a remoção não afetou linha nenhuma
```

O Administrador do distrito **não conseguia moderar conversa de Ação**, e nada
no caminho dizia isso. `ChatRepository.removeMessage` não olhava linhas
afetadas, então a tela do moderador reportava sucesso sobre uma mensagem que
continuava visível para todo mundo. A instância de recurso existia no papel e
não existia no banco — que é o pior lugar para uma promessa de moderação
falhar, porque quem depende dela é quem já está sendo prejudicado.

**Por que a suíte não pegou.** 29 testes de chat, e todos os de moderação
montavam cenário em chat de **Grupo**. A função que faltava era a de **Ação**.
Cobertura alta sobre metade do domínio lê como cobertura alta.

**Quem pegou.** A revisão do texto legal contra o código — o agente
`advogado-digital` precisava afirmar na Política qual é o alcance do
Administrador, foi conferir na função, e a função discordava do comentário
dela mesma. Vale registrar o mecanismo: **escrever a promessa obriga a ler a
execução**, e é por isso que a Política é conferida contra o código e não
contra o design.

**Consertado**: braço acrescentado em `20260813200000`, com dois testes novos
em `chat_moderacao_test.dart` (Administrador remove em Ação; quem não tem nada
com a Ação não remove). `ChatRepository.removeMessage` passou a usar
`.select()` e a lançar quando a policy recusa — recusa de RLS em `update` é
zero linha, não exceção, e um método que não olha isso mente.

## Duas classes de defeito que esta change confirmou

**Recusa silenciosa é o modo de falha padrão do RLS.** `update` recusado afeta
zero linha e não levanta nada. Todo caminho de escrita do cliente precisa
olhar o resultado, ou vai reportar sucesso sobre nada. Já era verdade em
`acao-direcionada-a-grupo`; aqui custou uma instância de recurso.

**Ordem de gatilho AFTER é alfabética, e as ações referenciais entram na
fila.** O gatilho que marcava denúncia como `sem_mensagem` nunca rodava:
`on delete set null` da chave estrangeira é um `RI_ConstraintTrigger_…`, e
maiúscula ordena antes de minúscula. Quando o gatilho olhava, o vínculo já era
nulo. Virou `before delete`. Denúncia pendente sobre mensagem expurgada ficava
pendurada apontando para o nada, sem erro.

## Poder amplo, declarado

O Administrador do distrito lê o chat de **qualquer** Grupo e de **qualquer**
Ação. É o preço de existir instância de recurso quando o abuso vem de quem
manda no espaço, e está escrito na Política de Privacidade em vez de ficar só
aqui. O corte de 18 anos vale para ele também — `maior_de_idade()` está fora
do `or`, de propósito.

## Verificação

Números de fechamento da change, medidos em 2026-08-14:

| Gate | Resultado |
|---|---|
| `flutter analyze` | 0 issues |
| `dart test test/integration` | 380 testes, 0 falhas |
| `flutter test test/unit test/widget` | 404 testes, 0 falhas |
| `flutter build web --release` | sucesso (`✓ Built build/web`, 18,2 s) |

O canal de Realtime foi provado com três sessões reais por WebSocket:
participante adulta recebe, não participante e menor de 18 não recebem —
janela de não entrega derivada do aquecimento cronometrado (entrega medida em
407 ms, piso de 3 s aplicado). Prova de canal só vale usando o canal.

## O pentest do fechamento — 2026-08-14

Superfície nova atacada por REST e por WebSocket, com cinco credenciais criadas
para isso: dono adulto, menor de 15 que **participa do Grupo e confirmou na
Ação**, participante comum, não participante, e Visitante autenticado sem
Perfil, mais `anon` puro.

### O que caiu: `grant` sem `revoke` não restringe nada

**Função nova no Postgres nasce com `execute` para `PUBLIC`.** O
`grant execute ... to authenticated` que a migration escrevia ACRESCENTA um
privilégio; não substitui o que já estava lá. `anon` — a role que o PostgREST
usa em requisição sem `Authorization` — herdava o direito de chamar as seis
funções da change, e a chave publicável está no bundle público do app.

Medido: `anon` chamou `expurgar_mensagens_de_acao()` por `curl`, **sem login**,
e apagou mensagem real. Ela é `security definer` e faz `delete` global.

```
antes: 1
anon chama o expurgo => HTTP 200
depois: 0
```

O dano de dado era limitado — só apaga o que já venceu, e o cron faria igual —
mas escrita destrutiva alcançável sem autenticação não era o que aquelas linhas
diziam oferecer. Consertado com `revoke execute ... from public` nas seis, e
provado por `chat_privilegio_funcao_test.dart`, que olha o **privilégio** e não
o resultado: um teste que conferisse só "anon não lê mensagem" continuaria
verde com a RPC aberta, porque são barreiras diferentes.

**O precedente existe e ficou aberto**: seis funções `security definer` de
features anteriores continuam chamáveis por `anon`, três delas de escrita. Está
em `PENDENCIAS.md` 2.18, com a pior nomeada — `fechar_rodada_se_devido` só
checa `auth.uid()` no caminho forçado.

Sinal genérico para procurar em qualquer migration: `proacl` com uma entrada
que começa em `=` (nada antes do sinal) é o grant a `PUBLIC`.

### O que resistiu, e vale tanto quanto

Cada item abaixo foi tentado com comando real e devolveu bloqueio:

- **Corte etário no REST.** A menor de 15 participava do Grupo **e** estava
  confirmada na Ação — o cenário mais favorável possível ao atacante. `select`
  devolveu `[]` nos dois espaços; `insert` devolveu `42501` HTTP 403.
- **Corte etário no canal.** Menor e não participante assinaram e receberam
  **zero** payload enquanto o autorizado recebia o texto. O canal não entrega o
  TEXTO a quem a RLS nega.
- **Embeds do PostgREST como caminho lateral** — `grupos?select=*,mensagens(*)`
  e as três variantes. A RLS do recurso embutido é aplicada; não dá para ler
  mensagem "por dentro" de outra tabela.
- **Spoof de autor**, **edição de texto** (o gatilho, não a policy),
  **`delete` de mensagem** por qualquer papel, **denúncia por quem não lê o
  chat**, e **o denunciante resolvendo o próprio caso** — todos recusados.
- **Oráculo por forma de resposta**: "conversa inexistente" e "conversa que
  você não pode ver" dão o mesmo `[]` HTTP 200. Não dá para inferir existência.

Sobrou uma dívida de observação em `PENDENCIAS.md` 2.19: o canal entrega ao
`anon` um envelope vazio com tipo e horário da operação — volume de atividade,
nunca conteúdo.

---

# O texto removido continuava na tela de quem o removeu — 2026-08-16

Change `chat-de-grupo-e-acao`, convergências 5 e 6, **depois** do pentest de
14/08. Nada aqui é falha de RLS: o banco fez a coisa certa em todos os casos.
O que falhava era a tela continuar desenhando o que o banco já tinha apagado.

Entra neste ledger e não em nota de release porque a spec de moderação é
categórica — *"NÃO DEVE devolver o texto removido a ninguém"* — e "ninguém"
inclui quem escreveu e quem removeu. Um texto que a pessoa pediu para tirar e
continua legível na tela dela é o dado ainda circulando, mesmo com a linha do
banco já nula.

## O que foi medido

Todos em 2026-08-16, com o canal de tempo real derrubado de propósito — que é a
condição em que os três aparecem, e a razão de nenhum ter sido visto antes: com
o canal de pé, o eco do próprio `update` redesenhava a tela e escondia o
defeito.

| Caminho | Medida |
|---|---|
| Remover pela conversa | `chamou_o_banco=1`, `texto_ainda_na_tela=true`, `lapide_na_tela=false` |
| Reconectar após remoção ocorrida na queda | `texto_na_tela='o texto que a moderação tirou'`, `removida_em=null`, `lapide=visible` |
| Remover pela tela de denúncias, conversa montada atrás | `texto_ainda_na_conversa=true`, `lapide=false` |
| Expurgo de 30 dias com página anterior carregada | `antiga_na_tela=true`, `recente_na_tela=false` |

O quarto não devolve texto removido — devolve texto **expurgado**, que a
Política de Privacidade declara ter deixado de existir. Mesma classe.

## A causa, e por que ela é uma só

A regra estava escrita no `design.md` desde a convergência 4: *"sobreposição
local existe para o que o servidor ainda não disse, e é descartada assim que ele
diz"*. Ela foi **implementada em um lugar** — a ordem dos argumentos num
`mergeMessages` — e a lista se compunha em **quatro**. Escrever a regra não a
aplica.

Havia um segundo erro por baixo, e este é o que vale guardar: a precedência era
**"quem chega depois vence"**, que é ordem de rede. Ela mente nos dois sentidos.
A consulta ainda em voo responde com a linha anterior à remoção que o canal já
entregou; a cópia de antes da queda ganha da consulta que a reconexão refez. Não
existe ordem de argumentos que acerte os dois casos.

## O conserto

Uma costura só (`ChatNotifier` — três fontes, uma composição), e uma regra de
precedência que não depende de tempo:

> **A lápide é absorvente.** Entre duas versões da mesma linha vence a que
> avançou mais — visível, depois conta excluída, depois removida por moderação.

É o banco que a torna sempre correta, e não uma heurística: o gatilho
`mensagens_so_remove` recusa qualquer `update` que deixe `texto` não nulo e
preserva `removida_em` uma vez gravado. **Texto não ressuscita**, logo a versão
com menos texto é sempre a mais nova — sem relógio, sem número de versão, sem
depender de quem chegou primeiro.

## Verificação

Um teste por caminho, todos provados carregadores por mutação — inverter a
comparação de `_tombstoneRank` deixa três testes vermelhos em três arquivos, e
desfazer qualquer um dos dois consertos da convergência 6 deixa o seu vermelho.

`flutter analyze` 0 issues; `flutter test test/unit test/widget` 424 passed;
`dart test test/integration` 417 passed.

## O que fica em aberto, declarado

A reconsulta da reconexão cobre **a página mais recente**, não as páginas
anteriores já carregadas. Remoção ocorrida durante a queda sobre linha de página
antiga não é aprendida, e o texto fica na tela daquela pessoa até ela sair da
conversa (`consultas_recentes=2`, `texto_antigo_na_tela=true`). Aceito por
custo: refazer todas as páginas carregadas é uma ida ao servidor por página em
cada reconexão. Escrito no `design.md` para não ser "consertado" por simetria.

## A lição que não é sobre chat

O pentest de 14/08 procurou o dado saindo do banco para quem não podia lê-lo, e
não achou nada — corretamente. Estes quatro são o dado **já entregue a quem
podia**, e continuando na tela depois de o direito acabar. É uma superfície que
teste de RLS não alcança por construção, e a única forma que a pegou foi
derrubar o canal de propósito e olhar o que a tela desenhava.

---

# `nome_valido` era um oráculo da lista secreta — 2026-08-16

Change `fechar-superficie-anon`. Achado ao medir a superfície que a role `anon`
alcança, e **não estava em ledger nenhum** — nem no pentest de 14/08, que
procurou dado saindo do banco e não pergunta sendo respondida.

## O achado

`palavras_bloqueadas` tem RLS ligada e **nenhuma policy**. É de propósito: a
lista de palavras que o cadastro recusa fica escondida de todo mundo, inclusive
do Administrador do distrito. Leitura direta por `anon` devolve
`42501 permission denied`.

`nome_valido(text)` lê essa tabela, e é `security definer` justamente para
conseguir — o mesmo desenho de `maior_de_idade()` no chat. O que ninguém
decidiu foi **quem pode perguntar**: a função nasceu sem `grant` nenhum, e
função sem ACL no Postgres é chamável por `PUBLIC`.

Medido em 2026-08-16, como `anon`, sem sessão e sem `Authorization`:

| pergunta | resposta |
|---|---|
| `nome_valido('idiota')` | `false` |
| `nome_valido('burro')` | `false` |
| `nome_valido('estupido')` | `false` |
| `nome_valido('Maria Silva')` | `true` |

Quatro chamadas sobre uma lista de cinco palavras. Sonda-se um termo por
chamada e a lista sai inteira.

## A lição, que é maior que esta função

**A tabela recusar leitura direta não protege a lista enquanto a função aceitar
a pergunta.** Um "sim/não" sobre o conteúdo de um conjunto escondido entrega o
conjunto a quem tiver paciência — e paciência, aqui, é um `for` sobre um
dicionário.

Vale para qualquer `security definer` que responda sobre dado que a RLS esconde.
Virou requirement em `openspec/specs/privilegios-de-banco`, "Função que lê dado
escondido não vira oráculo dele", para não depender de alguém lembrar deste
arquivo.

## Por que o pentest de 14/08 não pegou

Ele testou as barreiras de LEITURA — `select` em tabela, embed do PostgREST,
canal de Realtime — e todas resistiram. O oráculo não é leitura: é uma função
autorizada respondendo a quem não devia poder chamá-la. Barreira diferente,
consulta diferente.

## O conserto, e o que NÃO se fez

`revoke execute ... from public` seguido de `grant execute ... to
authenticated`.

**Ela continua `security definer`**, e trocar para `invoker` seria o conserto
errado: sem privilégio para ler a lista ela passaria a devolver "válido" para
tudo, e a validação de nome sumiria em silêncio — o modo de falha que
`20260806090000_nome_valido_security_definer.sql` foi escrita para eliminar. O
defeito era quem podia perguntar, não a função.

Também não se trocou o retorno booleano pela palavra casada. Não muda nada:
quem sonda já sabe o termo que perguntou. O oráculo é a permissão de perguntar.

## Verificação

`superficie_sem_sessao_test.dart` exige RECUSA na sondagem sem sessão, e
resposta normal para quem tem — se voltar a devolver `false` em vez de recusar,
o oráculo reabriu, e é `false` que entrega que o termo está na lista.

`inventario_superficie_anon_test.dart` impede a próxima: enumera toda função de
`public` e falha se alguma alcançar `anon` fora de uma lista de exceções escrita
à mão, com motivo por linha.

---

# O limite de ritmo era contornável mandando `created_at` — 2026-08-17

Change `filtro-e-intervalo-de-mensagem`. Achado pela **convergência 1**, não por
pentest e não por revisão: `flutter analyze` estava limpo, 447 testes de
unidade/widget e 479 de integração estavam verdes, e o controle não valia.

## O que foi medido

Pela API real — PostgREST, sessão `authenticated` de verdade com JWT assinado,
não `set request.jwt.claims`:

```
POST /rest/v1/mensagens
{"grupo_id":"…","autor_id":"…","texto":"flood","created_at":"2020-01-01T00:00:00Z"}
```

**30 mensagens inseridas em segundos. Zero recusas.** O limite recém-escrito —
3 segundos entre mensagens e 20 por 5 minutos, por pessoa e por conversa — não
recusou nenhuma.

## A causa

`mensagens_ritmo_de_envio` conta `max(created_at)` e `count(*)` das linhas que
**já existem** dentro da janela. Linha gravada com data antiga nasce fora da
janela, e a checagem seguinte não a vê. Cada mensagem nova apagava o rastro que
tornaria a próxima recusável.

O que permitiu escrever a coluna veio de antes:
`20260813200000_chat_de_grupo_e_acao.sql:328` deu
`grant select, insert, update on public.mensagens to authenticated` — a tabela
inteira, sem recorte. Medido em `information_schema.column_privileges`:
`authenticated` tinha `insert` nas **oito** colunas, `created_at`, `id` e
`removida_por` inclusive.

## A lição, e ela não é sobre chat

**Um `grant` sem recorte não é dívida enquanto ninguém depende da coluna.** Até
esta change, forjar `created_at` só bagunçava a ordem da conversa — feio, sem
consequência. No dia em que um controle passou a LER aquela coluna, o mesmo
grant virou contorno do controle.

O sinal genérico, para procurar em qualquer feature nova: **toda vez que uma
regra de segurança passar a depender de uma coluna, conferir quem pode
escrevê-la.** A pergunta não é "esta coluna é sensível?" — é "alguma decisão
agora depende dela?".

## O conserto, e o que NÃO se fez

```sql
revoke insert on public.mensagens from authenticated;
grant insert (grupo_id, acao_id, autor_id, texto) on public.mensagens to authenticated;
```

Mesmo precedente de `20260811160000_grant_update_perfis_por_coluna.sql`. Grant
de coluna restringe a cláusula do próprio `insert` e recusa com `42501` antes de
qualquer policy rodar. Fecha `id` e `removida_por` forjados junto, e o app não
mudou uma linha — `ChatRepository.send` já mandava exatamente essas quatro.

**Policy com `with check` não serviria**: a linha resultante de um `created_at`
forjado é perfeitamente válida, e não há predicado que a distinga de uma
legítima sem comparar com `now()` — o que recusaria também restauração de dump.

**Não se carimbou `new.created_at := now()` no gatilho.** Reescrever em silêncio
um valor que alguém mandou é pior do que recusar: quem mandou não fica sabendo
que foi ignorado. E impediria semear histórico como superusuário, que é como a
suíte monta conversa antiga e como uma restauração funciona.

`update` continua com a tabela inteira, de propósito: lá quem protege é o
gatilho `mensagens_so_remove`, que recusa mudança em `id`, `grupo_id`,
`acao_id`, `autor_id` e `created_at` uma a uma, com mensagem que diz o que
aconteceu. Recortar o grant trocaria essa mensagem por um `permission denied`
genérico sem ganhar barreira.

## Verificação

`limites_de_chat_test.dart` prova pela **API**, e a escolha é o ponto: como
`postgres` o grant de coluna não se aplica (superusuário), e o caso passaria
verde sobre o defeito intacto. É a mesma armadilha que
`security_nome_valido_rls_test.dart` documenta para RLS, aplicada a privilégio
de coluna.

Dois casos: mandar `created_at` devolve `42501`; e o flood de 5 tentativas grava
**exatamente 1** — a primeira passa, a de data forjada cai por privilégio, as
demais pelo intervalo. Medido em 30 antes do conserto.

## Achados vizinhos da mesma varredura

- **A trava do ritmo foi provada por remoção**, não por leitura: sem o
  `perform 1 from perfis … for update`, duas inserções simultâneas da mesma
  pessoa gravam **2 linhas**; com ela, 1.
- **O filtro de palavra no `motivo` da denúncia valia só na inserção**
  (convergência 3): um moderador reescreveu o motivo alheio para uma palavra da
  lista e o banco aceitou. Conserto em `20260817140000`. A metade que continua
  aberta — moderador reescrevendo `motivo` e trocando `denunciante_id` — é de
  `chat-de-grupo-e-acao` e está em `PENDENCIAS.md` 2.24.
