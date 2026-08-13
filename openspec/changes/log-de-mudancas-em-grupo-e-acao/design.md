## Context

Ver `proposal.md` — Why. Três fatos do código moldam tudo abaixo:

1. **Nenhuma linha é apagada de verdade neste app.** Não existe policy
   `for delete` em `grupos` nem em `acoes` (só em `participacoes_grupo`,
   `confirmacoes_acao`, `acoes_sugeridas` e `fotos_capa`). Grupo se arquiva
   (`grupos.arquivado_em`), Ação se cancela (`acoes.cancelada_em`).
2. **Três dos quatro fatos a registrar são públicos e seguirão públicos.**
   `grupos_select_public`, `participacoes_grupo_select_public` e
   `confirmacoes_acao_select_public` são `to anon, authenticated
   using (true)`. `acoes_select_public` também é hoje — mas a change
   `acao-direcionada-a-grupo` a substitui por uma policy que esconde a Ação
   restrita de quem não participa do Grupo, e faz `confirmacoes_acao` herdar
   essa regra por subconsulta. Consequência para este desenho: o registro não
   pode **copiar** a visibilidade da origem, tem de **herdá-la**. Ver a decisão
   de RLS abaixo.
3. **`acoes.grupo_id` é anulável** (`20260724084300_rodada_votacao.sql:14`).
   Ação avulsa não tem Grupo onde um registro apareceria.

## Goals / Non-Goals

**Goals:**
- Uma origem de verdade cronológica para os seis eventos, consultável por Grupo
  e por Ação com um índice, sem `join`.
- Impossível forjar: o cliente não escreve no registro por nenhum caminho.

**Non-Goals:**
- Valor anterior e valor novo. O registro diz *que* mudou, não *de que para
  que*. Guardar o par exigiria uma coluna `jsonb` ou uma tabela por campo, e a
  tela não usaria.
- Registro de desconfirmação de presença. Ver Risks.
- Notificação (push, e-mail, badge). O registro é passivo: quem abre a tela vê.
- Retroatividade. Ver spec, "Não há registro retroativo".

## Decisions

### Uma tabela `mudancas`, não uma por origem

```
public.mudancas
  id          uuid pk
  grupo_id    uuid null  → grupos(id)  on delete cascade
  acao_id     uuid null  → acoes(id)   on delete cascade
  tipo        text not null check (tipo in (...))
  autor_id    uuid null  → perfis(id)
  created_at  timestamptz not null default now()
```

Alternativa recusada: uma tabela por origem (`mudancas_acao`,
`mudancas_participacao`, …). A tela precisa das duas intercaladas em ordem de
tempo; com tabelas separadas, todo carregamento vira `union all` + `order by`
sobre o resultado, e nenhum índice cobre a ordenação final.

### Evento de Ação que pertence a um Grupo grava **as duas** chaves

Uma Ação com Grupo gera registro com `acao_id` **e** `grupo_id` preenchidos,
copiados de `acoes.grupo_id` no momento do gatilho. Consequência: o feed do
Grupo é um único `where grupo_id = ? order by created_at desc`, sem tocar
`acoes`. O feed da Ação é `where acao_id = ?`.

Alternativa recusada: só `acao_id`, e resolver o Grupo por `join` na leitura.
Custa um `join` em toda abertura de tela para economizar uma coluna anulável.

Consequência aceita: se a Ação for movida de Grupo depois, os registros antigos
continuam apontando para o Grupo onde o evento aconteceu. Isso é o
comportamento correto — o evento aconteceu lá.

### `tipo` é `text` com `check`, não tipo `enum` do Postgres

Precedente no projeto: `confirmacoes_acao.status text check (status in
('confirmado','fila'))` e `perfis.genero text check`. Um `enum` do Postgres
exige `alter type` para crescer, que não roda dentro de transação em versões
mais antigas e complica migration. Valores:

`acao_criada`, `acao_horario_alterado`, `acao_local_alterado`,
`acao_cancelada`, `participacao_entrou`, `participacao_saiu`,
`confirmacao_confirmado`, `confirmacao_fila`, `confirmacao_cancelada`,
`grupo_arquivado`.

Chave de banco em português, identificador Dart em inglês (`ChangeLogEntry`,
`ChangeLogRepository`) — Princípio I.

### Gatilho `after`, na mesma transação, sem tratamento de erro

