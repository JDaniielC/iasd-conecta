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
