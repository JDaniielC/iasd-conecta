## Why

Hoje não existe um jeito de chamar alguém para uma Ação **por dentro do app**.
Nas 35 migrations não há tabela de convite, e a única escrita possível em
`confirmacoes_acao` é sobre si mesmo: `confirmacoes_acao_insert_self` é
`with check (auth.uid() = usuario_id)`
(`supabase/migrations/20260723230639_acoes.sql:143-146`). Quem cria uma Ação
consegue confirmar a própria presença e mais nada — chamar as pessoas acontece
fora do app, no WhatsApp, e quem não está naquele grupo de WhatsApp não fica
sabendo.

Também não existe agenda. `perfis_select_own` restringe a leitura de `perfis` a
`auth.uid() = id` (`20260723191202_perfis_igrejas.sql:66-69`); o nome de outra
pessoa só sai por `perfil_publico(uuid)`, uma chamada por pessoa
(`lib/features/group/data/group_repository.dart:151-161` faz exatamente isso,
em `Future.wait` sobre a lista de ids). Não há de onde tirar "meus contatos" —
mas há um substituto honesto e já modelado: **os Grupos em que a pessoa
participa**. Quem divide um Grupo comigo é quem eu posso chamar.

Esta change entrega **só o convite**. A restrição de quem *vê* uma Ação de
Grupo é outra change (`acao-direcionada-a-grupo`), separada porque mexe em
`acoes_select_public` — é mudança de privacidade e precisa de teste de RLS
próprio, enquanto o convite não tira visibilidade de ninguém.

## What Changes

- **Tabela nova de convites de Ação**, com o Grupo pelo qual o convite foi
  feito gravado na própria linha. É o que torna o filtro do item 2 trivial e
  não ambíguo: o convite nasce dentro de um Grupo, então ele sabe de qual.
- **Convite aponta, não reserva vaga.** Quem foi convidado ainda precisa
  confirmar presença, e cai em `confirmado` ou `fila` pela regra que já existe.
  `confirmacoes_acao_decidir_status()`
  (`20260723230639_acoes.sql:26-88`, substituída em
  `20260724110000_dupla_missionaria.sql`) **não muda uma linha**, e nenhuma
  vaga fica presa esperando resposta.
- **Lista de quem dá pra convidar** = os participantes dos Grupos em que quem
  convida participa, agrupada por Grupo. A mesma pessoa em dois Grupos aparece
  nos dois — o Grupo é o contexto do convite, não um detalhe de exibição.
- **Uma função de banco devolve essa lista inteira numa chamada só.** O caminho
  de hoje (`fetchMembers`) é N+1: um RPC `perfil_publico` por membro. Repetido
  por Grupo, numa tela que abre com todos os Grupos da pessoa, isso vira dezenas
  de round-trips.
- **Tela de convidar**, a partir da Ação, e **tela de convites recebidos**, com
  filtro por Grupo (item 2).
- **Convidar exige Conta** (não-anônima), mesmo critério já usado em
  `declarar_lideranca` (`20260724100000_leadership.sql:26-31`). Receber convite
  não exige — qualquer Perfil recebe.
- Cancelar a Ação e sair do Grupo têm efeito definido sobre convites em aberto.
  Não sobra convite apontando para Ação cancelada.

## Capabilities

### New Capabilities
- `convite-para-acao`: quem pode convidar quem, o que o convite faz (e não faz)
  com a vaga, como a lista de contatos é derivada dos Grupos, o que a pessoa
  convidada vê e filtra, e o que acontece com o convite quando a Ação é
  cancelada, o Grupo é arquivado ou alguém sai do Grupo.

### Modified Capabilities
Nenhuma. `perfil-proprio`, `privilegios-de-banco`, `publicacao-do-site` e
`suite-de-integracao` não mudam de requisito. O requisito "Tabela nova nasce
fechada" de `privilegios-de-banco` já cobre a tabela nova — esta change o
obedece, não o altera.

## Impact

**Banco** — uma migration: tabela de convites, RLS, índices, e uma função
`security definer` de listagem de contatos. Nenhuma tabela existente muda de
coluna; nenhum gatilho existente é reescrito.

**Exposição** — muda, e é o ponto sensível desta change. Quem participa de qual
Grupo já é público hoje (`participacoes_grupo_select_public` é `using (true)`,
`20260723220703_grupos.sql:121-124`), mas o **nome** só sai um a um por
`perfil_publico`. A função nova entrega vários nomes de uma vez, então ela
precisa checar participação por dentro: só devolve membros de Grupos em que
`auth.uid()` participa. Sem essa checagem, a change viraria um dump de nomes do
distrito inteiro para qualquer conta anônima. Entra em `MAPA-DE-DADOS.md`.

**LGPD** — o convite em si é dado pessoal novo: quem chamou quem, quando, por
qual Grupo. Referencia `perfis(id)`, nunca o nome copiado — pelo mesmo motivo
de `20260806140000_exclusao_de_conta.sql:14-16`: nome desnormalizado sobrevive
à anonimização.

**Código** — feature nova de convite (domínio, repositório, providers), duas
telas, duas rotas em `lib/app.dart`, e um ponto de entrada em
`action_detail_page.dart`. `group_repository.dart` ganha nada; a listagem de
contatos é da feature nova.

**Ledger** — `MAPA-DE-DADOS.md` (tabela nova + a função que entrega nomes em
lote, com `arquivo:linha`).
