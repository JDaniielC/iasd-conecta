# Research: Cadastro de Perfil e Upgrade para Conta

## Sessão anônima como Perfil

**Decision**: usar Supabase Anonymous Sign-in (`supabase.auth.signInAnonymously()`)
na primeira abertura do app, antes de qualquer tela de cadastro. O
`auth.uid()` gerado vira a chave primária de `public.perfis`.

**Rationale**: satisfaz FR-001 (sem e-mail/senha) e FR-007 (persistência entre
sessões no mesmo aparelho) usando exatamente o mecanismo que o Supabase já
persiste localmente (sessão salva via `supabase_flutter`, sobrevive fechar/abrir
o app). Não exige nenhuma tabela ou lógica de sessão própria.

**Alternatives considered**: gerar um UUID local sem nenhuma conta Supabase
(rejeitado — não teria como fazer upgrade pra Conta preservando histórico sem
reescrever `perfis.id`, e perderia RLS nativo por usuário); exigir e-mail
obrigatório desde o início (rejeitado por instrução explícita do usuário).

## Upgrade de Perfil para Conta

**Decision**: com a sessão anônima ativa, chamar
`supabase.auth.updateUser(UserAttributes(email: ..., password: ...))` (ou o
fluxo equivalente de telefone + OTP). O GoTrue do Supabase converte o usuário
anônimo em permanente **preservando o mesmo `auth.uid()`** — não há
migração de linha em `perfis`.

**Rationale**: é o mecanismo documentado do Supabase para exatamente esse caso
(anonymous → permanent), e cumpre a exigência explícita do usuário de manter o
mesmo user id no upgrade.

**Alternatives considered**: criar uma segunda tabela/linha `contas` separada
e vincular por FK (rejeitado — complexidade extra sem necessidade; "ter Conta"
vira só um booleano derivado de `auth.users.is_anonymous = false`, não uma
entidade nova).

## Idade nunca exposta: RLS + função pública, não só UI

**Decision**: RLS na tabela base `perfis` restringe `SELECT` ao próprio dono
(`auth.uid() = id`). Toda leitura pública (Grupo, Ação, listagens) passa por
uma função `SECURITY DEFINER` (`public.perfil_publico`) que devolve só
`id, nome_exibido, igreja_id` — nunca `idade`. Views comuns não bastam: no
Postgres uma view não contorna RLS da tabela base por si só (RLS é avaliada
pelo papel que consulta, não pelo dono da view); função `SECURITY DEFINER` é o
padrão correto e documentado pelo próprio Supabase para "leitura pública
controlada".

**Rationale**: cumpre o Princípio II (idade "nunca deve ser exibida", já
estrutural no banco, não dependente de nenhum client se comportar direito).

**Alternatives considered**: esconder `idade` só no client Flutter (rejeitado
— violaria a garantia "nunca", já que qualquer chamada direta à REST API do
Supabase exporia a coluna); view simples sem `SECURITY DEFINER` (rejeitado —
não contorna RLS, geraria erro ou resultado vazio para não-donos).

## Apelido obrigatório para menor: constraint de banco

**Decision**: `CHECK (idade >= 18 OR apelido IS NOT NULL)` na tabela `perfis`.

**Rationale**: Princípio IV exige teste automatizado pra essa regra; uma
constraint de banco é a forma mais forte de garanti-la — nenhum caminho de
código (app, script, admin) consegue violar sem passar pelo Postgres.

**Alternatives considered**: validar só no client (rejeitado — mais frágil,
não cobre acesso direto à API).

## Moderação de nome contra palavrões

**Decision**: tabela `public.palavras_bloqueadas(palavra text)` + função
`public.nome_valido(nome text) returns boolean` (normaliza case/acentos,
verifica substring) usada em `CHECK (public.nome_valido(nome))` na tabela
`perfis`. Client Flutter faz a mesma checagem client-side (contra uma cópia
local da lista, cacheada) só pra feedback instantâneo — o gate real é a
constraint de banco.

**Rationale**: defesa em profundidade sem duplicar fonte de verdade — lista
de palavras vive só no banco; client cacheia, não reimplementa moderação.

**Alternatives considered**: moderação só client-side (rejeitado — burlável
via chamada direta à API); serviço externo de moderação (rejeitado por
complexidade desnecessária nesta escala — Princípio V).

## Estado gerenciável e navegação em Flutter

**Decision**: `flutter_riverpod` para expor `PerfilAtual` (estado do Perfil
logado) e `go_router` para navegação declarativa com redirect baseado nesse
estado (ex.: força tela de Apelido se `idade < 18 && apelido == null`).

**Rationale**: Riverpod é testável sem `BuildContext` (facilita unit tests dos
FRs) e é o padrão mais comum hoje no ecossistema Flutter+Supabase. `go_router`
é o roteador declarativo oficialmente recomendado pelo time Flutter.

**Alternatives considered**: `Provider` puro (mais verboso pra este caso);
`Navigator` imperativo (dificulta redirect centralizado por estado de auth).

## Estética 7me

**Decision**: tema Material 3 customizado — `ColorScheme` com primária azul
marinho (`#1B2A4A`-ish, a confirmar com print de referência) sobre fundo
branco; tipografia sem serifa, pesos moderados (sem negrito exagerado);
componentes com `Card` de cantos suave-arredondados e espaçamento generoso
(mínimo 16px de padding); wordmark do app em uma fonte script leve só na tela
de splash/abertura, não repetida em cada tela interna (evita ruído).

**Rationale**: reproduz a linguagem visual do 7me (minimalista, azul+branco,
wordmark script como assinatura, não como elemento recorrente) sem copiar
assets proprietários — paleta e tipografia são interpretação, não cópia
pixel-a-pixel.

**Alternatives considered**: tema escuro por padrão (rejeitado — 7me é
claro/branco predominante); Material Design "cru" sem customização (rejeitado
— não atende ao pedido de estética consistente com o 7me).
