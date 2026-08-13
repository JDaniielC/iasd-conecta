## 1. Banco — colunas e gatilho

- [ ] 1.1 **Reler o gatilho `before update` de `mensagens` que
      `chat-de-grupo-e-acao` deixou**, antes de escrever qualquer coisa. Esta
      change o edita; se ele mudou, a edição planejada não casa
- [ ] 1.2 `alter table public.mensagens add column fixada_em timestamptz, add
      column fixada_por uuid references public.perfis(id)`
- [ ] 1.3 Acrescentar `fixada_em` e `fixada_por` à lista de colunas que aquele
      gatilho permite alterar — e **nada mais** na lista
- [ ] 1.4 Constante nomeada do teto (3) na migration, com comentário de que é
      escolha e não medição
- [ ] 1.5 `comment on column` nas duas, dizendo que fixada não expira e que
      desfixar devolve a mensagem ao prazo

## 2. Banco — regras de fixar e desfixar

- [ ] 2.1 No gatilho: transição nulo → não nulo exige autoridade do espaço
      (dono do Grupo, criador da Ação, dono do Grupo da Ação, Administrador do
      distrito). Reusar o mesmo predicado da remoção, não reescrever
- [ ] 2.2 Transição não nulo → nulo aceita autoridade do espaço **ou** autor da
      mensagem
- [ ] 2.3 Teto: na transição nulo → não nulo, `for update` na linha do Grupo ou
      da Ação **primeiro**, depois contar as fixadas do chat e recusar acima de
      3
- [ ] 2.4 Fixar mensagem já fixada não altera `fixada_por` nem `fixada_em`
- [ ] 2.5 Quando `texto` passa a nulo no mesmo `update`, zerar `fixada_em` e
      `fixada_por` na mesma linha — sem segundo gatilho, sem recursão

## 3. Banco — expurgo e exclusão de conta

- [ ] 3.1 `expurgar_mensagens_de_acao()` ganha `and fixada_em is null`. Nada
      mais muda naquela função
- [ ] 3.2 Confirmar que `excluir_conta` **não** precisa de linha nova: o
      `update ... set texto = null` existente já dispara o desfixe de 2.5.
      Provar por teste, não por leitura

## 4. Prova no banco (test/integration)

- [ ] 4.1 Autoridade: dono do Grupo fixa; criador da Ação avulsa fixa;
      Administrador fixa; participante comum é recusado; participante comum
      fixando a própria mensagem é recusado; dono de outro Grupo é recusado.
      Seis casos
- [ ] 4.2 Autor desfixa mensagem que outra pessoa fixou; autor sem autoridade
      tentando fixar de volta é recusado
- [ ] 4.3 Teto: 3 fixadas passam, a 4ª é recusada; desfixar libera e a 4ª passa
- [ ] 4.4 Concorrência: duas fixações simultâneas com uma vaga resultam em
      exatamente 1 fixada. Sem este teste a trava não está provada
- [ ] 4.5 Expurgo: Ação de 31 dias com 1 fixada mantém a fixada e apaga o
      resto, com contagem antes e depois
- [ ] 4.6 Desfixar depois do prazo: expurgo seguinte apaga, sem carência nova
- [ ] 4.7 Remoção por moderação de mensagem fixada a desfixa e libera a vaga
- [ ] 4.8 `excluir_conta` sobre autor de mensagem fixada: `texto` nulo e
      `fixada_em` nulo, na mesma transação
- [ ] 4.9 Mensagem de Grupo fixada nunca é apagada por expurgo — Grupo não
      expira, mas confirmar que a condição nova não introduziu caminho
- [ ] 4.10 Não participante e menor de 18 consultando as fixadas recebem 0
      linhas. A fixação não pode ter aberto porta que a leitura não abria
- [ ] 4.11 `update` tentando alterar coluna fora da lista permitida continua
      recusado — o teste de `chat-de-grupo-e-acao` estendido com as duas novas

## 5. Dart — dados

- [ ] 5.1 Modelo ganha `fixadaEm`/`fixadaPor`; teto como constante num lugar só
- [ ] 5.2 Teste de integração comparando o teto do Dart com o da migration
- [ ] 5.3 Repositório: fixar, desfixar, e carregar as fixadas do chat —
      incluindo fixada antiga, fora da primeira página do histórico
- [ ] 5.4 Decidir entre `union` na consulta de histórico e segunda consulta
      cacheada **medindo** as duas, não escolhendo antes (ver design)

## 6. Dart — tela

- [ ] 6.1 Faixa de fixadas acima da conversa, **recolhida por padrão**,
      expandindo sob toque
- [ ] 6.2 Sem fixada, nenhuma faixa ocupa espaço
- [ ] 6.3 Ação de fixar/desfixar visível só a quem pode executá-la; desfixar
      aparece também para o autor
- [ ] 6.4 Teto atingido: dizer que é preciso desfixar alguma, não devolver erro
      cru

## 7. Prova no cliente (test/widget, test/unit)

- [ ] 7.1 Widget: 3 fixadas de 2000 caracteres cada, **na largura de celular** —
      a conversa continua visível e rolável sem interação extra. Julgar em
      celular, nunca no desktop
- [ ] 7.2 Widget: chat sem fixada não mostra faixa
- [ ] 7.3 Widget: participante comum não vê ação de fixar; autor vê desfixar na
      própria mensagem fixada
- [ ] 7.4 Widget: lápide nunca aparece na faixa

## 8. Legal e ledgers — bloqueia o fechamento

- [ ] 8.1 Política de Privacidade (`lib/features/legal/`): o prazo de 30 dias
      passa a ter exceção declarada, com o teto. Manter "30 dias" sem ressalva
      torna a política falsa. Rodar o agente `advogado-digital`
- [ ] 8.2 `REVISAO-JURIDICA.md`: a exceção ao prazo, o teto, e o limite
      conhecido — quem é citado por outro não tem caminho para desfixar
- [ ] 8.3 `MAPA-DE-DADOS.md`: as duas colunas novas com `arquivo:linha`
- [ ] 8.4 Rodar o agente `promessa-vs-execucao` cruzando o prazo e a exceção
      declarados na Política contra o `where` real do expurgo
- [ ] 8.5 `PENDENCIAS.md`: o que ficar aberto

## 9. Fechamento

- [ ] 9.1 Gates com números reais: `flutter analyze` (0 issues), `flutter test
      test/unit test/widget` (contagem), `dart test test/integration` com
      `supabase start` (contagem), `flutter build web --release`
- [ ] 9.2 Commit registra que o rollback **não** é sem perda: reverter apaga
      mensagem fixada de Ação já vencida no expurgo seguinte
- [ ] 9.3 Rodar a skill `openspec-converge` e resolver o que ela achar
