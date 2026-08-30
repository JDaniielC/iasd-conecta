## Why

A Política de Privacidade promete que as mensagens de uma Ação são apagadas 30
dias depois do encontro. **O expurgo funciona** — está provado nos dois lados
da fronteira em `chat_expurgo_test.dart`. O problema é outro: **ninguém no
sistema sabe dizer se ele rodou** (`PENDENCIAS.md` 2.17, achado pelo agente
`promessa-vs-execucao`).

Os dois executores falham calados, cada um do seu jeito:

- `ChatRepository.purgeExpiredActionMessages` engole toda exceção, devolve `0`
  e é chamada com `unawaited`. Isso é deliberado e continua certo — faxina que
  falha não pode estragar a leitura da conversa. Mas a função devolve a
  contagem de linhas apagadas, e o app **joga fora**.
- O `pg_cron` em produção pode simplesmente não existir. `INFRA-PRODUCAO.md` já
  declara que, se o `cron.schedule` não tiver rodado no projeto hospedado, a
  consulta devolve zero linhas e **não há erro em lugar nenhum** — porque o
  segundo gatilho continua funcionando e escondendo a ausência do primeiro.

Somando: não há tabela de última execução, nem `/health`, nem alerta. A única
forma de conferir se a promessa foi cumprida ontem é ir ao banco à mão.

**O que torna isto urgente agora e não antes:** desde `mensagem-fixada`, o
expurgo tem uma **exceção** (`and fixada_em is null`), e a Política declara o
prazo, a exceção e o teto. Quanto mais condições a promessa tem, menos aceitável
é não saber se ela é cumprida. E `denuncia-como-registro` acrescenta um
**segundo** expurgo com a mesma forma.

Junto vem a dívida vizinha (`PENDENCIAS.md` 2.10, declarada no design de
`log-de-mudancas-em-grupo-e-acao`): `public.mudancas` é a única tabela do app
que **só cresce**, sem prazo e sem job. O registro é dado pessoal (`autor_id`) e
a Política fala de prazos.

## What Changes

- Toda faxina de retenção passa a **deixar rastro**: quando rodou, quanto
  apagou, quem disparou — o cron ou o app.
- Quem administra o distrito **vê** esse rastro, e vê quando a última execução
  ficou velha demais.
- `public.mudancas` ganha prazo de retenção e um executor, pelo mesmo
  mecanismo.
- O rastro tem prazo próprio. Um registro de faxina que nunca é apagado é a
  próxima tabela que só cresce.

**NÃO muda o que é apagado, nem quando.** O prazo de 30 dias, a exceção da
fixada e o teto continuam exatamente como estão.

## Capabilities

### New Capabilities
- `observador-de-retencao`: o rastro de execução das faxinas de retenção — o
  que se grava, quem lê, por quanto tempo fica, e o que a tela diz quando o
  prazo parece não estar sendo cumprido.

### Modified Capabilities
Nenhuma. O expurgo de mensagens não muda de comportamento; ele passa a ser
observado. `chat-de-grupo-e-acao` continua valendo como está.

## Impact

**Independente das outras duas changes** — não toca `mensagens` nem
`denuncias_mensagem`. Se `denuncia-como-registro` entrar antes, o expurgo dela
nasce já observado; se entrar depois, ela ganha uma linha para se registrar.

**Banco** — tabela de execuções, uma função de registro, retenção própria dela,
e ajuste nas funções de expurgo para escreverem uma linha.

**Dado pessoal** — a tabela de execuções **não** guarda dado pessoal: quando,
quanto e qual faxina. `mudancas` guarda (`autor_id`), e é dela que o prazo novo
trata.

**Legal** — se `mudancas` passa a ter prazo, a Política ganha esse prazo, e a
versão sobe. O rastro de faxina em si não é dado pessoal e não muda o texto.

**Código** — uma tela de Administrador do distrito, no molde das que já
existem.

**Ledgers** — `PENDENCIAS.md` 2.17 e 2.10; `INFRA-PRODUCAO.md` (o que produção
exige à mão continua exigindo, e agora dá para conferir de dentro do app);
`MAPA-DE-DADOS.md` (o prazo de `mudancas`); `REVISAO-JURIDICA.md` se o prazo de
`mudancas` for adotado.
