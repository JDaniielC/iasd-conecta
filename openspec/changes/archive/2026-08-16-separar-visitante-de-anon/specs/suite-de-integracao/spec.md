## ADDED Requirements

### Requirement: A suíte exercita o papel que o app usa

Um teste que afirma algo sobre uma categoria de pessoa DEVE rodar sob o papel
de banco que essa pessoa realmente tem no app. Rodar sob outro papel prova
outra coisa, e passa.

Neste projeto a distinção que importa é **Visitante** — pessoa sem cadastro,
que o app coloca numa sessão anônima e que chega ao banco **autenticada** —
contra **sem sessão nenhuma**, que é o que existe quando não há credencial na
requisição. Um teste de Visitante rodado sem sessão não prova nada sobre
Visitante.

A regra vale para os dois sentidos. Um teste que afirma **recusa** também
precisa recusar pelo motivo certo: parar antes da regra que se queria exercer
é um verde que não protege nada.

#### Scenario: Teste de quem não tem cadastro
- **WHEN** um teste afirma o que uma pessoa sem cadastro enxerga
- **THEN** ele roda com sessão, como o app coloca essa pessoa
- **AND** o resultado é o mesmo que ela veria na tela

#### Scenario: Teste da superfície sem credencial
- **WHEN** um teste afirma o que uma requisição sem credencial alcança
- **THEN** ele roda sem sessão, e o nome do teste diz isso

#### Scenario: Recusa que acontece antes da regra
- **WHEN** um teste espera recusa e ela acontece numa barreira anterior à que o
  teste existe para exercer
- **THEN** o teste não serve como prova daquela regra, e é reescrito ou
  substituído por um que alcance a barreira certa

### Requirement: Cada papel de teste tem uma definição só

As formas de assumir um papel no banco DEVEM viver num lugar só, compartilhado
pelos arquivos da suíte. Arquivo novo NÃO DEVE escrever a própria.

Cópias divergem, e a divergência aqui é invisível: dois arquivos que dizem
testar a mesma pessoa sob nomes iguais passam a testar coisas diferentes, e
nada fica vermelho.

**A divergência não é hipótese — foi medida em 2026-08-16.** Havia três
definições de "Visitante", duas locais a um arquivo, e as três faziam a coisa
errada. Pior, e num papel que ninguém suspeitava: das **48 cópias locais de
"usuário autenticado", 16 não devolvem `request.jwt.claims` ao estado
anterior** e 32 devolvem. O comentário que explica por que o reset é
obrigatório — sem ele o papel seguinte ainda enxerga a identidade anterior —
mora dentro de UMA das 32, onde as outras 47 não o leem.

**Débito declarado, e é permissão para não consertar agora, não para deixar
crescer:** as 48 continuam existindo. Unificá-las é varredura de risco próprio
— cada arquivo tem um `tearDown` diferente — e está registrada em
`PENDENCIAS.md` com a contagem e a data. O que esta requirement proíbe a partir
de hoje é a 49ª.

#### Scenario: Arquivo novo precisa de um papel que já existe
- **WHEN** um teste novo precisa rodar sob um papel que a suíte já usa
- **THEN** ele usa a definição compartilhada, sem escrever a própria

#### Scenario: Uma cópia esquece de desfazer o que fez
- **WHEN** uma forma de assumir papel não devolve a sessão ao estado anterior
- **THEN** o teste seguinte roda sob a identidade errada e passa ou falha por
  motivo que não é o dele
- **AND** nada aponta para a cópia que causou isso, porque o arquivo que falha
  não é o que tem o defeito
