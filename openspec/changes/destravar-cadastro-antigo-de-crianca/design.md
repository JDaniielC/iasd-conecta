## Context

A feature 015 passou a exigir nome do responsável, contato dele e autorização
para menor de 13. A check constraint vale para a linha inteira, então cadastro
antigo sem esses campos recusa qualquer `update`.

A spec da 015 **excluiu de propósito** pedir autorização retroativamente. Esta
change existe para decidir se aquela exclusão continua valendo agora que o app
vai ao ar.

## Goals / Non-Goals

**Goals:**
- Saber o número real em produção.
- Registrar a decisão, qualquer que seja, com data e motivo.

**Non-Goals:**
- Afrouxar a constraint. Ela é o que faz a exigência valer; contorná-la para
  conveniência de manutenção desfaz a feature 015.

## Decisions

**PENDENTE — decisão do dono do app.** Três saídas, e o número de produção pode
decidir sozinho:

**A. Não fazer nada, e registrar.** Se a consulta devolver zero, é a resposta
certa e a change fecha aqui. Custo: uma consulta. Risco: se aparecer um caso
depois, o caminho é o e-mail de contato, que já funciona.

**B. Corrigir caso a caso, à mão, pelo e-mail.** Serve para número pequeno.
Custo: nenhum código; o esforço é humano e por pessoa. Risco: alguém precisa
estar disponível para responder, e isso não escala nem tem prazo.

**C. Pedir a autorização dentro do app a quem já está cadastrado.** É o único que
resolve sozinho, e é o mais caro: tela nova, texto novo, e a pergunta difícil de
**como falar com a criança** sobre pedir autorização de um responsável — que é
exatamente o que a 015 preferiu não improvisar.

A ordem natural é medir e só então escolher. Se o número for zero, A. Se for um
punhado, B. C só se passar de um punhado.

## Risks / Trade-offs

**Medir em produção exige acesso ao banco de produção** e é a única parte que não
pode ser feita localmente — localmente o número é zero por construção.

**A decisão tem prazo natural**: ela vale mais antes do lançamento ao distrito
(6 de outubro) do que depois, porque o número tende a crescer.
