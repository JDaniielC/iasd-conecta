## Context

Ver `proposal.md` — Why. O que já está estabelecido e este design não pode
contrariar:

- **Visitante é `authenticated`.** `signInAnonymously` no arranque
  (`lib/core/supabase_client.dart`), e a falha dele **não derruba o app** — a
  Home é estática nesse caso, por decisão registrada nas linhas 41-51 do mesmo
  arquivo. `image_report_repository.dart:15-22` documenta o defeito medido que
  veio de confundir Visitante com ausência de sessão.
- **`privilegios-de-banco` já existe** e diz, na própria Purpose: *"o que `anon`
  e `authenticated` conseguem fazer **antes** de qualquer policy entrar em
  cena"*. O `execute` de função é esse mesmo piso; entra lá, não numa capability
  nova.
- **O teste-modelo existe.** `test/integration/chat_privilegio_funcao_test.dart`
  olha o **privilégio** (`has_function_privilege`) e não o resultado, e o
  comentário dele explica por quê: um teste que conferisse só "anon não lê
  mensagem" continuaria verde com a RPC aberta.
- **`unaccent*` é do `supabase_admin`**, veio com a extensão. Fora de escopo:
  mexer no ACL de função de extensão quebra a extensão.

## Goals / Non-Goals

**Goals:**
- Uma migration só, mecânica, sem tabela nem função nova.
- Um inventário que falhe por omissão futura, não uma lista de consertos.
- A distinção Visitante / sem-sessão escrita onde alguém a lerá antes de
  reverter.

**Non-Goals:**
- Mexer no que `authenticated` alcança. Esta change não estreita nada para quem
  tem sessão; fazer as duas juntas confundiria a causa de qualquer regressão.
- § 2.19 (envelope de Realtime a `anon`). Outra forma de prova, outra change.
- Trocar a chave publicável ou mexer em autenticação.

## Decisions

### O critério de fechamento: quem precisa disto sem sessão?

Uma tabela fica legível sem sessão apenas se o app precisar dela **no caminho
degradado** — arranque com `signInAnonymously` falhado. Nesse estado a Home é
estática, por decisão anterior.

A consequência é forte e é o ponto: **a superfície sem sessão pode ir a zero**.
Nenhuma tela do app depende dela, porque nenhuma tela do app roda sem sessão
exceto a Home estática, que não consulta nada.

Isto NÃO é o mesmo que fechar para Visitante, e a diferença é a change inteira.
As 13 policias hoje dizem `to anon, authenticated`; passam a dizer
`to authenticated`. O `using` de cada uma **não muda** — quem tem sessão
continua vendo exatamente o que via.

Alternativa recusada: **manter aberto o que a página pública mostra**
(`grupos`, `acoes`, `igrejas`, `categorias_grupo`, `fotos_capa`,
`versoes_texto_legal`). Foi a primeira leitura, e ela está errada pelo mesmo
motivo que a superfície cresceu: "página pública" no app é vista por Visitante,
que tem sessão. Manter essas seis abertas seria conservar a confusão que esta
change existe para desfazer, e deixar seis linhas com o motivo "achei que
precisava".

Alternativa recusada: **`revoke select ... from anon` no lugar de estreitar a
policy**. Fecharia igual e com menos linhas, mas o erro devolvido muda de
"zero linhas" para `42501 permission denied` — e `42501` diz que a tabela
existe. Estreitar a policy mantém a resposta indistinguível de "não há nada
aqui", que é o que os testes de oráculo desta base já cobram (ver
`SECURITY-AUDIT.md`, "Oráculo por forma de resposta"). **As duas juntas** é o
que se faz: `revoke` no `grant` de tabela também, mas só depois de a policy já
não alcançar `anon`, para que nenhum passo intermediário mude a forma da
resposta para quem tem sessão.

### O `revoke` das funções: cinco, não seis

Medido em 2026-08-16 — 6 funções `security definer` alcançáveis por `anon`, em
três situações diferentes, e a situação decide o conserto:

| Função | ACL medido | O que fazer |
|---|---|---|
| `autor_de_mudanca()` | sem ACL (herda PUBLIC) | `revoke` + `grant authenticated` |
| `nome_valido(text)` | sem ACL (herda PUBLIC) | `revoke` + `grant authenticated` |
| `versao_texto_legal_vigente()` | sem ACL (herda PUBLIC), `invoker` | `revoke` + `grant authenticated` |
| `declarar_lideranca(uuid,int)` | `=X` + `authenticated` | `revoke from public` |
| `decidir_lideranca(uuid,bool)` | `=X` + `authenticated` | `revoke from public` |
| `fechar_rodada_se_devido(uuid,bool)` | `=X` + `authenticated` | `revoke from public` |
| `perfil_publico(uuid)` | `anon=X` explícito | **fica** — pública por desenho |
| `acao_encerrada(...)`, `limiar_crianca()` | `anon=X` explícito, `invoker` | **ficam** |

