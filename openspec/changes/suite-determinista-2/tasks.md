## 1. Identidade própria por arquivo

- [ ] 1.1 Levantar os pares que colidem hoje. Medido em 2026-08-16: **17
      identificadores em dois arquivos**; um par foi consertado em 2026-08-17,
      então esperam-se **16**. Confirmar o número antes de mexer — se der
      outro, a varredura está errada e não os arquivos
- [ ] 1.2 Para cada par, decidir **qual dos dois** troca. Regra: troca o que
      tem menos ocorrências, e no empate o mais novo
- [ ] 1.3 Trocar por prefixo conferido livre em TODA a suíte — não só nos dois
      arquivos do par. Foi assim que a troca de 2026-08-17 quase colidiu de
      novo: `c9000000` e `cb000000` já tinham dono
- [ ] 1.4 Limpar do banco de desenvolvimento as linhas com os uids antigos, que
      nenhum `tearDownAll` alcança mais
- [ ] 1.5 A cada arquivo trocado, rodar a suíte inteira. Commit por frente
      verificada, `git add` por caminho — nunca `-A`

## 2. A verificação que impede a volta

- [ ] 2.1 Teste da própria suíte que varre `test/` procurando identificadores
      no formato de UUID e falha quando um aparece em mais de um arquivo
- [ ] 2.2 A falha DIZ quais dois arquivos colidem e qual identificador — uma
      falha que só diz "há colisão" custa a mesma investigação que ela deveria
      evitar
- [ ] 2.3 Conferir que ela falha de verdade: reintroduzir uma colisão de
      propósito, ver vermelho, desfazer. Verificação que nunca falhou não está
      provada

## 3. `administradores_distrito` na eleição de herdeiro

- [ ] 3.1 **CONFIRMAR ANTES DE CONSERTAR.** `PENDENCIAS.md` 2.7 é hipótese
      medida uma vez, não confirmada por desligamento do culpado. Reproduzir
      com o Administrador de outro arquivo vivo de propósito, e ver o cenário
      12 de `account_deletion_test` passar quando deveria recusar
- [ ] 3.2 Se a hipótese se confirmar: tomar o **mesmo** `pg_advisory_lock` que
      `createTestDistrictAdmin` já toma, onde a contagem importa
- [ ] 3.3 Se NÃO se confirmar: registrar em `PENDENCIAS.md` o que a reprodução
      mostrou e não consertar o que não é a causa. É resultado válido
- [ ] 3.4 Comentário no lugar do lock explicando o recurso disputado, no molde
      do que `createTestDistrictAdmin` já tem

## 4. As 48 cópias locais de papel

- [ ] 4.1 Listar as 48 e **ler cada uma antes de trocar**. Tratar como achado
      toda diferença que não seja o `reset request.jwt.claims` — é bem possível
      que alguma esconda comportamento de que o arquivo depende
- [ ] 4.2 Trocar pela definição compartilhada de `acao_restrita_helper.dart`,
      arquivo a arquivo, com a suíte rodando entre um e outro
- [ ] 4.3 **NÃO usar `sed` em lote.** As 48 não são idênticas — 32 fazem uma
      coisa e 16 fazem outra —, e varredura cega vira defeito novo
- [ ] 4.4 Nenhuma asserção muda nesta frente. Um diff que altera expectativa de
      teste aqui é erro, e deve ser revertido e investigado à parte
- [ ] 4.5 Teste da suíte que falha quando alguém escreve definição local de
      papel, dizendo em qual arquivo
- [ ] 4.6 Conferir que ela falha de verdade, como em 2.3

## 5. A prova

- [ ] 5.1 **Laço de 30 execuções** de `dart test test/integration`, com o
      número de testes registrado. Trinta porque a falha de 2.7 apareceu na
      execução 29 de 30 — reduzir é ficar abaixo da única janela que este
      projeto já observou
- [ ] 5.2 Gates com números reais: `flutter analyze`, `flutter test test/unit
      test/widget`, `dart test test/integration`
- [ ] 5.3 Registrar no commit o número de execuções e a contagem de testes de
      cada uma — "a suíte passou" sem número não é prova aqui, e esta change é
      inteira sobre isso

## 6. Ledgers

- [ ] 6.1 `PENDENCIAS.md` 2.21, 2.20 e 2.7 fecham, com os números de
      fechamento — quantos pares, quantas cópias, e o resultado da reprodução
      de 2.7
- [ ] 6.2 A capability perde a permissão de dívida: registrar que as cópias
      deixaram de ser toleradas e que a regra virou verificável
- [ ] 6.3 **Nenhuma Novidade** — é exatamente o que o `CRITERIO-DE-NOVIDADE.md`
      manda deixar de fora. Registrado aqui para ninguém escrever uma por
      simetria com as outras changes
- [ ] 6.4 Rodar a skill `openspec-converge` e resolver o que ela achar
