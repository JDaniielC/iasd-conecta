# Research: Ação — encerramento, contagem de confirmados e clareza do título

**Feature**: 011-acoes-titulo-e-encerramento | **Date**: 2026-08-09

---

## D-001 — Encerramento é derivado, nunca gravado

**Decisão**: nenhuma coluna `encerrada`, nenhum job agendado, nenhum `Timer` na UI. Uma
função pura em `lib/features/action/domain/action.dart`:

```
ActionTimeStatus actionTimeStatus(DateTime dateTime, DateTime now)
  → upcoming | happeningNow | ended
```

com `ended` quando `now.difference(dateTime) > 4h`, e `happeningNow` no intervalo
`[dateTime, dateTime + 4h]`.

**Rationale**: gravar um estado que só depende do relógio cria a obrigação de mantê-lo
atualizado — job, cron ou trigger — e a garantia de que um dia ele vai ficar defasado.
Derivar é a versão mais simples que atende (Princípio V), e é a mesma abordagem que
`actionPeriod`/`isOnSabbath` já usam no mesmo arquivo, então não introduz um segundo jeito
de pensar sobre tempo neste módulo.

**Fronteira exata, para o teste não ficar ambíguo**: no instante `dateTime + 4h` cravado a
Ação ainda está *acontecendo agora*; encerra no primeiro instante depois disso. Um teste por
fronteira: `-1s`, `+0s`, `+4h`, `+4h+1s`.

**Alternativas descartadas**:
- *Coluna `encerrada_em` preenchida por job*: exige agendador (pg_cron ou equivalente), que
  o projeto não tem, para produzir informação que já está em `data_hora`.
- *Filtrar no `select` do servidor* (`.gt('data_hora', now - 4h)`): esconderia a Ação
  encerrada da listagem **e** do detalhe por link direto, quebrando FR-004. O filtro tem de
  ser da listagem, não da consulta.
- *`Timer` que reconstrói a tela quando a Ação encerra*: a spec diz explicitamente que a Ação
  não some embaixo do dedo do Usuário; o `Timer` seria trabalho para produzir o comportamento
  errado.

---

## D-002 — Filtrar na tela, não no provider nem no repositório

**Decisão**: `actionsProvider` e `actionsWithChurchProvider` continuam trazendo tudo.
`ActionListPage` filtra as encerradas no `build`, no mesmo lugar onde já filtra "Só Sábado" e
agrupa por período.

**Rationale**: `ActionDetailPage` precisa da Ação encerrada (FR-004). Filtrar no provider ou
no repositório a esconderia de todo consumidor, presente e futuro, e a tela de detalhe teria
de arranjar um caminho paralelo — dois caminhos para o mesmo dado é como se cria divergência.
Filtrar na tela também mantém o padrão que o arquivo já usa.

**Consequência aceita**: a listagem baixa Ações que vai jogar fora. Num distrito de 15+
igrejas isso é ruído irrelevante. Se um dia o histórico crescer a ponto de doer, a saída é
paginar por data no servidor — e aí a Ação encerrada continua alcançável por
`fetchAction(id)`, que é por id e não passa pelo filtro.

---

## D-003 — FR-007 é reforçado no banco, por política de acesso, não por trigger

**Decisão**: apertar duas políticas existentes de `confirmacoes_acao` para exigir que a Ação
não esteja encerrada:

- `confirmacoes_acao_insert_self` — `with check` ganha a condição de tempo (bloqueia
  confirmar presença em Ação encerrada).
- `confirmacoes_acao_delete_self` — `using` ganha a mesma condição (bloqueia desistir, e é
  isso que impede a promoção da fila, porque `confirmacoes_acao_promover_fila` é
  `after delete`).

**Rationale**: FR-007 promete que ninguém é promovido da fila depois do encerramento.
Esconder botão é promessa; política de acesso é execução. A constituição trata divergência
entre as duas como violação (Princípio IV e a seção "Fluxo de Desenvolvimento"), e a fila de
espera está na lista explícita de regras que exigem teste automatizado.

**Por que política e não trigger — este é o ponto crítico da feature**: a feature 009 apaga a
conta com `delete from public.confirmacoes_acao` dentro de `excluir_conta`
(`supabase/migrations/20260806140000_exclusao_de_conta.sql:132`). Um
`trigger before delete` genérico bloquearia esse delete para quem tivesse confirmação em
Ação encerrada — ou seja, uma feature de UX criaria um bug de LGPD, impedindo a exclusão de
conta. Política de acesso não tem esse efeito: função `security definer` não passa por RLS.

**Premissas a verificar antes de escrever a migration** (se qualquer uma cair, o plano muda):

1. `public.excluir_conta` é `security definer`.
2. Nenhuma das tabelas está com `force row level security` (que faria RLS valer até para o
   dono).

