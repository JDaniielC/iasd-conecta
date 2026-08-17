## Why

Duas coisas se perdem no chat que `chat-de-grupo-e-acao` entrega:

1. **O que importa afunda.** "O ponto de encontro mudou para a frente da
   igreja" fica a quarenta mensagens de distância de quem abre a tela na
   véspera. Não há nada acima da conversa.
2. **A conversa de Ação some inteira em 30 dias.** O prazo existe para reduzir
   exposição, e está certo para o bate-papo. Mas a combinação que precisa
   sobreviver ao encontro — o endereço, a lista do que cada um leva, o
   agradecimento — some junto com ela.

## What Changes

- Quem tem autoridade sobre o espaço (dono do Grupo, criador da Ação,
  Administrador do distrito) **fixa** uma mensagem. Ela passa a aparecer acima
  da conversa.
- **Mensagem fixada não expira.** É a única exceção ao prazo de 30 dias do chat
  de Ação, e por isso precisa estar declarada na Política de Privacidade — não
  basta estar no código.
- Limite de mensagens fixadas por chat. Sem teto, fixar vira uma forma de
  desligar a retenção inteira.
- **O autor sempre desfixa a própria mensagem**, mesmo sem ter autoridade no
  espaço. É o que devolve a ele o controle do prazo do que ele escreveu.
- Mensagem removida por moderação e mensagem cujo autor excluiu a conta são
  desfixadas sozinhas. Lápide fixada no topo do chat não serve a ninguém.

## Capabilities

### New Capabilities
- `mensagem-fixada`: quem fixa, quantas cabem, o que acontece com o prazo de
  expiração, e o que desfixa sozinho.

### Modified Capabilities
Nenhuma. A regra de expiração de `chat-de-grupo-e-acao` continua valendo como
está — esta capability define a exceção e as condições dela.
`openspec/specs/chat-de-grupo-e-acao/spec.md` só passa a existir depois que
aquela change for arquivada; um delta escrito agora diverge do texto que diz
modificar.

## Impact

**Depende de** `chat-de-grupo-e-acao` aplicada. Independente de
`filtro-e-intervalo-de-mensagem`: as duas tocam `mensagens`, mas em colunas e
gatilhos diferentes — filtro e ritmo em `before insert`, fixação em `update`.
Podem ser feitas em qualquer ordem, ou em paralelo, desde que quem fizer a
segunda releia o gatilho da primeira antes de escrever o dela.

**Banco** — duas colunas em `mensagens`, gatilho de teto, ajuste na função de
expurgo e no `excluir_conta`.

**Retenção** — esta é a mudança de peso: `expurgar_mensagens_de_acao()` passa a
ter uma exceção. A promessa de 30 dias vira "30 dias, salvo o que estiver
fixado, com teto de N por chat". É verificável de fora e precisa bater com o
texto legal.

**Nenhum dado pessoal novo** além de quem fixou e quando.

**Ledgers** — `REVISAO-JURIDICA.md` (a exceção ao prazo), `MAPA-DE-DADOS.md`
(as duas colunas novas), `PENDENCIAS.md`.

**Legal** — Política de Privacidade: o prazo declarado passa a ter exceção.
Manter "30 dias" sem ressalva depois desta change torna a política falsa.

**Código** — `lib/features/chat/`: faixa de fixadas acima da conversa, ação de
fixar/desfixar.
