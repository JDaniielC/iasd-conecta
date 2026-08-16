## Context

Ver `proposal.md` — Why. O que o código já estabelece e que este design não
pode contrariar:

- **Visitante é sessão anônima sem Perfil** (`supabase_client.dart:37,49`,
  `app.dart:55,72`). Logo, qualquer regra baseada em `perfis` já exclui
  Visitante sem precisar tocar em `auth.users`.
- **`perfis.idade` é obrigatória** (`20260723191202:35`) e vira nula na
  anonimização (`20260806140000`, seção 2). Um corte por idade falha fechado
  nos dois casos, que é o lado certo de falhar.
- **A autoridade sobre uma Ação já existe e já é um par**:
  `acoes_update_criador_ou_dono_grupo` (`20260724084300:228-239`) — criador da
  Ação **ou** dono do Grupo dela. O chat reusa o predicado, não inventa outro.
- **Denúncia já tem forma no projeto**: `denuncias_imagem` (`20260810120000`)
  — `motivo` obrigatório, denunciante anulável, `estado` como `text` com
  `check`, `resolvida_em`. O `with check` de `insert` impede assinar por
  outro; o `with check` do `update` é gêmeo do `using` de propósito.
- **`pg_cron` sozinho não cumpre prazo** (`20260810170000:9-14`): plano
  gratuito pausa o projeto por inatividade e o cron para junto. Todo prazo
  deste projeto precisa de um segundo gatilho no app.

## Goals / Non-Goals

**Goals:**
- Um único predicado de acesso por espaço, reusado por leitura, escrita, canal
  de tempo real e denúncia. Quatro cópias divergem; uma não.
- Corte de idade no banco, não na tela.
- Prazo de retenção que se cumpre com o banco pausado.

**Non-Goals:**
- Anexo, imagem ou áudio. Só texto. Imagem traria de volta toda a máquina de
  `fotos_capa`, `denuncias_imagem`, drenagem e varredura.
- Mensagem direta entre duas pessoas. Todo chat é de um espaço que já existe e
  que já tem dono.
- Edição de mensagem, reação, resposta encadeada, confirmação de leitura,
  indicador de digitando, contagem de não lidas.
- **Filtro automático de palavrão.** `palavras_bloqueadas` e `nome_valido()`
  existem e seriam reuso de uma linha, mas foram desenhados para barrar um
  nome de cadastro por substring: `like '%...%'` sem fronteira de palavra
  produz falso positivo em texto corrido e nenhum caminho para a pessoa
  entender por que a mensagem foi recusada. A moderação aqui é humana e
  reativa, por decisão. Ver Risks.
- Notificação por push ou e-mail.

## Decisions

### Uma tabela `mensagens`, com `grupo_id` XOR `acao_id`

```
public.mensagens
  id          uuid pk
  grupo_id    uuid null → grupos(id) on delete cascade
  acao_id     uuid null → acoes(id)  on delete cascade
  autor_id    uuid not null → perfis(id)
  texto       text null            -- nulo = lápide
  removida_em   timestamptz null
  removida_por  uuid null → perfis(id)
  created_at  timestamptz not null default now()

  check ((grupo_id is not null) <> (acao_id is not null))   -- exatamente um
  check (texto is null or length(trim(texto)) between 1 and 2000)
```

Alternativa recusada: duas tabelas, `mensagens_grupo` e `mensagens_acao`.
Duplicaria policies, gatilhos, publicação de Realtime, expurgo e o modelo Dart
— e a única diferença real entre as duas é o predicado de quem lê.

**Limite de 2000 caracteres.** Número escolhido, não medido: é conversa de
combinação, não redação. Fica no `check`, e a tela mostra o contador antes do
envio para a recusa nunca chegar como erro de servidor.

### Duas lápides diferentes, distinguidas sem coluna nova

