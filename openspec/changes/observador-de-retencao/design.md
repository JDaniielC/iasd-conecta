## Context

Ver `proposal.md` — Why. O que vem pronto:

- `expurgar_mensagens_de_acao()`, `security definer`, que **já devolve** a
  contagem de linhas apagadas — o número existe e é descartado.
- Dois executores: `cron.job` id 4, `43 3 * * *`, e
  `ChatRepository.fetchHistory` chamando `purgeExpiredActionMessages` com
  `unawaited`.
- `INFRA-PRODUCAO.md`, que já declara que o `cron.schedule` pode não ter rodado
  no projeto hospedado.
- `public.mudancas`, com dois índices parciais e nenhuma retenção.
- Telas de Administrador do distrito já existentes, como molde.

## Goals / Non-Goals

**Goals:**
- Responder "rodou ontem?" de dentro do app.
- Distinguir "rodou e não havia nada" de "não rodou".

**Non-Goals:**
- **Mudar o que é apagado, ou quando.** O prazo de 30 dias, a exceção da
  fixada e o teto ficam exatamente como estão. Esta change observa; não decide
  retenção de conversa.
- Alerta que persegue alguém — aviso in-app, e-mail, push. Quem administra vê
  quando abre. Um alerta sobre faxina atrasada acorda a pessoa errada na hora
  errada, e a change não tem como saber qual é o limiar certo.
- `/health` público. A informação diz volume de atividade do app, e a superfície
  sem sessão foi fechada de propósito em `fechar-superficie-anon`.
- Guardar O QUE foi apagado. O rastro é contagem, nunca conteúdo — conservar o
  que a retenção acabou de eliminar é o defeito que a retenção existe para não
  ter.

## Decisions

### Uma tabela de execuções, escrita pela própria função de expurgo

```
execucoes_de_faxina(id, faxina text, quando timestamptz, quantas integer,
                    disparada_por text)
```

`faxina` é texto e não enum: uma faxina nova não deveria exigir `alter type`, e
`denuncia-como-registro` já traz a segunda.

`disparada_por` distingue `cron` de `app`. Sem essa coluna, o modo de falha
descrito em `INFRA-PRODUCAO.md` continua invisível — o app dispara, a linha
aparece, e a ausência do cron fica escondida atrás dela. **Este é o ponto da
change**, e é a coluna que o resolve.

Como a função sabe quem a chamou: parâmetro com valor padrão, e o
`cron.schedule` passa o dele explicitamente. Alternativa recusada: inferir por
`current_user` — o `pg_cron` e o PostgREST podem chegar com o mesmo papel, e uma
inferência que às vezes acerta é pior do que uma coluna que sempre diz.

### O registro é `exception`-safe, e a faxina não depende dele

O bloco que escreve a execução vai dentro de `begin ... exception when others
then null end` **depois** do `delete`. A ordem e o `exception` são a decisão: a
promessa é o descarte, e o rastro serve à promessa.

Alternativa recusada: escrever a execução antes do `delete`, para registrar
tentativa. Registraria faxina que não aconteceu, e a pergunta que a tabela
existe para responder é sobre o que aconteceu.

### Sem dado pessoal, e por isso sem policy de dono

A tabela guarda quando, quanto e qual — nada de `autor_id`, nada de conteúdo.
A leitura é do Administrador do distrito, e a policy tem um braço só.

RLS ligada e `grant select` só a `authenticated`, com o braço de Administrador
— a disciplina de `fechar-superficie-anon` vale aqui como em tudo que nasce.

A escrita não tem policy nenhuma: quem escreve é a função `security definer`.

### O limiar de "atrasada" é do app, não do banco

A tela precisa de um número para dizer "atrasada". Ele mora no Dart, como
`ChatLimits`, e é conferido contra o agendamento real por teste — como o teto
de fixadas é conferido contra a migration.

**Escolha, não medição**, e escrita como tal: o cron roda diariamente, então
mais de dois dias sem execução é sinal. Dois e não um, porque uma execução que
atrasa algumas horas é normal e um alerta que dispara toda semana deixa de ser
lido.

### A última execução de cada faxina não expira

O prazo do rastro tem uma exceção, e ela é o oposto da que `mensagem-fixada`
declarou: lá a exceção conserva conteúdo, aqui ela conserva a única linha que
distingue "parada há muito tempo" de "nunca rodou". Sem ela, a limpeza do
rastro apagaria exatamente a informação que a change existe para dar.

É uma exceção sobre dado que não é pessoal, então não vai para a Política.

### `mudancas` ganha prazo — e o prazo é decisão do dono do app

O mecanismo é o mesmo das outras faxinas. O **número** não é decisão técnica:
`mudancas` é o histórico que explica por que um Grupo mudou, e apagá-lo cedo
demais tira contexto de quem chega depois.

A tarefa manda decidir antes de escrever a migration, e a decisão entra em
`REVISAO-JURIDICA.md` porque tem efeito legal — o registro é dado pessoal e a
Política fala de prazos.

## Risks / Trade-offs

**Mais uma tabela que cresce, para vigiar tabelas que crescem.** → Por isso o
rastro tem prazo próprio nesta mesma change, e não na seguinte. Uma
capability de observação que cria a dívida que observa seria piada.

**O prazo de `mudancas` apaga contexto.** → Decisão do dono, escrita, com o
custo declarado. O mecanismo não força número nenhum.

**A tela pode dizer "atrasada" por causa do relógio ou de um cron que rodou e
falhou ao registrar.** → O `exception` do registro torna isso possível de
propósito. A tela diz o que sabe — "não há registro desde X" —, e não afirma que
a faxina não rodou.

**O segundo gatilho do app esconde a ausência do cron.** É o defeito que motivou
a change, e ele **continua existindo** depois dela — o que muda é que passa a
ser visível. → Escrito aqui e em `INFRA-PRODUCAO.md`: ver `disparada_por` só
`app` por vários dias É o sintoma, e a tela precisa deixar isso legível.

## Migration Plan

Aditiva: tabela nova, função de registro, ajuste nas funções de expurgo
existentes para chamá-la, agendamento da faxina do rastro e da de `mudancas`.

Nenhum dado existente muda. As primeiras execuções aparecem só depois da
subida — a tela precisa tratar "nunca rodou" como estado normal no primeiro
dia, e não como alarme.

Rollback: `drop table` e reverter as funções de expurgo ao que eram. **Sem
perda** do que a promessa protege — o descarte continua igual; some o rastro.
