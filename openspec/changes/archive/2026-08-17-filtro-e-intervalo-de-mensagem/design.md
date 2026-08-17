## Context

Ver `proposal.md` — Why. Restrições que vêm do que já existe:

- **`nome_valido()` casa por trecho e é `security definer`**
  (`20260806090000:31-41`). A escolha de `definer` lá foi para sobreviver a
  RLS na tabela da lista; o comentário da migration (`:7`) diz por quê: sem
  isso a moderação sumiria "sem nenhum erro no app e sem nenhum teste
  vermelho".
- **`palavras_bloqueadas` não é legível por `anon`/`authenticated`** desde
  aquela mesma migration. A lista de conversa herda essa postura.
- **`confirmacoes_acao_decidir_status()` já resolve concorrência com
  `for update`** (`20260723230639:35`). O limite de ritmo tem o mesmo problema
  e usa a mesma solução.
- **`chat-de-grupo-e-acao` já tem um gatilho `before update` em `mensagens`**
  que restringe quais colunas mudam. O filtro e o ritmo entram como
  `before insert`, ao lado, sem tocar naquele.

## Goals / Non-Goals

**Goals:**
- Recusa na escrita, nunca na exibição — o canal de tempo real entrega antes de
  qualquer filtro de tela poder agir.
- Limite que vale contra a API, não só contra a tela.
- Zero dado novo sobre comportamento de pessoa.

**Non-Goals:**
- Detecção por contexto, ironia, sigla ou grafia criativa. Lista de palavra
  inteira pega o caso óbvio; o resto é denúncia.
- Limite global por pessoa somando todos os chats. Ver spec.
- Bloqueio ou silenciamento de pessoa. Quem passa do ritmo espera; não é
  punido, não entra em lista.
- Interface de administração da lista. Ela se edita fora do app, como a de
  nomes.
- Aplicar o filtro retroativamente ao que já foi escrito.

## Decisions

### Tabela própria, `palavras_bloqueadas_mensagem`

Mesmo formato de `palavras_bloqueadas` (uma coluna, a palavra como chave
primária), RLS ligada e sem policy nenhuma.

Alternativa recusada: uma coluna `escopo` em `palavras_bloqueadas`. Além de
alterar tabela que hoje sustenta um `check` de `perfis`, a regra de casamento é
**diferente** entre os dois usos — trecho para nome, palavra inteira para
conversa. Duas regras sobre uma tabela é onde a próxima pessoa erra qual das
duas está aplicando.

### `mensagem_valida(texto)` devolve a palavra, não um booleano

```sql
create function public.palavra_bloqueada_em(p_texto text) returns text
language sql stable security definer set search_path = public, extensions, pg_temp
as $$
  select b.palavra from public.palavras_bloqueadas_mensagem b
  where unaccent(lower(p_texto)) ~ ('\y' || unaccent(lower(b.palavra)) || '\y')
  limit 1;
$$;
```

Devolve `null` quando está limpo. O gatilho levanta exceção com a palavra na
mensagem de erro, e o cliente a mostra.

`security definer` com `search_path` fixo pelo motivo já escrito em
`20260806090000` — `extensions` na lista porque `unaccent` pode morar em
`public` ou em `extensions` conforme a extensão foi criada.

`\y` é a fronteira de palavra do Postgres. `~` (regex) em vez de `like`: é
exatamente a diferença que separa esta lista da de nomes. Custo: regex não usa
índice — mas a lista é de dezenas de palavras num distrito, e a alternativa
(`to_tsvector`) traria dicionário e stemming, que decidem sozinhos coisas que
esta lista precisa decidir explicitamente.

Devolver a palavra em vez de um booleano é o que permite a recusa ser
corrigível. Não vaza a lista: só sai palavra que já estava no texto enviado.

### Recusa é exceção no gatilho, não `check constraint`

Um `check (palavra_bloqueada_em(texto) is null)` seria mais declarativo, mas a
mensagem de erro de um `check` violado não carrega qual palavra casou — só o
nome da constraint. E `check` não pode chamar função `security definer` de
forma confiável em restauração de dump.

Gatilho `before insert` em `mensagens` e em `denuncias_mensagem`, levantando
exceção com código distinto por causa (filtro, intervalo, teto) para o cliente
diferenciar sem interpretar texto de erro.

### Ritmo: mesmo gatilho, consulta sobre `mensagens`, sob trava