| Estado | `texto` | `removida_em` | O que a tela escreve |
|---|---|---|---|
| normal | preenchido | nulo | a mensagem |
| removida por moderação | nulo | preenchido | "mensagem removida" |
| autor excluiu a conta | nulo | nulo | "mensagem de conta excluída" |

Derivável das duas colunas que já precisam existir. Alternativa recusada: uma
coluna `motivo_ausencia` — informação redundante que pode divergir do estado
real das outras duas.

### O texto removido não é guardado em lugar nenhum

Remover faz `texto = null`, e ponto. Nem tabela de auditoria, nem coluna
`texto_original`, nem cópia para o Administrador.

Alternativa recusada: conservar o texto para o Administrador julgar a denúncia.
Recusada porque recria, dentro do banco, exatamente o dado que a remoção existe
para eliminar — e num lugar com menos gente olhando. O que fica como registro
do caso é o `motivo` que o denunciante escreveu, mesmo desenho de
`denuncias_imagem`. Consequência aceita: quem remove precisa ler antes de
remover, porque depois não dá para reconsiderar.

### `maior_de_idade()` é `security definer` com `search_path` fixo

```sql
create function public.maior_de_idade() returns boolean
language sql stable security definer set search_path = public, pg_temp
as $$ select exists (
  select 1 from public.perfis
  where id = auth.uid() and idade is not null and idade >= 18
); $$;
```

Como `invoker`, a função depende de `perfis_select_own` continuar existindo. Se
uma mudança futura apertar aquela policy, a função passa a devolver `false`
para todo mundo e o chat some da tela sem erro, sem log e sem teste vermelho —
indistinguível de "você é menor de idade". É o mesmo modo de falha que
`nome_valido_security_definer` (`20260806090000:7`) foi escrita para eliminar,
e a resposta é a mesma.

`idade is not null` explícito: Perfil anonimizado tem idade nula, e
`null >= 18` é `null`, não `false`. Dentro de `exists` daria no mesmo, mas
escrito é o que se lê numa revisão.

Visitante não tem linha em `perfis`, então falha aqui sem checagem extra —
diferente de `administradores_distrito_checar_regras`, que precisou ler
`auth.users.is_anonymous` porque lá o alvo tinha Perfil.

### Dois predicados de acesso, um por espaço, usados em todo lugar

```sql
public.pode_ver_chat_grupo(p_grupo_id uuid) -- participa do Grupo  E maior_de_idade()
public.pode_ver_chat_acao (p_acao_id  uuid) -- (confirmação em qualquer status
                                            --  OU criador da Ação
                                            --  OU dono do Grupo dela
                                            --  OU Administrador do distrito)
                                            --  E maior_de_idade()
```

`stable`, `security invoker` — e isso não é detalhe de implementação, é o
mecanismo.

Como `invoker`, as duas funções enxergam `acoes` e `confirmacoes_acao` sob a
RLS de quem chamou. Hoje as quatro tabelas que elas consultam são `select`
público `using (true)`, então a escolha não muda nada. Depois de
`acao-direcionada-a-grupo`, muda tudo do jeito certo: uma Ação restrita ao
Grupo some para quem não participa, a confirmação dela some junto
(`confirmacoes_acao_select_conforme_acao` herda de `acoes`), e
`pode_ver_chat_acao` passa a devolver falso para essa pessoa **sem uma linha
de código nova aqui**.

Trocar por `security definer` — o reflexo, já que `maior_de_idade()` é definer
— quebraria exatamente isso: as funções passariam a enxergar toda Ação
restrita e todo par de confirmação como dono do banco, e o chat de uma Ação
fechada ficaria acessível a quem a própria Ação esconde. `maior_de_idade()` é
definer por um motivo oposto e específico (ler `perfis` sem depender de uma
policy que pode apertar; ver acima); as duas de acesso são invoker pelo motivo
simétrico. A diferença precisa estar comentada na migration, senão a próxima
pessoa uniformiza as três e abre o buraco.