**Plano B, se as premissas não valerem**: trigger `before insert or delete` que pula a
verificação quando um sinalizador de sessão estiver ligado, e `excluir_conta` liga esse
sinalizador com `set local`. Funciona, mas acopla duas features por uma variável de sessão —
por isso é plano B, não plano A.

**Fora do bloqueio de propósito**: cancelar Ação encerrada continua permitido no banco.
FR-005 só manda não *oferecer* o botão; cancelar uma Ação que já passou é inofensivo e
bloquear criaria mais uma regra para manter.

---

## D-004 — Contar sem trazer quem é quem

**Decisão**: uma consulta só, para toda a listagem:

```
from('confirmacoes_acao').select('acao_id, status')
```

agrupada em Dart por `acao_id`, produzindo confirmados e tamanho da fila por Ação.

**Rationale**: três exigências de uma vez.
- *Privacidade* (Princípio II): `usuario_id` não sai do banco. O cliente recebe um número, não
  uma lista de pessoas. É mais forte do que o mínimo que a spec pede.
- *Sem N+1*: uma consulta para a lista inteira, não uma por Ação.
- *Sem migration*: a política `confirmacoes_acao_select_public` já é `using (true)`, então
  Visitante lê (FR-014) sem nenhuma mudança de permissão.

**A armadilha**: `select()` sem argumento traz todas as colunas, incluindo `usuario_id`. O
código atual (`action_repository.dart:19`) usa `select()` puro em `acoes` — copiar esse padrão
aqui vazaria a identidade de todo mundo que confirmou presença no distrito para qualquer
Visitante. A lista de colunas é explícita de propósito, e o `research` registra isso para que
uma refatoração futura não "simplifique" de volta.

**Alternativas descartadas**:
- *View `acoes_com_contagem` no banco*: mais limpa em consulta, mas custa migration, teste de
  integração e uma segunda fonte de verdade sobre o que conta como confirmado. Princípio V
  manda esperar a dor aparecer.
- *Reusar `attendeesProvider(actionId)` por Ação na lista*: N+1 e, pior, traria a lista
  nominal completa de cada Ação para desenhar um número.

---

## D-005 — Comparação do nome: normalizar acento, caixa e espaço

**Decisão**: a recusa de FR-017 compara nome digitado × nome de exibição do criador, ambos
normalizados por: `trim`, caixa baixa, colapso de espaços internos e remoção de acentuação.
Igualdade exata após normalizar — nunca `contains`.

**Rationale**: FR-019 diz que "Visita a José" deve ser aceita. `contains` recusaria, e a
pessoa ficaria sem entender o motivo. Igualdade após normalização recusa
`"  josé danilo silva do carmo "` e aceita qualquer nome de atividade que apenas mencione uma
pessoa.

**De onde vem o nome do criador**: do Perfil da sessão, pela RPC `perfil_publico` que o app já
usa (`ActionRepository._fetchPublicProfile`), via `publicProfileProvider`. É importante que seja
o **nome de exibição** e não o nome real: para menor de idade, `perfil_publico` devolve o
Apelido, e FR-017 pede que o Apelido também seja recusado. Usar a RPC dá isso de graça e
mantém a invariante de nunca ler `perfis` direto.

**Normalização de acento**: não existe pronta na base de código. `NameModeration._normalize`
(`lib/features/profile/domain/name_moderation.dart`) só faz `toLowerCase`. A remoção de
acentuação entra como função pura pequena no domínio de Ação, com teste unitário — não como
dependência nova.

**Comportamento quando o nome do criador não está disponível** (offline, RPC falhando): a
validação **não** bloqueia a criação. Recusar por falta de dado transformaria um problema de
rede numa acusação ao Usuário. O texto de apoio (FR-016) continua lá, que é a parte que faz o
trabalho de verdade.

---

## D-006 — Relógio injetável

**Decisão**: `clockProvider` em `lib/core/providers.dart`:

```
final clockProvider = Provider<DateTime Function()>((ref) => DateTime.now);
```

`ActionListPage` e `ActionDetailPage` leem o instante atual daí, em vez de chamar
`DateTime.now()` direto.

**Rationale**: sem isso, não há como escrever "Ação de 4h01 atrás não aparece na lista" como
teste de widget — o teste teria de criar dados relativos ao relógio real, ficando frágil e
dependente do momento em que roda. O provider é a menor mudança que torna FR-001 a FR-003
verificáveis, e vive em `core/` porque tempo não é assunto do módulo de Ação.

**Alternativas descartadas**:
- *Passar `DateTime agora` por parâmetro do widget*: contamina a assinatura de telas que são
  construídas pelo roteador, que não tem de onde tirar o valor.
- *Pacote de fake clock*: dependência nova para o que cabe em uma linha.

**Onde `DateTime.now()` continua legítimo**: dentro do banco (`now()` na política) e em
`ActionRepository.cancelAction`, que grava um instante real. A regra é: quem **decide** olhando
o relógio usa o provider; quem **carimba** um instante usa o relógio direto.
