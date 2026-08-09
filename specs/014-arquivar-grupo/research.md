# Research: Arquivar Grupo

**Feature**: 014-arquivar-grupo | **Date**: 2026-08-09

---

## D-001 — Arquivar é uma RPC `security definer`, não trabalho do cliente

**Decisão**: duas funções de banco — `arquivar_grupo(p_grupo_id)` e
`desarquivar_grupo(p_grupo_id)` — ambas `security definer`, validando quem pode logo na
primeira linha. O cliente chama e pronto.

**Rationale**: não é preferência, é o que as políticas atuais permitem. Três portas fechadas:

| Política | Onde | Fecha o quê |
|---|---|---|
| `grupos_update_dono` — `using (auth.uid() = dono_id)` | `20260723220703_grupos.sql:115` | O Administrador do distrito não altera Grupo alheio |
| `acoes_update_criador` — `using (auth.uid() = criador_id)` | `20260723230639_acoes.sql:131` | O Dono não cancela Ação que outra pessoa criou no Grupo dele |
| RLS de `rodadas_votacao` | `20260724084300_rodada_votacao.sql:197+` | Idem para encerrar Rodada de terceiro |

Para o cliente fazer o trabalho, as três precisariam ser afrouxadas — o que daria ao Dono
poder de escrita sobre Ação alheia em caráter permanente, para servir a uma operação que ele
faz uma vez na vida. Uma função com um propósito é muito menos superfície.

**O segundo motivo é atomicidade**: arquivar faz quatro coisas. Em quatro chamadas do cliente,
uma falha no meio deixa Ações canceladas dentro de um Grupo que continua ativo — estado pior
do que não ter arquivado. Função é transação.

**Precedente na casa**: `excluir_minha_conta` (feature 009) resolve o mesmo tipo de problema
do mesmo jeito, e a 011 confirmou que `security definer` não passa por RLS.

**Alternativa descartada** — *soft delete no cliente com políticas novas*: exigiria uma
política de update em `acoes` do tipo "o Dono do Grupo pai também pode", que passaria a valer
**sempre**, não só ao arquivar.

---

## D-002 — O estado são duas colunas em `grupos`, e nada é apagado

**Decisão**: `arquivado_em timestamptz` e `arquivado_por uuid references perfis(id)`.
Arquivado é `arquivado_em is not null`. Nenhuma linha é removida de lugar nenhum.

**Rationale**: espelha `acoes.cancelada_em` e `perfis.anonimizado_em`, que já existem — o app
tem um padrão para "isto saiu de circulação sem deixar de ter existido", e criar um terceiro
jeito seria confundir. `arquivado_por` responde "quem fez isso", que é o que o Administrador
precisa para decidir se desarquiva (FR-019).

**Por que não uma tabela `grupos_arquivados`**: obrigaria toda consulta de Grupo a fazer join
para saber se está ativo. Duas colunas na própria tabela é a leitura mais simples que atende.

**Desarquivar** é `arquivado_em = null, arquivado_por = null`. O registro de quem arquivou
some junto — o Grupo voltou, e guardar histórico de arquivamentos não foi pedido.

---

## D-003 — A Rodada aberta encerra sem apurar, e isso é escrito à mão

**Decisão**: dentro de `arquivar_grupo`, para cada Rodada aberta do Grupo:

```
update rodadas_votacao set fechada_em = now(), vencedora_id = null  -- sem vencedora
delete from acoes where rodada_id = <a rodada> and confirmada = false  -- todas as candidatas
```

**Rationale, e este é o ponto mais importante do arquivo**: existe a tentação de reusar
`fechar_rodada_se_devido(p_rodada_id, true)`, que já sabe fechar Rodada. **Não serve.** Ela
**apura** (`20260724084300_rodada_votacao.sql:168-184`): escolhe a mais votada, resolve empate
por sorteio, marca a vencedora como Ação confirmada e descarta só as perdedoras.

Chamá-la ao arquivar produziria uma **Ação confirmada dentro de um Grupo que acabou de sair do
ar** — um encontro marcado por um Grupo que não existe mais. Não tem leitura sensata.

O arquivamento é descarte **total**: nenhuma vencedora, todas as candidatas fora.