**Consequência de ordem:** esta change fica correta antes e depois de
`acao-direcionada-a-grupo`, e não depende dela para entrar.

As policies de `select`, `insert`, `update` e `delete` de `mensagens` e de
`denuncias_mensagem` chamam **estas duas funções**, nunca a condição inline.
Alternativa recusada: repetir o `exists` em cada policy — são no mínimo oito
lugares, e a primeira divergência entre eles é um vazamento.

Escrita tem uma condição a mais que leitura: `grupos.arquivado_em is null`.
Ela entra na policy de `insert`, ao lado — mesma escolha que
`20260809230000:161-171` fez para participação.

### O Administrador do distrito lê, porque no banco remover exige alcançar

**Corrigido em 2026-08-14, durante a implementação.** A primeira versão deste
design excluía o Administrador de `pode_ver_chat_*` com a frase "moderar não é
ler", dando a ele apenas a policy de `update`. Não funciona: remover é um
`update` com `where id = ...`, e um `update` com `where` aplica também a policy
de `select`. Sem leitura o Administrador não alcança a linha denunciada, e a
remoção afeta **zero linha, em silêncio** — medido, não deduzido, e é a mesma
mecânica que `acao-direcionada-a-grupo` já havia registrado.

As três saídas foram avaliadas: RPC `security definer` de remoção (preserva as
duas metades, custa uma função e tira o `update` do cliente), Administrador
dentro de `pode_ver_chat_*` (uma linha, e ele passa a ler tudo), ou Administrador
fora da moderação de chat (deixa o distrito sem instância de recurso quando o
abuso vem do dono do espaço).

Escolhida a segunda, com o poder declarado no spec em vez de escondido. O corte
de idade fica **fora** do `or`, de propósito: autoridade não levanta a idade.

### Remoção é `update`, não `delete`

Policy de `update` em `mensagens` restrita a: autor da mensagem, ou quem tem
autoridade no espaço (dono do Grupo / criador da Ação / Administrador do
distrito). O `with check` é gêmeo do `using`, como em
`denuncias_imagem_update_admin` (`20260810120000:63-69`) — sem isso a linha
poderia sair do conjunto que a própria policy protege.

Não há policy de `delete` em `mensagens` para nenhum papel. Apagar de verdade é
só do expurgo, que roda como dono.

Um gatilho `before update` impede que o `update` toque em qualquer coluna que
não seja `texto`, `removida_em` e `removida_por` — sem ele, quem pode remover
poderia reescrever `texto` e a spec "mensagem enviada não se edita" seria
letra morta. O gatilho também recusa `texto` não nulo: o único `update`
permitido é o que apaga.

### Realtime: o canal não é uma segunda porta

`alter publication supabase_realtime add table public.mensagens`, com RLS
ligado. O `postgres_changes` do Supabase avalia as policies de `select` por
assinante, então os mesmos dois predicados valem no canal.

O risco não é a regra, é a configuração: publicação sem RLS, ou policy que não
cobre o caminho do canal, entrega mensagem a quem não deveria receber — e
falha calada, porque a tela do atacante não precisa mostrar nada para o dado
ter saído. Por isso a prova disso é teste, não revisão. Ver Risks.

O cliente combina os dois caminhos: uma consulta ao abrir (histórico) e a
assinatura (novidade), deduplicando por `id`. Sem a consulta, quem abre a tela
vê conversa vazia até alguém falar; sem a dedução por `id`, a mensagem que
chega pelos dois caminhos aparece duas vezes.

### Quem manda na lista da conversa: a CONSULTA, não o canal

Decisão tomada na convergência 3, depois de dois defeitos com a mesma causa.

O canal de tempo real é **otimização sobre uma consulta que a tela sabe
refazer**. Não é a fonte. A regra prática:

> A lista que a tela desenha é `servidor ∪ o que eu acabei de escrever`, e toda
> ação da pessoa que muda esse conjunto atualiza a tela **sem depender de o
> canal estar de pé**.

