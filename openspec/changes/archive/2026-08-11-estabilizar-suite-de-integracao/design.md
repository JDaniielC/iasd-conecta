## Context

`dart test` roda os arquivos em paralelo contra o mesmo Postgres local. Este
projeto já teve esta classe de falha antes — a feature 014 encontrou quatro
arquivos fazendo `delete from public.acoes` **sem filtro**, o que derrubava
arquivos que não tinham feito nada errado. Aquilo foi escopado por UUID e a
suíte ficou estável, então a causa de agora é outra.

Uma hipótese **já foi descartada**: `versao_texto_legal_registro_test.dart`
executa `delete from public.versoes_texto_legal`, mas como `authenticated` e
esperando que falhe — não é ele que apaga o catálogo.

## Goals / Non-Goals

**Goals:**
- Encontrar a causa, com reprodução em laço, antes de mudar qualquer linha.
- Eliminar a causa, não o sintoma.

**Non-Goals:**
- Marcar o teste como `skip`, ou dar `retry`. Isso apaga o sinal e mantém o
  defeito — e o defeito pode não estar no teste.
- Reescrever a suíte inteira.

## Decisions

**Reproduzir antes de consertar, com laço.** O primeiro passo não é ler código: é
`for i in $(seq 1 20); do dart test test/integration; done` registrando qual
execução falha. Sem um laço que falhe de propósito, qualquer conserto aqui é
adivinhação — e adivinhação num teste intermitente parece funcionar por sorte.

**A investigação começa pelo que some, não pelo teste que falha.** O balde da
versão `9.9-anon` desaparece. Ou as duas linhas de `perfis` criadas pelo caso (d)
deixaram de existir no meio do teste, ou a linha de `versoes_texto_legal` saiu.
Cada hipótese tem um conjunto pequeno de arquivos capazes de causá-la — é por aí
que se estreita, e não relendo o arquivo que falha.

## Risks / Trade-offs

**Pode não reproduzir em 20 execuções.** A taxa medida foi 2 em 8; 20 execuções
dão margem confortável, mas não garantia. Se não reproduzir, o caminho é
aumentar o paralelismo ou o número de execuções até a taxa subir — nunca declarar
resolvido por ausência de falha.

**A causa pode estar em código de produção**, e não no teste — por exemplo em
`consentimentos_por_versao()` dependendo de estado global. Se for isso, o escopo
desta change muda, e é melhor descobrir cedo.
