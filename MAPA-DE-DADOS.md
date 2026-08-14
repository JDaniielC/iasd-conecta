# Mapa de dados — Rede IASD Vitória de Santo Antão

Levantado direto do código para escrever a Política de Privacidade e os
Termos de Uso (`lib/features/legal/`). Serve também de rascunho do registro
de operações de tratamento (ROPA, LGPD art. 37). Toda linha tem
`arquivo:linha` — sem isso, não é mapa, é palpite.

## Dados coletados (tabela `public.perfis`)

`supabase/migrations/20260723191202_perfis_igrejas.sql:28-39`, as quatro colunas de responsável em `supabase/migrations/20260810000000_autorizacao_responsavel.sql:61`, e as duas colunas de versão em `supabase/migrations/20260809220000_versao_do_consentimento.sql:139`

| Campo | Obrigatório | Onde é lido/exibido | Nunca exposto a outros? |
|---|---|---|---|
| `nome` | sim | moderado por `nome_valido()` (linha 16-26); exibido publicamente via `perfil_publico` | não — é o nome de exibição |
| `apelido` | só se `idade < 18` (constraint `apelido_obrigatorio_menor`, linha 38) | substitui `nome` em `perfil_publico` quando presente (`perfis_igrejas.sql:48`) | não — é o substituto público do nome de menor |
| `igreja_id` | não | exibido via `perfil_publico` (linha 48); usado para destaque em Grupo/Ação | não |
| `telefone` | não | só `criarPerfil`/`toInsertMap` grava (`perfil.dart:49`); nenhum outro código lê ou exibe | sim, hoje ninguém lê |
| `genero` | sim, só `masculino`/`feminino` (check, linha 34) | usado server-side por `confirmacoes_acao_decidir_status()` (`dupla_missionaria.sql:63-77`) pra validar composição de Dupla Missionária | sim — nunca sai em `perfil_publico`, RLS restringe select da tabela base ao próprio dono (`perfis_select_own`) |
| `idade` | sim (`>= 0`) | só decide `apelido_obrigatorio_menor` no banco e `menorDeIdade`/`precisaDeApelido` no client (`perfil.dart:34-36`) | sim — confirmado em `perfil.dart:57-58` e no comentário de `perfil_repository.dart:11` |
| `consentimento_lgpd_aceito_em` | sim (`not null`) | o cliente manda o campo como **sinal** de que a caixa foi marcada; o **valor** é o `now()` do banco, gravado pelo gatilho `perfis_carimbar_consentimento` (feature 017) | não se aplica |
| `consentimento_lgpd_versao` | não (anulável) | versão do texto legal vigente no aceite, carimbada pelo mesmo gatilho a partir de `versao_texto_legal_vigente()`. `NULL` = aceite anterior à feature 017, versão **desconhecida** — nunca um palpite | sim — só o Administrador do distrito vê, e em contagem agregada, nunca por pessoa (`consentimentos_por_versao()`) |
| `consentimento_lgpd_igreja_versao` | não (anulável) | idem, para o consentimento destacado de Igreja de origem; gravada e zerada junto com `consentimento_lgpd_igreja_aceito_em` | sim, mesma regra |
| `responsavel_nome` | sim, se `idade < 13` (constraint `autorizacao_responsavel_crianca`) | nenhuma tela lê — só é gravado no cadastro | sim, e é **dado de terceiro**: a pessoa não usa o app, não tem tela e não tem como pedir exclusão sozinha |
| `responsavel_contato` | idem | idem. É **registro, não canal** — o app nunca escreve para este endereço | sim, mesma regra |
| `autorizacao_responsavel_em` | idem | data da autorização; junto com a versão é o que dá valor probatório (LGPD art. 8º §2º) | sim |
| `autorizacao_responsavel_versao` | idem | versão do texto legal vigente no aceite | sim |

