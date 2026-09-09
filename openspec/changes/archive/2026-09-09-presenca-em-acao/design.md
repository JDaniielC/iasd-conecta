## Context

Ver `proposal.md` § Why para a motivação, e os dois `spec.md` para o contrato.
Aqui só o que a implementação precisa saber e que não está lá.

Estado de hoje que restringe o desenho:

- `public.confirmacoes_acao` tem chave primária `(acao_id, usuario_id)` e nada
  além de `status` e `created_at` (`20260723230639_acoes.sql:16-22`). O par que
  identifica "esta pessoa nesta Ação" já existe e já é único.
- A policy de leitura é `confirmacoes_acao_select_conforme_acao`
  (`20260813120000_acao_restrita_ao_grupo.sql:165-173`): a confirmação é legível
  quando a Ação correspondente é legível. **Quem sai do Grupo de uma Ação
  restrita deixa de enxergar a própria confirmação** — e no Postgres o `update`
  não alcança o que o `select` não enxerga.
- `perfis` só é legível pelo próprio dono (`perfis_select_own`). Quem organiza a
  Ação **não tem como ler** `consentimento_lgpd_versao` de quem participa.
- `grant update` em `perfis` hoje cobre `nome, apelido, igreja_id, telefone,
  consentimento_lgpd_igreja_aceito_em`
  (`20260811160000_grant_update_perfis_por_coluna.sql:43-45`) — e **não**
  `consentimento_lgpd_aceito_em`.
- O gatilho `perfis_carimbar_consentimento` **já trata reaceite por `update`**:
  quando `consentimento_lgpd_aceito_em` muda para um valor não nulo distinto do
  anterior, ele carimba `now()` e `versao_texto_legal_vigente()`. O ramo `else`
  restaura os valores antigos, o que impede backfill fabricado pelo cliente.
  Nenhuma máquina nova de consentimento precisa ser escrita.
- `execucoes_de_faxina` e a capability `observador-de-retencao` já existem; a
  faxina nova entra sob a regra que já vale.

## Goals / Non-Goals

**Goals**

- Que "não registrado" seja **estruturalmente** distinto de "ausente", e não
  distinto só por disciplina de quem escrever a consulta.
- Que "linha contestada nunca conta" sobreviva a quem escrever a próxima
  consulta sem ler esta change.
- Que o alcance do titular esteja na policy de `select`, não na tela.
- Reaceite sem inventar máquina de consentimento nova.

**Non-Goals**

- Nenhuma consulta de envolvimento é escrita aqui. Esta change **coleta**; medir
  é de outra.
- Nenhuma tela de Administrador. O agregado é da change `saude-de-grupo`.
- Nenhuma mudança na superfície de leitura de `authenticated` sobre `acoes`,
  `grupos` e `participacoes_grupo` — ticket próprio.

## Decisions

### D-001 — Coluna em `confirmacoes_acao`, não tabela nova de presença

`compareceu_em timestamptz`, `marcado_por uuid references perfis(id)` na própria
`confirmacoes_acao`.

**Recusado: tabela `presencas` própria.** Ela repetiria a chave
`(acao_id, usuario_id)` que já é a PK da confirmação, e criaria a possibilidade
de presença sem confirmação — que a spec proíbe de propósito. Uma tabela a mais
para representar um atributo de uma linha que já existe.

**Custo aceito**: a linha de comparecimento herda o ciclo de vida da confirmação,
inclusive o `on delete cascade` de `acoes` e de `perfis`.

### D-002 — O fechamento é uma coluna em `acoes`, com a contagem congelada junto

`acoes.presenca_fechada_em timestamptz` e `acoes.presentes_no_fechamento integer`.

A contagem é gravada **no momento do fechamento**, não calculada quando a faxina
apagar as linhas nominais.

**Recusado: calcular a contagem na hora de apagar.** A quantidade mudaria entre o
fechamento e a faxina toda vez que alguém excluísse a conta ou uma confirmação
sumisse por cascade, e o histórico do ministério passaria a depender de quando a
faxina rodou. Congelar no fechamento faz o agregado ser um fato datado.

**Recusado: derivar o fechamento do tempo** (`data_hora + N dias`). É a única
coisa que a spec proíbe nominalmente: máquina nenhuma converte desconhecido em
ausente.

### D-003 — Contestação em tabela própria, append-only, com marca irreversível na confirmação

`public.contestacoes_presenca` — `acao_id`, `usuario_id`, `contestada_em`,
`decidida_em`, `decidida_por`, `decisao` em `mantida`/`desfeita`. Sem `grant
delete`, sem `grant update` fora da coluna de decisão, no padrão que
`denuncia-como-registro` estabeleceu.

