## Context

Ver `proposal.md` — Why. O que vem pronto:

- `denuncias_mensagem` com `motivo`, `denunciante_id` (not null), `estado` em
  quatro valores, `created_at`, `resolvida_em`, e `mensagem_id` com
  `on delete set null` — deliberado, para a denúncia não sumir com o expurgo.
- Três policies (insert/select/update) e `grant select, insert, update` **na
  tabela inteira**.
- `denuncias_mensagem_filtro_de_palavra_trigger`, `before insert` e `before
  update` do `motivo` (`20260817140000`).
- `mensagens_so_remove` como molde do que falta aqui.
- `excluir_minha_conta`, que já esvazia o texto das mensagens do titular numa
  transação só.

## Goals / Non-Goals

**Goals:**
- O que os Termos prometem sobre o motivo passa a ser verdade.
- A denúncia deixa de ser dado imortal sem que o desfecho se perca.

**Non-Goals:**
- **Limite de ritmo em denúncia.** Recusado, e a recusa fica escrita na spec
  para não virar decisão por inércia: um limite por tempo atrapalha quem
  denuncia abuso em série.
- Revelar a quem lê quem denunciou. Continua fora.
- Mudar quem resolve denúncia. `pode_moderar_espaco` continua sendo o
  predicado, sem o autor.
- Editar denúncia antiga para corrigir erro de digitação. Registro é registro;
  quem errou denuncia de novo depois do desfecho.

## Decisions

### Gatilho, e não recorte de `grant`

`denuncias_mensagem` precisa continuar aceitando `update` de `estado` e
`resolvida_em`. As duas formas de conseguir isso:

| | Recorte de `grant` por coluna | Gatilho `before update` |
|---|---|---|
| Recusa | `42501 permission denied for table` | mensagem que diz o que aconteceu |
| Precedente | `20260811160000`, `20260817120000` | `mensagens_so_remove` |

**Gatilho**, e o motivo é o mesmo que `20260817120000` registrou ao NÃO
recortar o `update` de `mensagens`: aqui o gatilho cobre exatamente as mesmas
colunas e devolve uma frase legível, enquanto o `grant` devolveria um
`permission denied` genérico sem ganhar barreira nenhuma.

O gatilho nasce no molde de `mensagens_so_remove`: compara coluna a coluna com
`is distinct from` e recusa com frase própria.

**`security invoker`**, ao contrário de `mensagens_so_remove`: aqui não há
contagem a fazer, e nada no corpo depende de enxergar linha que a RLS esconde.
Privilégio que não é necessário não se pede.

### Índice único parcial sobre `estado = 'pendente'`

```
create unique index ... on public.denuncias_mensagem (mensagem_id, denunciante_id)
  where estado = 'pendente';
```

Parcial é o ponto: fora de `pendente`, repetir é legítimo — fato novo depois de
um julgamento é outro caso, e a spec diz isso.

`mensagem_id` é anulável (`on delete set null`), e no Postgres nulo não colide
com nulo em índice único. Consequência aceita: depois do expurgo da mensagem, a
mesma pessoa poderia registrar outra pendente órfã — mas não há tela que
denuncie mensagem que não existe, então o caminho não é alcançável pelo app.
Escrito aqui para quem for endurecer isso não descobrir sozinho.

Alternativa recusada: `check` com subconsulta. `check` não pode consultar outra
linha, e um gatilho que conta abriria a mesma corrida que o índice fecha de
graça.

### O prazo conta do DESFECHO, não da criação

Pendente não expira — é a razão de `on delete set null` existir. Contar da
criação apagaria o motivo de uma denúncia que ninguém julgou, que é exatamente
o resultado que aquela decisão evitou.

Contar do desfecho tem um efeito que precisa ser dito: **denúncia esquecida
sem julgar fica para sempre.** É o incentivo certo — o que resolve isso é
julgar, não apagar.

O executor segue o molde de `expurgar_mensagens_de_acao`: função
`security definer`, `pg_cron`, **e** um segundo gatilho no app, porque no plano
gratuito o projeto pausa por inatividade e o cron para junto. Uma promessa de
prazo com um executor só não é promessa — foi a lição de
`chat-de-grupo-e-acao`, e ela vale aqui igual.

**Qual prazo é decisão aberta**, e ela é do dono do app. O que a change
recomenda: o mesmo que a Política já usa noutro lugar, para a titular não ter
de aprender um segundo número. A tarefa manda escolher antes de escrever a
migration, e o número escolhido é constante nomeada.

### O motivo sai na exclusão de conta, pela linha que já existe

`excluir_minha_conta` já esvazia o texto das mensagens do titular. Uma linha ao
lado, na mesma transação, esvazia o `motivo` das denúncias em que ele é o
`denunciante_id`.

`denunciante_id` NÃO é anulado: ele aponta para `perfis`, e a anonimização do
Perfil já tira o nome. Anular a coluna transformaria a denúncia em órfã e
quebraria o índice único parcial acima.

### `denuncias_imagem` ganha o `btrim` da irmã mais nova

Uma linha, e a razão está medida em `chat-de-grupo-e-acao`:
`length(trim(E'\n\t '))` é 2 e `length(btrim(E'\n\t ', E' \t\n\r'))` é 0. Um
motivo de quebras de linha passa hoje como se dissesse alguma coisa.

Entra aqui, e não numa change própria, porque é a mesma promessa — motivo é
registro — na tabela vizinha, e separá-la deixaria duas regras de "motivo
vazio" convivendo por mais um ciclo.

## Risks / Trade-offs

**Apagar o motivo apaga o porquê da remoção.** É o trade-off central, e não tem
saída elegante: conservar o texto para explicar a decisão é conservar o texto
que a pessoa escreveu, indefinidamente, sobre algo que outra pessoa disse. →
O desfecho e o instante permanecem; o texto, não. Mesma escolha da remoção de
mensagem, e ela precisa estar na Política.

**BREAKING para escrita direta na API.** `update` de `motivo` ou
`denunciante_id` passa a ser recusado. → Medido: nenhuma tela do app faz isso —
`ChatRepository.resolveReport` manda `estado` e `resolvida_em`. A tarefa manda
conferir de novo antes de escrever a migration.

**O índice único pode recusar uma denúncia legítima** se a anterior ficou
pendente para sempre. → É o mesmo incentivo de julgar, e a tela precisa dizer
"já está aguardando desfecho" em vez de devolver erro cru.

**Prazo novo na Política.** → Sobe a versão do texto legal, pelo critério da
1.6 e da 1.7.

## Migration Plan

Aditiva, exceto pela recusa nova: gatilho, índice único parcial, função de
expurgo com agendamento, uma linha em `excluir_minha_conta`, `check` de
`denuncias_imagem` refeito.

O `check` de `denuncias_imagem` é o único passo que pode **falhar na subida**,
se já houver linha cujo motivo só tenha quebras de linha. A tarefa manda contar
antes, e decidir o que fazer com o que existir — não `not valid` em silêncio.

Rollback: `drop` do gatilho, do índice e da função; reverter o `check`. **A
reversão não devolve motivo já apagado pelo prazo** — e isso precisa estar
escrito no commit.
