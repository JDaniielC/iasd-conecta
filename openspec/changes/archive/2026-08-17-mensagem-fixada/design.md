## Context

Ver `proposal.md` — Why. O que vem pronto de `chat-de-grupo-e-acao`:

- `mensagens` com as três lápides derivadas de `texto` + `removida_em`, sem
  coluna de estado.
- Gatilho `before update` que só deixa passar alteração em `texto`,
  `removida_em` e `removida_por`. **Esta change precisa alterá-lo** — é o único
  ponto em que ela toca código daquela.
- `expurgar_mensagens_de_acao()`, chamada por `pg_cron` e pelo app.
- Policy de `update` restrita a autor + autoridade do espaço, com `with check`
  gêmeo do `using`.
- `excluir_conta` já esvazia `texto` do titular numa transação só.

## Goals / Non-Goals

**Goals:**
- A exceção ao prazo é explícita, limitada e reversível pelo autor.
- Nenhum caminho em que fixar amplie quem lê a mensagem.

**Non-Goals:**
- Fixar por participante comum. Ver spec.
- Ordenar as fixadas à mão. Ordem é a de fixação, mais recente primeiro.
- Fixar em chat de Grupo com efeito sobre prazo — Grupo não expira; lá fixar é
  só posição.
- Prazo próprio para fixada (fixar por 90 dias, por exemplo). Um segundo prazo
  a declarar na Política, para resolver um problema que desfixar já resolve.
- Notificar que algo foi fixado.

## Decisions

### Duas colunas em `mensagens`, não tabela separada

```
alter table public.mensagens
  add column fixada_em  timestamptz,
  add column fixada_por uuid references public.perfis(id);
```

Alternativa recusada: tabela `mensagens_fixadas`. A fixação é um atributo de
uma mensagem, sempre 0 ou 1 por linha, e o expurgo precisa dela no mesmo `where`
— com tabela separada, todo `delete` do expurgo vira `not exists`.

`fixada_por` referencia `perfis(id)`, como `removida_por`. Anonimização
propaga sozinha.

### O gatilho `before update` de `chat-de-grupo-e-acao` ganha duas colunas

Aquele gatilho recusa `update` que toque qualquer coluna fora de `texto`,
`removida_em`, `removida_por`. Sem alterá-lo, fixar é impossível.

A alteração é acrescentar `fixada_em` e `fixada_por` à lista permitida — e
**nada mais**. É o único ponto de contato desta change com aquela, e o motivo
de ela precisar entrar depois.

Alternativa recusada: uma função `security definer` que fixa por fora, sem
mexer no gatilho. Contornar a própria trava para não editá-la deixa duas
regras sobre a mesma tabela, e a segunda é invisível para quem lê a primeira.

### Teto de 3 por chat, verificado em gatilho sob trava

Três: cabe numa tela de celular como faixa recolhida, e força escolher. Número
escolhido, não medido; constante nomeada na migration.

`before update`, quando `fixada_em` passa de nulo a não nulo: trava a linha do
Grupo ou da Ação (`for update`), conta as fixadas daquele chat, recusa acima do
teto. A trava é no espaço, não no Perfil — ao contrário do limite de ritmo em
`filtro-e-intervalo-de-mensagem`, aqui o recurso disputado é do chat, e duas
pessoas com autoridade fixando ao mesmo tempo é exatamente o caso a serializar.

Alternativa recusada: `unique` parcial com número de posição. Obrigaria a
gerenciar posições livres e a renumerar ao desfixar.

### Desfixar tem policy mais larga que fixar

A policy de `update` de `mensagens` já cobre autor + autoridade do espaço. O
gatilho é que separa:

| Operação | Quem |
|---|---|
| `fixada_em` nulo → não nulo | autoridade do espaço |
| `fixada_em` não nulo → nulo | autoridade do espaço **ou** autor da mensagem |

Escrito no gatilho, não em duas policies, porque é a mesma coluna na mesma
operação — duas policies sobre o mesmo `update` se combinam por `or` e a mais
larga venceria as duas.