**Registro honesto**: esta decisão foi tomada por mim, não pelo usuário, e está marcada em
Assumptions da spec como a mais discutível da feature. A alternativa seria apurar antes de
arquivar, deixando a vencedora virar uma Ação avulsa órfã — o que exigiria decidir quem
cancela essa Ação depois, e o glossário não prevê Ação de Grupo sem Grupo.

**Consequência para o Princípio IV**: o desempate por sorteio **não roda** neste caminho, e o
descarte de candidatas é total em vez de parcial. Os dois viram teste de integração próprio.

---

## D-004 — Os quatro números da confirmação vêm do cliente, sem RPC nova

**Decisão**: a prévia de FR-003 — Ações futuras a cancelar, presenças confirmadas nelas,
Rodadas abertas a encerrar, participantes — é montada com consultas normais do cliente, não
com uma função de banco.

**Rationale**: as quatro tabelas envolvidas já têm leitura pública:
`acoes_select_public`, `confirmacoes_acao_select_public`, `rodadas_votacao_select_public`,
e a de `participacoes_grupo`. Os números não são segredo — são o que qualquer pessoa veria
navegando. Criar uma RPC só para contar seria mais uma superfície de banco para manter, sem
ganhar nada.

**Corrida aceita**: entre ver os números e confirmar, alguém pode confirmar presença numa das
Ações. A prévia é informativa; quem faz o trabalho de verdade é a RPC, que age sobre o estado
do momento. Mostrar um número com um segundo de atraso é aceitável; travar o banco para
mostrá-lo não é.

**O que a prévia NÃO faz**: nada. É só leitura. FR-006 e SC-002 exigem que desistir da
confirmação altere zero registros — com a contagem no cliente, isso é verdade por construção.

---

## D-005 — Participações ficam onde estão, e "suspensa" é ausência de permissão

**Decisão**: `participacoes_grupo` **não é tocada** pelo arquivamento. O que impede a pessoa de
participar, propor ou votar é o Grupo estar arquivado, verificado em cada operação.

**Rationale**: FR-017 pede que as participações não sejam apagadas e FR-021 pede que o
desarquivamento as devolva sem ninguém precisar entrar de novo. Se elas fossem apagadas,
desarquivar exigiria guardar uma lista de quem estava dentro — um segundo registro do mesmo
fato, que um dia divergiria.

Não apagar resolve os dois de graça: elas continuam lá, e "suspensa" passa a significar
simplesmente que nenhuma operação as aceita enquanto o Grupo está arquivado.

**Onde a verificação entra**: nas políticas de insert de `participacoes_grupo`, `votos` e das
Ações candidatas, e nas telas. As políticas são o que executa; a tela é só cortesia.

---

## D-006 — Onde o Grupo arquivado precisa sumir, e onde ele não pode sumir

**Decisão**: filtrar `arquivado_em is null` na **listagem** de Grupos, e conferir cada outro
consumidor um a um. O Grupo arquivado continua alcançável por link direto (FR-013).

**A lista de consumidores, que a spec não enumera**:

| Onde | O que fazer | Se esquecer |
|---|---|---|
| Listagem de Grupos | filtrar | O Grupo continua aparecendo — FR-010 quebrado, visível |
| Exibição do Líder/Diretor do Ministério | filtrar | **A identificação pública continua no ar, para Visitante.** FR-016 quebrado **em silêncio** — é o pior caso |
| Resolução de Igreja da lista de Ações (`action_providers.dart`, lê `grupos.igreja_id`) | não filtrar | Ações passadas do Grupo perderiam a Igreja e sairiam do agrupamento |
| Detalhe do Grupo por link | **não** filtrar | FR-013 pede que abra, mostrando que está arquivado |
| Rodadas fechadas do Grupo, por link | **não** filtrar | FR-014 pede que a apuração continue lá, intacta |

**O caso do Líder é o risco central da feature** e está registrado como risco 4 do plano:
`liderancas` não é tocada de propósito, então nada no banco impede a exibição. Só a consulta
filtra. Falha silenciosa, invisível a teste de unidade, e o dado exposto é justamente o que a
spec diz que sai do ar.

**Alternativa descartada** — *apagar as declarações de liderança ao arquivar*: destruiria
histórico de quem foi responsável perante a igreja, para resolver um problema de exibição.