O que forçou a decisão: `chatProvider` emitia em cinco pontos — carga inicial,
sessão ausente, erro de carga, evento do canal, transição para `subscribed` — e
**nenhum era ação da pessoa**. Duas consequências caíram juntas:

- enviar com o canal caído limpava o campo e não mostrava nada, sem erro, porque
  o `insert` tinha dado certo e só o canal desenharia o resultado;
- as 50 mensagens da consulta viraram teto em vez de página, porque "carregar
  mais antigas" também é ação da pessoa e não tinha por onde entrar.

Alternativa recusada: fazer o canal ser a fonte e reconsultar a cada evento,
como `notificationSignalProvider`. Lá isso é certo — o filtro de "aviso ainda
válido" mora numa view e não cabe num payload. Aqui seria uma ida ao servidor
por palavra dita em Grupo ativo.

Alternativa recusada: transformar `chatProvider` num `Notifier` com métodos
`send` e `loadOlder`. É a forma mais limpa no papel, e paga uma reescrita do
ciclo de vida do canal — o pedaço com mais risco desta change, e o único cuja
prova exige duas sessões reais. Fica registrado como o refactor a fazer se uma
terceira fonte aparecer.

**Como fica:** a tela compõe três fontes pela `mergeMessages`, que já existe e
já é testada — o histórico paginado, o que o canal entregou, e o que a pessoa
acabou de escrever. `send` devolve a linha inserida, então a mensagem própria
aparece na hora sem consulta extra; a dedução por `id` a remove da sobreposição
quando ela chega pelo caminho normal.

**E a regra que faltava, sem a qual a decisão acima produz um vazamento:**

> Sobreposição local existe para o que o servidor **ainda não disse**, e é
> descartada assim que ele diz. Onde os dois falam da mesma linha, vence o
> servidor — sempre.

Isto não é detalhe de implementação, é o que separa "a tela mostra antes de
confirmar" de "a tela discorda do banco". A primeira versão desta decisão não
escreveu a regra, e o resultado apareceu na convergência seguinte:
`mergeMessages` faz quem chega por último vencer, a sobreposição local foi
passada por último, e com isso a cópia guardada na tela ganhava **da remoção**.
Quem escrevia uma mensagem continuava vendo o texto dela depois de removida — e
a spec de moderação diz que o texto removido não volta para ninguém, o que
inclui quem o escreveu.

**Escrever a regra não bastou, e a convergência 5 mostrou por quê.** Ela foi
implementada num lugar só — a ordem dos argumentos no `build` da tela — e a
lista se compunha em QUATRO. Nos outros três a cópia local continuava
ganhando, medido em 2026-08-16:

| caminho | o que se via |
|---|---|
| remover com o canal caído | `texto_ainda_na_tela=true`, `lapide_na_tela=false` |
| reconectar depois de uma remoção na queda | `texto_na_tela='o texto que a moderação tirou'`, `lapide=visible` |
| expurgo com página anterior carregada | `antiga_na_tela=true`, `recente_na_tela=false` |

**Duas mudanças estruturais, e é o que fecha a classe:**

**1. Uma costura.** `chatProvider` virou `ChatNotifier` — o refactor que esta
seção registrava como "a fazer se uma terceira fonte aparecer". Ela apareceu.
As três fontes (histórico paginado, canal, o que a pessoa acabou de escrever)
moram na mesma classe, e tudo o que o servidor diz entra por `_applyServer` ou
`_forgetRow`. A tela não junta nada. Fica registrada a consequência que pesava
contra: o ciclo de vida do canal foi reescrito, e é o pedaço de maior risco da
change — por isso `chat_reconexao_test.dart` e `conversa_sem_canal_test.dart`
passaram a exercitar o notifier DE VERDADE, com o canal em dublê, em vez de um
estado fixo.

