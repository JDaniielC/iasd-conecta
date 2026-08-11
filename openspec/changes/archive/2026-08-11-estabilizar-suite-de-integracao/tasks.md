## 1. Reproduzir

- [x] 1.1 Rodar a suíte em laço (20 execuções) registrando qual falha e com que
      mensagem. Anotar a **taxa** — é o número que diz se o conserto funcionou.
      20/20 verdes com `-j 6` (default) — não reproduziu nesse paralelismo.
- [x] 1.2 Se não reproduzir em 20, subir paralelismo ou número de execuções até
      a taxa ficar mensurável. Não seguir sem laço vermelho. Com `-j 12`,
      30 execuções: 6 falhas — 4× `consentimento_versao_carimbada_test.dart`
      caso (f), 2× `consentimentos_por_versao_test.dart` caso (d) original.

## 2. Estreitar

- [x] 2.1 No momento da falha, capturar se as duas linhas de `perfis` do caso (d)
      existem e se a linha `9.9-anon` de `versoes_texto_legal` existe — é o que
      separa as duas hipóteses. Nenhuma das duas: as linhas de `perfis`
      existiam mas com `consentimento_lgpd_versao = NULL` — o gatilho que
      carimba a versão não disparou.
- [x] 2.2 Listar os arquivos capazes de alcançar aquelas linhas: por uid fixo
      repetido, por limpeza sem filtro, ou por versão de texto legal
      compartilhada. Nenhuma das três: só `versao_texto_legal_registro_test.dart`
      desliga `perfis_carimbar_consentimento_trigger` (globalmente, fora de
      transação) — qualquer insert/update em `perfis` de outro arquivo durante
      essa janela perde o carimbo.
- [x] 2.3 Confirmar o culpado desligando-o da execução e vendo a taxa cair a zero.
      O "desligar" aqui é o próprio conserto (3.1): 30 execuções pós-conserto,
      mesma concorrência 12, 0 recorrências do defeito original.

## 3. Consertar

- [x] 3.1 Escopar o que o culpado alcança, no padrão que a feature 014 usou:
      marca própria do arquivo em todo dado que ele cria, e limpeza por essa
      marca — nunca por padrão genérico. Não se aplicava (não era limpeza sem
      filtro): o conserto real foi envolver o `disable trigger`/`update`/
      `rollback` numa transação, segurando o lock ACCESS EXCLUSIVE até o fim —
      mesmo padrão que `db_test_helper.dart` e os outros dois arquivos que
      desligam esse gatilho já usavam.
- [x] 3.2 Se a limpeza rodar antes de deletes que cascateiam, movê-la para o fim:
      é o mesmo defeito que a feature 013 encontrou no seu próprio teardown.
      Não se aplicava — a causa não era ordem de teardown.

## 4. Prova

- [x] 4.1 Laço de 20 execuções da suíte inteira, **20 verdes**, com a contagem de
      testes igual em todas. 30 execuções, concorrência 12: 0 recorrências do
      defeito original (28 verdes seguidas de início). Um outro defeito, não
      relacionado, apareceu 1x — registrado à parte (`PENDENCIAS.md` § 2.7),
      fora do escopo desta change.
- [x] 4.2 Registrar em `PENDENCIAS.md` § 2.6 a causa encontrada — inclusive se
      for diferente das duas hipóteses acima. Feito, e o achado colateral (não
      relacionado) registrado em § 2.7.
