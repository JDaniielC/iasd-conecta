## Why

O app não guarda histórico de nada. `acoes` tem `nome, data_hora, local,
detalhes, limite_vagas, cancelada_em` e **nenhuma coluna de atualização**
(`supabase/migrations/20260723230639_acoes.sql:5-14`); `grupos` idem
(`20260723220703_grupos.sql:1-11`). Nas 33 migrations não existe uma única
tabela de auditoria. Um `update` em `acoes` sobrescreve o valor antigo e não
deixa rastro em lugar nenhum.

O efeito para quem usa: entrou num Grupo, confirmou presença numa Ação, e a
Ação mudou de horário — não há tela, aviso ou registro que diga isso. A pessoa
descobre aparecendo no lugar errado na hora errada. Hoje o único jeito de saber
é ter memorizado o valor anterior.

Esta change entrega **só o registro de mudanças**. Ela saiu de uma exploração
maior que incluía chat de Grupo/Ação; as duas metades foram separadas porque o
log não movimenta texto livre, não toca menor de idade e não precisa de
moderação — e por isso pode entrar sozinho, antes e independente do chat.

## What Changes

- Tabela nova de registro de mudanças, escrita **só por gatilho**. Nenhum
  caminho do cliente escreve nela.
- Sete eventos passam a ser registrados, a partir do momento em que a migration
  roda:

  | Evento | Origem |
  |---|---|
  | Ação criada dentro de um Grupo | `insert` em `acoes` com `grupo_id` |
  | Ação mudou de horário ou de local | `update` em `acoes.data_hora` / `acoes.local` |
  | Ação cancelada | `update` em `acoes.cancelada_em` |
  | Alguém entrou ou saiu de um Grupo | `insert`/`delete` em `participacoes_grupo` |
  | Alguém confirmou presença ou entrou na fila | `insert` em `confirmacoes_acao` |
  | Alguém desconfirmou presença | `delete` em `confirmacoes_acao` |
  | Grupo arquivado | `update` em `grupos.arquivado_em` |

- Seção "Mudanças recentes" em `group_detail_page.dart` e em
  `action_detail_page.dart`.
- Todo Grupo e toda Ação que já existem começam com o registro **vazio**. Não
  há retroatividade: o dado que a reconstruiria nunca foi gravado.

## Capabilities

### New Capabilities
- `log-de-mudancas`: registro de eventos de Grupo e de Ação, quem vê o quê, e
  como esse registro se comporta quando um Perfil é anonimizado.

### Modified Capabilities
Nenhuma. As capabilities existentes (`perfil-proprio`, `privilegios-de-banco`,
`publicacao-do-site`, `suite-de-integracao`) não mudam de requisito.

## Impact

**Banco** — uma migration nova: tabela, índices, RLS, e gatilhos em quatro
tabelas existentes (`acoes`, `participacoes_grupo`, `confirmacoes_acao`,
`grupos`). Os gatilhos entram **ao lado** dos existentes, sem reescrevê-los —
`confirmacoes_acao_decidir_status()` e o gatilho de arquivamento continuam
intactos.

**Exposição** — nenhuma, hoje e depois. Os quatro fatos registrados já são
públicos por policy: `participacoes_grupo_select_public` e
`confirmacoes_acao_select_public` são ambas `using (true)`
(`20260723220703_grupos.sql:121-124`, `20260723230639_acoes.sql:136-139`), e
`grupos_select_public` idem. O registro não cria visibilidade nova; ele dá
forma cronológica a dado que já se lê.

O "e depois" é a parte que exige desenho, não sorte. `acao-direcionada-a-grupo`
tira `acoes` dessa lista, e um registro que **copiasse** a visibilidade de hoje
passaria a vazar: `acao_horario_alterado` com `grupo_id` revelaria que o Grupo
tem encontro marcado, e `confirmacao_confirmado` entregaria o par nominal
`(acao_id, autor_id)` — o mesmo formato que a feature 021 fechou em `votos`.
Por isso a policy deste registro **herda** a visibilidade de `acoes` por
subconsulta em vez de copiá-la (ver design). Enquanto `acoes` for público o
comportamento é idêntico ao de `using (true)`, então esta change não depende
daquela para entrar.

**Anonimização** — o registro referencia `perfis(id)`, nunca o nome copiado.
`exclusao_de_conta` anonimiza o Perfil e o conserva como âncora
(`20260806140000_exclusao_de_conta.sql:14-16`); com referência, a linha antiga
passa a exibir o Perfil anonimizado sozinha. Com nome desnormalizado, o nome
sobreviveria à anonimização — que é exatamente o que aquela migration existe
para impedir.

**Ledger** — `MAPA-DE-DADOS.md` ganha a tabela nova com `arquivo:linha`.

**Código** — repositório e providers novos na feature de Grupo e na de Ação;
duas telas ganham uma seção. Nenhum arquivo existente muda de contrato.
