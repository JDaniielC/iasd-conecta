## Why

Toda Ação deste app é pública para o mundo. `acoes_select_public` é
`to anon, authenticated using (true)`
(`supabase/migrations/20260723230639_acoes.sql:121-124`), e `acoes` já tem
`grupo_id` desde a feature 004
(`20260724084300_rodada_votacao.sql:13-16`) — a coluna que diz de quem a Ação é
existe, mas não filtra nada. Uma reunião de liderança, uma visita de Dupla
Missionária com `genero_visitado` marcado, um encontro interno de um Ministério:
tudo aparece igual para qualquer pessoa que abra `/acoes`, inclusive sem login.

Isso é o oposto do que a liderança precisa. Quando um Grupo marca algo dele, o
"tudo mundo vê" não é neutro: expõe agenda interna e enche o feed público de
Ação que não interessa a quem não é do Grupo.

Esta change dá ao criador de uma Ação de Grupo a escolha de fechá-la ao Grupo:
quem não participa não vê. É a metade de privacidade do pedido original;
convidar pessoas é a change `convite-para-acao`, separada porque não tira
visibilidade de ninguém e pode entrar antes ou depois desta, em qualquer ordem.

## What Changes

- **Ação de Grupo passa a poder ser restrita ao Grupo.** Coluna nova em `acoes`
  marcando a restrição. Ação sem `grupo_id` (avulsa) **não pode** ser restrita —
  não há a quem restringir; o banco recusa a combinação por `check`.
  Ação de Grupo aqui quer dizer candidata de Rodada e a Ação que vence a Rodada:
  são a mesma linha de `acoes`, e é a única forma de uma Ação ter Grupo.
- **A restrição vive na policy, não na tela.** `acoes_select_public` é
  substituída por uma policy que esconde a Ação restrita de quem não participa
  do Grupo. A tela filtrar não é garantia: o REST do Supabase é público e
  qualquer pessoa consegue chamar `/rest/v1/acoes` direto.
- **O padrão continua sendo público.** Toda Ação que já existe permanece
  visível, e Ação nova nasce pública a menos que quem cria marque o contrário.
  Nenhuma Ação some do feed de ninguém no dia da migration. **Não é BREAKING.**
- **A restrição alcança tudo que revela a Ação**, não só a linha de `acoes`:
  `confirmacoes_acao_select_public` é `using (true)`
  (`20260723230639_acoes.sql:136-139`) e devolve a lista de quem vai. Esconder
  a Ação e deixar a lista de presença aberta é vazamento por porta lateral.
- **Rodada de votação e Ação candidata** (`rodadas_votacao`, `acoes` com
  `rodada_id`) entram na conta: uma candidata restrita não pode reaparecer pela
  tela de rodada.
- **Quem restringe**: quem já pode editar a Ação —
  criador, Dono do Grupo, Administrador do distrito
  (`acoes_update_criador_dono_grupo_ou_admin`). A restrição não ganha regra de
  escrita própria. Ser Líder confirmado (`liderancas.confirmado_em`) **não** é
  exigido — amarrar em liderança quebraria o caso do participante comum que
  marca algo interno do Grupo. Decisão e a dívida que ela aceita estão no
  design.
- **Grupo arquivado**: efeito definido sobre Ação restrita, junto do que
  `20260809230000_arquivar_grupo.sql` já faz.

## Capabilities

### New Capabilities
- `visibilidade-de-acao`: quem vê uma Ação, quando uma Ação pode ser restrita
  ao Grupo, quem pode restringi-la, e o que a restrição alcança além da própria
  Ação (presenças, contagem, rodada de votação, destaque, busca).

### Modified Capabilities
Nenhuma das quatro capabilities de `openspec/specs/` muda de requisito.
`privilegios-de-banco` fala do piso de `grant`, que esta change não toca — ela
mexe em policy, que é a camada de cima.

## Impact

**Banco** — uma migration: coluna nova em `acoes` com `check` amarrando-a a
`grupo_id`, substituição de `acoes_select_public` e de
`confirmacoes_acao_select_public`, e um índice que sustente o `exists` de
participação sem varrer `participacoes_grupo` a cada linha do feed.

**Exposição** — esta change **só fecha**, nunca abre. Mas o risco real é o
inverso do usual: uma policy escrita errado esconde Ação pública de todo mundo,
ou deixa a restrita à mostra. Os dois lados precisam de teste de integração
contra o banco de verdade, com sessão de quem participa e de quem não participa,
mais uma sessão `anon`. Teste de widget não prova RLS.

**Performance** — `acoes_select_public` hoje é `using (true)`, o plano mais
barato que existe. Trocar por um `exists` sobre `participacoes_grupo` roda em
toda leitura de `/acoes`, que é a tela mais aberta do app. Medir antes de
fechar.

**Interação com changes em voo** —
`destaque-de-acoes-distritais-e-de-grupo` decide o que entra na faixa de
destaque de `/acoes`. As duas se encontram: Ação restrita não pode aparecer no
destaque de quem não participa. Como a policy filtra na origem, o destaque
herda o filtro sem código novo — mas isso é afirmação a verificar em teste, não
a assumir.

**Código** — `create_candidate_page.dart` ganha o controle de restrição.
`create_action_page.dart` **não** ganha: naquela tela toda Ação é avulsa, e
Ação de Grupo neste app só nasce como candidata de Rodada
(`acoes_candidata_checar_regras`). `action_detail_page.dart` mostra que a Ação
é restrita e deixa mudar. O repositório de Ação não precisa filtrar nada: o
banco já não devolve.

**Ledger** — `MAPA-DE-DADOS.md` e `SECURITY-AUDIT.md` (mudança de policy de
leitura em tabela com dado pessoal, com data e números do teste; mais a dívida
aceita de o Administrador do distrito conseguir reabrir toda Ação restrita numa
escrita sem filtro).
