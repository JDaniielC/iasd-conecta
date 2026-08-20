# Disciplina De Teste Specification

## Purpose

Quando um teste precisa existir em relação ao código que ele prova, e qual é o
piso de cobertura que a árvore não pode furar. O Princípio IV da constituição
diz *que* a regra de domínio é testada; esta capability diz *quando* o teste é
escrito e *como* se sabe que ele ainda existe amanhã.

## Requirements

### Requirement: O teste é escrito antes do código que ele prova

Comportamento novo ou alterado DEVE ter, antes do código de produção que o
satisfaz, um teste que descreve esse comportamento e que **falha**.

O teste NÃO DEVE ser escrito depois, a partir do código pronto. Um teste
escrito olhando para a implementação descreve o que o código faz, não o que o
requisito pede — e as duas coisas divergirem em silêncio é exatamente o defeito
que o teste existia para pegar.

Exceções declaradas, e são só estas quatro: correção de texto de tela sem
mudança de regra, tradução de identificador, mudança que só move código sem
alterar comportamento observável, e **cobertura retroativa de código que já
existe** — que não é comportamento novo nem alterado, e por isso nasce verde.

A quarta não é frouxidão. Teste-primeiro pressupõe comportamento que ainda não
existe; escrever teste para uma tela que já funciona não tem vermelho legítimo a
oferecer, e forjar um — comentar a tela para descomentar depois — seria teatro
apresentado como disciplina.

#### Scenario: Comportamento novo

- **WHEN** alguém vai implementar um comportamento que o app ainda não tem
- **THEN** o teste desse comportamento é escrito primeiro, roda, e falha
- **AND** só então o código de produção é escrito, até o teste passar

#### Scenario: Correção de defeito

- **WHEN** um defeito é relatado
- **THEN** existe um teste que reproduz o defeito e falha antes do conserto
- **AND** esse teste passa a integrar a suíte, para o defeito não voltar sem
  ninguém perceber

#### Scenario: Mudança que a exceção cobre

- **WHEN** a mudança é só texto de tela, tradução de identificador ou
  movimentação de código sem efeito observável
- **THEN** nenhum teste novo é exigido, e o que já existe continua verde

#### Scenario: Cobertura retroativa de código que já existe

- **WHEN** alguém escreve teste para código que já está em produção e funciona
- **THEN** o teste nasce verde, e isso não é violação — não há comportamento
  novo nem alterado a provar
- **AND** ninguém forja um vermelho desabilitando o código para reabilitá-lo
  depois

### Requirement: O vermelho prova o que o teste diz provar

Um teste que falha antes do código só serve de prova se falhar **pelo motivo do
requisito**. Falhar porque não compila, porque o widget não foi encontrado na
árvore, ou porque o setup não montou, é vermelho que não prova nada — e vira
verde assim que o obstáculo sai, com o requisito ainda por implementar.

Quem escreve o teste DEVE conferir a mensagem da falha antes de escrever o
código de produção.

Em escrita do cliente contra o Supabase, o vermelho de uma recusa de RLS é
**contagem de linhas afetadas igual a zero**, nunca exceção — a policy que
recusa faz a linha não existir para aquela sessão, e o `update` volta com
sucesso sobre nada. Um teste que espera exceção aí passa pelo motivo errado ou
não passa nunca.

#### Scenario: A falha é do requisito

- **WHEN** o teste escrito primeiro roda e falha
- **THEN** a mensagem da falha aponta para a asserção do requisito — valor
  errado, contagem errada, estado errado

#### Scenario: A falha é de andaime

- **WHEN** o teste falha por erro de compilação, por elemento não encontrado na
  árvore, ou por falha de setup
- **THEN** o teste é consertado até falhar pelo motivo certo, antes de qualquer
  linha de código de produção

#### Scenario: A regra sob teste é uma recusa de RLS

- **WHEN** o teste prova que uma policy recusa uma escrita
- **THEN** a asserção é sobre linhas afetadas serem zero, e não sobre exceção
  levantada

### Requirement: A cobertura é medida e o piso não desce

O repositório DEVE ter um comando único que mede a cobertura de linhas dos
testes de unidade e de widget, imprime o número medido, e **termina com falha
quando o número fica abaixo do piso registrado**.

O piso DEVE estar escrito no repositório, versionado, com o número e a data em
que foi medido. Ele sobe quando a cobertura sobe; NÃO DEVE ser baixado para
fazer uma árvore vermelha passar.

O gate DEVE rodar na integração contínua, no mesmo estágio dos outros gates
rápidos. Uma queda de cobertura NÃO DEVE ser descoberta só quando alguém rodar
o comando à mão.

#### Scenario: Cobertura acima do piso

- **WHEN** o comando de cobertura roda numa árvore cuja cobertura está no piso
  ou acima
- **THEN** ele imprime o número e termina com sucesso

#### Scenario: Cobertura abaixo do piso

- **WHEN** código de produção entra sem teste e a cobertura cai abaixo do piso
- **THEN** o comando imprime o número medido, o piso, e termina com falha
- **AND** a execução de CI aparece como falha

#### Scenario: Baixar o piso não é o conserto

- **WHEN** o gate reprova
- **THEN** o caminho é escrever o teste que falta
- **AND** alterar o número do piso para baixo exige justificativa escrita no
  commit — remoção deliberada de código testado, por exemplo — porque o piso é
  o registro do que já esteve provado

#### Scenario: A suíte falha antes da medição

- **WHEN** algum teste de unidade ou widget falha
- **THEN** o comando termina com falha por causa do teste, e não reporta número
  de cobertura — medir cobertura de suíte vermelha informa uma porcentagem de
  execução parcial, que não é comparável com o piso

### Requirement: O denominador da cobertura é declarado

O que entra e o que sai da conta de cobertura DEVE estar escrito junto do
comando que mede, com o motivo de cada exclusão.

Exclusão sem motivo escrito é como o número sobe sem o código melhorar: basta
tirar do denominador o que não tem teste. O motivo escrito é o que permite
alguém, depois, discordar dele.

Neste projeto a exclusão que existe é a camada de repositório
(`lib/features/*/data/`): quem a exercita é a suíte de integração, que roda
contra Postgres e não entra nesta medição. Mantê-la no denominador faria o
número medir a ausência da integração, não a cobertura do código.

#### Scenario: Um caminho é excluído da conta

- **WHEN** um caminho de `lib/` fica fora do denominador
- **THEN** o motivo está escrito junto da exclusão, e diz onde aquele código é
  provado, ou por que não precisa ser

#### Scenario: Código sem teste em nenhuma suíte

- **WHEN** um caminho é excluído do denominador e não é coberto por nenhuma
  outra suíte
- **THEN** a exclusão não é aceita — o número precisa refletir que aquele
  código não está provado