**2. A precedência deixou de ser ordem de chegada.** "Quem chega depois vence"
é ordem de rede, e ela mente nos dois sentidos — a consulta em voo responde com
a linha anterior à remoção que o canal já entregou, e a cópia de antes da queda
ganha da consulta que a reconexão refez. Não há ordem de argumentos que acerte
os dois.

> **A lápide é ABSORVENTE.** Entre duas versões da mesma linha vence a que
> avançou mais em `MessageTombstone` — visível, depois conta excluída, depois
> removida por moderação.

É o banco que torna isso sempre correto, e não uma heurística: o gatilho
`mensagens_so_remove` recusa qualquer `update` que deixe `texto` não nulo e
preserva `removida_em` uma vez gravado. Texto não ressuscita, logo a versão com
menos texto é sempre a de depois — sem relógio, sem número de versão e sem
depender de quem chegou primeiro.

**O alcance da reconexão, e é limite aceito, não esquecimento.** Ao voltar, o
canal refaz **a página mais recente** — `fetchHistory` sem `before` — e não as
páginas anteriores que a pessoa já tinha carregado. Consequência medida em
2026-08-16: uma remoção ocorrida DURANTE a queda, sobre uma linha de página
antiga, não é aprendida (`consultas_recentes=2`, `texto_antigo_na_tela=true`).
O texto fica na tela daquela pessoa até ela sair da conversa.

Refazer todas as páginas carregadas seria uma ida ao servidor por página em
cada reconexão, e reconexão em rede de celular é frequente. Fica assim de
propósito. Quem for ampliar isto precisa de um motivo melhor que simetria.

### Retenção: `pg_cron` **e** segundo gatilho, como a drenagem

```sql
public.expurgar_mensagens_de_acao()  -- delete de mensagens cuja Ação
                                     -- passou de data_hora + 30 dias
```

Agendada no `pg_cron` **e** chamada pelo app ao abrir um chat. O `pg_cron`
sozinho não cumpre: o plano gratuito pausa o projeto e o cron para junto
(`20260810170000:9-14`). O app é quem acorda o banco, então o app é o segundo
gatilho — mesma lição, mesma solução.

A função sai cedo quando não há nada a expurgar, mas **depois** de consultar —
não antes. `20260810170000:21-27` documenta o erro oposto: sair cedo com base
num estado que é justamente o que se procura.

**30 dias após `acoes.data_hora`**, não após a criação: o que dá sentido à
conversa é o encontro. Trinta é escolha, não medição — dá margem para o
"manda as fotos" da semana seguinte sem virar arquivo. Precisa entrar na
Política de Privacidade como prazo declarado, e aí vira promessa.

Chat de Grupo não expira. Grupo arquivado também não expurga: o histórico é
justamente o que sobra de um Grupo arquivado.

### `denuncias_mensagem`, no molde de `denuncias_imagem`

```
  id, mensagem_id → mensagens(id) on delete set null,
  motivo text not null check (length(trim(motivo)) > 0),
  denunciante_id → perfis(id),
  estado text check (estado in
    ('pendente','mensagem_removida','improcedente','sem_mensagem')),
  created_at, resolvida_em
```

`on delete set null`, não `cascade` — é a diferença deliberada em relação a
`denuncias_imagem`. O expurgo de 30 dias apagaria a denúncia junto com a
mensagem, e uma denúncia pendente que some sem desfecho é o pior resultado
possível para quem denunciou. Um gatilho **`before delete`** em `mensagens`
marca as pendentes como `sem_mensagem`.

`before`, e não `after` como esta seção dizia antes: a ação `on delete set
null` da chave estrangeira é ela própria um gatilho AFTER interno, e o
Postgres dispara os AFTER de uma linha em ordem de nome — `RI_ConstraintTrigger_…`
vem antes de qualquer nome em minúscula. Como `after`, o gatilho encontrava
`mensagem_id` já nulo e não marcava nada, calado. Medido pelo teste de expurgo
desta change.

