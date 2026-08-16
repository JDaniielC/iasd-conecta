## Why

`anon` é a role que o PostgREST usa em requisição **sem** `Authorization`, e a
chave publicável que a alcança vai dentro do JavaScript publicado. Hoje ela
chega mais longe do que ninguém decidiu: `PENDENCIAS.md` § 2.18 (seis funções
`security definer`) e § 2.8 (`participacoes_grupo` inteira), mais o que a
medição de 2026-08-16 acrescentou aos dois.

**A medição que muda o custo do conserto:** no app, todo Visitante é
`authenticated`, não `anon`. `supabase_client.dart` faz `signInAnonymously` no
arranque, e `image_report_repository.dart:15-22` documenta o bug medido que veio
de confundir os dois — *"todo Visitante tem `currentUser`, inclusive quem nunca
criou Perfil"*. Logo `anon` só aparece em duas situações: `curl` com a chave
publicável, e o caminho degradado em que o login anônimo falhou — onde, por
decisão registrada em `supabase_client.dart:47-51`, a Home é **estática**.

Estreitar `to anon, authenticated` para `to authenticated` quase não custa nada
ao app. É a razão de esta change ser barata, e a razão de ela nunca ter sido
feita: o custo parecia alto porque "sem login" foi lido como `anon`.

**Achado novo, que não está em nenhum ledger.** `nome_valido(text)` é
`security definer` e nasceu sem `grant` nenhum, então herdou o `execute` de
`PUBLIC`. A tabela `palavras_bloqueadas` tem RLS sem policy — `anon` lendo
direto leva `42501 permission denied`. Mas pela função ela é sondável palavra a
palavra. Medido em 2026-08-16 contra o banco local, como `anon`:
`nome_valido('idiota')` = `false`, `'burro'` = `false`, `'estupido'` = `false`,
`'Maria Silva'` = `true`. A lista tem 5 palavras e é enumerável por quem abrir
o bundle.

**Por que agora:** a change `filtro-e-intervalo-de-mensagem` cria uma **segunda**
lista secreta lida por função `security definer`. Sem esta change antes, ela
nasce com o mesmo oráculo, e aí são duas listas para consertar em vez de um
padrão para travar.

## What Changes

- **`revoke execute ... from public`** nas funções `security definer` que
  alcançam `anon` sem que ninguém tenha decidido isso. Medido: 6 alcançáveis,
  das quais 3 nunca tiveram `grant` (`autor_de_mudanca`, `nome_valido`,
  `versao_texto_legal_vigente` — esta última `invoker`) e 3 receberam `grant`
  sem `revoke` (`declarar_lideranca`, `decidir_lideranca`,
  `fechar_rodada_se_devido`). `perfil_publico`, `acao_encerrada` e
  `limiar_crianca` têm `anon=X` explícito e **continuam** — são públicas por
  desenho.
- **BREAKING para chamada externa, não para o app**: as 13 policies de `select`
  que hoje endereçam `anon` passam a endereçar só `authenticated`, tabela a
  tabela, cada uma com o motivo escrito. Nenhuma tela muda, porque o app nunca
  chega ao banco como `anon`.
- **Um teste de inventário**, e é ele que faz esta change valer mais que o
  conserto: enumera toda função `security definer` e toda policy de `select` do
  schema, e falha se alguma alcançar `anon` sem estar numa **lista de exceções
  declarada no próprio teste**, cada linha com o motivo. Função ou policy nova
  esquecida quebra o teste. Sem isso, a sétima ocorrência é questão de tempo —
  foram três até aqui (`20260806090000`, `20260813200000`, e estas).
- **O caminho degradado ganha prova**: rodar o app com o `signInAnonymously`
  falhando de propósito e confirmar que a Home estática aparece. É a única
  situação em que o app é `anon`, e ela nunca foi exercitada.
- **Correção de ledger**: `PENDENCIAS.md` § 2.1 está desatualizado. Medido em
  2026-08-16, `authenticated` só tem `update` em `apelido`,
  `consentimento_lgpd_igreja_aceito_em`, `igreja_id`, `nome` e `telefone`, e
  `has_table_privilege(... 'update')` na tabela é `false`. A change
  `endurecer-grant-update-perfis` fechou isso em 12/08 e o ledger não foi
  atualizado — mesmo modo de falha da § 2.13, corrigida em 16/08.

**Não entra**, e é declarado: § 2.19 (o canal de Realtime entrega envelope de
atividade a `anon`) fica aberta. Ela não se resolve por `revoke` nem por policy
— é configuração do servidor de Realtime, e misturá-la aqui traria uma frente
com outra forma de prova.

## Capabilities

### New Capabilities
- `superficie-sem-login`: o que uma requisição **sem sessão nenhuma** alcança do
  banco, e a distinção entre Visitante (que tem sessão e é `authenticated`) e
  `anon` (que não tem). É a distinção que fez esta superfície crescer sem
  ninguém decidir, e ela precisa de um lugar próprio para não ser reaprendida.

### Modified Capabilities
- `privilegios-de-banco`: ganha a requirement de que **função nova não nasce
  chamável por papel público**. Hoje a capability cobre `TRUNCATE`,
  `REFERENCES` e `TRIGGER` em tabela; o `execute` de função é o mesmo piso de
  privilégio, com o mesmo modo de falha (o padrão do Postgres concede, e o
  `grant` seguinte não revoga).

## Impact

**Banco** — uma migration com `revoke` nas funções e `alter policy ... to
authenticated` nas 13. Nenhuma tabela nova, nenhuma coluna nova, nenhuma função
nova.

**Nenhum dado pessoal novo, e nenhum a menos.** A change não muda o que se
grava; muda quem alcança o que já está gravado. Três das 13 expõem pessoa e são
o motivo prático: `participacoes_grupo` (quem participa de qual Ministério),
`administradores_distrito` (quem manda no distrito, por nome) e
`confirmacoes_acao` (quem vai a qual encontro).

**Não contradiz `visibilidade-de-acao`.** Aquela capability diz "Ação é pública
por padrão — todo mundo, inclusive sem login". "Sem login" ali significa **sem
Perfil e sem Conta**, que é o Visitante, e o Visitante continua vendo tudo o que
via. A frase é ambígua o bastante para alguém reverter esta change achando que
ela quebra aquela requirement, e por isso a distinção entra como requirement
própria em `superficie-sem-login` em vez de virar comentário de migration.

**Ledgers** — `SECURITY-AUDIT.md` (o oráculo de `nome_valido`, que é achado
novo), `PENDENCIAS.md` (§ 2.18 e § 2.8 fecham; § 2.1 é correção de registro;
§ 2.19 continua aberta com o motivo escrito).

**Ordem** — antes de `filtro-e-intervalo-de-mensagem`, pelo motivo em Why.

**Legal** — nada. Fechar acesso não muda o que se promete ao titular; a
Política já não afirma que essas tabelas sejam públicas.