Um gatilho por tabela de origem, `after insert/update/delete`, decidindo o
`tipo` a partir das colunas que mudaram. Nenhum `exception when others then
null`: se a gravação falhar, a transação inteira volta atrás e a operação de
origem falha junto.

Alternativa recusada: registro assíncrono ou tolerante a falha, para não deixar
o registro derrubar uma alteração de Ação. Recusada porque produz buraco
silencioso — a tela mostraria um histórico incompleto sem nenhum sinal de que
está incompleto. É o modo de falha que a migration `nome_valido_security_definer`
foi escrita para eliminar em outro lugar do schema
(`20260806090000:7`: "falha em silêncio, que é o pior modo de falhar").

### Os gatilhos entram ao lado dos existentes, não dentro deles

`confirmacoes_acao_decidir_status()` é `before insert` e decide
`confirmado` vs `fila` sob `for update`. O gatilho de registro é `after
insert` e lê `new.status` **já decidido**. Não se mexe na função existente.

Idem para o arquivamento de Grupo e para as policies de `acoes`.

### `autor_id` referencia `perfis(id)` e é anulável

Referência, nunca cópia do nome — para que a anonimização de
`exclusao_de_conta` (`20260806140000:14-16`) propague sozinha.

Anulável porque nem todo evento tem autor identificável no momento do gatilho:
a saída de Grupo pode ser executada pelo dono sobre outra pessoa
(`participacoes_grupo_delete_self_or_dono`), e uma remoção em cascata não tem
`auth.uid()`. Onde há autor, é `auth.uid()`; onde não há, é nulo, e a tela
escreve a frase sem sujeito.

Para `participacao_entrou` e `participacao_saiu`, `autor_id` é quem **executou**
a operação. O Perfil **afetado** é o mesmo em 100% das entradas (só se entra
sozinho: `participacoes_grupo_insert_self`), mas não nas saídas. Como a spec
só exige registrar o evento, e a lista de participantes vigente já está na
mesma tela, não se guarda o afetado separado do autor.

### Desconfirmação é registrada, senão o registro mente

`confirmacoes_acao` tem policy `for delete` (`20260723230639:147`): quem
confirmou pode desconfirmar. Sem um evento para isso, `confirmacao_confirmado`
ficaria no registro para sempre e a seção diria "Ana confirmou presença" depois
de Ana já ter saído — um registro que afirma o contrário do estado atual é pior
que registro nenhum, porque ninguém desconfia dele.

Gatilho `after delete` em `confirmacoes_acao`, gravando `confirmacao_cancelada`.
O `old.status` não entra no tipo: sair da fila e desconfirmar presença são o
mesmo fato para quem lê ("não vem mais"), e distinguir criaria dois tipos que a
tela renderizaria com a mesma frase.

### RLS: uma policy de `select` que herda a visibilidade da origem, e nada mais

```
mudancas_select_conforme_origem   for select  to anon, authenticated
  using (
    acao_id is null
    or exists (select 1 from public.acoes a where a.id = acao_id)
  )
```

Nenhuma policy de `insert`, `update` ou `delete`. Com RLS ligado e sem policy,
Postgres recusa a operação — que é exatamente o requisito "o registro é escrito
só pelo banco". Os gatilhos não são afetados: rodam como o dono da função.

**Por que não `using (true)`.** A versão anterior deste desenho era
`mudancas_select_public ... using (true)`, justificada por "espelha a
visibilidade das quatro tabelas de origem". Essa frase deixa de ser verdadeira
assim que `acao-direcionada-a-grupo` entra, e o registro passa a vazar dois
níveis:

- `acao_criada`, `acao_horario_alterado` e `acao_cancelada` carregam `grupo_id`
  público. Sem filtro, qualquer pessoa da internet lê que o Grupo X tem
  encontro marcado e que ele mudou de hora — que é exatamente o que a reunião
  de liderança queria esconder.
- Pior: `confirmacao_confirmado` guarda o par nominal `(acao_id, autor_id)`. É
  o mesmo formato de vazamento que a feature 021 fechou em `votos`
  (`20260809200000_votos_visibilidade.sql:8-17`), onde três requisições com a
  chave pública montavam "Clara Demo votou em Entrega de cestas".

A subconsulta roda sob a RLS de `acoes` para a mesma sessão, então **a regra de
visibilidade de Ação continua existindo num lugar só**. Duplicar aqui a
condição de participação seria a segunda cópia que ficaria para trás na
primeira mudança.

