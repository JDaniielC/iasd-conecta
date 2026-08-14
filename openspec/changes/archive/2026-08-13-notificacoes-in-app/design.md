## Context

Ver `proposal.md - Why` para a motivação e para a suposição sobre "o tipo de
notificação já usado no projeto" (não há nenhum).

O que o projeto já oferece e limita:

- `pg_cron` já instalado (`20260810110000_drenagem_capas.sql:26`), com um aviso
  registrado ali mesmo: no plano Free, projeto pausado após uma semana sem
  atividade **para o cron junto** (`:14-21`). Por isso a drenagem de capas tem
  dois gatilhos, não um.
- `grant update` por coluna já é padrão do projeto
  (`20260811160000_grant_update_perfis_por_coluna.sql`) — o jeito de deixar o
  cliente mudar um campo sem deixar mudar os outros.
- Índice parcial já é padrão (`grupos_ativos`, `20260809230000:41`).
- `acao_encerrada(uuid)` = `data_hora + 4h`
  (`20260809174740_acao_encerrada_bloqueia_presenca.sql:33-50`).
- `confirmacoes_acao` tem gatilho `before insert` que decide `confirmado`/`fila`
  e gatilho `after delete` que promove a fila (`20260723230639_acoes.sql`).
- Nenhuma tabela está na publicação `supabase_realtime` — não há uma
  referência sequer a ela em `supabase/`. Esta change estreia esse caminho.
- Depende de `convites_acao`, criada pela change `convite-para-acao`.

## Goals / Non-Goals

**Goals:**
- Um aviso que só a pessoa dona dele lê, escrito só pelo banco.
- Contador que sobe sozinho com o app aberto, e que se corrige quando a conexão
  de tempo real falha em vez de mentir.
- Formato de tabela que um push futuro consuma sem migration.

**Non-Goals:**
- Push de navegador, e-mail, SMS. Change própria.
- Preferência por tipo ("não quero aviso de convite"). Com três tipos e um só
  assunto, a tela de preferência teria mais linhas que a lista de avisos.
- Agrupar avisos ("3 pessoas aceitaram"). Volume de distrito não pede isso
  ainda.
- Aviso de qualquer evento que não seja convite. `log-de-mudancas` é change
  irmã e entra como tipo novo depois.

## Decisions

### Tabela própria, não uma projeção de `mudancas`

```
public.notificacoes
  id              uuid pk
  destinatario_id uuid not null → perfis(id)
  tipo            text not null check (tipo in ('convite_recebido',
                                                'convite_aceito',
                                                'convite_recusado'))
  ator_id         uuid null     → perfis(id)
  acao_id         uuid null     → acoes(id)   on delete cascade
  grupo_id        uuid null     → grupos(id)  on delete cascade
  lida_em         timestamptz null
  created_at      timestamptz not null default now()
```

`mudancas` (change `log-de-mudancas-em-grupo-e-acao`) é **por espaço, sem
destinatário e sem estado de lida**: a policy dela não nomeia ninguém, herda a
visibilidade da Ação por subconsulta, e quem alcança o espaço lê o registro
inteiro. Notificação é **dirigida e privada** — a policy é
`destinatario_id = auth.uid()`, e duas pessoas no mesmo Grupo veem listas
diferentes.

Derivar uma da outra exigiria, a cada leitura, recalcular **para quem** cada
evento é relevante — que é exatamente o trabalho que a coluna
`destinatario_id`, gravada uma vez pelo gatilho, faz de graça. E o primeiro
tipo desta change nem existe lá: convite é privado e nunca vai virar
`mudanca`.

`ator_id` é anulável porque tipo futuro pode não ter autor humano (aviso do
sistema). `acao_id` e `grupo_id` são anuláveis pelo mesmo motivo, e são
`cascade` porque um aviso sobre Ação apagada não tem o que dizer.

_Alternativa recusada:_ uma tabela por tipo de aviso. A tela precisa dos tipos
intercalados em ordem de tempo; separadas, todo carregamento vira `union all`
sem índice que cubra a ordenação final — mesmo raciocínio já registrado no
design de `log-de-mudancas`.

### `tipo` é `text` com `check`, não `enum` do Postgres

Precedente: `confirmacoes_acao.status`, `perfis.genero`. `enum` exige
`alter type` para crescer, e esta tabela **vai** crescer em tipos: é o motivo
de ela ser genérica.

### Escrita só por gatilho; o cliente só muda `lida_em`, por `grant` de coluna

Sem `grant insert` e sem `grant delete` para ninguém. Com RLS ligada e sem
policy, Postgres recusa — é o mecanismo, não esquecimento, e vale comentário na
migration.

Para a leitura e para marcar como lida:

```
grant select on public.notificacoes to authenticated;
grant update (lida_em) on public.notificacoes to authenticated;

notificacoes_select_propria  for select  using (auth.uid() = destinatario_id)
notificacoes_update_propria  for update  using (auth.uid() = destinatario_id)
                                         with check (auth.uid() = destinatario_id)
```

Nada para `anon`: aviso não é público, e aqui não existe o argumento de canal
lateral que fez a feature 021 manter o `grant` de `votos` — ninguém pode
descobrir a existência de um aviso que não é dele por diferença de resposta,
porque não há id de aviso circulando fora do dono.

O `grant update` **por coluna** é o que impede o cliente de reescrever `tipo`,
`ator_id` ou `destinatario_id` com a policy achando que está tudo bem. Policy
filtra linha; só o `grant` filtra coluna — a lição de
`20260811160000_grant_update_perfis_por_coluna.sql`.

### Três gatilhos, ao lado dos existentes