Por que o autor desfixa: fixar tira a mensagem do prazo de expiração. Sem esse
caminho, o prazo do que uma pessoa escreveu passaria a depender de outra
indefinidamente, e o direito de eliminação dela dependeria de pedir. Fixar de
volta continua sendo só da autoridade — senão o autor decidiria o que todo
mundo vê primeiro.

### O expurgo ganha `and fixada_em is null`

Uma condição a mais no `delete` de `expurgar_mensagens_de_acao()`. Nada mais
muda: o agendamento, o segundo gatilho no app e a saída-cedo-depois-de-consultar
continuam como estão.

Consequência: mensagem desfixada depois do prazo é apagada no expurgo seguinte,
sem carência nova. É o comportamento que a spec exige, e cai fora
naturalmente — não precisa de código.

### Lápide desfixa sozinha, no mesmo gatilho e na mesma transação

Quando `texto` passa a nulo — por remoção de moderação ou por `excluir_conta` —
o gatilho `before update` zera `fixada_em` e `fixada_por` na mesma linha.

Alternativa recusada: um segundo gatilho `after update`. Precisaria de um
`update` na mesma tabela que acabou de disparar o gatilho — recursão a
desarmar, para fazer numa segunda passada o que a primeira já podia fazer.

Para `excluir_conta`, isso significa que o passo existente (`update mensagens
set texto = null where autor_id = ...`) desfixa junto, sem linha nova naquela
função. A transação única continua única.

### Consulta: uma só, não duas

A tela pede as mensagens do chat uma vez e separa fixadas de não fixadas em
memória, em vez de fazer duas consultas. As fixadas são no máximo 3 e já vêm na
página mais recente na maioria dos casos — mas não sempre: uma fixada antiga
está fora da primeira página.

Então a consulta de histórico ganha um `union` com as fixadas daquele chat, ou
uma segunda consulta pequena e cacheada. Decidir na implementação medindo, não
antes; as duas satisfazem a spec, e o teto de 3 mantém qualquer das duas barata.

### Faixa recolhida por padrão

Três mensagens de 2000 caracteres expandidas ocupam mais que uma tela de
celular inteira. A faixa mostra a primeira linha de cada e expande sob toque.

O julgamento do layout é **na largura de celular**, não no desktop: é onde a
faixa compete com a conversa, e onde o desenho quebra primeiro.

## Risks / Trade-offs

**A promessa de 30 dias ganha exceção.** Depois desta change, "as mensagens da
Ação são apagadas em 30 dias" é falso sem ressalva. → A Política de Privacidade
passa a dizer o prazo **e** a exceção **e** o teto. É a classe de defeito que o
agente `promessa-vs-execucao` procura, e ele roda como tarefa desta change.

**Fixar é uma forma de conservar dado pessoal de terceiro indefinidamente.**
Quem tem autoridade fixa uma mensagem que cita alguém, e ela deixa de expirar.
→ Teto de 3 limita o volume; o autor desfixa a própria a qualquer momento; a
denúncia continua sendo o caminho para mensagem de terceiro. O que **não**
existe é caminho para a pessoa citada por outro desfixar — é o mesmo limite já
registrado em `chat-de-grupo-e-acao`, agora com efeito mais longo.

**Esta change edita um gatilho de outra change.** Se
`chat-de-grupo-e-acao` mudar antes de esta ser aplicada, a edição não casa. →
A tarefa manda reler o gatilho antes de escrever, e o teste que prova a lista
de colunas permitidas é o mesmo daquela change, estendido.

**Três é escolha sem medição.** → Constante nomeada num lugar só, conferida
entre Dart e migration por teste, como em `filtro-e-intervalo-de-mensagem`.

## Migration Plan

Aditiva: duas colunas anuláveis, alteração do gatilho existente, uma condição
no expurgo. Depende de `chat-de-grupo-e-acao` aplicada.

Rollback: `drop column` das duas, reverter o gatilho e o expurgo. **A reversão
apaga mensagem fixada de Ação já vencida** no primeiro expurgo seguinte — o que
estava protegido pela fixação deixa de estar. Não é reversão sem perda, e
precisa estar escrito no commit.