**Não coletado**: CPF, endereço, **foto de Perfil**, dado de saúde, dado de
pagamento.

⚠️ **Existe imagem no app desde a feature 013, e ela não é da pessoa.** A
afirmação anterior desta linha — "foto/avatar não coletado, nenhuma ocorrência
de `foto`/`avatar`/`imagem`, confirmado por grep" — deixou de ser verdade.

## Foto de capa (feature 013)

A imagem ilustra o **Grupo/Ministério ou a Ação**, nunca a pessoa. **Não existe
foto de Perfil**, e a distinção importa: uma capa não é dado pessoal de quem a
enviou, mas *pode conter* dado pessoal de terceiro — que é o risco inteiro
desta feature.

| Onde | O quê |
|---|---|
| Tabela | `public.fotos_capa` (`supabase/migrations/20260810100000_foto_de_capa.sql:47`) — `grupo_id` **ou** `acao_id`, `caminho`, `enviada_por`, `created_at`. Exatamente um dono, por constraint |
| Binário | Bucket `fotos-capa`, **público** (`:245`). Máx. 5 MB, só `image/jpeg`, `image/png`, `image/webp` |
| Quem envia | Dono do Grupo, criador da Ação, Administrador do distrito — policies `fotos_capa_insert_admin` (`:118`) e `fotos_capa_objetos_insert` (`:271`), que confere o dono pelo **caminho** |
| Quem vê | **Qualquer pessoa na internet, inclusive sem cadastro.** O bucket é público e a policy de select é `using (true)` (`:112`) |
| Sensível? | A imagem em si não é classificada. **Mas pode conter rosto de terceiro**, inclusive de criança — e é por isso que existe aviso obrigatório antes de cada envio e denúncia aberta a Visitante |

**O controle é preventivo e reativo, não automático — e isso está escrito na
Política.** O app mostra um aviso antes de cada envio
(`cover_photo_advice_sheet.dart`) e aceita denúncia de qualquer pessoa, sem
cadastro. Ele **não** solicita nem verifica autorização de responsável para
imagem de menor, e **não** analisa o conteúdo do que é enviado. Omitir isso
deixaria subentendido um controle que não existe.

**Remoção** (`capas_a_remover`, `:87`): apagar a linha **não** apaga o binário —
a documentação do fornecedor diz que exclusão por SQL deixa o objeto órfão. Por
isso o gatilho `fotos_capa_enfileirar_remocao` (`:107`) enfileira, e a drenagem
chama a API fora da transação. Enfileirar em vez de chamar a rede no gatilho é
o que impede uma falha de rede de abortar `excluir_minha_conta` — trocar
vazamento de imagem por perda do direito do art. 18, VI seria pior.

**A janela de 60 segundos**: removida a imagem, quem já tiver o endereço direto
pode abri-lo por até um minuto, enquanto o cache de borda expira. Medido em
fonte primária (`specs/013-foto-de-capa/research.md` D-004) e **aceito pelo
responsável pelo app em 2026-08-10**. A Política diz isso com esse número, e
não "removida imediatamente".

**Auth (fora de `public.perfis`)**: sessão anônima por padrão
(`lib/core/supabase_client.dart:19`, `signInAnonymously()`); upgrade opcional
para e-mail+senha via `AuthRepository.upgradeParaConta`
(`lib/features/perfil/data/auth_repository.dart:15-22`), gerido pelo Supabase
Auth — e-mail e hash de senha ficam no schema `auth`, fora de `public.perfis`.

## Classificação de sensibilidade (LGPD art. 5º, II)

- **`igreja_id` — provavelmente dado sensível.** Art. 5º, II lista
  "filiação a organização de caráter religioso" como dado sensível. Escolher
  uma das 15+ igrejas do distrito é exatamente isso, de forma estruturada.
  Campo é opcional no banco e na UI (`cadastro_perfil_page.dart:154`), o que
  mitiga mas não resolve a base legal. **[EM ABERTO — precisa de advogado]**:
  se confirmado sensível, a base do art. 7º (legítimo interesse etc.) não
  serve — precisa do art. 11. O app hoje só tem **um** consentimento genérico
  (`consentimento_lgpd_aceito_em`), não um consentimento destacado específico
  pra esse campo (art. 11, I). Ver achado A-2.
