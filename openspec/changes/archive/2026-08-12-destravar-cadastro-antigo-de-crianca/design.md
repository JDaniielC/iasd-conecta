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

**DECIDIDO em 2026-08-12: saída A — não fazer nada, e registrar.**

**Medido em produção, não deduzido**: a consulta rodou no SQL Editor do painel,
projeto `mbfcnebyxzoagwatjxuh` (`iasd-conecta-vsa`, branch `main`, PRODUCTION),
role `postgres`, em 2026-08-12 — **count = 0**. Nenhum cadastro de menor de 13
sem dados de responsável.

O resultado era o esperado pelas datas, e as datas continuam registradas porque
explicam *por que* zero: produção nasceu em 2026-08-07, a constraint da 015
entrou lá no push de 2026-08-11, e o lançamento ao distrito é 2026-10-06 — a
única janela possível eram quatro dias de produção fechada. Mas o que fecha esta
change é a medição, não o raciocínio.

Se um caso aparecer depois do lançamento, o caminho é o e-mail de contato, que
já funciona.

As três saídas abaixo ficam registradas porque são o motivo de A ter sido
escolhida — não porque continuem em aberto:

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

A ordem natural era medir e só então escolher. O que decidiu foi a data: com
produção fechada até outubro, o conjunto é vazio antes de qualquer consulta, e
A é a resposta. B e C continuam descritas aqui porque, se o número deixar de
ser zero depois do lançamento, é por elas que se começa.

## Risks / Trade-offs

**Medir em produção exige acesso ao banco de produção** e é a única parte que não
pode ser feita localmente — localmente o número é zero por construção.

**A decisão tem prazo natural**: ela vale mais antes do lançamento ao distrito
(6 de outubro) do que depois, porque o número tende a crescer.