**Correta nos dois mundos, e por isso sem dependência de ordem.** Enquanto
`acoes_select_public` for `using (true)`, o `exists` é verdadeiro para toda
linha e o comportamento é idêntico ao de `using (true)`. Quando a restrição
entrar, o registro aperta sozinho, sem migration nova. Esta change **não**
precisa esperar `acao-direcionada-a-grupo`.

Linha com `grupo_id` e sem `acao_id` (`participacao_entrou`,
`participacao_saiu`, `grupo_arquivado`) continua pública, porque
`participacoes_grupo` e `grupos` continuam públicas. Apertar essas sem apertar
a origem seria teatro: o mesmo fato continuaria legível lá.

O nome muda junto com a regra, pelo precedente que a feature 021 registrou
(`:21-27`): uma policy chamada `_select_public` que não é pública é pior que
policy sem nome, e a troca de nome faz qualquer referência antiga falhar
visivelmente.

`acoes` tem `on delete cascade` para `mudancas`, então `exists` falso significa
**escondida**, nunca **apagada** — a linha de origem some junto com o registro.
A subconsulta resolve pela PK de `acoes`, um índice único por linha avaliada.

### Índices parciais, um por eixo de leitura

```
create index mudancas_por_grupo on public.mudancas (grupo_id, created_at desc)
  where grupo_id is not null;
create index mudancas_por_acao  on public.mudancas (acao_id, created_at desc)
  where acao_id is not null;
```

Precedente de índice parcial: `grupos_ativos` (`20260809230000:41`).

### A seção carrega um limite fixo, não a tabela inteira

20 registros mais recentes, com indicação de que há mais. Sem isso, o custo de
abrir o detalhe de um Grupo cresce com a idade dele — e o registro é a única
tabela do app que só cresce.

### Código Dart em `lib/features/change_log/`

Feature própria, com `data/`, `domain/`, `presentation/`, no mesmo formato das
outras 12. Alternativa recusada: duplicar em `features/group/` e
`features/action/` — o mesmo modelo e o mesmo repositório serviriam as duas, e
duas cópias divergem.

`group_detail_page.dart` e `action_detail_page.dart` só consomem o widget de
seção. Nenhum contrato existente muda.

## Risks / Trade-offs

**Registro de participação sem o Perfil afetado.** `participacao_saiu` guarda
quem **executou** a saída, não necessariamente quem saiu — o dono do Grupo pode
remover outra pessoa (`participacoes_grupo_delete_self_or_dono`). A frase na
tela fica "alguém saiu do Grupo" nesse caso. → A lista de participantes
vigente está na mesma tela. Guardar o afetado separado do autor é uma coluna a
mais que só esse evento usaria.

**Registro vazio em todo Grupo existente no dia 1.** → A tela diz que o
registro começa agora (spec, "Não há registro retroativo"). Sem esse texto, a
seção vazia lê como bug.

**Cascata de remoção inserindo em tabela já esvaziada.** Se um dia existir
remoção física de Grupo ou de Ação, a cascata apaga `participacoes_grupo`, o
gatilho tenta inserir em `mudancas` apontando para um Grupo em remoção, e o
resultado depende da ordem de processamento da cascata. → Hoje não há caminho:
não existe policy `for delete` em `grupos` nem em `acoes`. O gatilho de
`participacoes_grupo` verifica a existência da linha de origem antes de
inserir, defensivamente, e um teste cobre a remoção física via superusuário.

**Uma tabela que só cresce.** Sem retenção, `mudancas` acumula
indefinidamente. → Volume por evento é pequeno (5 colunas, sem texto livre) e
os índices são parciais e ordenados. Retenção fica registrada como dívida em
`PENDENCIAS.md`, não se resolve aqui.

## Migration Plan

Migration puramente aditiva: cria tabela, índices, policy de `select`, quatro
funções e os gatilhos. Nenhuma tabela existente muda de coluna; nenhuma função
existente é reescrita.

Rollback: `drop trigger` nos quatro, `drop function`, `drop table mudancas
cascade`. Nada fora da migration depende dela — as telas degradam para a seção
ausente se o repositório não encontrar a tabela, mas o caminho suportado é
reverter o build junto.

Ordem de deploy: migration antes do build web, como as anteriores. O app antigo
ignora a tabela nova; o app novo contra o banco antigo quebraria a seção — por
isso a migration vai primeiro.
