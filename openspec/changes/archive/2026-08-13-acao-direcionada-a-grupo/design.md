## Context

Ver `proposal.md - Why` para a motivação. O que restringe o desenho:

- `acoes_select_public` é `to anon, authenticated using (true)`
  (`20260723230639_acoes.sql:121-124`) — o plano mais barato possível, na tela
  mais aberta do app.
- `acoes.grupo_id` já existe desde a feature 004
  (`20260724084300_rodada_votacao.sql:13-16`) e é nulo na Ação avulsa.
- `confirmacoes_acao_select_public` também é `using (true)` (`:136-139`) e
  devolve o par nominal `(acao_id, usuario_id)`.
- `participacoes_grupo` tem PK `(grupo_id, usuario_id)`
  (`20260723220703_grupos.sql:21-26`) — nenhum índice serve para procurar
  **pelos Grupos de uma pessoa**, que é exatamente a direção que uma policy
  nova vai percorrer.
- `votos` já foi fechado a "só o próprio voto" na feature 021
  (`20260809200000_votos_visibilidade.sql`), e a migration documenta o
  raciocínio de canal lateral que este desenho reaproveita: manter o `grant` e
  devolver **lista vazia** em vez de erro, porque a diferença entre "não existe"
  e "não posso ver" é contável.
- `acao_encerrada(uuid)` existe e é `data_hora + 4h`
  (`20260809174740_acao_encerrada_bloqueia_presenca.sql:33-50`).
- A escrita em `acoes` **não** é só do criador. `acoes_update_criador` foi
  substituída por `acoes_update_criador_dono_grupo_ou_admin`
  (`20260724092132_district_admin.sql`), que aceita criador, Dono do Grupo da
  Ação **ou** Administrador do distrito. Versões anteriores deste design
  afirmavam o contrário; a afirmação era falsa e foi o que motivou a decisão
  registrada abaixo.
- `acoes_protege_campos_internos` (`before update`) já recusa mudança de
  `confirmada/grupo_id/rodada_id/criador_id`, com escape por
  `app.bypass_acoes_protecao`. É onde uma regra de escrita por coluna entraria,
  se houvesse.
- **Ação de Grupo só nasce como candidata de Rodada.**
  `acoes_candidata_checar_regras` (`before insert`) recusa `grupo_id` sem
  `rodada_id` — "Ação de Grupo só pode ser criada como candidata de uma Rodada
  de votação" — e, quando há Rodada, deriva `new.grupo_id` dela e força
  `new.confirmada := false`. `Action.toInsertMap`
  (`lib/features/action/domain/action.dart:42-58`) não tem chave `grupo_id`, e
  `voting_round_repository.dart:51` registra que ela nunca é enviada. Logo
  **não existe "criar Ação e escolher Grupo"** neste app, e versões anteriores
  desta change supunham que existia.
- `rodadas_votacao_select_public` e `grupos_select_public` são `using (true)`.
  A Rodada e o Grupo continuam públicos depois desta change; some a candidata,
  não a existência da Rodada.

## Goals / Non-Goals

**Goals:**
- A restrição é uma condição de policy, e toda tela herda dela sem código de
  filtro.
- O feed público não fica mais lento de um jeito que dê para sentir.

**Non-Goals:**
- Níveis de visibilidade além de público/Grupo. Nada de "só a minha Igreja" ou
  "só a liderança" nesta change.
- Convite. É a change `convite-para-acao`; esta só acrescenta o limite de que
  convite para Ação restrita não sai do Grupo.
- Esconder Ação **cancelada** ou **encerrada**. Continuam com a visibilidade
  que sempre tiveram.

## Decisions

### Uma coluna booleana, não um enum de níveis

`acoes.restrita_ao_grupo boolean not null default false`, com
`check (restrita_ao_grupo = false or grupo_id is not null)`.

Existem dois estados reais: público e restrito ao Grupo. Um enum
`visibilidade text check (... in ('publica','grupo'))` com dois valores custa o
mesmo hoje e convida a inventar um terceiro nível antes de alguém pedir. Quando
um terceiro aparecer de verdade, migrar booleano para enum é uma migration
mecânica, com o requisito na mão.

O `check` no banco é o que faz "Ação avulsa não pode ser restrita" ser
verdade — a tela esconder o controle é conveniência, não garantia.

_Alternativa recusada:_ tabela `acoes_restritas` à parte. `left join` em toda
leitura do feed, para guardar um booleano.

### A restrição vive na policy de `acoes`, e `confirmacoes_acao` herda por subconsulta

