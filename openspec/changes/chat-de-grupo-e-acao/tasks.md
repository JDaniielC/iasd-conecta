## 1. Banco — funções de acesso

- [ ] 1.1 `maior_de_idade()`: `stable`, `security definer`, `set search_path =
      public, pg_temp`, com `idade is not null and idade >= 18` explícito.
      Comentário na migration dizendo por que é `definer` e não `invoker`
      (ver design)
- [ ] 1.2 `pode_ver_chat_grupo(uuid)`: participa do Grupo **e**
      `maior_de_idade()`. `stable`, `security invoker`
- [ ] 1.3 `pode_ver_chat_acao(uuid)`: confirmação em qualquer status **ou**
      criador da Ação **ou** dono do Grupo dela — e `maior_de_idade()`. Reusar
      o predicado de `acoes_update_criador_ou_dono_grupo`
      (`20260724084300:228-239`), não reescrever
- [ ] 1.3a As duas funções de acesso são `security invoker`, **não** `definer`
      — é o que faz o chat herdar sozinho a restrição de
      `acao-direcionada-a-grupo`. Comentário na migration explicando por que
      `maior_de_idade()` é definer e estas duas não são; sem ele, a próxima
      pessoa uniformiza as três e abre o chat de Ação restrita
- [ ] 1.4 Testes de unidade SQL das três funções, isolados das policies: cada
      combinação de participação × idade × papel, com número real de casos
      anotado

## 2. Banco — tabela `mensagens`

- [ ] 2.1 Tabela com o `check` de XOR entre `grupo_id` e `acao_id`, `texto`
      anulável com limite de 2000, `removida_em`/`removida_por`, `autor_id`
      não nulo
- [ ] 2.2 Índices parciais `(grupo_id, created_at desc)` e `(acao_id,
      created_at desc)`
- [ ] 2.3 Policies chamando **só** as funções de 1.2/1.3, nunca a condição
      inline: `select`, `insert` (com `auth.uid() = autor_id` e Grupo não
      arquivado), `update` restrito a autor + autoridade do espaço com
      `with check` gêmeo do `using`. **Nenhuma** policy de `delete`
- [ ] 2.4 Gatilho `before update` que recusa qualquer alteração fora de
      `texto`, `removida_em`, `removida_por`, e recusa `texto` não nulo — sem
      ele, quem remove consegue reescrever e "mensagem não se edita" é letra
      morta
- [ ] 2.5 `comment on table`/`on column` registrando as três lápides e que o
      texto removido não é guardado em lugar nenhum

## 3. Banco — moderação

- [ ] 3.1 `denuncias_mensagem` no molde de `denuncias_imagem`
      (`20260810120000`), com `mensagem_id ... on delete set null` (não
      cascade) e `estado` incluindo `sem_mensagem`
- [ ] 3.2 Policies: `insert` para quem lê aquele chat, com `with check`
      impedindo assinar por outro; `select` e `update` só para autoridade do
      espaço e Administrador do distrito, `with check` gêmeo do `using`
- [ ] 3.3 Gatilho `after delete` em `mensagens` que marca denúncia pendente
      como `sem_mensagem`, preservando `motivo`

## 4. Banco — retenção e exclusão de conta

- [ ] 4.1 `expurgar_mensagens_de_acao()`: apaga mensagem cuja Ação passou de
      `data_hora + interval '30 days'`. Consulta **antes** de sair cedo — ver
      `20260810170000:21-27`
- [ ] 4.2 Agendamento `pg_cron` na migration, e registrar em
      `INFRA-PRODUCAO.md` que produção exige criá-lo à mão
- [ ] 4.3 Segundo gatilho: o app chama o expurgo ao abrir um chat. Sem ele o
      prazo não se cumpre com o banco pausado (`20260810170000:9-14`)
- [ ] 4.4 `excluir_conta` ganha `update mensagens set texto = null where
      autor_id = ...`, dentro da transação existente. Não criar caminho de
      falha parcial novo