- **`genero`**: não é, por si, uma das categorias do art. 5º, II (a lista não
  inclui gênero/sexo isoladamente — é diferente de "dado referente à vida
  sexual"). Tratado aqui como dado comum, mas nunca exposto a terceiros
  (ver tabela acima) — minimização por padrão, correta independente da
  classificação.
- **`idade`**: não sensível por si, mas o produto tem usuários crianças e
  adolescentes (Desbravadores 10-15, Aventureiros 6-9, ver
  `CATEGORIAS-DE-ACAO.md:6-18`) — isso ativa a LGPD art. 14, não o art. 5º,
  II. Ver achado A-1.

## Quem vê o quê (RLS = a fonte de verdade, não a UI)

As policies abaixo concedem `select` a `anon, authenticated` — ou seja,
**visível até para quem nunca fez cadastro**, via API direta, independente do
que a tela de fato renderiza. A maioria ainda é `using (true)`, sem filtro
nenhum. Quatro já não são, e ficam na tabela justamente para registrar que já
foram: `votos` (feature 021), `liderancas` (feature 018), `acoes` e
`confirmacoes_acao` (change `acao-direcionada-a-grupo`):

| Tabela | Policy | Arquivo:linha |
|---|---|---|
| `perfis` (só via RPC `perfil_publico`, nunca `select` direto) | `perfil_publico(uuid)` retorna `id, nome_exibido, igreja_id` — nunca `idade`/`telefone`/`genero` | `20260723191202_perfis_igrejas.sql:41-53` |
| `participacoes_grupo` | `participacoes_grupo_select_public` | `20260723220703_grupos.sql:121-124` |
| `acoes` | **não é irrestrita desde a change `acao-direcionada-a-grupo`** — `acoes_select_visivel` devolve a Ação quando `restrita_ao_grupo = false` **ou** quem lê participa do Grupo dela. Ação restrita some para `anon` e para autenticado de fora, como linha ausente, nunca erro. O padrão continua público: a coluna nasceu `default false` e nenhuma Ação existente mudou de visibilidade | `20260813120000_acao_restrita_ao_grupo.sql:142-152` |
| `confirmacoes_acao` | **não é irrestrita desde a mesma change** — `confirmacoes_acao_select_conforme_acao` devolve a confirmação só quando a Ação correspondente é legível para quem lê. A condição não repete a regra de participação: a subconsulta roda sob a RLS de `acoes`, então a regra vive num lugar só | `20260813120000_acao_restrita_ao_grupo.sql:165-173` |
| `rodadas_votacao` | `rodadas_votacao_select_public` | `20260724084300_rodada_votacao.sql:197-200` |
| `convites_acao` | **nasceu fechada** (change `convite-para-acao`) — `convites_acao_select_partes` devolve a linha só para quem convidou e para quem foi convidado; `anon` não tem `grant` nenhum. Escrita: criar passa pela RPC `convidar_para_acao` (sem `grant insert`), e recusar é `grant update (recusado_em)` + `convites_acao_update_convidado`, recorte por coluna | `20260813140000_convite_para_acao.sql:25` (tabela), `:83` (grant de coluna), `:87` e `:95` (policies) |
| `votos` | **não é público desde a feature 021** — `votos_select_own` devolve só a linha da própria pessoa (`auth.uid() = usuario_id`), e `anon` fica sem policy de `select`, portanto recebe lista vazia. A apuração conta todos os votos por fora da RLS, em `fechar_rodada_se_devido` (`security definer`) | `20260809200000_votos_visibilidade.sql:41-44` |
| `administradores_distrito` | `administradores_distrito_select_public` | `20260724092132_district_admin.sql:52-55` |
| `liderancas` | **não é irrestrita desde a feature 018** — `liderancas_select_confirmada_propria_ou_admin`, com três disjuntos: a declaração **confirmada** (e não rejeitada) é pública, que é a "identificação do Líder" que o glossário promete; a **própria pessoa** vê a sua em qualquer estado, porque precisa saber se foi confirmada, rejeitada ou se ainda espera; e o **Administrador do distrito** vê todas, porque é ele quem decide. Pendente e rejeitada de terceiro: negadas por default | `20260809210000_liderancas_visibilidade.sql:100-110` |

A change `convite-para-acao` acrescentou **dado pessoal novo**: quem chamou
quem, quando, e por qual Grupo. `convites_acao`
(`20260813140000_convite_para_acao.sql:25`) referencia `perfis(id)` e **nunca
copia o nome** — as duas FKs de Perfil são sem `on delete cascade` de propósito,
porque o Perfil é anonimizado e não apagado, e um nome desnormalizado
sobreviveria a isso. Um teste de integração trava a lista de colunas da tabela
para essa otimização não voltar por descuido.

`contatos_para_convite(uuid)` (`:118`) é a função mais sensível da change: ela é
`security definer` sobre `perfis`, que é fechado, e entrega **vários nomes de
exibição de uma vez**. Um a um esse nome já é público por `perfil_publico`; em
lote e sem checagem, seria a lista de nomes do distrito inteiro. A defesa é não
ter parâmetro de Grupo — o filtro é `auth.uid()` por dentro, e o `nome_exibido`
usa a mesma expressão `coalesce(apelido, nome)` de `perfil_publico`, que é a que
protege menor de idade. Ela toca: nome, apelido e participação em Grupo. Não
toca idade, telefone, gênero nem Igreja.

`convidar_para_acao(uuid, uuid, uuid[])` (`:177`) lê `auth.users.is_anonymous`
para exigir Conta de quem convida — mesmo precedente de `declarar_lideranca`.
Não devolve nome nenhum, só ids e a classificação do lote.

`acoes.restrita_ao_grupo` (`20260813120000_acao_restrita_ao_grupo.sql:30`) não
é dado pessoal — é um booleano de configuração da Ação. Está registrado aqui
porque **decide o alcance de dado pessoal alheio**: com ele verdadeiro, a lista
nominal de quem vai (`confirmacoes_acao`) deixa de ser legível fora do Grupo.
A constraint `acoes_restrita_exige_grupo`
(`20260813120000_acao_restrita_ao_grupo.sql:35-37`) garante que ele só existe
onde há Grupo a que restringir. Quem escreve a coluna é quem edita a Ação
(`acoes_update_criador_dono_grupo_ou_admin`), com a ressalva registrada em
`SECURITY-AUDIT.md`.

Até a feature 018, a UI de `detalhe_grupo_page.dart:118-119` só *renderiza*
Líder/Diretor confirmado (via `currentLeadersProvider`), mas a RLS permitia ler
a tabela inteira: quem se declarou e foi **rejeitado** era legível por qualquer
Visitante. Esconder na tela não é proteger, e este era o exemplo — a política de
privacidade descreve o nível de acesso real (RLS), não o que a tela mostra.
Agora as duas coisas dizem o mesmo, e `fetchCurrentLeaders`
(`leadership_repository.dart`) carrega o predicado gêmeo do da policy, com o
aviso de que os dois mudam juntos.

## Terceiros

- **Supabase** — hospeda Postgres + Auth + API. `lib/core/supabase_client.dart:14-17`
  lê `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` do `.env`. **Produção existe**:
  `.env.prod` aponta para um projeto Supabase Cloud real, e
  `.github/workflows/deploy-web.yml:33-42` injeta os secrets `SUPABASE_URL` e
  `SUPABASE_PUBLISHABLE_KEY` no build web. O ambiente local
  (`http://127.0.0.1:54321`, `.env.example`, `supabase/config.toml`) continua
  existindo em paralelo.
  A região exigida (`sa-east-1`, São Paulo) e a **verificação da região que a
  produção de fato usa** ficam em `INFRA-PRODUCAO.md` — é de lá que sai a
  base para a política afirmar, ou não, que há transferência internacional.
  Enquanto essa verificação não estiver preenchida, a afirmação da política
  descreve uma decisão tomada, não um fato conferido.
- Nenhum outro SDK de terceiro no `pubspec.yaml:33-42`: sem analytics, sem
  push notification, sem e-mail/SMS transacional, sem pagamento.

## Retenção e exclusão

- **A exclusão de conta existe e é autoatendida** desde a feature 009
  (`20260806140000_exclusao_de_conta.sql`, rota `/delete-account`). A função
  `excluir_minha_conta()` roda numa transação só: anonimiza a linha de
  `perfis` (nome vira `'Membro removido'`; apelido, telefone, igreja, gênero
  e idade viram nulos; `anonimizado_em` marca o estado), apaga os vínculos
  vivos e apaga o `auth.users`.
- `perfis.id` **não referencia mais** `auth.users(id)`. A FK era
  `on delete cascade` e apagar o login levava o Perfil junto — o oposto do
  que a anonimização precisa, já que é a linha anonimizada que ancora o
  histórico de terceiros. Consequência aceita: passa a existir legitimamente
  linha de `perfis` sem `auth.users` correspondente, que é justamente o
  estado "anonimizado". Ver `specs/009-exclusao-de-conta/research.md` § 2.
- As FKs sem `on delete cascade` — `grupos.dono_id`, `acoes.criador_id`,
  `rodadas_votacao.aberta_por`, `administradores_distrito.usuario_id`/
  `promovido_por`, `liderancas.usuario_id`/`confirmado_por` — continuam como
  estavam, e **deixaram de ser um problema**: nada é apagado de `perfis`, a
  linha permanece anonimizada. O que exige alguém capaz de agir (posse de
  Grupo, Rodada ainda aberta) é transferido ao Administrador do distrito
  mais antigo; o resto permanece apontando pro Perfil anonimizado, como
  histórico. **O achado A-4 está resolvido.**
- Única recusa possível: quem sai é o único Administrador do distrito. Sem
  nenhum Administrador, o distrito não consegue promover outro
  (`administradores_distrito_checar_regras` exige um pré-existente) e não
  sairia desse estado sem rodar migration.
- `genero` e `idade` passaram a aceitar nulo em `perfis`, exclusivamente para
  a anonimização: num distrito pequeno, gênero + idade + quais Grupos a
  pessoa participava reidentifica, e o art. 16 da LGPD só dispensa a exclusão
  quando o dado está de fato anonimizado.
- **Não existe tela de "meu perfil"/editar cadastro** — `perfis_update_own`
  permite `UPDATE` via RLS (`20260723191202_perfis_igrejas.sql:76-79`), mas
  nenhuma página em `lib/features/perfil/presentation/` usa esse caminho
  (só `cadastro_perfil_page.dart`, que só faz `insert`, e
  `upgrade_conta_page.dart`, que só mexe em `auth.users`). Direito de acesso
  e correção (art. 18, II e III) não tem mecanismo de autoatendimento hoje.

## Consentimento

- **Desde a feature 017, cada aceite grava a versão do texto aceito**, ao lado da
  data: `consentimento_lgpd_versao` e `consentimento_lgpd_igreja_versao`. Quem
  grava é o banco, pelo gatilho `perfis_carimbar_consentimento`
  (`20260809220000_versao_do_consentimento.sql:193`), a partir do catálogo
  `public.versoes_texto_legal`. Valor de versão mandado pelo cliente é
  descartado — um registro de base legal que valesse o que o cliente diz não
  demonstraria nada.
- **Existem aceites sem versão conhecida.** Foram colhidos entre **2026-07-23**
  (criação de `public.perfis`, `20260723191202_perfis_igrejas.sql`) e
  **2026-08-09**, data desta migration. Nesse período o app gravava só a
  data/hora. Essas linhas ficam com versão `NULL`, que quer dizer
  **desconhecida** e mais nada — nenhuma foi preenchida retroativamente, e o
  gatilho impede que sejam.
- **O que se sabe sobre os documentos, e que não vira dado da pessoa**: a 1.0
  vigorou até 2026-08-05; a 1.1 desde 2026-08-06; a 1.2 desde 2026-08-09
  (feature 021, quando o voto deixou de ser público). Só a 1.1 e a 1.2 estão no
  catálogo — a 1.0 não tem data de vigência documentada no repositório, e
  inventar uma seria o mesmo chute que a coluna existe para evitar.
- **Atribuir cada aceite antigo a uma dessas versões pela data é estimativa, não
  registro.** É possível sob demanda, com as ressalvas de
  `specs/017-versao-do-consentimento/research.md` D-006 ao lado, e **nunca
  gravada na coluna**: o valor da coluna é o que o banco carimbou, e mais nada.
- Consulta de conformidade: `public.consentimentos_por_versao()`, restrita ao
  Administrador do distrito, devolve contagem por versão com os de versão
  desconhecida contados à parte. Devolve quantidade, nunca identidade.
- Antes da tarefa de revisão jurídica, o único texto apresentado no aceite era o
  rótulo do checkbox ("Aceito o uso dos meus dados (LGPD)") — sem link para
  nenhum documento. Corrigido (link para `/privacidade` e `/termos` antes do
  checkbox), mas isso não resolve retroativamente quem já tinha aceitado a
  versão anterior.

## Crianças e adolescentes

- Idade mínima não é imposta em lugar nenhum: `idade integer not null check (idade >= 0)`
  (`20260723191202_perfis_igrejas.sql:35`) aceita qualquer idade a partir de 0.
- `CATEGORIAS-DE-ACAO.md:6-18` confirma público infantil ativo: Desbravadores
  (10-15), Aventureiros (6-9).
- **Desde a feature 015 existe consentimento de responsável.** Criança é quem tem
  **menos de 13** — o número vive em `public.limiar_crianca()` e é espelhado por
  `childAgeThreshold` em `profile.dart`, com teste de integração comparando os dois.
  Abaixo do limiar, o cadastro exige nome do responsável, um contato dele e uma
  autorização destacada, e as duas constraints `autorizacao_responsavel_crianca` e
  `autorizacao_responsavel_so_para_crianca` garantem isso **no banco** — um `insert`
  direto sem autorização é recusado.
- **O que a feature NÃO faz, e precisa continuar dito**: não verifica a identidade de
  quem marca a caixa, não notifica o responsável por nenhum canal (o contato é
  registro), e **não corrige retroativamente** cadastros de criança anteriores a ela.
- **Cadastro antigo de criança virou somente-leitura**: qualquer `update` naquela linha
  é recusado pela constraint, inclusive de campo sem relação. A exclusão de conta
  continua funcionando (a anonimização zera `idade` e as constraints passam), então o
  direito do art. 18 VI está a salvo. A feature 016 traduz essa recusa numa frase que
  diz o que fazer (`profile_error_message.dart`).
- Proteções que já existiam e continuam: Apelido obrigatório abaixo de 18
  (`apelido_obrigatorio_menor`) e idade nunca exposta.
- **Retenção**: a anonimização de `excluir_minha_conta()` zera as quatro colunas do
  responsável junto com as da criança — sem isso o app teria excluído a conta da
  criança e guardado o nome e o telefone da mãe.