`denunciante_id` é `not null` aqui, ao contrário de `denuncias_imagem` — lá
podia ser Visitante; aqui só denuncia quem lê o chat, e quem lê o chat tem
Perfil.

### `excluir_conta` ganha um passo, dentro da transação que já existe

Um `update mensagens set texto = null where autor_id = p_usuario_id`, junto dos
demais passos da função (`20260806140000`, seção 3: "a operação inteira, numa
transação só"). Não é caminho de falha novo — ou tudo acontece, ou nada.

Mensagem de terceiro que cite o titular fica intacta. É limite real e precisa
estar escrito na Política de Privacidade, não implícito: o caminho para
removê-la é a denúncia.

### Código Dart em `lib/features/chat/`

Feature própria, `data/` `domain/` `presentation/`, como as outras 13. As duas
telas de detalhe ganham uma aba; nenhum widget existente muda de contrato.

## Risks / Trade-offs

**Realtime entregando o que a consulta não entregaria.** É o vazamento mais
provável desta change, e o mais silencioso. → Prova: teste de integração que
assina o canal com credencial de não participante e com credencial de menor de
18, espera uma janela determinada depois de uma escrita real, e falha se
qualquer evento chegar. Teste que só verifica "o participante recebe" não
prova nada sobre quem não deveria receber.

**Moderação só humana e só reativa.** Sem filtro automático, a primeira
mensagem ofensiva fica no ar até alguém denunciar e o dono do Grupo abrir o
app. Num distrito pequeno isso é minutos ou dias, sem previsão. → Aceito por
decisão (ver Non-Goals). Se virar problema, o caminho não é reusar
`palavras_bloqueadas` como está: é uma lista com fronteira de palavra e uma
mensagem de recusa que a pessoa entenda.

**O corte em 18 anos exclui parte real do público.** Um app de distrito de
igreja tem adolescente em Grupo de jovens, e eles ficam de fora da conversa do
próprio Grupo — vendo a aba não existir, sem explicação. → A tela precisa dizer
por que, em vez de simplesmente não mostrar nada. Sem isso, o corte lê como bug.

**Texto livre é o único dado do app cujo conteúdo não se declara antes.** O
`MAPA-DE-DADOS.md` tem `arquivo:linha` para cada campo justamente porque cada
campo tem forma conhecida. `mensagens.texto` não tem. → A entrada no mapa
declara isso explicitamente, em vez de fingir que declara o conteúdo. A
Política de Privacidade precisa dizer que a pessoa é responsável pelo que
escreve e que não deve escrever dado sensível de terceiro.

**Trinta dias vira promessa.** Uma vez na Política de Privacidade, o prazo é
verificável de fora, e a metade da execução (o `pg_cron` de produção) mora
fora do repositório. → `INFRA-PRODUCAO.md` registra o agendamento a criar à
mão, e o segundo gatilho no app é o que sustenta o prazo quando o cron não
roda. É a mesma classe de defeito que o agente `promessa-vs-execucao` procura.

**Uma mensagem removida não volta.** Quem remove por engano perdeu o texto. →
Aceito: é o preço de não guardar cópia. A tela pede confirmação antes de
remover e diz que é definitivo.

## Migration Plan

Ordem: migration → `pg_cron` agendado em produção à mão → build web. O app
antigo ignora as tabelas novas; o app novo contra o banco antigo quebra a aba.

Rollback: `drop` das duas tabelas, das funções e do gatilho, e reverter
`excluir_conta` para a versão anterior. **A reversão apaga conversa real** —
depois que a primeira mensagem existir, reverter é perda de dado, não volta ao
estado anterior. Por isso a change entra depois de
`log-de-mudancas-em-grupo-e-acao`, que é reversível sem perda.

## Open Questions

- **30 dias é o prazo certo?** Trocar o número muda uma linha do `check` de
  expurgo e uma frase da Política de Privacidade. Não muda spec, abordagem nem
  a lista de tarefas — dá para decidir na revisão do texto legal.
