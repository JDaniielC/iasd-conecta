## Why

Quatro pendências abertas em `PENDENCIAS.md` (§ 2.31, § 2.32, § 2.33, § 2.35)
são a mesma frase dita de quatro jeitos: **o app afirma o que não conferiu.**

- **§ 2.35** — das 20 escritas `update`/`delete` que o cliente manda ao Supabase,
  **13 não conferem linhas afetadas**. Uma foi fechada em `cobertura-e-tdd`;
  restam 12. Medido em 2026-08-20, sob o papel `authenticated` que o app usa:
  `DELETE 0`, sem exceção, linha intacta. A tela recarrega e diz que fez.
- **§ 2.31** — `ProfileGuard` decide com `ref.read(hasProfileProvider).value ??
  false`. Um `FutureProvider` nunca lido antes nasce `AsyncLoading`, `.value` é
  `null`, e o guard afirma "você não tem Perfil" sobre uma resposta que ainda
  não chegou. Só não quebra hoje porque `lib/app.dart:47` faz
  `ref.listen(hasProfileProvider, ...)` no arranque — a corretude do guard mora
  em outro arquivo, que ninguém tem motivo para preservar.
- **§ 2.32** — a change `cobertura-e-tdd` achou **três estouros de layout a 360**
  (229px, 72px, 39px) nas primeiras telas que passaram a ser julgadas nessa
  largura. As outras ~25 telas nunca foram julgadas, e nenhum gate as julga:
  cobertura mede execução, não largura.
- **§ 2.33** — `make coverage` mede unidade e widget e reporta `3511/4131 =
  85,0%`. Esse número **não é a cobertura do projeto**: 695 linhas de
  `lib/features/*/data/` estão fora do denominador, e quem as prova é
  `dart test test/integration`, que não entra na medição. Ninguém nunca mediu o
  número verdadeiro.

O caso mais grave do § 2.35 não é silêncio — é **ambiguidade**.
`confirmacoes_acao_delete_self` recusa desistir de Ação encerrada
(`and not public.acao_encerrada(acao_id)`, migration `20260809174740`). Zero
linhas ali significa "você não estava confirmada" **ou** "a Ação encerrou e a
recusa foi deliberada", e a tela hoje mostra a mesma coisa nos dois casos.

## What Changes

- **Nove escritas passam a conferir linhas afetadas** e a lançar com a frase que
  a tela mostra: `cancelAction`, `CoverPhotoRepository.remove`, `archiveChurch`,
  `updateGroup`, `removeMember`, `transferOwnership`,
  `resolveByRemovingImage`, `updateMyProfile`, e `withdraw`.
- **Três continuam podendo afetar zero linhas**, com o motivo escrito no código:
  `leave`, `dismiss` e `markRead`. Nelas o filtro já inclui a condição que a
  escrita muda (`.eq('estado', pendente)`, `.isFilter('lida_em', null)`) ou a
  operação é remoção do próprio vínculo — zero quer dizer "já estava assim".
- **`withdraw` desambigua as duas causas** antes de decidir a frase. É a única
  das nove que precisa de mais que `.select()`.
- **`ProfileGuard` passa a esperar a resposta** em vez de ler um valor que pode
  não ter chegado. Muda de síncrono para assíncrono, e com ele os pontos de
  chamada.
- **Toda tela do app ganha julgamento de largura de celular** — 360, a mesma das
  dez telas de `cobertura-e-tdd`. Onde houver estouro, ele é consertado.
- **`make coverage-full`**: alvo novo que sobe o Supabase local, roda as três
  suítes com cobertura e reporta o número verdadeiro do projeto, sobre as 4824
  linhas. **Fora do gate rápido do CI**, para não herdar o problema de ciclo de
  vida que fez `travar-deploy-com-teste-vermelho` recusar isso em `deploy-web`.
  `make coverage` continua como está e continua sendo o gate.

Nenhuma mudança de regra de domínio. As telas passam a **dizer a verdade** sobre
escritas que já se comportavam assim no banco. Nada de **BREAKING** no schema.

## Capabilities

### New Capabilities

- `o-que-a-tela-pode-afirmar`: o que uma tela tem o direito de dizer que
  aconteceu, e o que ela DEVE ter conferido antes de dizer. Cobre escrita
  recusada pela RLS, o caso em que zero linhas é legítimo, o caso em que zero é
  ambíguo, e a decisão tomada sobre resposta que ainda não chegou.

### Modified Capabilities

- `disciplina-de-teste`: a requirement "O denominador da cobertura é declarado"
  ganha a medição completa (o número do gate não é o número do projeto, e o
  projeto passa a ter um número); e entra requirement nova sobre julgar largura
  de celular, que é a única coisa neste repo que pega estouro de layout.

## Impact

- `lib/features/*/data/` — nove métodos em seis repositórios passam a lançar.
  As telas que os chamam já tratam exceção; o que muda é a exceção passar a
  acontecer.
- `lib/features/profile/domain/profile_guard.dart` — assinatura muda para
  `Future<bool>`. Cinco pontos de chamada acompanham.
- `test/integration/` — um teste por escrita, com asserção sobre `affectedRows`,
  nunca `throwsA`. Escopado por UUID próprio, e **sem Administrador do distrito
  onde der para evitar**: `excluir_minha_conta` transfere Grupo para o
  Administrador mais antigo, e um Administrador vivo num arquivo vira herdeiro
  dos Grupos de `account_deletion_test` — medido em 2026-08-20.
- `test/widget/` — varredura de largura sobre as telas ainda não julgadas.
- `Makefile`, `CLAUDE.md` — alvo `coverage-full` e o que ele significa.
- `PENDENCIAS.md` — § 2.31, § 2.32, § 2.33 e § 2.35 fecham; § 2.34 (a variação
  de 0,24pp) fica aberta, fora do escopo desta change.
- `lib/main.dart` e a camada `data/` entram no denominador da medição completa,
  então o número dela nasce mais baixo que 85,0% e isso é o esperado.
