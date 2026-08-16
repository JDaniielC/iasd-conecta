# Contrato de conteúdo — o que vira Novidade, e como se escreve

Criado pela feature 022. Este arquivo mora na raiz do repositório de propósito: quem escreve
uma Novidade precisa tropeçar nele.

Este é o contrato mais importante da feature, e ele não é de código. A tela é simples; o que
falha com o tempo é o **texto**.

O modo de falha é conhecido e previsível: quem escreve a Novidade é quem acabou de fazer a
mudança, com o commit fresco na cabeça. "Corrigido bug na RLS de votos" sai naturalmente — é
verdadeiro, é inútil e é assustador. Seis meses assim e a tela é um changelog técnico que
ninguém do distrito lê.

As Novidades ficam em `lib/features/news/domain/news_item.dart`, na lista `allNews`.

## Vira Novidade

O que **a pessoa percebe**:

- algo que ela passou a poder fazer;
- algo que parou de funcionar como antes, ou sumiu;
- algo sobre **os dados dela** que mudou — quem vê o quê, o que é guardado, o que é apagado.

## Não vira Novidade

O que só quem constrói percebe: refatoração, correção sem efeito visível, ajuste de
infraestrutura, mudança de teste, atualização de dependência.

**Exceção que importa**: correção de segurança **com** efeito sobre o que os outros enxergam
da pessoa **vira** Novidade — não como "corrigimos uma falha", mas dizendo o que mudou para
ela. Ver o terceiro exemplo abaixo.

## Como se escreve

1. **Na segunda pessoa, sobre o que muda para ela.** Não sobre o que o app passou a fazer.
2. **Sem jargão** (FR-003): nada de nome de arquivo, tabela, função, política ou número de
   versão interna.
3. **Uma ideia por item.** Duas mudanças no mesmo dia são dois itens.
4. **Remoção se descreve igual** (FR-016). Alguém usava aquilo.
5. **Teste final**: leia em voz alta para alguém do distrito. Se precisar explicar depois de
   ler, não está pronto.

## Exemplos — o mesmo fato, das duas formas

| ❌ Como sai naturalmente | ✅ Como se escreve |
|---|---|
| "Fechada a policy `votos_select_public`, que era `using (true)`" | "Em quem você votou agora só você vê. Antes, qualquer pessoa conseguia consultar." |
| "Adicionada tela `MyProfilePage` consumindo `perfis_update_own`" | "Você já pode ver e corrigir seus dados sozinho, em Meu Perfil — sem precisar escrever para a gente." |
| "Corrigido vazamento em `liderancas_select_public`" | "Quem se declara Líder de um Ministério e não é confirmado não aparece mais para ninguém." |
| "Implementado `arquivar_grupo` com `security definer`" | "O Dono de um Grupo pode arquivá-lo. As Ações já marcadas são canceladas, e quem tinha confirmado presença é avisado na própria Ação." |
| "Bump de `LegalMetadata.version` para 1.3" | *(não vira Novidade — a mudança do texto legal já tem o próprio aviso)* |

## Quando se escreve

**Ao fechar a change, junto com o último commit dela — não depois.** A regra existe porque o
modo de falha já aconteceu: entre 11 e 13 de agosto de 2026, cinco changes com efeito visível
foram arquivadas em `main` e **nenhuma** escreveu Novidade. Nenhuma delas tinha uma tarefa
para isso, e ninguém sentiu falta: a tela continuava funcionando, os testes continuavam
verdes, e o `openspec validate` não olha para cá. O buraco só apareceu porque alguém
perguntou se a tela estava em dia — três dias e cinco changes depois.

Na prática, para quem está aplicando uma change:

- Se ela muda algo que **a pessoa percebe** pelos critérios acima, ela tem uma tarefa de
  Novidade na seção de fechamento do `tasks.md`, ao lado dos gates.
- Se ela **não** muda, escreva isso em uma linha na tarefa de fechamento. "Não vira Novidade
  porque nenhuma tela muda" é uma decisão registrada; silêncio não é.

O que **não** funciona, e por isso não está escrito como alternativa: escrever as Novidades
em lote depois, olhando o histórico do git. Cada item precisa do que a pessoa passou a
perceber, e isso está na cabeça de quem fez a mudança — não na commit message.

## Sobre o marco

Só entra na tela o que tem data a partir de **6 de outubro de 2026**, o lançamento para o
distrito. O que veio antes é o app como ele nasceu.

Novidade com data anterior pode ser escrita — ela simplesmente não aparece. É filtro de
exibição, não regra de escrita, e é o que permite mudar de ideia sobre o marco sem reescrever
nada.
