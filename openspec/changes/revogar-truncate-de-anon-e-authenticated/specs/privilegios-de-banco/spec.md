## Purpose

O piso de privilégio dos papéis públicos do banco: o que `anon` e
`authenticated` conseguem fazer **antes** de qualquer policy entrar em cena.
Policy filtra um acesso que o `grant` já deu; o que nunca foi concedido não
precisa ser filtrado.

## ADDED Requirements

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
