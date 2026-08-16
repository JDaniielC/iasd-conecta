# superficie-sem-login Specification

## Purpose

O que uma requisição **sem sessão nenhuma** alcança do banco, e a distinção
entre ela e o Visitante. As duas foram tratadas como a mesma coisa desde o
começo do projeto, e é por isso que a superfície cresceu sem ninguém decidir.

## Requirements

### Requirement: Visitante tem sessão; sem sessão não é Visitante

O sistema DEVE tratar como coisas diferentes: quem usa o app **sem Perfil e sem
Conta** (Visitante), que tem sessão anônima e alcança o banco como usuário
autenticado, e quem chega **sem sessão nenhuma**, que alcança o banco como papel
público.

Toda regra escrita como "vale sem login" se refere ao **Visitante**, salvo onde
esta capability disser o contrário. Fechar o papel público NÃO DEVE ser lido
como fechar para Visitante.

A confusão entre os dois já produziu defeito medido: a denúncia de imagem de
quem não tem cadastro não acontecia, porque o código usava o id da sessão
anônima como se fosse ausência de Perfil.

#### Scenario: Visitante abre o app e vê o que é público
- **WHEN** alguém sem Perfil e sem Conta abre o app
- **THEN** enxerga os Grupos, as Ações públicas e as imagens de capa, como
  antes desta change
- **AND** consegue denunciar uma imagem sem se cadastrar

#### Scenario: Requisição sem sessão nenhuma
- **WHEN** uma requisição chega sem credencial de sessão, só com a chave que o
  app publica
- **THEN** ela não é Visitante, e alcança apenas o que esta capability declara

### Requirement: Sem sessão, o banco não entrega dado de pessoa

O sistema NÃO DEVE entregar, a uma requisição sem sessão, qualquer linha que
diga o que uma pessoa identificável faz: de que Grupo participa, a que Ação vai,
ou que cargo ocupa no distrito.

O critério é a chave publicável ir dentro do JavaScript publicado: qualquer
pessoa que abra o app a tem, e a partir dela monta a consulta que quiser sem se
identificar de forma nenhuma.

#### Scenario: Consulta sem sessão à lista de quem participa de um Grupo
- **WHEN** uma requisição sem sessão consulta quem participa dos Grupos
- **THEN** a consulta é recusada ou devolve zero linhas
- **AND** o mesmo vale para quem confirmou presença numa Ação e para quem
  administra o distrito

#### Scenario: A mesma consulta, agora como Visitante
- **WHEN** um Visitante consulta quem participa de um Grupo
- **THEN** a consulta devolve as linhas, como antes — o fechamento é do papel
  sem sessão, não do Visitante

### Requirement: O que fica aberto sem sessão é declarado, um a um

Para cada tabela que uma requisição sem sessão PODE ler, o sistema DEVE ter o
motivo registrado. Tabela sem motivo escrito NÃO DEVE ficar aberta.

A regra existe porque a abertura hoje não foi decidida: ela é o padrão de quem
escreveu a policy copiando a anterior. Um inventário sem motivo por linha volta
a crescer do mesmo jeito.

#### Scenario: Tabela aberta sem motivo escrito
- **WHEN** uma tabela pode ser lida sem sessão e não há motivo registrado para
  isso
- **THEN** a verificação do projeto acusa, e a tabela é fechada ou o motivo é
  escrito

#### Scenario: Tabela nova entra aberta por descuido
- **WHEN** uma tabela nova nasce legível sem sessão e ninguém declarou o motivo
- **THEN** a verificação do projeto acusa antes de a mudança ser publicada

### Requirement: O app continua abrindo quando a sessão anônima falha

O sistema DEVE abrir a tela inicial mesmo quando a sessão anônima não se
estabelece. É a única situação real em que o app fala com o banco sem sessão, e
ela existe hoje por decisão registrada — a falha do login anônimo não derruba o
arranque.

Fechar a superfície sem sessão NÃO DEVE transformar essa falha silenciosa numa
tela de erro.

#### Scenario: A sessão anônima não se estabelece
- **WHEN** o app arranca e o login anônimo falha
- **THEN** a tela inicial aparece
- **AND** nenhuma mensagem de erro cru é mostrada à pessoa

#### Scenario: A pessoa tenta uma ação que precisa do banco nesse estado
- **WHEN** ela toca algo que exige consulta ao banco enquanto está sem sessão
- **THEN** vê uma explicação, e não uma tela vazia nem um erro de servidor
