## 1. Reproduzir

- [ ] 1.1 Rodar a suíte em laço (20 execuções) registrando qual falha e com que
      mensagem. Anotar a **taxa** — é o número que diz se o conserto funcionou
- [ ] 1.2 Se não reproduzir em 20, subir paralelismo ou número de execuções até
      a taxa ficar mensurável. Não seguir sem laço vermelho

## 2. Estreitar

- [ ] 2.1 No momento da falha, capturar se as duas linhas de `perfis` do caso (d)
      existem e se a linha `9.9-anon` de `versoes_texto_legal` existe — é o que
      separa as duas hipóteses
- [ ] 2.2 Listar os arquivos capazes de alcançar aquelas linhas: por uid fixo
      repetido, por limpeza sem filtro, ou por versão de texto legal
      compartilhada
- [ ] 2.3 Confirmar o culpado desligando-o da execução e vendo a taxa cair a zero

## 3. Consertar

- [ ] 3.1 Escopar o que o culpado alcança, no padrão que a feature 014 usou:
      marca própria do arquivo em todo dado que ele cria, e limpeza por essa
      marca — nunca por padrão genérico
- [ ] 3.2 Se a limpeza rodar antes de deletes que cascateiam, movê-la para o fim:
      é o mesmo defeito que a feature 013 encontrou no seu próprio teardown

## 4. Prova

- [ ] 4.1 Laço de 20 execuções da suíte inteira, **20 verdes**, com a contagem de
      testes igual em todas
- [ ] 4.2 Registrar em `PENDENCIAS.md` § 2.6 a causa encontrada — inclusive se
      for diferente das duas hipóteses acima