`acoes_select_public` sai (com o nome junto, pelo mesmo motivo que a feature
021 registrou: policy com nome que mente é pior que policy sem nome). Entra:

```
restrita_ao_grupo = false
or exists (select 1 from public.participacoes_grupo p
           where p.grupo_id = acoes.grupo_id and p.usuario_id = auth.uid())
```

Em sessão `anon`, `auth.uid()` é nulo, o `exists` é falso, e a Ação restrita
some — sem `if` especial e sem erro, só linha a menos.

Para `confirmacoes_acao`, a policy nova é
`exists (select 1 from public.acoes a where a.id = acao_id)` — e mais nada. A
subconsulta roda sob a RLS de `acoes` para a mesma sessão, então **a regra de
visibilidade existe num lugar só**. Se um dia a condição de `acoes` mudar, a
lista de presença acompanha sozinha; duplicar o `exists` de participação aqui
seria a segunda cópia que fatalmente ficaria para trás.

_Alternativa recusada:_ filtrar na consulta do Dart. O REST do Supabase é
público — `GET /rest/v1/acoes` com a chave anônima responde direto, e é assim
que a feature 021 descobriu que os votos vazavam.

_Alternativa recusada:_ função `security definer` para a checagem de
participação. `participacoes_grupo` já é legível por todo mundo
(`participacoes_grupo_select_public`), então definer não acrescenta acesso
nenhum — só esconderia a condição do plano de execução e do `explain`.

### Índice em `participacoes_grupo (usuario_id, grupo_id)`

A PK é `(grupo_id, usuario_id)`. A policy procura na direção contrária, uma vez
por linha de `acoes` avaliada, em toda leitura do feed. Sem esse índice, cada
leitura de `/acoes` vira varredura de `participacoes_grupo`.

Medir é tarefa, não suposição: `explain analyze` do feed antes e depois, com o
número real nas tasks.

### A restrição segue a permissão de escrita que já existe

Quem já pode editar a Ação pode mexer na restrição: criador, Dono do Grupo,
Administrador do distrito — a lista de
`acoes_update_criador_dono_grupo_ou_admin`. Nenhuma regra de escrita nova,
nenhuma coluna protegida a mais.

Decisão tomada com o custo na mesa: as três opções (só criador; criador ou
Dono; a lista inteira) custavam o mesmo gatilho. Escolhida a lista inteira
porque a restrição é configuração da Ação como qualquer outra, e partir a
permissão de escrita em duas — uma para o resto da Ação, outra só para esta
coluna — cria a segunda regra que diverge da primeira na próxima mudança.

O que falta é impedir mudança depois de encerrada, e isso é gatilho
`before update` usando `acao_encerrada` — mesma função que já bloqueia presença.

**O que isso permite, medido, não suposto.** Três experimentos contra o
Postgres local, com uma tabela de brinquedo cuja policy de `select` esconde a
linha quando a coluna `oculta` é verdadeira:

```
update t set marca='x'    where id = <linha visível>    -> UPDATE 1
update t set oculta=true  where id = <linha visível>    -> ERROR: new row
                                                           violates row-level
                                                           security policy
update t set <coluna>='x'  -- sem filtro nenhum          -> alcança a linha oculta
```

O segundo é o que importa: **a policy de `select` vale também como `with check`
implícito do `update`**. Ninguém consegue empurrar uma linha para fora da
própria visibilidade. Logo o Administrador NÃO fecha uma Ação de Grupo do qual
não participa — o banco recusa. Fechar é possível só para quem participa, e
quem participa continua vendo. Este lado não precisou de código nenhum.

O que sobra é o sentido inverso, o de **abrir**: desmarcar a restrição deixa a
linha mais visível, então o `with check` implícito não barra. Pelo id o
Administrador não alcança (o filtro traz a regra de leitura junto), mas sem
filtro alcança — e a policy de `update` dele não recorta por linha. Com o Dono
do Grupo o mesmo caminho existe e é inofensivo: a policy dele já recorta pelos
Grupos dele.

_Alternativa recusada:_ acrescentar `restrita_ao_grupo` à lista de
`acoes_protege_campos_internos` com condição de criador. Fecharia o caminho
sem filtro, ao preço de a restrição passar a ter dona diferente do resto da
Ação — o Dono do Grupo editaria nome, data e local do que é dele, mas não a
visibilidade. Fica registrado como o recuo pronto, se a dívida abaixo incomodar.

Não há reversão de presença quando uma Ação pública vira restrita: quem
confirmou continua confirmado e continua ocupando vaga. Tirar a vaga de alguém
por uma mudança de configuração feita por outra pessoa seria pior do que a
inconsistência de ver na lista um nome de fora do Grupo.

