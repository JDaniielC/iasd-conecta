## 1. Medir

- [x] 1.1 Rodar em produção a consulta que conta cadastros de menor de 13 sem
      dados de responsável, e **registrar o número com a data**. Rodada pelo dono
      do app em **2026-08-12**, no SQL Editor do painel, projeto
      `mbfcnebyxzoagwatjxuh` (`iasd-conecta-vsa`, branch `main`, PRODUCTION),
      role `postgres`: **count = 0**. O registro deixou de ser "por construção" e
      passou a ser **medido** — mesma subida de nível de evidência que o § 4.2 do
      `PENDENCIAS.md` teve quando a afirmação do controlador virou saída de painel
- [x] 1.2 Se for zero: registrar em `PENDENCIAS.md` § 2.3 que a situação não
      existe em produção, e fechar esta change sem código. Feito em 2026-08-12:
      § 2.3 marcada DECIDIDO, com as três datas que sustentam o "vazio por
      construção", a consulta de medição, e o caminho se o número mudar

## 2. Decidir (bloqueado por 1.1)

- [x] 2.1 Com o número na mão, escolher entre A, B e C do `design.md`.
      **Saída A** (não fazer nada, e registrar), decidida em 2026-08-12 pelo
      dono do app e registrada no `design.md` desta change
- [x] 2.2 Registrar a decisão em `REVISAO-JURIDICA.md` com data e motivo — ela
      tem efeito sobre dado de criança, e é o documento que guarda essas.
      Feito em 2026-08-12: seção **1-B**, ao lado da seção 1 (consentimento de
      criança), seguindo a convenção de adendo numerado que a 4-B já usava.
      Arquivo é gitignored de propósito — o repositório é público

## 3. Implementar (só se a decisão for C)

- [x] 3.1 Escrever a spec do fluxo de autorização retroativa como change própria.
      Não improvisar aqui: a 015 evitou este texto de propósito.
      **NÃO SE APLICA** — a seção inteira era condicional a "só se a decisão for
      C", e a decisão foi A. Fica registrado como não-aplicável, e não como
      feito: se o número deixar de ser zero depois do lançamento, esta tarefa
      volta a existir junto com a saída C

## 4. Sempre

- [x] 4.1 Confirmar, por teste, que a exclusão de conta funciona para uma linha
      nessa situação — é a garantia de art. 18, VI, e ela não pode depender da
      decisão acima. **O teste já existia**, e a confirmação foi verificá-lo, não
      escrevê-lo: `test/integration/autorizacao_responsavel_test.dart`, grupo
      "cadastro antigo, anterior à feature", caso "LGPD art. 18 VI: mas a
      exclusão de conta continua funcionando". A linha é semeada com a constraint
      derrubada **dentro de uma transação** (o lock é segurado até o commit — é o
      mesmo cuidado que a change `estabilizar-suite-de-integracao` teve de
      ensinar a outro arquivo). **13/13** naquele arquivo em 2026-08-12
