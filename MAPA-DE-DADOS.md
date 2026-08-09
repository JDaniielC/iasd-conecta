# Mapa de dados — Rede IASD Vitória de Santo Antão

Levantado direto do código para escrever a Política de Privacidade e os
Termos de Uso (`lib/features/legal/`). Serve também de rascunho do registro
de operações de tratamento (ROPA, LGPD art. 37). Toda linha tem
`arquivo:linha` — sem isso, não é mapa, é palpite.

## Dados coletados (tabela `public.perfis`)

`supabase/migrations/20260723191202_perfis_igrejas.sql:28-39`

| Campo | Obrigatório | Onde é lido/exibido | Nunca exposto a outros? |
|---|---|---|---|
| `nome` | sim | moderado por `nome_valido()` (linha 16-26); exibido publicamente via `perfil_publico` | não — é o nome de exibição |
| `apelido` | só se `idade < 18` (constraint `apelido_obrigatorio_menor`, linha 38) | substitui `nome` em `perfil_publico` quando presente (`perfis_igrejas.sql:48`) | não — é o substituto público do nome de menor |
| `igreja_id` | não | exibido via `perfil_publico` (linha 48); usado para destaque em Grupo/Ação | não |
| `telefone` | não | só `criarPerfil`/`toInsertMap` grava (`perfil.dart:49`); nenhum outro código lê ou exibe | sim, hoje ninguém lê |
| `genero` | sim, só `masculino`/`feminino` (check, linha 34) | usado server-side por `confirmacoes_acao_decidir_status()` (`dupla_missionaria.sql:63-77`) pra validar composição de Dupla Missionária | sim — nunca sai em `perfil_publico`, RLS restringe select da tabela base ao próprio dono (`perfis_select_own`) |
| `idade` | sim (`>= 0`) | só decide `apelido_obrigatorio_menor` no banco e `menorDeIdade`/`precisaDeApelido` no client (`perfil.dart:34-36`) | sim — confirmado em `perfil.dart:57-58` e no comentário de `perfil_repository.dart:11` |
| `consentimento_lgpd_aceito_em` | sim (`not null`) | gravado em `perfil.dart:52` com `DateTime.now().toUtc()` no momento do envio | não se aplica |

**Não coletado**: CPF, endereço, foto/avatar, dado de saúde, dado de pagamento
(nenhuma ocorrência de `foto`/`avatar`/`imagem` em `lib/` ou
`supabase/migrations/`, confirmado por grep).

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

As policies abaixo concedem `select` a `anon, authenticated` com
`using (true)` — ou seja, **visível até para quem nunca fez cadastro**,
via API direta, independente do que a tela de fato renderiza. A exceção é
`votos`, fechada pela feature 021 e mantida na tabela justamente para
registrar que ela já esteve aberta:

| Tabela | Policy | Arquivo:linha |
|---|---|---|
| `perfis` (só via RPC `perfil_publico`, nunca `select` direto) | `perfil_publico(uuid)` retorna `id, nome_exibido, igreja_id` — nunca `idade`/`telefone`/`genero` | `20260723191202_perfis_igrejas.sql:41-53` |
| `participacoes_grupo` | `participacoes_grupo_select_public` | `20260723220703_grupos.sql:121-124` |
| `acoes` | `acoes_select_public` | `20260723230639_acoes.sql:121-124` |
| `confirmacoes_acao` | `confirmacoes_acao_select_public` | `20260723230639_acoes.sql:136-139` |
| `rodadas_votacao` | `rodadas_votacao_select_public` | `20260724084300_rodada_votacao.sql:197-200` |
| `votos` | **não é público desde a feature 021** — `votos_select_own` devolve só a linha da própria pessoa (`auth.uid() = usuario_id`), e `anon` fica sem policy de `select`, portanto recebe lista vazia. A apuração conta todos os votos por fora da RLS, em `fechar_rodada_se_devido` (`security definer`) | `20260809200000_votos_visibilidade.sql:41-44` |
| `administradores_distrito` | `administradores_distrito_select_public` | `20260724092132_district_admin.sql:52-55` |
| `liderancas` | `liderancas_select_public` — **sem filtro por `confirmado_em`**: declaração pendente/rejeitada também é publicamente selecionável, não só a confirmada | `20260724100000_leadership.sql:73-76` |

A UI de `detalhe_grupo_page.dart:118-119` só *renderiza* Líder/Diretor
confirmado (via `currentLeadersProvider`), mas a RLS acima permite ler a
tabela inteira — a política de privacidade descreve o nível de acesso real
(RLS), não só o que a tela de hoje mostra.

## Terceiros

- **Supabase** — hospeda Postgres + Auth + API. `lib/core/supabase_client.dart:14-17`
  lê `SUPABASE_URL`/`SUPABASE_PUBLISHABLE_KEY` do `.env`; hoje só existe
  configuração para **ambiente local** (`http://127.0.0.1:54321`,
  `.env.example:1`, `supabase/config.toml`). **Nenhuma configuração de
  produção (região do projeto Supabase Cloud, ou self-host) existe no
  repositório.** Sem isso, a política não pode declarar transferência
  internacional com precisão — ver achado A-3.
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

- Um único campo, `consentimento_lgpd_aceito_em` (timestamp), sem coluna de
  versão do texto aceito — `20260723191202_perfis_igrejas.sql:36`. Se o texto
  da política mudar, não há como saber qual versão uma pessoa aceitou. Ver
  achado A-5 e `lib/features/legal/legal_metadata.dart`.
- Antes desta tarefa, o único texto apresentado no aceite era o rótulo do
  checkbox ("Aceito o uso dos meus dados (LGPD)") — sem link pra nenhum
  documento. Corrigido nesta entrega (link pra `/privacidade` e `/termos`
  antes do checkbox, `cadastro_perfil_page.dart`), mas isso não resolve
  retroativamente quem já tinha aceitado a versão anterior (não há
  usuários reais em produção ainda, pelo que o código local indica).

## Crianças e adolescentes

- Idade mínima não é imposta em lugar nenhum: `idade integer not null check (idade >= 0)`
  (`20260723191202_perfis_igrejas.sql:35`) aceita qualquer idade a partir de 0.
- `CATEGORIAS-DE-ACAO.md:6-18` confirma público infantil ativo: Desbravadores
  (10-15), Aventureiros (6-9).
- Proteção existente: Apelido obrigatório abaixo de 18
  (`apelido_obrigatorio_menor`) e idade nunca exposta. **Não existe**
  nenhum mecanismo de consentimento parental/responsável — nem campo, nem
  tela, nem verificação. Ver achado A-1 (o mais crítico deste levantamento).