E, **na `confirmacoes_acao`**, uma coluna `contestada_em timestamptz` escrita por
gatilho quando a contestação nasce, que **nada jamais limpa** — nem a decisão
"mantida", nem a "desfeita".

**Por que a coluna redundante existe.** "Linha contestada nunca conta" é a regra
mais fácil de perder: ela vive em consultas que ainda não foram escritas, numa
change que ainda não existe. Se depender de `join` com a tabela de contestação,
a primeira consulta que esquecer o `join` traz a linha de volta em silêncio. Com
a coluna, a exclusão é um `where contestada_em is null` que qualquer pessoa
escreve por reflexo, e a `check` constraint pode até exigi-lo. Redundância
deliberada, e este é o motivo.

**Recusado: um `estado` na própria confirmação, sem tabela.** Perderia quem
contestou quando, quem decidiu e o quê — que é exatamente o que
`denuncia-como-registro` concluiu que não se pode perder.

### D-004 — A trava de consentimento é `security definer` porque não há alternativa

Quem marca não pode ler `perfis` de quem é marcado. A checagem vai numa função
`security definer` que devolve **apenas booleano**.

Dentro de função `security definer` a RLS não se aplica, então o que precisa de
checagem explícita é a autoridade de quem chamou — regra do `CLAUDE.md`. A função
DEVE recusar quando quem chama não é o criador daquela Ação, e DEVE recusar
quando a pessoa consultada não tem confirmação naquela Ação. Sem esses dois
braços ela vira oráculo geral de "fulano está com o aceite atrasado".

**Vazamento residual, declarado e aceito**: mesmo com os dois braços, quem cria a
Ação descobre que alguém do próprio evento está com aceite defasado. É um bit
sobre um conjunto que a pessoa já conhece, e não há como travar a coleta sem ele.
Registrar aqui para não ser redescoberto como achado.

**Recusado: filtrar na consulta em vez de na escrita.** Guardaria por dois anos
dado provavelmente sensível de quem não consentiu com a finalidade. É a decisão
que o dono do projeto tomou explicitamente.

### D-005 — Alcance do titular: um braço a mais na policy de `select`

`confirmacoes_acao_select_conforme_acao` ganha o disjunto `auth.uid() =
usuario_id`, incondicional — sem passar pela visibilidade da Ação.

É a mesma correção de `alcance-do-titular-sobre-texto-proprio`, pelo mesmo
motivo: a promessa de que a pessoa alcança o dado sobre si tem que viver na
policy de leitura, senão o `update` de contestação não encontra a linha e o
direito evapora justamente para quem saiu.

**Efeito colateral a testar de propósito**: a própria confirmação passa a ser
legível em Ação restrita de Grupo do qual a pessoa saiu. Isso é o pretendido —
o dado é dela.

### D-006 — Escrita recortada por coluna, não por `with check`

`revoke update` e `grant update (compareceu_em)` para quem organiza;
`marcado_por` e `contestada_em` **nunca** são concedidos ao cliente — quem os
escreve é gatilho. Em `perfis`, acrescentar `consentimento_lgpd_aceito_em` ao
`grant update` existente, para o reaceite.

`marcado_por` saiu do `grant` durante a implementação: concedê-lo deixaria quem
marca **atribuir a outra pessoa** a afirmação que ele mesmo fez, que é o defeito
que `perfis_carimbar_consentimento` já evita do outro lado. O cliente manda o
sinal em `compareceu_em`; o gatilho carimba `now()` e `auth.uid()`.

O padrão já é do repo (`grant_update_perfis_por_coluna`,
`mensagens_insert_por_coluna`): o `grant` restringe a cláusula `SET` inteira, e
uma policy com `with check` não faz isso.

### D-009 — Uma view define o que conta, e ela nasce nesta change

`public.presencas_computaveis` — `acao_id`, `usuario_id`, `presente boolean`.
Devolve linha **apenas** de Ação com `presenca_fechada_em` preenchido e
`contestada_em` nulo; `presente` é `compareceu_em is not null`.

Descoberto ao escrever o teste do fechamento: a spec afirma que Ação não fechada
fica fora do numerador **e** do denominador, e sem um primitivo isso não é
asserível — a change construiria as três colunas e deixaria a regra inteira para
uma consulta futura escrever certo por conta própria. É o oposto do que ela
existe para fazer.

A view **não é métrica**: não agrega, não classifica ninguém, não sabe o que é
afastamento. Ela é a definição de "esta linha conta", num lugar só. A change
`queda-relativa` lê daqui e não toca em `confirmacoes_acao`.

