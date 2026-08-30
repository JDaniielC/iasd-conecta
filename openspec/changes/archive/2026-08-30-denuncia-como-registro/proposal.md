## Why

Os Termos de Uso dizem: *"O motivo que você escrever fica registrado como a
história do caso, inclusive depois de a mensagem deixar de existir."* A
migration de `chat-de-grupo-e-acao` repete: *"o `motivo` escrito por quem
denunciou é o que fica como registro do caso."*

**Não fica.** Medido em 2026-08-17 (`PENDENCIAS.md` 2.24), como
`authenticated`, o dono de um Grupo:

- **reescreveu o `motivo`** de uma denúncia alheia — ACEITO;
- **trocou o `denunciante_id`** da denúncia para si mesmo — ACEITO.

`information_schema.column_privileges`: `authenticated` tem `update` em `id`,
`mensagem_id`, `created_at`, `denunciante_id`, `motivo`, `estado` e
`resolvida_em`. `pg_trigger`: nenhum gatilho recortando coluna em
`denuncias_mensagem`. A tabela irmã `mensagens` tem `mensagens_so_remove`, que
recusa mudança em cinco colunas uma a uma; `denuncias_mensagem` nasceu sem o
equivalente.

Trocar `denunciante_id` é pior do que revelar quem denunciou — é **atribuir** a
denúncia a outra pessoa, e a spec diz que a denúncia não revela a quem a lê quem
denunciou.

Três dívidas vizinhas nunca decididas, todas sobre a mesma tabela:

- **Sem unicidade** (`PENDENCIAS.md` 2.23, medido em `pg_constraint` e
  `pg_indexes`): nada impede a mesma pessoa de denunciar a mesma mensagem mil
  vezes. A fila que enche é a de quem modera, e o `motivo` é texto livre lido
  por gente.
- **Sem prazo, e fora da exclusão de conta** (2.14): `mensagens` de Ação some
  em 30 dias; a denúncia sobre ela fica para sempre, e
  `excluir_minha_conta` não toca no `motivo`. As duas metades da exclusão
  discordam.
- **`denuncias_imagem.motivo` usa `trim`** (2.12), que remove só espaços: um
  motivo feito de quebras de linha passa como se dissesse alguma coisa.
  `denuncias_mensagem` já usa `btrim` com a lista explícita; a tabela mais
  velha ficou para trás.

## What Changes

- O que já foi denunciado **não se reescreve**: `motivo`, `denunciante_id`,
  `mensagem_id` e `created_at` param de aceitar alteração. O que se altera numa
  denúncia é o **desfecho**, e só ele.
- **Uma denúncia pendente por (mensagem, denunciante)**. Não é limite de ritmo
  — a decisão de não ter limite de ritmo em denúncia continua valendo e fica
  escrita —, é impedir repetir a mesma denúncia sem limitar quantas mensagens
  diferentes a pessoa denuncia.
- A denúncia ganha **prazo** contado do desfecho, e o `motivo` some quando o
  denunciante exclui a conta.
- `denuncias_imagem.motivo` passa a usar `btrim` com a lista explícita, como a
  tabela mais nova.

**BREAKING** para quem escrevia direto na API: `update` de `motivo` ou de
`denunciante_id` passa a ser recusado. Nenhuma tela do app faz isso.

## Capabilities

### New Capabilities
Nenhuma. Tudo aqui é a capability de moderação cumprindo o que já declara.

### Modified Capabilities
- `moderacao-de-mensagem`: a requirement "A denúncia tem desfecho registrado"
  ganha que o resto da denúncia é imutável; "Qualquer participante do chat
  denuncia uma mensagem" ganha a unicidade de pendente; e entra o prazo e o
  alcance da exclusão de conta sobre o `motivo`.

## Impact

**Independente de** `alcance-do-titular-sobre-texto-proprio`, que toca
`mensagens`. Podem ser feitas em qualquer ordem.

**Banco** — gatilho novo em `denuncias_mensagem` no molde de
`mensagens_so_remove`; índice único parcial; função de expurgo de denúncia com
agendamento; uma linha em `excluir_minha_conta`; `check` de `denuncias_imagem`
refeito.

**Retenção** — é a mudança de peso, e ela tem um custo declarado: **apagar o
`motivo` de uma denúncia julgada apaga o registro de por que uma mensagem foi
removida.** É a decisão que a change precisa tomar por escrito, não um conserto
óbvio.

**Legal** — a Política declara hoje que o motivo não expira. Se ele passa a
expirar, o texto muda, e a versão sobe.

**Ledgers** — `PENDENCIAS.md` 2.24, 2.23, 2.14, 2.12; `REVISAO-JURIDICA.md`;
`MAPA-DE-DADOS.md` (o `motivo` ganha prazo e ganha alcance de exclusão).
