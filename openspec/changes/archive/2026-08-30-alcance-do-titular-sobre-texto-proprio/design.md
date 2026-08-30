## Context

Ver `proposal.md` — Why. O que vem pronto de `mensagem-fixada`:

- `mensagens.fixada_em` / `fixada_por`, com `check mensagens_fixada_completa`.
- Gatilho `mensagens_so_remove`, `security definer`, que já separa fixar de
  desfixar e já aceita o autor no braço de desfixe
  (`pode_moderar_mensagem`, com `coalesce`).
- Policy `mensagens_update_autor_ou_autoridade`, cujo `using` **já passa** para
  o autor fora do espaço — medido, `pode_moderar_mensagem` = `t`.
- `ChatRepository.unpinMessage`, chamada só de dentro de `chat_page.dart`.

**A peça que falta não é permissão, é ALCANCE.** É o achado que decide o
desenho desta change: no Postgres, um `UPDATE ... WHERE` só enxerga linha que a
policy de `SELECT` deixa a sessão ler. A policy de `update` acerta e não
adianta.

## Goals / Non-Goals

**Goals:**
- O autor alcança a própria mensagem fixada de qualquer conversa, inclusive das
  que ele já não lê.
- A superfície nova é a mais estreita que resolve: uma operação, uma condição,
  duas colunas.

**Non-Goals:**
- **Caminho de desfixe para quem é CITADO por outro** (`PENDENCIAS.md` 2.25).
  Ela não escreveu a mensagem, e dar-lhe o botão seria dar a um terceiro poder
  sobre o texto de quem escreveu. Continua saindo por denúncia. Fica aberto, e
  fica escrito que ficou.
- Devolver a leitura da conversa a quem saiu. O que ela recupera é o próprio
  texto, não o alheio.
- Fixar de fora da conversa. Fixar decide o que todo mundo vê primeiro, e
  continua sendo da autoridade do espaço.
- Prazo automático para fixada. Recusado em `mensagem-fixada` e continua
  recusado — um segundo prazo a declarar na Política para resolver o que
  desfixar resolve.

## Decisions

### Uma função `security definer`, e não uma policy de `select` mais larga

A alternativa óbvia — acrescentar ao `using` de `mensagens_select_do_espaco` um
braço "ou você é o autor" — resolveria o alcance e **abriria a leitura**: o
autor que saiu do Grupo passaria a ler a própria mensagem, e o `select` não
distingue "ler para desfixar" de "ler". Pior, ele passaria a ler a linha inteira
de uma conversa de que não participa mais.

A função é a única forma de alcançar a linha sem alargar quem lê o quê.

**Ela precisa ser estreita, e isto é o contrato dela:**

- recebe o id da mensagem, e nada mais;
- confere `auth.uid() = autor_id` — o predicado inteiro, sem braço de
  autoridade, porque autoridade já tem o caminho de dentro da conversa;
- toca **apenas** `fixada_em` e `fixada_por`, as duas para nulo;
- devolve quantas linhas mudou, para o cliente distinguir "não era sua" de "não
  estava fixada".

`security definer` com `search_path = ''`, `revoke execute from public` e
`grant execute to authenticated`, no molde de `expurgar_mensagens_de_acao` e
com a disciplina de `20260816120000_revogar_execute_de_public.sql`.

O gatilho `mensagens_so_remove` continua rodando — a função não o contorna, e é
por isso que ela não precisa reimplementar a regra de desfixe. A trava de
edição continua sendo uma só.

### A lista das próprias fixadas também é função, pelo mesmo motivo

Para desfixar de fora, a pessoa precisa **ver o que tem fixado**, e a consulta
esbarra na mesma policy. Uma segunda função `security definer`, `stable`, que
devolve as mensagens fixadas cujo `autor_id` é `auth.uid()`.

Ela devolve o texto da própria pessoa, o instante da fixação e o nome do espaço
— sem nada de terceiro, e sem quem fixou. **Quem fixou não entra**: é dado
sobre outra pessoa, e saber que "alguém com autoridade fixou" basta para
decidir desfixar.

Alternativa recusada: devolver só os ids e deixar a tela pedir cada linha.
Seriam N idas ao servidor para uma tela que existe justamente para quem já foi
mal servido.

### A tela mora em "Meu Perfil", não numa aba nova

`Meu Perfil` já é onde a pessoa exerce direito sobre os próprios dados —
corrigir cadastro e excluir a conta estão lá, e a Política aponta para lá. Uma
entrada a mais no mesmo lugar é o que ela vai encontrar quando procurar.

A tela lista as fixadas com um botão de desfixar por linha, e **some quando não
há nenhuma** — mesma escolha da faixa: seção vazia declarando que não há nada é
espaço gasto à toa.

**Julgar na largura de celular**, como o resto do app.

### O que a tela diz quando a lista está vazia por outro motivo

Zero fixadas e "você não tem nada fixado" são a mesma frase, e está certo: a
pessoa não precisa saber se é porque ninguém fixou ou porque alguém desfixou
antes dela.

## Risks / Trade-offs

**Superfície nova de escrita na REST.** Duas funções `security definer`
alcançáveis por qualquer sessão autenticada. → O predicado é `auth.uid() =
autor_id`, sem parâmetro de identidade, então não há o que forjar; e o teste
precisa exercitar a sessão de OUTRA pessoa contra a mesma mensagem, não só a
do autor. É a armadilha "provar o papel errado" que este projeto já pagou.

**A função de leitura devolve linha que a policy esconde.** É o ponto dela, e é
o que exige que o `where` seja lido por alguém — um `or` a mais ali abre a
conversa inteira. → Teste com sessão de não autor pedindo a lista e recebendo
zero linhas, e teste de que a lista de uma pessoa não traz mensagem de outra na
mesma conversa.

**A Política muda de novo, uma versão depois.** → É o certo: a 1.7 declarou um
limite, e esta change o remove. Manter o texto que manda escrever para o e-mail
depois que o botão existe seria a mesma classe de defeito que a 1.7 consertou.

**`PENDENCIAS.md` 2.25 continua aberta e agora fica mais visível** — o autor
ganha caminho, a pessoa citada não. → Escrito na Política e no ledger, com o
motivo. Não é omissão: é a decisão que ninguém tomou ainda.

## Migration Plan

Aditiva: duas funções novas, nenhuma coluna, nenhuma policy alterada.

Rollback: `drop function` nas duas e reverter a tela e o texto legal. **Sem
perda de dado** — nada é gravado por esta change. O que se perde é o caminho, e
o estado volta a ser o que a Política 1.7 já descreve.