1. `after insert on convites_acao` → `convite_recebido` para `new.convidado_id`,
   `ator_id = new.convidante_id`. Idempotência sai de graça: o convite repetido
   não gera linha nova em `convites_acao`, então não dispara.
2. `after update on convites_acao` quando `recusado_em` passa de nulo para
   preenchido → `convite_recusado` para `new.convidante_id`.
3. `after insert on confirmacoes_acao` → um `convite_aceito` **por convite**
   que exista para `(new.acao_id, new.usuario_id)`, cada um para o
   `convidante_id` daquele convite. Quem não foi convidado não gera nada, e
   duas pessoas que convidaram recebem cada uma o seu.

Gatilho 3 é `after insert`, então roda depois do `before insert` que decide
`confirmado`/`fila` — a ordem importa e é por isso que não é `before`.
A promoção de fila é `update`, não `insert`, então promover alguém não gera
aviso duplicado.

### O aviso de aceite não copia o status; a tela lê o status atual

`convite_aceito` não guarda se a pessoa entrou como `confirmado` ou em `fila`.
Quem estava na fila é promovido depois (`promover_fila_acao`), e um aviso com o
status congelado passaria a mentir — o mesmo defeito que a decisão
"desconfirmação é registrada" evita em `log-de-mudancas`.

A tela lê `confirmacoes_acao` na hora de renderizar e diz o estado de agora.

### Realtime é sinal, não fonte de dado

`alter publication supabase_realtime add table public.notificacoes`. O app se
inscreve, e ao receber **qualquer** evento **reconsulta** a contagem e a lista.
O payload do evento não é usado para montar tela.

Três motivos, nessa ordem:
1. O filtro de "aviso ainda válido" (Ação não cancelada, não encerrada) não
   cabe num payload de linha — ele depende de `acoes`. Montar tela pelo payload
   mostraria aviso de Ação cancelada.
2. Não depender do payload respeitar RLS reduz o estrago se a configuração do
   canal estiver errada. **Não substitui** o teste de RLS no canal, que é
   obrigatório.
3. Reconsultar é o que torna "a conexão caiu" recuperável sem código de
   reconciliação: a próxima abertura de tela já corrige.

_Alternativa recusada:_ `stream()` do `supabase_flutter` alimentando a lista
direto. Amarra a tela ao formato da linha e reintroduz o problema 1.

### Uma view `notificacoes_ativas` para contagem e lista usarem o mesmo filtro

```
create view public.notificacoes_ativas with (security_invoker = true) as
  select n.* from public.notificacoes n
  left join public.acoes a on a.id = n.acao_id
  where n.acao_id is null
     or (a.cancelada_em is null and not public.acao_encerrada(a.id));
```

O contador e a lista **precisam** bater — é requisito. Duas consultas com o
mesmo `where` escrito duas vezes divergem na primeira mudança; uma view não.

`security_invoker = true` é obrigatório: sem ele a view roda com os
privilégios de quem a criou e **ignora a RLS de `notificacoes`**, entregando
aviso alheio. É a linha mais perigosa desta change e precisa de teste próprio.

### Retenção por `pg_cron`: 90 dias depois de lida

Job diário apagando `where lida_em < now() - interval '90 days'`. Não lido
nunca é apagado — se ninguém viu, o prazo não começou.

90 dias porque o aviso é sobre um encontro que já passou; o que sobrevive ao
aviso é a confirmação de presença, que fica em `confirmacoes_acao`.

Herdando o aviso de `drenagem_capas` (`:14-21`): com o projeto pausado no plano
Free o cron para. Aqui isso é atraso de faxina, não defeito de correção —
nenhum requisito depende do aviso ter sumido no dia certo. Por isso **não** se
justifica o segundo gatilho que a drenagem de capas precisou ter.

### Marcar como lida em lote, ao abrir a tela

Um `update` só, sobre as linhas exibidas. A policy e o `grant` de coluna já
garantem que só as próprias mudam, então não é preciso RPC.

## Risks / Trade-offs

- **View sem `security_invoker` vaza aviso alheio** → teste de integração com
  duas sessões lendo `notificacoes_ativas`, cada uma vendo só o seu. Sem esse
  teste, a change não fecha.
- **Canal Realtime entregando evento de linha alheia** → teste com duas sessões
  inscritas, gerando aviso para uma e verificando que a outra **não** recebe
  evento. Se o canal não respeitar RLS na configuração do projeto, o recuo é
  não publicar a tabela e atualizar o contador por consulta ao voltar para o
  app — o requisito de "sobe sozinho" cai, o de privacidade não.
- **Canal aberto sem `dispose` vaza conexão** → o ciclo de vida da inscrição
  fecha junto com o widget; plano Free tem teto de conexões concorrentes.
- **Contador divergente da lista** → mitigado pela view; verificado por teste
  de widget com aviso de Ação cancelada no meio.
- **Depende de `convite-para-acao`** → esta change não entra antes. Se aquela
  mudar o nome da tabela ou das colunas, os três gatilhos aqui quebram; a
  primeira tarefa é reler o schema aplicado, não o design de lá.

## Migration Plan

Uma migration, aditiva: tabela, índices
(`(destinatario_id, created_at desc) where lida_em is null` e
`(destinatario_id, created_at desc)`), RLS com as duas policies, os `grant`
(select, e update só de `lida_em`), os três gatilhos, a view, a entrada na
publicação `supabase_realtime` e o job de `pg_cron`.

Nenhuma tabela existente muda de coluna; nenhum gatilho existente é reescrito.

Rollback: `drop` da view, dos três gatilhos, do job, da entrada na publicação e
da tabela. Nada em Ação, Grupo, presença ou convite depende dela — o convite
continua funcionando sem aviso nenhum, que é o estado de hoje.
