# Privilegios De Banco Specification

## Purpose

O piso de privilégio dos papéis públicos do banco: o que `anon` e
`authenticated` conseguem fazer **antes** de qualquer policy entrar em cena.
Policy filtra um acesso que o `grant` já deu; o que nunca foi concedido não
precisa ser filtrado.

## Requirements

### Requirement: Papéis públicos não truncam tabela

`anon` e `authenticated` NÃO DEVEM ter `TRUNCATE`, `REFERENCES` nem `TRIGGER`
em nenhuma tabela de `public`, existente ou futura.

`TRUNCATE` ignora RLS e não dispara gatilho `after delete` — as duas garantias
sobre as quais este projeto constrói privacidade e limpeza de arquivo.

#### Scenario: TRUNCATE é recusado em toda tabela

- **WHEN** um papel público tenta `truncate` em qualquer tabela de `public`
- **THEN** o banco recusa com `permission denied`

#### Scenario: O que o app faz continua funcionando

- **WHEN** a suíte de integração inteira roda depois da revogação
- **THEN** todos os testes passam — nenhum caminho legítimo do app dependia
  desses três privilégios

#### Scenario: Tabela nova nasce fechada

- **WHEN** uma migration futura cria uma tabela em `public`
- **THEN** os papéis públicos não recebem `TRUNCATE` nela, sem que ninguém
  precise lembrar de revogar

### Requirement: Função nova não nasce chamável por papel público

O sistema NÃO DEVE deixar que uma função de `public` fique chamável por papel
público sem que alguém tenha decidido isso.

É o mesmo piso de privilégio que esta capability já cobre para `TRUNCATE`, e o
modo de falha é o mesmo em espelho: **o padrão do Postgres concede, e conceder a
mais não revoga o padrão**. Função nova nasce com `execute` para todos; um
`grant` a quem precisa acrescenta um privilégio e deixa o anterior de pé. A
diferença para `TRUNCATE` é que ali o defeito é ter esquecido de tirar, e aqui é
ter achado que dar a alguém tirava dos outros.

Esta requirement alcança função `security definer` com força maior: ela roda com
os privilégios de quem a escreveu, então uma função aberta por descuido entrega
o que a RLS da tabela nega.

#### Scenario: Função nova chega ao papel sem sessão
- **WHEN** uma função de `public` pode ser chamada por um papel público sem que
  isso esteja declarado
- **THEN** a verificação do projeto acusa antes de a migration ser publicada

#### Scenario: Função pública de propósito
- **WHEN** uma função precisa ser chamável sem sessão
- **THEN** ela consta de uma lista de exceções, com o motivo escrito ao lado
- **AND** a verificação passa por causa da declaração, não por omissão

#### Scenario: Conceder a quem precisa não abre para os demais
- **WHEN** uma função é concedida a quem precisa dela
- **THEN** quem não foi nomeado continua sem poder chamá-la

### Requirement: Função que lê dado escondido não vira oráculo dele

Quando uma função `security definer` consulta uma tabela que a RLS esconde, o
sistema NÃO DEVE deixá-la responder a quem não pode ler a tabela.

Uma função que devolve "sim/não" sobre o conteúdo de uma lista secreta entrega a
lista inteira a quem tiver paciência: pergunta-se um termo de cada vez. A tabela
recusar leitura direta não protege nada enquanto a função aceitar a pergunta.

Isto foi medido neste projeto, não deduzido: a lista de palavras bloqueadas está
atrás de uma tabela sem policy nenhuma — leitura direta é recusada — e era
sondável, sem sessão, uma palavra por chamada.

#### Scenario: Sondagem termo a termo sem sessão
- **WHEN** alguém sem sessão pergunta à função se um termo específico está na
  lista escondida
- **THEN** a pergunta é recusada

#### Scenario: A mesma pergunta por quem o app autoriza
- **WHEN** o app pergunta a mesma coisa em nome de quem está usando
- **THEN** a resposta vem normalmente, e a lista continua sem poder ser lida
  direto