_Alternativa recusada:_ congelar a restrição no momento da criação. Simplifica
o banco e empurra o problema para quem marcou errado — que teria de cancelar a
Ação e recriar, perdendo todas as confirmações.

### Rodada de votação não precisa de regra própria

Ação candidata é linha de `acoes` (`rodada_id` não nulo), logo já cai na policy
nova. `votos` já está fechado a "só o próprio voto" desde a feature 021, então
não há caminho por ali para descobrir o nome de uma candidata restrita.

Isto é afirmação a **verificar em teste**, não a assumir: a tarefa
correspondente abre uma sessão de fora do Grupo contra uma Rodada com candidata
restrita.

### A restrição se marca na proposta da candidata

A Ação de Grupo e a candidata de Rodada são **a mesma linha** de `acoes`: a que
vence a Rodada continua com o `id` que tinha, ganha `confirmada = true` e fica.
Então marcar a restrição na proposta cobre as duas janelas de uma vez — o
período de votação, quando a pauta interna do Grupo está mais exposta, e a Ação
que sobra depois — sem herança, sem cópia, sem segunda coluna.

O controle vive em `create_candidate_page.dart`. `create_action_page.dart` não
ganha nada: toda Ação criada por ali é avulsa, sempre foi, e o `check`
`acoes_restrita_exige_grupo` já recusaria a combinação.

_Alternativa recusada:_ marcar só na vencedora, depois da Rodada fechar.
Menor, mas deixa toda a votação pública — que é exatamente quando o Grupo expõe
o que está pensando em fazer.

_Alternativa recusada:_ restringir a Rodada inteira, com coluna em
`rodadas_votacao` e candidatas herdando. É o modelo mais fiel — a Rodada é que
é do Grupo — e custa coluna em outra tabela, migration a mais e revisão da
policy de `rodadas_votacao`. Se um dia a Rodada precisar sumir junto, é por
aqui que se volta.

## Risks / Trade-offs

- **Policy errada esconde Ação pública de todo mundo** → o teste de integração
  cobre os dois sentidos: Ação pública visível para `anon`, e Ação restrita
  invisível para `anon` e para autenticado de fora. Um dos dois sozinho não
  prova nada.
- **Custo no feed, que é a tela mais aberta** → índice novo, mais `explain
  analyze` antes/depois com número na task. Se a diferença for sentida, o
  recuo é limitar a policy às Ações com `grupo_id not null` por índice parcial,
  antes de considerar desfazer.
- **Canal lateral por contagem** → nunca responder erro onde antes havia lista;
  Ação escondida é linha ausente. Mesmo raciocínio de
  `20260809200000_votos_visibilidade.sql:36-41`.
- **Colisão com `destaque-de-acoes-distritais-e-de-grupo`** → aquela change
  decide o que entra na faixa de destaque. Como o filtro é na origem, o
  destaque herda; mas se as duas entrarem juntas, a tarefa de teste de destaque
  com Ação restrita é obrigatória, não opcional.
- **Ação restrita fica invisível para o Administrador do distrito** → aceito e
  deliberado. Administrador não tem `bypass` de RLS em nenhuma leitura hoje, e
  criar o primeiro aqui abriria um caminho de acesso amplo sem que ninguém
  tenha pedido moderação de Ação de Grupo.
- **DÍVIDA DE SEGURANÇA ACEITA — escrita sem filtro reabre tudo** → uma única
  escrita de `restrita_ao_grupo` sem filtro, feita por Administrador do
  distrito, torna pública toda Ação restrita do distrito, inclusive as que ele
  nunca pôde ler. O sentido contrário (fechar o que não se enxerga) o próprio
  Postgres barra, então a dívida é só de exposição, nunca de ocultação. É consequência direta de a policy de `update` dele não ter
  recorte por linha, e não de nada que esta change introduza — mas é esta
  change que cria dado que essa escrita pode expor. Não é defeito a corrigir
  aqui: vai para `SECURITY-AUDIT.md` com o recuo já escrito acima. O que a
  change **deve** fazer é ter o teste que prova o comportamento, para ninguém
  descobrir isso em produção.

## Migration Plan

Uma migration: coluna com `default false` (nenhuma Ação existente muda de
visibilidade), `check`, `drop`+`create` das duas policies de `select`, índice
novo, e o gatilho de "encerrada não muda restrição".

Rollback: restaurar as duas policies `using (true)` e derrubar a coluna. Como o
padrão é público, um rollback parcial (policies antigas de volta, coluna
mantida) deixa o sistema no comportamento de hoje, sem dado perdido.
