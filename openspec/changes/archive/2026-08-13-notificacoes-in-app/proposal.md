## Why

A change `convite-para-acao` deixa um buraco declarado no próprio design dela:
o convite só aparece se a pessoa convidada resolver abrir a tela de convites por
conta própria. Um convite que ninguém vê é o mesmo que não ter convidado — e
quem convidou não descobre a resposta em lugar nenhum.

Não existe nenhuma forma de aviso no app hoje. A única ocorrência de "notifica"
em `lib/` é `app.dart:37`, um comentário sobre o `GoRouter` reavaliar
`redirect`. Não há Firebase no `pubspec.yaml`, não há service worker além do que
o Flutter gera, e o SMTP está comentado no `config.toml:237-239`.

**Suposição registrada:** o pedido foi "de acordo com o tipo de notificação já
utilizado no projeto". Como não há nenhum, a leitura adotada é *nenhum
fornecedor novo, nada fora do que a stack já tem*: aviso dentro do app,
atualizado por Realtime do Supabase — `[realtime] enabled = true`
(`supabase/config.toml:87-88`) e `supabase_flutter ^2.8.0` já sustentam isso sem
dependência nova. Push de navegador e e-mail ficam de fora e viram change
própria, com a tabela desta já no formato que eles consomem.

## What Changes

- **Tabela de notificações dirigidas a uma pessoa**, escrita **só por gatilho**.
  Nenhum caminho do cliente escreve nela; o cliente só marca como lida.
- **Genérica desde o primeiro dia.** Coluna `tipo`, no mesmo padrão de
  `confirmacoes_acao.status` (`text` com `check`). Convite é o primeiro tipo;
  `log-de-mudancas` e chat entram depois sem tabela nova.
- **Três eventos nesta change**, todos de convite:

  | Evento | Quem recebe | Origem |
  |---|---|---|
  | Recebeu um convite | quem foi convidado | `insert` em `convites_acao` |
  | Convite aceito | quem convidou | `insert` em `confirmacoes_acao` de quem tinha convite |
  | Convite recusado | quem convidou | `update` de `convites_acao.recusado_em` |

- **Contador de não lidas na barra do app**, atualizado por Realtime enquanto o
  app está aberto, e tela `/notificacoes` com a lista.
- **Marcar como lida** é a única escrita que o cliente faz, e só sobre as
  próprias linhas.
- **A notificação some quando o assunto some**: convite de Ação cancelada ou
  encerrada não fica pendurado na lista.
- **Retenção**: notificação lida é apagada depois de um prazo, por `pg_cron` —
  a extensão já está instalada (`20260810110000_drenagem_capas.sql:26`). Sem
  isso, esta vira a segunda tabela do app que só cresce.

## Capabilities

### New Capabilities
- `notificacoes`: o que gera um aviso dirigido a uma pessoa, quem consegue
  ler o aviso, como o não lido é contado e zerado, o que acontece com o aviso
  quando o assunto dele deixa de existir, e por quanto tempo o aviso fica
  guardado.

### Modified Capabilities
Nenhuma. `perfil-proprio`, `privilegios-de-banco`, `publicacao-do-site` e
`suite-de-integracao` não mudam de requisito. O requisito "Tabela nova nasce
fechada" de `privilegios-de-banco` já cobre a tabela nova.

## Impact

**Depende de `convite-para-acao`.** Os três gatilhos desta change leem
`convites_acao`, que aquela change cria. Esta não entra antes daquela.

**Banco** — uma migration: tabela, RLS, índices, três gatilhos, entrada na
publicação `supabase_realtime`, e um job de `pg_cron` para a retenção. Nenhuma
tabela existente muda de coluna; nenhum gatilho existente é reescrito — os
novos entram ao lado, como `log-de-mudancas` faz.

**Realtime é superfície nova de exposição.** Hoje nenhuma tabela está na
publicação `supabase_realtime` — não há uma única referência a ela em
`supabase/`. Uma tabela publicada emite evento para quem estiver inscrito no
canal, e o filtro de quem recebe o quê depende de RLS estar valendo no canal.
Configurar errado transforma a inscrição num feed de eventos alheios. Precisa
de teste de integração com duas sessões, não de confiança na documentação.

**Não confundir com `log-de-mudancas`** (change irmã, ainda não aplicada).
`mudancas` é registro **por espaço** — de um Grupo ou de uma Ação —, sem
destinatário e sem estado de lida: quem alcança o espaço alcança o registro
inteiro. `notificacoes` é **dirigida** e **privada**, com `lida_em`.
As duas coexistem de propósito; a decisão de não derivar uma da outra está no
design.

**LGPD** — a notificação referencia `perfis(id)`, nunca o nome copiado, mesmo
motivo de `20260806140000_exclusao_de_conta.sql:14-16`. E ela carrega um fato
novo sobre relações entre pessoas ("fulano convidou você"), então tem prazo de
guarda declarado em vez de ficar para sempre.

**Código** — feature nova `lib/features/notification/`, uma tela, uma rota, um
indicador na barra, e uma inscrição Realtime cujo ciclo de vida precisa fechar
junto com o app (canal aberto sem `dispose` vaza conexão).

**Ledger** — `MAPA-DE-DADOS.md` (tabela nova, com prazo de retenção) e
`INFRA-PRODUCAO.md` (a publicação `supabase_realtime` e o job de `pg_cron` são
configuração que produção precisa ter, no mesmo espírito do que a drenagem de
capas já exige lá).
