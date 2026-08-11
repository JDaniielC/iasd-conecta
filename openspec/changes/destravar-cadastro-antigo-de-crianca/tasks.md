## 1. Medir

- [ ] 1.1 Rodar em produção a consulta que conta cadastros de menor de 13 sem
      dados de responsável, e **registrar o número com a data**
- [ ] 1.2 Se for zero: registrar em `PENDENCIAS.md` § 2.3 que a situação não
      existe em produção, e fechar esta change sem código

## 2. Decidir (bloqueado por 1.1)

- [ ] 2.1 Com o número na mão, escolher entre A, B e C do `design.md`
- [ ] 2.2 Registrar a decisão em `REVISAO-JURIDICA.md` com data e motivo — ela
      tem efeito sobre dado de criança, e é o documento que guarda essas

## 3. Implementar (só se a decisão for C)

- [ ] 3.1 Escrever a spec do fluxo de autorização retroativa como change própria.
      Não improvisar aqui: a 015 evitou este texto de propósito

## 4. Sempre

- [ ] 4.1 Confirmar, por teste, que a exclusão de conta funciona para uma linha
      nessa situação — é a garantia de art. 18, VI, e ela não pode depender da
      decisão acima