```
intervalo mínimo:  3 segundos entre mensagens da mesma pessoa no mesmo chat
teto por janela:  20 mensagens por 5 minutos, mesma pessoa, mesmo chat
```

Números escolhidos, não medidos. Três segundos não atrapalha conversa real e
transforma "encher o chat" em trabalho manual longo; 20 em 5 minutos é acima do
ritmo de qualquer conversa de combinação observável neste app. Ficam como
constante nomeada na migration, com comentário dizendo que são escolha e não
medição.

A consulta é `max(created_at)` e `count(*)` sobre `mensagens` filtrado por
autor e por chat — os índices de
`(grupo_id, created_at desc)` / `(acao_id, created_at desc)` que
`chat-de-grupo-e-acao` cria já servem, mas a filtragem por autor pede um índice
próprio `(autor_id, created_at desc)`.

**Trava:** `perform 1 from public.perfis where id = auth.uid() for update` no
início do gatilho. Sem ela, duas escritas simultâneas leem o mesmo
`max(created_at)` e passam as duas. É o mesmo recurso que
`confirmacoes_acao_decidir_status` usa para o limite de vagas
(`20260723230639:35`), pelo mesmo motivo.

Alternativa recusada: trava na linha do Grupo ou da Ação. Serializaria o chat
inteiro por causa do limite de uma pessoa; travando o Perfil, só as escritas
daquela pessoa se serializam — que é exatamente o conjunto que o limite mede.

### Nada é gravado sobre a tentativa recusada

Sem tabela de tentativa, sem contador, sem log. A contagem sai do
`created_at` das mensagens que existem.

Alternativa recusada: uma tabela de eventos de recusa, para ver quem está
tentando. É dado de comportamento — quando esta pessoa tentou falar e quantas
vezes — e o projeto já escreveu por que não cria isso por conveniência
(`news_repository.dart:7-16`).

Consequência aceita e registrada na spec: quando as mensagens de uma Ação
expiram, o limite daquele chat zera. Chat expirado não é chat que se possa
encher.

### O cliente conhece os números, o banco decide

A tela mostra contagem regressiva e desabilita o envio — para isso precisa dos
números. Eles ficam como constante no Dart, e um teste de integração confere
que batem com os da migration. Se divergirem, a tela libera o envio antes e a
pessoa recebe erro do servidor.

Alternativa recusada: expor os números por uma função no banco. Uma consulta a
mais em toda abertura de chat para ler dois inteiros que mudam quase nunca.

## Risks / Trade-offs

**Falso negativo é o caso comum.** Lista de palavra inteira não pega grafia
alterada, espaçamento no meio, nem o insulto construído sem palavrão. → É o
limite assumido: o filtro reduz o volume óbvio; a denúncia continua sendo o
caminho para o resto. Prometer mais nos Termos de Uso seria promessa que o
código não cumpre.

**Falso positivo continua possível, e agora com nome.** Palavra inteira reduz
muito, mas uma palavra ambígua na lista recusa uso legítimo. → A recusa diz
qual palavra foi, então a pessoa entende e o dono do Grupo sabe o que pedir
para tirar da lista. Falso positivo sem nome era o desenho que esta change
recusou.

**Três segundos é escolha sem medição.** Pode incomodar em conversa animada. →
Constante nomeada num lugar só, com o Dart conferido contra a migration por
teste. Trocar é uma linha e um número no teste.

**A trava no Perfil é ponto de contenção novo.** Toda mensagem passa a travar a
linha de `perfis` do autor. → O conjunto serializado é o das escritas daquela
pessoa, que é o que o limite mede de qualquer jeito. Duas pessoas conversando
nunca esperam uma pela outra.

**Regex sem índice.** `~` sobre a lista inteira a cada mensagem. → Dezenas de
palavras, mensagem de até 2000 caracteres. Se a lista crescer a milhares, o
custo aparece — e aí a resposta é revisar a lista, não o mecanismo.

## Migration Plan

Migration puramente aditiva: tabela, função, dois gatilhos, um índice. Depende
de `mensagens` e `denuncias_mensagem` já existirem.

Rollback: `drop trigger`, `drop function`, `drop table`. Nenhuma mensagem é
alterada — o filtro nunca reescreve, só recusa; nada precisa ser desfeito.

A lista nasce vazia. Com lista vazia, toda mensagem passa e o comportamento é
idêntico ao de antes da change — então a migration pode subir antes de a lista
ser definida, sem janela em que o chat quebre.
