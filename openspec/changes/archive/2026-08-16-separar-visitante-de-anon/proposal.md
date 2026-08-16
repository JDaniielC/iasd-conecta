## Why

A suíte de integração chama `anon` de "Visitante" em **39 pontos de 21
arquivos**, e os dois não são a mesma coisa. `lib/core/supabase_client.dart`
faz `signInAnonymously` no arranque, antes de `runApp` — todo Visitante chega
ao banco como `authenticated`. A role `anon` é o que o PostgREST usa quando não
há `Authorization` nenhum, e o app só cai nela se aquele login anônimo falhar,
estado em que a Home é estática e não consulta o banco.

Não é confusão nova nem regressão: o login anônimo entrou em 2026-07-23
(feature 001) e `grupos_select_publico_test` no mesmo dia (feature 002). A
premissa nunca esteve certa; ela nunca tinha aparecido porque `anon` sempre
pôde ler tudo o que `authenticated` lia.

**O que isso custa hoje**, e é a razão de a change existir sozinha em vez de
virar detalhe da seguinte:

- **21 asserções provam o papel errado.** `acoes_select_publico_test` afirma
  "FR-010: papel anon (Visitante) vê a Ação sem sessão" — e o app nunca está
  sem sessão. O requisito real é sobre quem não tem cadastro, e ele continua
  sem prova.
- **18 asserções passam pelo motivo errado, ou vão passar.** As que afirmam
  RECUSA sob `asVisitor` param na porta do `grant`, não na policy que deveriam
  estar exercendo. Medido ao fechar `anon` na change `fechar-superficie-anon`:
  das 7 chamadas de `visibilidade_liderancas_test`, 3 falharam e **4 viraram
  verdes vazias**.
- **Três cópias do helper.** `acao_restrita_helper.dart` tem `asVisitor`,
  `visibilidade_liderancas_test.dart` tem o seu, `votos_visibilidade_test.dart`
  tem `_asVisitor`. Três definições da mesma ideia errada.

`fechar-superficie-anon` está parada esperando isto (branch
`change/fechar-superficie-anon`, migrations escritas e verificadas). Ela não
pode entrar antes: com a suíte apoiada na premissa errada, o diff de segurança
viria junto de 21 arquivos de teste e ninguém conseguiria ver qual das duas
coisas quebrou o quê.

## What Changes

- **Dois papéis onde hoje há um**, num helper só:
  - `asVisitor` passa a significar **sessão `authenticated` sem linha em
    `perfis`** — o que o app produz. Hoje significa `set role anon`.
  - `asAnon` é novo e significa **sem sessão nenhuma**. É para quem quer provar
    a superfície sem `Authorization`, de propósito.
- **Um Visitante de teste fiel**: `auth.users` com `is_anonymous = true` e
  **nenhuma** linha em `perfis`. Diferente de `createTestProfileWithoutAccount`,
  que é Perfil sem Conta — tem `perfis` e é outra coisa.
- **Os 39 pontos reatribuídos um a um**, cada um decidido pela pergunta "este
  queria provar Visitante ou queria provar sem sessão?". Não é substituição
  mecânica: onde a asserção era de recusa, o motivo da recusa muda e a
  asserção precisa ser reexaminada.
- **As duas cópias locais do helper somem**, e os arquivos passam a usar o
  compartilhado.
- **Nenhuma migration. Nenhuma linha de `lib/`.** Se algum teste só passa
  mudando o banco, isso é achado desta change e vira registro — não conserto
  aqui.

## Capabilities

### New Capabilities
Nenhuma.

### Modified Capabilities
- `suite-de-integracao`: ganha a requirement de que a suíte exercita **o papel
  que o app realmente usa**. Hoje a capability garante determinismo em
  paralelo; garantir o papel certo é da mesma natureza — uma propriedade da
  suíte sobre si mesma, que precisa estar escrita porque falha em silêncio.

## Impact

**Só `test/integration/`.** 21 arquivos, ~39 pontos, mais o helper
compartilhado e a remoção de duas cópias locais.

**Nenhum comportamento muda para quem usa o app.** Nenhuma migration, nenhum
arquivo de `lib/`, nenhum dado. O que muda é o que a suíte afirma estar
provando.

**Risco declarado:** um teste pode virar vermelho ao passar a exercer a policy
de verdade em vez de parar no `grant`. Isso é o resultado desejado, não um
acidente — cada vermelho é um requisito que nunca teve prova. A change fecha
com a suíte verde, e cada vermelho encontrado no caminho vira ou conserto de
teste ou registro em `PENDENCIAS.md` se for defeito de produção.

**Destrava** `fechar-superficie-anon`, que está parada na branch dela.

**Ledgers** — `PENDENCIAS.md` se algum vermelho for defeito de produção;
`SECURITY-AUDIT.md` não, porque nada aqui é vazamento: é prova ausente.
