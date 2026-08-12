## MODIFIED Requirements

### Requirement: Cadastro de criança anterior à exigência de autorização

Um cadastro de menor de 13 anos criado antes da exigência de autorização do
responsável NÃO DEVE deixar a titular sem saída. Ela DEVE conseguir, no mínimo,
entender por que não consegue editar, e DEVE conseguir excluir a própria conta.

O sistema DEVE saber quantos cadastros estão nessa situação — um número
desconhecido não permite decidir nada sobre eles.

#### Scenario: A recusa é explicada, não silenciosa

- **WHEN** uma criança cadastrada antes da exigência tenta corrigir qualquer
  campo do próprio Perfil
- **THEN** a tela diz por que não foi possível e como pedir ajuda, em vez de
  mostrar erro técnico

#### Scenario: Excluir a conta continua funcionando

- **WHEN** essa mesma pessoa pede exclusão de conta
- **THEN** a exclusão acontece por inteiro, porque a anonimização zera `idade` e
  as constraints deixam de recusar

#### Scenario: A quantidade é conhecida

- **WHEN** se pergunta quantos cadastros estão nessa situação em produção
- **THEN** existe uma consulta que responde, e a resposta está registrada com
  data — não "provavelmente nenhum"