**Recusado: deixar a regra em comentário na migration.** Comentário não é
executável, e a primeira consulta escrita sem lê-lo traz de volta a Ação
esquecida e a linha contestada.

**Recusado: `security definer` com checagem de autoridade.** A view é
`security_invoker`, como `notificacoes_ativas`: quem lê vê o que a RLS de
`confirmacoes_acao` já lhe permite, nem mais. Quem decide quem vê métrica é a
change que construir a métrica.

### D-007 — Retenção: faxina agendada, com rastro, e o agregado fora dela

Faxina de `pg_cron` apaga `compareceu_em`, `marcado_por` e `contestada_em` de
confirmação de Ação com mais de dois anos, e registra a execução em
`execucoes_de_faxina` — inclusive quando não apaga nada. `presentes_no_fechamento`
não é tocado.

**Recusado: apagar a linha inteira de `confirmacoes_acao`.** Apagaria também a
intenção, que é dado de outra finalidade e de outra idade. Zerar as colunas de
presença devolve a linha ao estado "não registrado", que é o estado que a spec já
define e já sabe tratar.

### D-008 — O reaceite reusa o gatilho que já existe

O cliente escreve `consentimento_lgpd_aceito_em` com qualquer valor não nulo
distinto do atual; o gatilho carimba `now()` e a versão vigente. Nenhuma RPC
nova, nenhuma coluna nova, nenhuma tabela de histórico de aceite.

**Consequência aceita**: o app guarda **um** aceite por pessoa, o mais recente.
Não há histórico de "aceitou a 1.9 em tal data e a 1.11 em tal outra". Construir
esse histórico é mudança de modelo, e a `versoes_texto_legal` já registra o que
cada versão dizia e desde quando — o que permite reconstruir a linha do tempo do
documento, ainda que não a de cada pessoa. **Fica registrado como limite
conhecido**, não como omissão.

## Risks / Trade-offs

- **A coluna `contestada_em` pode divergir da tabela de contestação** → o gatilho
  é a única escrita, e o teste de integração afirma que contestar sempre a
  preenche e que nenhuma decisão a limpa.
- **Quem organiza a Ação descobre que alguém está com aceite defasado** (D-004)
  → sem correção possível dentro da trava de coleta. Declarado acima e a
  registrar em `MAPA-DE-DADOS.md`.
- **Publicar a versão nova antes de o reaceite estar na mão do usuário deixa o
  check-in recusado para todo mundo** → ordem de implantação obrigatória: aviso e
  reaceite **antes** de a versão nova entrar em vigor. Ver Migration Plan.
- **Braço novo na policy de `select` alarga a leitura de `confirmacoes_acao`** →
  o disjunto é `auth.uid() = usuario_id`, e o teste tem que provar que ele não
  devolve confirmação de terceiro em Ação restrita.
- **Aviso de versão defasada em cima de todo mundo no primeiro deploy** → é o
  esperado, e é o que a LGPD art. 8º, §6º pede. O aviso não bloqueia o uso
  (spec `versao-aceita-e-vigente`), então o custo é um cartão a fechar.
- **A trava de coleta esvazia o histórico enquanto o reaceite não circula** →
  aceito conscientemente: o relógio que motivou a urgência só começa a contar
  para quem consentiu, e essa é a decisão, não um efeito indesejado.
- **`presentes_no_fechamento` congela um número que pode ficar errado** se uma
  confirmação sumir por cascade depois do fechamento → aceito: é um fato datado
  ("no fechamento, eram 12"), e isso está dito na spec.

## Migration Plan

A ordem não é preferência, é requisito — inverter deixa o app recusando
check-in para o distrito inteiro:

1. Schema, policies, grants, gatilho e faxina. Nada disso é observável ainda.
2. Aviso de versão defasada e reaceite, funcionando contra a versão **vigente
   atual**. Deploy. A partir daqui existe caminho para atualizar aceite.
3. Versão nova de texto legal em `versoes_texto_legal` — Política, Termos e o
   texto de autorização do responsável, todos citando comparecimento e a
   finalidade de acompanhamento de envolvimento. Só agora o aviso passa a
   aparecer para quem está atrasado.
4. Telas de marcar presença, fechar lista, ver e contestar.

**Rollback**: as colunas novas são anuláveis e a faxina é desligável no
agendamento. Reverter as telas é seguro em qualquer ponto. **Reverter a versão de
texto legal não é**: aceite carimbado não se desfaz, e `versoes_texto_legal` é
registro, não configuração — a correção de um texto publicado é outra versão,
nunca a edição da anterior.
