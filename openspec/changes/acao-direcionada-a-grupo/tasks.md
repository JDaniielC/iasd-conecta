## 1. Medir antes

- [ ] 1.1 `explain analyze` da leitura do feed (`select * from acoes` como
      `authenticated` e como `anon`) **antes** da mudança, com a base de seed.
      Guardar o número — sem ele, a comparação de 4.1 não existe
- [ ] 1.2 Conferir que `participacoes_grupo` não tem índice servindo busca por
      `usuario_id` (`\d public.participacoes_grupo`, PK é
      `(grupo_id, usuario_id)`) e colar a saída

## 2. Banco — coluna e restrição

- [ ] 2.1 Migration: `alter table public.acoes add column restrita_ao_grupo
      boolean not null default false`, mais
      `check (restrita_ao_grupo = false or grupo_id is not null)`. O `default
      false` é o que garante que nenhuma Ação existente muda de visibilidade
- [ ] 2.2 `comment on column` dizendo que restrição exige Grupo e que o padrão é
      público de propósito
- [ ] 2.3 Índice `participacoes_grupo_por_usuario (usuario_id, grupo_id)` — a
      policy percorre a direção contrária à PK, uma vez por linha de `acoes`
- [ ] 2.4 Gatilho `before update` em `acoes` recusando mudança de
      `restrita_ao_grupo` quando `acao_encerrada(id)` é verdadeiro, ao lado da
      regra irmã de `20260809174740_acao_encerrada_bloqueia_presenca.sql`

## 3. Banco — policies

- [ ] 3.1 `drop policy acoes_select_public` e criar `acoes_select_visivel` com
      `restrita_ao_grupo = false or exists (select 1 from
      public.participacoes_grupo p where p.grupo_id = acoes.grupo_id and
      p.usuario_id = auth.uid())`. Nome novo de propósito: policy com nome que
      mente é pior que nome nenhum (`20260809200000_votos_visibilidade.sql:21-27`)
- [ ] 3.2 `drop policy confirmacoes_acao_select_public` e criar
      `confirmacoes_acao_select_conforme_acao` com
      `exists (select 1 from public.acoes a where a.id = acao_id)` — e nada
      mais. A subconsulta roda sob a RLS de `acoes`, então a regra fica num
      lugar só; **não** duplicar aqui o `exists` de participação
- [ ] 3.3 Manter os `grant select` de `anon` como estão nas duas tabelas: Ação
      escondida vira **linha ausente**, nunca erro de permissão — a diferença
      entre "não existe" e "não posso ver" é contável
      (`20260809200000_votos_visibilidade.sql:36-41`)
- [ ] 3.4 `supabase db reset` roda limpo; `\d+ public.acoes` mostra a coluna e
      as policies novas (colar a saída)

## 4. Testes de integração — os dois sentidos

- [ ] 4.1 Atualizar `test/integration/acoes_select_publico_test.dart`: Ação
      pública continua visível para `anon` e para autenticado de fora. Este é o
      lado que impede a policy de esconder o que não devia
- [ ] 4.2 `acao_restrita_invisivel_test.dart`: Ação restrita não vem para
      `anon`, não vem para autenticado que não participa, **vem** para quem
      participa — e a resposta é lista vazia, não erro
- [ ] 4.3 `acao_restrita_presencas_test.dart`: as confirmações da Ação restrita
      não vêm para quem é de fora; as de Ação pública continuam vindo para
      `anon`
- [ ] 4.4 `acao_restrita_exige_grupo_test.dart`: `insert` de Ação sem
      `grupo_id` com `restrita_ao_grupo = true` é recusado pelo `check`
- [ ] 4.5 `acao_restrita_apenas_criador_test.dart`: terceiro não muda a
      restrição; criador muda nos dois sentidos; encerrada recusa a mudança
- [ ] 4.6 `acao_restrita_saida_do_grupo_test.dart`: sair do Grupo e ser
      removido pelo Dono tiram a Ação da leitura seguinte; Grupo arquivado
      mantém a restrição como estava
- [ ] 4.7 `acao_restrita_rodada_test.dart`: candidata restrita não aparece para
      quem é de fora, nem como candidata nem como vencedora. Verificar, não
      assumir que a policy de `acoes` cobre sozinha
- [ ] 4.8 `explain analyze` do feed **depois**, comparado com 1.1, com os dois
      números lado a lado. Se a diferença for sentida, aplicar o recuo previsto
      no design (índice parcial) antes de seguir

## 5. App

- [ ] 5.1 `create_action_page.dart`: controle de restrição, visível/habilitado
      só quando há Grupo escolhido, com a explicação de que a Ação some do feed
      de quem não participa
- [ ] 5.2 `edit`/detalhe: `action_detail_page.dart` mostra marca de "restrita ao
      Grupo X" para quem vê, e o criador consegue mudar enquanto não encerrada
- [ ] 5.3 `action_repository.dart` grava e lê a coluna nova. **Nenhum filtro de
      visibilidade no Dart** — o banco já não devolve; filtro no cliente aqui
      seria uma segunda regra para divergir da primeira
- [ ] 5.4 Ação restrita a que a pessoa não tem acesso, aberta por link direto,
      cai na tela de "Ação não encontrada" — sem revelar nome, data nem local
- [ ] 5.5 Julgar a tela de criação na **largura de celular**: o controle novo e
      seu texto explicativo não podem empurrar o formulário para rolagem
      horizontal

## 6. Interação com o que está em voo

- [ ] 6.1 Se `destaque-de-acoes-distritais-e-de-grupo` já estiver aplicada:
      teste de que Ação restrita não aparece na faixa de destaque de quem não
      participa. Obrigatório, não opcional
- [ ] 6.2 Se `convite-para-acao` já estiver aplicada: `convidar_para_acao` e
      `contatos_para_convite` passam a recusar convite de Ação restrita para
      quem não participa do Grupo dono da Ação, com teste de integração. Se
      ainda não estiver, registrar a dependência na tasks daquela change
- [ ] 6.3 Varrer as demais telas que listam ou contam Ação (`action_list_page`,
      `home`, `novidades`) confirmando que nenhuma monta a contagem por um
      caminho que ignore a policy

## 7. Gates e ledger

- [ ] 7.1 `flutter analyze` — zero issue (colar a linha final)
- [ ] 7.2 `flutter test test/unit test/widget` — colar a contagem real
- [ ] 7.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os sete testes de RLS identificados
- [ ] 7.4 `flutter build web --release` conclui
- [ ] 7.5 `SECURITY-AUDIT.md`: mudança das duas policies de leitura, com data,
      o que passou a ser escondido e os números de 4.8
- [ ] 7.6 `MAPA-DE-DADOS.md`: `acoes.restrita_ao_grupo` com `arquivo:linha`
- [ ] 7.7 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
- [ ] 7.8 `graphify --update` antes de considerar a change fechada