## 5. Prova no banco (test/integration)

- [ ] 5.1 Corte de idade: perfil com 17 anos lê 0 mensagens e tem `insert`
      recusado; perfil com 18 lê e escreve; Visitante (anônimo, sem Perfil)
      lê 0; Perfil anonimizado lê 0. Quatro credenciais
- [ ] 5.2 Chat de Grupo: participante lê e escreve; não participante lê 0;
      quem saiu do Grupo lê 0 inclusive das mensagens anteriores à saída
- [ ] 5.3 Chat de Ação: confirmado lê; em fila lê e escreve; participante do
      Grupo sem confirmação lê 0 da Ação e continua lendo o Grupo; dono do
      Grupo sem confirmar lê e escreve; quem desconfirmou lê 0
- [ ] 5.3a **Só se `acao-direcionada-a-grupo` já estiver aplicada** (conferir
      se `acoes.restrita_ao_grupo` existe antes de escrever este teste):
      Ação restrita ao Grupo — quem não participa do Grupo lê 0 mensagens
      daquele chat, mesmo tendo 18 anos ou mais. Prova que o `security
      invoker` de 1.3a está fazendo o trabalho. Se a coluna não existir ainda,
      registrar em `PENDENCIAS.md` que este teste é dívida daquela change
- [ ] 5.4 Escrita: assinar por outro é recusado; texto vazio recusado; 2001
      caracteres recusado; 2000 aceito
- [ ] 5.5 `update` de `texto` pelo autor é recusado; `update` que troca
      `grupo_id`, `acao_id`, `autor_id` ou `created_at` é recusado
- [ ] 5.6 Grupo arquivado: `insert` recusado, `select` das antigas continua
      funcionando
- [ ] 5.7 Remoção: dono do Grupo remove; criador da Ação avulsa remove;
      Administrador remove; autor remove a própria; participante comum é
      recusado; dono de **outro** Grupo é recusado. Seis casos
- [ ] 5.8 Depois de remover, `texto` volta nulo para todos os papéis,
      inclusive Administrador do distrito. Remover de novo não sobrescreve
      `removida_por`
- [ ] 5.9 Denúncia: participante denuncia; motivo vazio recusado; assinar por
      outro recusado; quem não lê o chat é recusado; participante comum lê 0
      denúncias, inclusive a que ele mesmo criou
- [ ] 5.10 Expurgo: Ação de 31 dias atrás perde as mensagens; Ação de ontem
      mantém; mensagem de Grupo nunca some; Grupo arquivado mantém
- [ ] 5.11 Denúncia pendente sobre mensagem expurgada vira `sem_mensagem`, com
      `motivo` preservado
- [ ] 5.12 `excluir_conta`: mensagens do titular ficam com `texto` nulo e
      `removida_em` nulo (lápide de conta excluída, distinta da de moderação);
      mensagem de terceiro que cite o titular fica intacta

## 6. Prova do canal de tempo real

- [ ] 6.1 `alter publication supabase_realtime add table public.mensagens`,
      com RLS ligado
- [ ] 6.2 Teste: participante assina o canal, outro escreve, o evento chega
      dentro de uma janela determinada
- [ ] 6.3 **Teste de não entrega** — o que prova a policy: não participante
      assina, alguém escreve, e o teste falha se **qualquer** evento chegar
      dentro da janela. Repetir com credencial de menor de 18. Sem estes dois,
      6.2 não prova nada sobre vazamento
- [ ] 6.4 Anotar a janela usada e por quê. Janela curta demais faz o teste
      passar por não ter esperado

## 7. Dart — dados e tempo real

- [ ] 7.1 `lib/features/chat/domain/message.dart`: as três lápides derivadas
      de `texto` + `removida_em`, sem coluna extra
- [ ] 7.2 `lib/features/chat/data/chat_repository.dart`: consulta de histórico
      paginada, envio, remoção, denúncia
