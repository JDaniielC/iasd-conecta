# Suite De Integracao Specification

## Purpose

O que a suíte de integração garante sobre si mesma. Ela roda os arquivos em
paralelo contra um único banco, então o isolamento entre arquivos é uma
propriedade que precisa ser escrita, não presumida.

## Requirements

### Requirement: A suíte é determinística em paralelo

Rodar `dart test test/integration` DEVE produzir o mesmo resultado em execuções
repetidas, com os arquivos rodando em paralelo contra o mesmo banco.

Um arquivo NÃO DEVE alcançar linha criada por outro — nem para ler contagem, nem
para apagar em limpeza.

Cada arquivo DEVE ter **identidade própria**: os Usuários que ele cria não são
os de nenhum outro arquivo. Duas limpezas concorrentes sobre a mesma pessoa são
a janela por onde a suíte deixa de ser prova.

Quando dois arquivos disputam um recurso que é **global por natureza** — uma
tabela cuja contagem o app usa para decidir —, essa disputa DEVE ser declarada
e serializada onde ela acontece. Descobri-la por falha intermitente é o modo de
falha que esta requirement existe para eliminar.

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

#### Scenario: Dois arquivos não compartilham identidade

- **WHEN** alguém varre os identificadores de Usuário declarados na suíte
- **THEN** nenhum aparece em mais de um arquivo

#### Scenario: Decisão que depende de contagem global

- **WHEN** um teste exercita uma regra que o app decide pela contagem de uma
  tabela global, e outro arquivo escreve na mesma tabela
- **THEN** os dois são serializados entre si, e a regra é exercida sobre a
  contagem que o teste montou

#### Scenario: Identidade repetida reintroduzida

- **WHEN** alguém acrescenta um arquivo com identificador de Usuário que já
  pertence a outro
- **THEN** uma verificação automática falha, e ela falha dizendo quais dois
  arquivos colidem

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

Assumir um papel DEVE devolver a sessão ao estado anterior, e isso inclui o que
`reset role` não limpa.

A regra DEVE ser verificável por máquina. Uma regra sobre 48 arquivos que só
uma pessoa lendo com atenção consegue conferir é uma regra que volta a ser
violada na change seguinte.

#### Scenario: Arquivo novo precisa de um papel que já existe
- **WHEN** um teste novo precisa rodar sob um papel que a suíte já usa
- **THEN** ele usa a definição compartilhada, sem escrever a própria

#### Scenario: Uma cópia esquece de desfazer o que fez
- **WHEN** uma forma de assumir papel não devolve a sessão ao estado anterior
- **THEN** o teste seguinte roda sob a identidade errada e passa ou falha por
  motivo que não é o dele
- **AND** nada aponta para a cópia que causou isso, porque o arquivo que falha
  não é o que tem o defeito

#### Scenario: Nenhuma cópia local resta
- **WHEN** alguém varre a suíte procurando definições locais de papel
- **THEN** não há nenhuma — todas usam a compartilhada

#### Scenario: Cópia local reintroduzida
- **WHEN** alguém escreve uma definição local de papel num arquivo de teste
- **THEN** uma verificação automática falha, e ela falha dizendo em qual
  arquivo

#### Scenario: A identidade não sobrevive ao fim do papel
- **WHEN** um trecho roda sob um papel e termina
- **THEN** a sessão volta a não ter identidade nenhuma, e o trecho seguinte que
  não assumir papel enxerga isso
