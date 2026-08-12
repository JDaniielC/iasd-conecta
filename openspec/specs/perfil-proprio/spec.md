# Perfil Proprio Specification

## Purpose

TBD — capability existia antes da adoção do OpenSpec (ver `specs/001-*` e
outras features anteriores); Purpose ainda não escrito aqui. Update Purpose
after archive.

## Requirements

### Requirement: Escrita no próprio Perfil é limitada por coluna

A titular DEVE poder corrigir os próprios dados de identificação e contato. Ela
NÃO DEVE poder escrever, por caminho nenhum — tela ou chamada direta à API —, as
colunas de que dependem regras de domínio: `idade` e `genero`.

Alterar essas duas é ato de correção de cadastro, não de edição de perfil, e sai
do alcance da própria titular.

#### Scenario: Corrigir nome e telefone continua funcionando

- **WHEN** uma pessoa autenticada atualiza `nome`, `apelido`, `telefone` ou
  `igreja_id` da própria linha em `perfis`
- **THEN** a atualização é aceita, e nada mais na linha muda

#### Scenario: Escrever a própria idade é recusado

- **WHEN** uma pessoa autenticada tenta atualizar `idade` da própria linha, por
  chamada direta à API
- **THEN** o banco recusa com `permission denied`, e o valor anterior permanece

#### Scenario: Escrever o próprio gênero é recusado

- **WHEN** uma pessoa autenticada tenta atualizar `genero` da própria linha, por
  chamada direta à API
- **THEN** o banco recusa com `permission denied`, e o valor anterior permanece

#### Scenario: A recusa não depende da tela

- **WHEN** a tentativa é feita sem passar pelo app, com a chave publicável e um
  token de sessão comum
- **THEN** a recusa é a mesma — a garantia é do banco, não do cliente
