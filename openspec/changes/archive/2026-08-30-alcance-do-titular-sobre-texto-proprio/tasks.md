## 1. Banco — as duas funções

- [x] 1.1 **Reler `mensagens_so_remove` antes de escrever qualquer coisa.** Ele
      é `security definer` e já aceita o autor no braço de desfixe; a função
      nova não pode reimplementar aquela regra, só alcançar a linha
- [x] 1.2 `desfixar_minha_mensagem(p_mensagem_id uuid) returns integer` —
      `security definer`, `search_path = ''`, `auth.uid() = autor_id` como
      predicado INTEIRO, sem braço de autoridade. Zera as duas colunas e
      devolve `row_count`
- [x] 1.3 `minhas_mensagens_fixadas()` — `security definer`, `stable`, devolve
      as fixadas de `auth.uid()`. **Sem `fixada_por`**: quem fixou é dado sobre
      outra pessoa. Com o nome do espaço, para a pessoa saber de onde é
- [x] 1.4 `revoke execute from public` nas duas e `grant execute to
      authenticated`, nessa ordem — `grant` acrescenta, não substitui
      (armadilha de 20260816120000)
- [x] 1.5 `comment on function` nas duas, dizendo por que existem: a policy de
      `select` esconde a linha, e um `update` não alcança linha que não lê

## 2. Prova no banco (test/integration)

- [x] 2.1 Autor que **saiu do Grupo** desfixa pela função: 1 linha, e a linha
      fica com `fixada_em` nulo. É o caso medido em `PENDENCIAS.md` 2.28, e o
      teste tem de falhar sem a função
- [x] 2.2 Autor que **desistiu da Ação** desfixa. Mesmo caso, espaço diferente
- [x] 2.3 Autor com idade corrigida para 17 desfixa — o corte de idade decide o
      que ela lê, não o que ela retira do que escreveu
- [x] 2.4 **Não autor** chamando a função sobre mensagem alheia: zero linhas, e
      a mensagem continua fixada. Inclui quem tem autoridade no espaço — ela
      tem o caminho de dentro, não este
- [x] 2.5 `minhas_mensagens_fixadas()` de uma pessoa **não** traz mensagem de
      outra na mesma conversa. Duas pessoas, uma conversa, duas fixadas
- [x] 2.6 `minhas_mensagens_fixadas()` de quem saiu do Grupo traz a fixada
      dele daquele Grupo — é o caso que a policy de `select` esconde
- [x] 2.7 A função de leitura **não devolve `fixada_por`** — conferir a lista
      de colunas, não o valor
- [x] 2.8 As duas funções **não** são alcançáveis sem sessão: `anon` recebe
      `42501`. Molde de `chat_privilegio_funcao_test.dart`
- [x] 2.9 Depois de desfixar pela função, o expurgo seguinte apaga a mensagem
      vencida — sem carência nova. Fecha o laço com a promessa da Política

## 3. Dart — dados e tela

- [x] 3.1 Repositório: `unpinMyMessage` e `fetchMyPinned`, pelas duas funções.
      `unpinMyMessage` distingue "não era sua" de "não estava fixada" pelo
      número devolvido, e não por texto de erro
- [x] 3.2 Entrada em `Meu Perfil`, junto de onde a pessoa já exerce direito
      sobre os próprios dados
- [x] 3.3 Lista das próprias fixadas, com desfixar por linha. **Some quando não
      há nenhuma** — seção vazia é espaço gasto à toa
- [x] 3.4 Julgar o layout **na largura de celular**

## 4. Prova no cliente (test/widget)

- [x] 4.1 Widget: a lista vazia não desenha seção nenhuma
- [x] 4.2 Widget: desfixar tira a linha da lista na hora, sem recarregar
- [x] 4.3 Widget: falha ao desfixar mantém a linha e diz o que aconteceu — não
      some com o item sobre uma operação que não deu certo

## 5. Legal e ledgers — bloqueia o fechamento

- [x] 5.1 Política de Privacidade: o trecho que hoje manda escrever para o
      e-mail de contato passa a apontar o caminho no app. Rodar o agente
      `advogado-digital`
- [x] 5.2 Subir a versão do texto legal (`LegalMetadata` + linha em
      `versoes_texto_legal`), pelo mesmo critério da 1.7 — o texto exibido
      mudou, e o carimbo de consentimento é a prova de qual texto a pessoa leu
- [x] 5.3 `REVISAO-JURIDICA.md` § 4-E: o limite do autor fecha; registrar que
      2.25 continua aberta e por quê
- [x] 5.4 `PENDENCIAS.md`: 2.28 fecha com a medição de fechamento; 2.25
      permanece, com o motivo de não ter entrado
- [x] 5.5 Rodar o agente `promessa-vs-execucao` cruzando "você pode desfixar" —
      agora sem ressalva — contra os dois caminhos reais. **Zero achado**:
      promessa e execução batem, inclusive nos limites (mensagem de terceiro
      citando o titular, corretamente fora deste caminho)
- [x] 5.6 Novidade em `news_item.dart`, pelo `CRITERIO-DE-NOVIDADE.md`: é algo
      que a pessoa passou a poder fazer sobre os dados dela

## 6. Fechamento

- [x] 6.1 Gates com números reais: `flutter analyze` 0 issues. `flutter test
      test/unit test/widget`: 636/636. `dart test test/integration`: 534/534,
      2x. `flutter build web --release`: build ok.
- [x] 6.2 Rodar a skill `openspec-converge` e resolver o que ela achar

## Convergence 1

- [x] Escrever `test/integration/alcance_do_titular_api_test.dart`, no molde
      de `chat_fixada_api_test.dart` (fala HTTP real, com `SupabaseClient` e
      sessão assinada — não conexão direta). `desfixar_minha_mensagem` e
      `minhas_mensagens_fixadas` só tinham prova por conexão direta
      (`test/integration/alcance_do_titular_test.dart`) e por
      `ChatRepository` mockado (`test/widget/pinned_messages_section_test.dart`).
      Nada provava que `.rpc('desfixar_minha_mensagem', params: {'p_mensagem_id':
      ...})` chega certo ao PostgREST de verdade — mesma classe de risco que
      `chat_fixada_api_test.dart` existe para cobrir (o `errcode` e o nome do
      parâmetro só se confirmam no caminho real). Verificado por `curl` com
      sessão real nesta sessão (`minhas_mensagens_fixadas` devolve `[]`,
      `desfixar_minha_mensagem` devolve `0` para id inexistente) — os dois
      batem, mas isso não fica como prova permanente até virar teste.
