## Context

Ver `proposal.md` — Why. O que já existe e este design reusa:

- **`asUser(conn, uid, action)`** (`test/integration/acao_restrita_helper.dart`)
  já faz o certo: `set role authenticated` + `request.jwt.claims` com o `sub`.
  Um Visitante é isto com um `uid` que não tem linha em `perfis`.
- **`createTestUser`** (`db_test_helper.dart`) cria `auth.users` mínimo, sem
  `perfis`. Falta só o `is_anonymous = true`.
- **`createTestProfileWithoutAccount`** é outra coisa: Perfil **sem Conta** —
  tem `perfis`, `is_anonymous = true`. Não confundir; é o Usuário que nunca fez
  upgrade, não o Visitante.
- **`is_anonymous` é lido de verdade** por `declarar_lideranca`
  (`20260724100000:27`), pelo gatilho de Administrador (`20260724092132:31`) e
  pelo convite (`20260813140000:66`). Um Visitante de teste com
  `is_anonymous = false` passaria em regra que o Visitante real não passa.

## Goals / Non-Goals

**Goals:**
- Cada asserção provando o que o nome dela diz.
- Uma definição por papel, compartilhada.
- Suíte verde no fim, sem tocar em `lib/` nem em migration.

**Non-Goals:**
- Fechar `anon`. É a change seguinte, e misturar as duas é o motivo de esta
  existir.
- Consertar defeito de produção que apareça. Se aparecer, vira registro em
  `PENDENCIAS.md` com a medição — conserto é change própria.
- Uniformizar o resto da suíte. Só os pontos que confundem Visitante com
  ausência de sessão.

## Decisions

### `asVisitor` muda de significado em vez de ganhar um irmão

O nome certo para "pessoa sem cadastro" é `asVisitor`, e é o nome que 21
arquivos já usam. Trocá-lo por `asAuthenticatedWithoutProfile` deixaria o nome
bom para o conceito errado — quem escrevesse um teste novo continuaria
alcançando `asVisitor` esperando o que o nome promete.

Então **`asVisitor` passa a ser o que o nome sempre disse**, e a semântica
antiga ganha nome próprio: **`asAnon`**, que diz exatamente o que faz e não
soa como categoria de pessoa.

Consequência aceita: o diff não mostra a mudança de significado nos pontos que
continuam chamando `asVisitor`. Um `git log -S` não acha o que mudou ali. Por
isso a varredura é ponto a ponto e registrada na `tasks.md`, e por isso a
requirement entra na spec — o próximo a ler precisa achar a distinção sem
depender do diff.

Alternativa recusada: **manter `asVisitor` como está e criar
`asRealVisitor`**. Menos churn e mais errado: deixa a armadilha armada com o
nome mais atraente, que é o modo de falha desta base — a regra que falha em
silêncio porque o nome errado é o mais fácil de alcançar.

### O Visitante de teste é `auth.users` anônimo sem `perfis`

`createTestVisitor(conn, id)`: insere em `auth.users` com
`is_anonymous = true` e **não** toca em `perfis`.

`is_anonymous = true` não é enfeite — três funções do banco leem essa coluna
para decidir. Um Visitante de teste com `false` seria um Usuário com Conta sem
Perfil, que não existe no app e passaria em regra que o Visitante real não
passa.

Alternativa recusada: **reusar `createTestUser` e aceitar
`is_anonymous = false`**. Mais barato e falso pelos três lugares acima.

### Os 39 pontos se classificam por PERGUNTA, não por arquivo

Para cada ponto, a pergunta é: *este teste existe para provar o que a pessoa
sem cadastro vê, ou para provar o que uma requisição sem credencial alcança?*

A resposta está no nome do teste e no comentário ao lado, e os dois grupos já
aparecem hoje:

| Sinal | Vira |
|---|---|
| "Visitante", "sem cadastro", "vê / não vê" | `asVisitor` |
| "anon", "sem sessão", "sem token", "privilégio", "grant" | `asAnon` |

Casos que precisam dos **dois**, e são os que valem mais: onde o teste hoje faz
uma afirmação só, ele passa a fazer duas — o Visitante vê, e sem sessão não
alcança. `chat_corte_de_idade_test` é o exemplo, e o comentário dele já
raciocina sobre o `revoke ... from public` das funções do chat.

Alternativa recusada: **substituir todos por `asVisitor` e ver o que quebra**.
Apagaria a cobertura de `anon` que existe de propósito —
`chat_privilegio_funcao_test` e `notificacao_anon_test` provam a superfície sem
sessão, e são justamente o modelo que a change seguinte reusa.

### O que fazer com um vermelho que aparecer

Passar a exercer a policy de verdade pode revelar que ela não faz o que o teste
afirmava. Três desfechos, nesta ordem de preferência:

1. **O teste estava errado** — conserta-se o teste, com a medição no comentário.
2. **O teste estava certo e a policy não** — registra-se em `PENDENCIAS.md` com
   número medido, e o conserto é change própria. Esta change não muda banco.
3. **Nem um nem outro** — a change para e o design volta à mesa.

Escrito aqui porque a tentação, no meio da varredura, é ajustar a asserção até
ficar verde. Ajustar a asserção é o desfecho 1 sem a parte de ter medido.

## Risks / Trade-offs

**A varredura vira substituição mecânica.** 39 pontos cansam, e `sed` resolve
em um comando. → A `tasks.md` quebra a varredura por arquivo, e cada tarefa
pede a classificação escrita. Um arquivo por vez também mantém o `git bisect`
útil se algo quebrar depois.

**Um teste que passa a exercer a policy pode ficar intermitente.** Sob `anon`
muita coisa parava cedo; sob `authenticated` a asserção passa a depender de
estado que outro arquivo pode tocar. → A capability `suite-de-integracao` já
cobre determinismo, e o gate é a suíte inteira rodando limpa, não o arquivo
isolado. Qualquer intermitência nova é achado desta change.

**`is_anonymous = true` pode barrar um teste que hoje passa.** Três funções
leem a coluna. → É o ponto: se barrar, o teste estava passando por ser um
Usuário que o app não produz.

## Migration Plan

Não há migration. A ordem é: helper primeiro, depois um arquivo por vez, com a
suíte inteira rodando ao fim de cada um. Reverter é `git revert` de um commit
de teste — nenhum dado, nenhum schema.

Depois desta, retomar `change/fechar-superficie-anon`, que está parada com as
duas migrations já escritas e verificadas.