O sinal genérico, já registrado em `SECURITY-AUDIT.md`: `proacl` com entrada
começando em `=` é o grant a `PUBLIC`; `proacl` nulo é o mesmo por omissão, e é
o caso mais fácil de não ver.

`fechar_rodada_se_devido` é a que mais dói: **escreve**, e o caminho de fechar
Rodada vencida não checa `auth.uid()`. O dano é limitado — o segundo gatilho do
app faria o mesmo —, mas escrita disparável sem autenticação não é o que a
migration dizia oferecer.

### O oráculo é da função, não da tabela

`nome_valido` é `security definer` porque precisa ler `palavras_bloqueadas`, que
tem RLS sem policy. Está certo assim: é o mesmo desenho de `maior_de_idade()` no
chat — `definer` para não depender de uma policy que pode apertar.

O que estava errado é **quem pode perguntar**. Com `execute` para `PUBLIC`,
`anon` sondava a lista termo a termo (medido: 5 palavras, 4 sondagens). O
conserto é o `revoke`, não trocar a função para `invoker` — como `invoker` ela
passaria a devolver "válido" para tudo, e a validação de nome sumiria em
silêncio, que é exatamente o modo de falha que `definer` foi escolhido para
eliminar.

Alternativa recusada: **fazer a função devolver a palavra casada em vez de um
booleano** (como `palavra_bloqueada_em` fará na change seguinte). Não muda nada
aqui: quem sonda já sabe o termo que perguntou. O oráculo é a permissão de
perguntar.

### O inventário: lista de exceções no teste, não no banco

Dois testes novos, no molde de `chat_privilegio_funcao_test.dart` — olhando o
privilégio e a policy, nunca o resultado de uma consulta.

1. **Funções**: enumera toda função de `public` com `prorettype <> trigger` e
   falha se `has_function_privilege('anon', ...)` for verdadeiro para alguma
   fora da lista de exceções.
2. **Policies**: enumera toda policy de `select` de `public` e falha se alguma
   endereçar `anon` (ou `PUBLIC`, que é `polroles = '{0}'`) fora da lista.

A lista de exceções mora **no arquivo de teste**, cada linha com o motivo ao
lado. Não numa tabela do banco e não num arquivo de configuração.

Alternativa recusada: **derivar a lista do banco** ("o que está aberto hoje é o
esperado"). É o teste que se escreve sozinho e nunca falha: ele grava o estado
atual como correto, inclusive o defeito. O ponto do inventário é a lista ser
escrita à mão por alguém que decidiu.

Alternativa recusada: **um `event trigger` no Postgres** recusando `create
function` sem `revoke`. Mais forte, e errado aqui: falharia no meio de uma
migration com uma mensagem que não explica nada, e `supabase db reset` passaria
a depender de ordem de criação. O teste falha no lugar onde se lê o motivo.

### `authenticated` também não devia poder truncar — e já não pode

A capability existente cobre isso desde `20260811120000`. Esta change não mexe
lá; só acrescenta a irmã sobre `execute`. Os dois cenários juntos são o piso
inteiro.

## Risks / Trade-offs

**Fechar demais e descobrir em produção.** O caminho degradado nunca foi
exercitado, e é justamente ele que passa a ser o único consumidor de `anon`. →
Tarefa própria: rodar o app com o `signInAnonymously` falhando de propósito, na
largura de celular, e confirmar que a Home aparece. Sem essa execução esta
change está provada só contra o banco, e a metade que importa é a tela.

**Alguém reverter por ler `visibilidade-de-acao`.** Aquela capability diz "Ação
é pública — todo mundo, inclusive sem login", e "sem login" ali é Visitante. →
Por isso a distinção virou requirement própria em `superficie-sem-login`, e não
comentário de migration. Comentário de migration não aparece quando a pessoa lê
a spec.

**A lista de exceções vira carimbo.** Daqui a um ano alguém acrescenta uma linha
para o teste passar, sem decidir nada. → Mitigação parcial e honesta: o teste
exige o motivo no mesmo lugar, e revisão de diff numa lista de sete linhas é
barata. Não há como impedir por código que alguém escreva um motivo ruim.

**`fechar_rodada_se_devido` deixa de ser chamável sem sessão, e algo externo
pode depender disso.** → Medido: não há chamador externo conhecido, e o app
chama com sessão. Se houver um cron externo não documentado, ele quebra — e
quebrar alto é melhor que continuar aberto.

## Migration Plan

Ordem: migration → testes de inventário → execução manual do caminho degradado
→ build web. A migration é reversível sem perda: `grant execute ... to public`
e `alter policy ... to anon, authenticated` devolvem o estado anterior, e
nenhum dado é tocado.

Produção não exige passo à mão: não há `pg_cron` novo nem configuração fora do
repositório.

## Open Questions

Nenhuma. As três que existiam — quais tabelas fechar, se `revoke` ou policy, e
onde mora a lista de exceções — foram decididas acima com a medição de
2026-08-16 na mão.
