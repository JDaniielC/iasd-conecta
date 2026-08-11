## Purpose

O que a suíte de integração garante sobre si mesma. Ela roda os arquivos em
paralelo contra um único banco, então o isolamento entre arquivos é uma
propriedade que precisa ser escrita, não presumida.

## ADDED Requirements

### Requirement: A suíte é determinística em paralelo

Rodar `dart test test/integration` DEVE produzir o mesmo resultado em execuções
repetidas, com os arquivos rodando em paralelo contra o mesmo banco.

Um arquivo NÃO DEVE alcançar linha criada por outro — nem para ler contagem, nem
para apagar em limpeza.

#### Scenario: Vinte execuções seguidas, mesmo resultado

- **WHEN** a suíte inteira roda 20 vezes seguidas
- **THEN** as 20 passam, com a mesma contagem de testes

#### Scenario: A limpeza de um arquivo não alcança dado de outro

- **WHEN** um arquivo termina e roda seu `tearDownAll`
- **THEN** ele apaga apenas linhas que ele mesmo criou, identificadas por marca
  própria — nunca por padrão que outro arquivo possa casar

#### Scenario: A causa da falha conhecida está eliminada

- **WHEN** o caso "(d) Perfil anonimizado sai da contagem" roda dentro da suíte
  completa, 20 vezes
- **THEN** ele passa nas 20, e o balde da versão isolada existe em todas