- [ ] 7.3 Assinatura do canal por espaço, com dedução por `id` entre o que veio
      da consulta e o que veio do canal — sem ela a mensagem aparece duas vezes
- [ ] 7.4 Estado de conexão exposto à tela: ao vivo / reconectando / sem tempo
      real. Ao reconectar, refazer a consulta para pegar o que passou na queda
- [ ] 7.5 Chamada do expurgo ao abrir um chat (segundo gatilho da tarefa 4.3),
      sem bloquear a renderização

## 8. Dart — tela

- [ ] 8.1 Aba de conversa em `group_detail_page.dart` e em
      `action_detail_page.dart`, só quando a pessoa pode ver o chat
- [ ] 8.2 Quando não pode por idade, a tela **diz por quê** em vez de esconder
      sem explicação — ver design, Risks
- [ ] 8.3 Campo de envio com contador de 2000 e recusa local antes do envio
- [ ] 8.4 Renderização das três lápides com textos distintos
- [ ] 8.5 Remover pede confirmação e avisa que é definitivo
- [ ] 8.6 Denunciar: motivo obrigatório; tela de denúncias visível só a quem
      tem autoridade no espaço
- [ ] 8.7 Grupo arquivado: histórico legível, campo de envio ausente

## 9. Prova no cliente (test/widget, test/unit)

- [ ] 9.1 Unidade: derivação das três lápides, seis casos (`texto` × `removida_em`)
- [ ] 9.2 Unidade: dedução por `id` entre consulta e canal não duplica e não
      perde
- [ ] 9.3 Widget: menor de 18 vê a explicação, não a aba vazia
- [ ] 9.4 Widget: sem tempo real, o chat funciona e sinaliza; não fica em
      carregamento perpétuo
- [ ] 9.5 Widget: Grupo arquivado mostra histórico sem campo de envio
- [ ] 9.6 Widget: as três lápides renderizam sem `null` na tela

## 10. Legal e ledgers — bloqueia o fechamento

- [ ] 10.1 `MAPA-DE-DADOS.md`: `mensagens` e `denuncias_mensagem` com
      `arquivo:linha`, **declarando que o conteúdo de `texto` é indeterminado**
      em vez de fingir que o descreve
- [ ] 10.2 Política de Privacidade e Termos de Uso (`lib/features/legal/`):
      categoria de dado nova, prazo de 30 dias como promessa, corte de idade,
      responsabilidade de quem escreve, e o limite explícito de que mensagem de
      terceiro que cite a pessoa não é apagada pela exclusão de conta — só por
      denúncia. Rodar o agente `advogado-digital`, que lê o código antes
- [ ] 10.3 `REVISAO-JURIDICA.md`: registrar as decisões com efeito legal —
      corte etário em 18, retenção de 30 dias, moderação humana reativa, texto
      removido não conservado
- [ ] 10.4 `INFRA-PRODUCAO.md`: o `pg_cron` a agendar à mão em produção
- [ ] 10.5 `SECURITY-AUDIT.md` / `PENDENCIAS.md`: o que ficar aberto, com o
      porquê
- [ ] 10.6 Rodar o agente `promessa-vs-execucao` cruzando o prazo prometido na
      Política contra o expurgo real. É exatamente a classe de defeito que ele
      procura

## 11. Fechamento

- [ ] 11.1 Gates com números reais anotados: `flutter analyze` (0 issues),
      `flutter test test/unit test/widget` (contagem), `dart test
      test/integration` com `supabase start` (contagem), `flutter build web
      --release` (sucesso)
- [ ] 11.2 Rodar o agente `pentest-etico` sobre a superfície nova — REST do
      Supabase e canal de Realtime, com credencial de menor e de não
      participante
- [ ] 11.3 Rodar a skill `openspec-converge` e resolver o que ela achar antes
      de arquivar
