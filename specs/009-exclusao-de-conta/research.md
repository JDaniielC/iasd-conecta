# Research: Exclusão de conta (009)

Nenhum `NEEDS CLARIFICATION` restou da spec. O que este documento registra
são as decisões técnicas que a spec deliberadamente não tomou, e as
alternativas que foram descartadas — para que ninguém precise redescobrir
o porquê daqui a seis meses.

## 1. Onde a operação acontece

**Decisão**: uma função PL/pgSQL `SECURITY DEFINER` chamada por `rpc()`.

**Rationale**: FR-015 exige tudo-ou-nada. Uma função é uma transação só;
qualquer exceção no meio desfaz tudo, inclusive a anonimização parcial. Se
o Dart orquestrasse (apaga confirmações, depois transfere Grupo, depois
anonimiza), uma queda de rede entre chamadas deixaria um Perfil meio
apagado — exatamente o cenário do Acceptance Scenario 3 da US3. É também o
padrão do projeto: regra de negócio no banco, cliente burro.

**Alternativas consideradas**:

- *Orquestrar no Dart com várias chamadas*: descartada por não ser atômica.
- *Edge Function*: o projeto não tem nenhuma (ver README), e introduzir a
  primeira para isso adicionaria um runtime a manter sem resolver a
  atomicidade melhor do que uma transação já resolve.
- *Script manual operado pelo mantenedor*: descartada na grelha que
  originou a spec — transforma "a qualquer momento" em "quando o mantenedor
  abrir o email".

## 2. A FK `perfis.id -> auth.users`

**Decisão**: derrubar a constraint.

**Rationale**: ela é `on delete cascade`. Enquanto existir, apagar o login
apaga a linha de `perfis`, e a linha anonimizada — que é a âncora do
histórico de terceiros — não sobrevive. Não há variação de `on delete` que
resolva: `set null` é impossível (a coluna é PK) e `no action` bloquearia a
exclusão do próprio login.

**Consequência aceita**: `perfis` deixa de ter garantia referencial contra
`auth.users`, e passa a existir legitimamente linha de `perfis` sem
`auth.users` correspondente — que é precisamente o estado "anonimizado". A
única escrita em `perfis.id` continua sendo o cadastro, que grava
`auth.uid()`, então não se abre caminho para id inventado.

**Alternativas consideradas**:

- *Manter a FK e não apagar o `auth.users`, só invalidando a senha*:
  descartada. Deixaria email e metadados de autenticação — dado pessoal —
  guardados indefinidamente, o que é o oposto do pedido do titular.
- *Copiar o histórico para uma tabela de arquivo antes de apagar*:
  descartada por complexidade sem ganho; a linha anonimizada já é o
  arquivo.

## 3. Ordem das operações dentro da função

**Decisão**: eleger herdeiro → inserir participação do herdeiro nos Grupos
que ele vai receber → transferir `dono_id` → transferir Rodadas abertas →
apagar vínculos vivos (votos em Rodada aberta, confirmações futuras,
participações, declarações próprias, linha de Administrador) → anonimizar
`perfis` → apagar `auth.users`.

**Rationale**: `grupos_dono_deve_participar` é `BEFORE UPDATE` e
`grupos_dono_vira_participante` é `AFTER INSERT` **apenas** — verificado no
banco local. Transferir posse por `update` sem criar a participação antes é
recusado pelo trigger. A anonimização vem depois das transferências porque
a eleição do herdeiro lê `administradores_distrito`, que a própria função
altera.

**Alternativas consideradas**:

- *Estender `grupos_dono_vira_participante` para `AFTER INSERT OR UPDATE`*:
  descartada. Mudaria o comportamento de toda transferência de posse feita
  pela tela existente, que hoje só permite transferir para quem já
  participa — uma regra de domínio da feature 002 que esta feature não tem
  mandato para mexer.
- *Desabilitar o trigger dentro da função*: descartada. Desligar validação
  de domínio para passar por cima dela é o tipo de atalho que esconde
  regressão; inserir a participação é honesto e produz o mesmo estado final
  que a regra exige.

## 4. Fila de espera e Dupla Missionária

**Decisão**: apenas `delete` nas confirmações de Ações futuras. Nada de
lógica de promoção nesta feature.

**Rationale**: `confirmacoes_acao_promover_fila` já é `AFTER DELETE` e
chama `promover_fila_acao()` — verificado no banco local. Reimplementar
promoção aqui duplicaria a regra do Princípio IV em dois lugares. Pelo mesmo
caminho, a composição de Dupla Missionária fica protegida **onde importa**:
como um Perfil anonimizado nunca permanece em vaga futura (FR-013), nenhuma
Dupla que ainda vai acontecer é validada contra gênero nulo. Em Ação já
passada o Perfil anonimizado continua confirmado, e `promover_fila_acao()`
lê `perfis.genero` sem filtrar por data — ali o gênero nulo é alcançável. O
impacto é nulo na prática (o evento já ocorreu), mas a invariante não é
universal e não deve ser documentada como se fosse.

**Alternativas consideradas**:

- *Ensinar o trigger da Dupla a lidar com gênero nulo*: descartada na
  grelha. Conserta o sintoma e deixa uma vaga ocupada por quem não vai
  aparecer.

## 5. Retirada de voto em Rodada aberta

**Decisão**: `delete` nos votos cujas Rodadas ainda não fecharam; votos de
Rodadas fechadas permanecem.

**Rationale**: FR-018. `votos` não tem policy de `delete` — verificado no
banco local — então isso só é possível de dentro da função
`SECURITY DEFINER`, o que é desejável: continua impossível apagar voto pela
API. O desempate ao fechar segue por sorteio, regra que já existe; a saída
de alguém não introduz critério novo.

## 6. `genero` e `idade` anuláveis

**Decisão**: relaxar `not null` nas duas colunas.

**Rationale**: num distrito pequeno, gênero + idade + quais Grupos a pessoa
participava reidentifica. O art. 16 da LGPD só dispensa a exclusão quando o
dado está anonimizado — manter esses dois campos tornaria a base para
conservar a linha frágil. Verificado que os `check` existentes toleram nulo:
`apelido_obrigatorio_menor` (`idade >= 18 or apelido is not null`) avalia
como nulo, e no Postgres um `check` que resulta em nulo passa.

**Consequência**: o modelo Dart `Perfil` passa a ter `genero` e `idade`
anuláveis, e `menorDeIdade` precisa de um comportamento definido para
Perfil anonimizado (proposta: `false`, já que não há menor a proteger — não
existe mais pessoa por trás).

**Alternativas consideradas**:

- *Gravar valores neutros mantendo `not null`*: descartada — inventaria
  gênero e idade para quem saiu, falsificando dado e enviesando contagem.
- *Apagar só nome, Apelido, telefone e Igreja*: descartada — continua
  reidentificável, que é o problema que se queria resolver.

## 7. Encerramento da sessão

**Decisão**: o cliente chama `signOut()` imediatamente após a `rpc()`
retornar com sucesso.

**Rationale**: apagar `auth.users` invalida o refresh token, mas o JWT já
emitido continua criptograficamente válido até expirar. Sem `signOut()`
explícito, o app parece logado por mais alguns minutos, contra FR-004.

## 8. Exibição do Perfil anonimizado

**Decisão**: nenhuma mudança em `perfil_publico()`.

**Rationale**: ela já devolve `coalesce(apelido, nome)` — verificado no
banco local. Com `apelido` nulo e `nome = 'Membro removido'`, o
comportamento pedido por FR-005 aparece sem uma linha nova. Vale um teste
que trave isso, para ninguém "otimizar" o `coalesce` depois.
