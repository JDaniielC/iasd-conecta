## 1. Medir antes

- [x] 1.1 `explain analyze` da leitura do feed (`select * from acoes` como
      `authenticated` e como `anon`) **antes** da mudança, com a base de seed.
      Guardar o número — sem ele, a comparação de 4.1 não existe
      - Base medida: 10 `acoes`, 2 `grupos`, 2 `participacoes_grupo` — que era
        resíduo de execuções anteriores de teste, não a seed. Depois do
        `supabase db reset` de 3.4, `supabase/seed.sql` deixa **zero** `acoes`.
        Mais um motivo para 4.8 medir contra volume sintético.
      - `anon`: `Seq Scan on acoes (actual rows=10 loops=1)`, `Buffers: shared
        hit=1`, Execution Time **0.063 ms**
      - `authenticated`: `Seq Scan on acoes (actual rows=10 loops=1)`,
        `Buffers: shared hit=1`, Execution Time **0.024 ms**
      - **A seed é pequena demais para a comparação de 4.8 significar algo** —
        num Seq Scan de 10 linhas nenhum `exists` aparece. 4.8 mede também
        contra volume sintético (5000 Ações / 500 Grupos / 200 participações),
        criado e desfeito em transação, com o mesmo script nos dois lados
- [x] 1.2 Conferir que `participacoes_grupo` não tem índice servindo busca por
      `usuario_id` (`\d public.participacoes_grupo`, PK é
      `(grupo_id, usuario_id)`) e colar a saída
      - `Indexes: "participacoes_grupo_pkey" PRIMARY KEY, btree (grupo_id,
        usuario_id)` — é o único. Confirmado: nada serve busca por
        `usuario_id`

## 2. Banco — coluna e restrição

- [x] 2.1 Migration: `alter table public.acoes add column restrita_ao_grupo
      boolean not null default false`, mais
      `check (restrita_ao_grupo = false or grupo_id is not null)`. O `default
      false` é o que garante que nenhuma Ação existente muda de visibilidade
- [x] 2.2 `comment on column` dizendo que restrição exige Grupo e que o padrão é
      público de propósito
- [x] 2.3 Índice `participacoes_grupo_por_usuario (usuario_id, grupo_id)` — a
      policy percorre a direção contrária à PK, uma vez por linha de `acoes`
- [x] 2.4 Gatilho `before update` em `acoes` recusando mudança de
      `restrita_ao_grupo` quando `acao_encerrada(id)` é verdadeiro, ao lado da
      regra irmã de `20260809174740_acao_encerrada_bloqueia_presenca.sql`

## 3. Banco — policies
      - Implementado como `acoes_restricao_apos_encerrada_trigger` usando a
        sobrecarga nova `acao_encerrada(timestamptz)` sobre `old.data_hora`,
        **não** `acao_encerrada(id)`. Motivo de segurança, não de estilo: a
        versão por id é `security invoker` e lê `acoes`, então para quem escreve
        numa Ação restrita que não enxerga ela devolve NULL, `not null` vira
        NULL, o `if` não dispara e a trava falharia calada exatamente na Ação
        restrita. O gatilho já tem OLD na mão. As 4 horas continuam definidas
        uma vez só: a versão por uuid passou a delegar para a nova
- [x] 3.1 `drop policy acoes_select_public` e criar `acoes_select_visivel` com
      `restrita_ao_grupo = false or exists (select 1 from
      public.participacoes_grupo p where p.grupo_id = acoes.grupo_id and
      p.usuario_id = auth.uid())`. Nome novo de propósito: policy com nome que
      mente é pior que nome nenhum (`20260809200000_votos_visibilidade.sql:21-27`)
- [x] 3.2 `drop policy confirmacoes_acao_select_public` e criar
      `confirmacoes_acao_select_conforme_acao` com
      `exists (select 1 from public.acoes a where a.id = acao_id)` — e nada
      mais. A subconsulta roda sob a RLS de `acoes`, então a regra fica num
      lugar só; **não** duplicar aqui o `exists` de participação
- [x] 3.2b **Não** acrescentar `restrita_ao_grupo` à lista protegida de
      `acoes_protege_campos_internos`. Decisão da change: a restrição segue a
      permissão de escrita da Ação, sem dona própria. O recuo está escrito no
      design, caso a dívida de 7.5b incomode
- [x] 3.3 Manter os `grant select` de `anon` como estão nas duas tabelas: Ação
      escondida vira **linha ausente**, nunca erro de permissão — a diferença
      entre "não existe" e "não posso ver" é contável
      (`20260809200000_votos_visibilidade.sql:36-41`)
- [x] 3.4 `supabase db reset` roda limpo; `\d+ public.acoes` mostra a coluna e
      as policies novas (colar a saída)

## 4. Testes de integração — os dois sentidos
      - `restrita_ao_grupo | boolean | not null | false`
      - `acoes_restrita_exige_grupo CHECK (((restrita_ao_grupo = false) OR
        (grupo_id IS NOT NULL)))`
      - `POLICY acoes_select_visivel FOR SELECT TO anon,authenticated`
      - `POLICY confirmacoes_acao_select_conforme_acao FOR SELECT TO
        anon,authenticated`
      - `participacoes_grupo_por_usuario btree (usuario_id, grupo_id)`
      - `supabase db reset` aplicou as 34 migrations e semeou sem erro
- [x] 4.1 Atualizar `test/integration/acoes_select_publico_test.dart`: Ação
      pública continua visível para `anon` e para autenticado de fora. Este é o
      lado que impede a policy de esconder o que não devia
      - Mais dois casos no arquivo existente: Ação pública visível para
        autenticado de fora, e confirmações de Ação pública ainda legíveis para
        ele. 5 testes, verdes
- [x] 4.2 `acao_restrita_invisivel_test.dart`: Ação restrita não vem para
      `anon`, não vem para autenticado que não participa, **vem** para quem
      participa — e a resposta é lista vazia, não erro
      - `acao_restrita_invisivel_test.dart`, 6 testes verdes
- [x] 4.3 `acao_restrita_presencas_test.dart`: as confirmações da Ação restrita
      não vêm para quem é de fora; as de Ação pública continuam vindo para
      `anon`
      - `acao_restrita_presencas_test.dart`, 4 testes verdes
- [x] 4.4 `acao_restrita_exige_grupo_test.dart`: `insert` de Ação sem
      `grupo_id` com `restrita_ao_grupo = true` é recusado pelo `check`
      - `acao_restrita_exige_grupo_test.dart`, 3 testes verdes
- [x] 4.5 `acao_restrita_quem_restringe_test.dart`: quem não edita a Ação não
      muda a restrição; criador muda nos dois sentidos; Dono do Grupo muda Ação
      criada por outra pessoa; encerrada recusa a mudança de todos eles
      - `acao_restrita_quem_restringe_test.dart`, 4 testes verdes
- [x] 4.5b `acao_restrita_admin_assimetria_test.dart`: o Administrador do
      distrito restringe uma Ação de Grupo do qual não participa e a perde de
      vista; pelo id não reabre (`0` linhas afetadas); **sem filtro reabre**.
      O terceiro caso é a dívida aceita — o teste existe para ela ser
      conhecida, então ele afirma o comportamento real, não o desejado
      - `acao_restrita_admin_assimetria_test.dart`, 4 testes verdes. **A
        medição corrigiu o que a change afirmava**: o Postgres aplica a policy
        de `select` como `with check` implícito do `update`, então o
        Administrador NÃO consegue restringir Ação de Grupo do qual não
        participa (`new row violates row-level security policy`). Fechar o que
        não se enxerga é impossível; o que sobra de dívida é só reabrir sem
        filtro. Spec, design e o comentário da migration foram corrigidos
- [x] 4.6 `acao_restrita_saida_do_grupo_test.dart`: sair do Grupo e ser
      removido pelo Dono tiram a Ação da leitura seguinte; Grupo arquivado
      mantém a restrição como estava
      - `acao_restrita_saida_do_grupo_test.dart`, 3 testes verdes
- [x] 4.7 `acao_restrita_rodada_test.dart`: candidata restrita não aparece para
      quem é de fora, nem como candidata nem como vencedora. Verificar, não
      assumir que a policy de `acoes` cobre sozinha
      - `acao_restrita_rodada_test.dart`, 4 testes verdes. Inclui a
        candidata restrita montada para VENCER: se `fechar_rodada_se_devido`
        deixar de ser `security definer`, a apuração para de contar a restrita
        e este teste fica vermelho
- [x] 4.8 `explain analyze` do feed **depois**, comparado com 1.1, com os dois
      números lado a lado. Se a diferença for sentida, aplicar o recuo previsto
      no design (índice parcial) antes de seguir

## 5. App
      - Volume sintético determinístico, 5000 Ações / 500 Grupos / 500
        Rodadas, metade restrita. Policy nova e policy antiga medidas na MESMA
        transação, sobre a MESMA base, com `rollback` no fim.
      - Leitora realista (participa de 3 Grupos entre 500), consulta de feed
        `where cancelada_em is null and data_hora > now() order by data_hora
        limit 50`:
        - antes (`using (true)`): **1.296 ms**, `Buffers: shared hit=108`
        - depois: **0.971 ms**, `Buffers: shared hit=110`
        - A policy nova ficou MAIS RÁPIDA. Ela descarta 2485 das 5000 linhas
          antes do `Sort`, e sobra menos para ordenar. O `Bitmap Index Scan on
          participacoes_grupo_por_usuario` aparece no plano com 3 linhas e 2
          buffers — o índice de 2.3 se paga exatamente aqui
      - Pior caso (participa dos 500 Grupos, ninguém é assim no app): antes
        **1.296 ms**, depois **1.875 ms** — +0.58 ms
      - Leitura da tabela inteira (`select * from public.acoes`), que não é o
        feed mas é comparável com 1.1: `anon` de 0.522 para 1.189 ms,
        `authenticated` de 0.514 para 1.180 ms
      - **A suposição do design estava errada, e para melhor.** Ele temia o
        `exists` rodando "uma vez por linha de `acoes`". O planejador transforma
        a subconsulta em `hashed SubPlan`: `participacoes_grupo` é lida UMA vez
        por consulta, não por linha. Nada do recuo previsto (índice parcial) foi
        preciso
- [x] 5.1 `create_candidate_page.dart`: controle de restrição, com a explicação
      de que a Ação some do feed de quem não participa do Grupo.
      **`create_action_page.dart` não muda** — Ação de Grupo neste app só nasce
      como candidata de Rodada (`acoes_candidata_checar_regras` recusa
      `grupo_id` sem `rodada_id`), então ali toda Ação é avulsa e o controle
      não teria Grupo a que se referir. A vencedora da Rodada herda de graça:
      é a mesma linha de `acoes`
      - `SwitchListTile` "Só para quem participa do Grupo" em
        `create_candidate_page.dart`; `NewAction.restrictedToGroup` e
        `proposeCandidate` passando adiante. `toInsertMap` só envia
        `restrita_ao_grupo` quando há `rodada_id` — o formulário não tem como
        formar a combinação que o `check` recusa
      - `test/unit/acao_restrita_model_test.dart`, 7 testes verdes
- [x] 5.2 `edit`/detalhe: `action_detail_page.dart` mostra marca de "restrita ao
      Grupo X" para quem vê, e o criador consegue mudar enquanto não encerrada
      - `action_detail_page.dart`: marca com cadeado para quem só lê, e
        `SwitchListTile` para quem pode mudar (a marca e o controle são
        mutuamente exclusivos, senão o mesmo texto sairia duas vezes). Some em
        Ação cancelada ou encerrada
      - `test/widget/acao_restrita_tela_test.dart`, 4 testes verdes
- [x] 5.3 `action_repository.dart` grava e lê a coluna nova. **Nenhum filtro de
      visibilidade no Dart** — o banco já não devolve; filtro no cliente aqui
      seria uma segunda regra para divergir da primeira
      - `ActionRepository.setRestrictedToGroup`, e `Action.fromMap` lendo a
        coluna. Nenhum filtro de visibilidade no Dart — varredura de 6.3
        confirma
- [x] 5.4 Ação restrita a que a pessoa não tem acesso, aberta por link direto,
      cai na tela de "Ação não encontrada" — sem revelar nome, data nem local
      - Já era o comportamento: `fetchAction` usa `.single()`, que estoura
        quando a policy esconde a linha, e a tela cai em `error:` →
        "Ação não encontrada.". O teste existe para a cadeia continuar valendo
        — trocar `.single()` por `.maybeSingle()` pareceria gentileza e passaria
        a desenhar uma tela vazia no lugar
- [x] 5.5 Julgar a tela de criação na **largura de celular**: o controle novo e
      seu texto explicativo não podem empurrar o formulário para rolagem
      horizontal

## 6. Interação com o que está em voo
      - `test/widget/propor_candidata_restrita_test.dart`, 2 testes verdes,
        renderizando em 360x800. O Flutter transforma estouro de layout em
        falha, então renderizar nessa largura é a asserção
- [x] 6.1 Se `destaque-de-acoes-distritais-e-de-grupo` já estiver aplicada:
      teste de que Ação restrita não aparece na faixa de destaque de quem não
      participa. Obrigatório, não opcional
      - `destaque-de-acoes-distritais-e-de-grupo` está arquivada, então foi
        obrigatório. `test/widget/acao_restrita_destaque_test.dart`, 2 testes
        verdes. O primeiro alimenta a tela com uma Ação restrita de Grupo que
        NÃO está em `myGroupIds` — situação que a RLS torna impossível — para
        pegar uma faixa que um dia passe a se alimentar de outro lugar
- [x] 6.2 Se `convite-para-acao` já estiver aplicada: `convidar_para_acao` e
      `contatos_para_convite` passam a recusar convite de Ação restrita para
      quem não participa do Grupo dono da Ação, com teste de integração. Se
      ainda não estiver, registrar a dependência na tasks daquela change
      - `convite-para-acao` ainda não foi aplicada. Dependência registrada
        na tasks dela, seção "0. Dependência declarada por outra change", com o
        requisito e o aviso de que Ação de Grupo é candidata de Rodada
- [x] 6.3 Varrer as demais telas que listam ou contam Ação (`action_list_page`,
      `home`, `novidades`) confirmando que nenhuma monta a contagem por um
      caminho que ignore a policy

## 7. Gates e ledger
      - Varredura de `from('acoes')` e `from('confirmacoes_acao')` em
        `lib/`: 12 ocorrências, todas via PostgREST com a sessão de quem lê,
        logo sob RLS. Nenhuma tela monta contagem por caminho paralelo —
        `fetchConfirmationCounts` lê `confirmacoes_acao`, que agora herda a
        regra de `acoes`
      - `fetchArchivePreview` (`group_repository.dart:57`) conta Ações futuras
        do Grupo, e só o Dono abre aquela tela; Dono participa, então o número
        bate com o que ele consegue abrir
      - A única função `security definer` que lê `acoes` para decidir algo é
        `fechar_rodada_se_devido`, e 4.7 prova que a apuração continua contando
        a candidata restrita
- [x] 7.1 `flutter analyze` — zero issue (colar a linha final)
      - `No issues found! (ran in 1.8s)`
- [x] 7.2 `flutter test test/unit test/widget` — colar a contagem real
      - `00:14 +335: All tests passed!` — 335 testes, 0 falhas (contagem final, depois das tarefas de convergência)
- [x] 7.3 `supabase start` + `dart test test/integration` — colar a contagem
      real, com os oito testes de RLS identificados
      - `00:06 +249: All tests passed!` — 249 testes, 0 falhas, depois de
        `supabase db reset` limpo. Os oito arquivos novos/alterados de RLS:
        `acoes_select_publico_test.dart` (5), `acao_restrita_invisivel_test`
        (6), `_presencas` (4), `_exige_grupo` (3), `_quem_restringe` (4),
        `_admin_assimetria` (4), `_saida_do_grupo` (3), `_rodada` (4)
- [x] 7.4 `flutter build web --release` conclui
      - `✓ Built build/web`
- [x] 7.5 `SECURITY-AUDIT.md`: mudança das duas policies de leitura, com data,
      o que passou a ser escondido e os números de 4.8
      - `SECURITY-AUDIT.md`, seção "Mudança de policy de leitura — `acoes`
        e `confirmacoes_acao` (2026-08-13)": o que passou a ser escondido, o que
        NÃO mudou de propósito (padrão público, grants de `anon`, `rodadas_votacao`
        e `grupos`, ausência de `bypass` para o Administrador), e os números de
        4.8 e dos gates
- [x] 7.5b `SECURITY-AUDIT.md`: dívida aceita — Administrador do distrito
      reabre toda Ação restrita numa escrita sem filtro, porque a policy de
      `update` dele não recorta por linha. Com a medição (`UPDATE 0` com
      filtro, alcança sem filtro), o recuo previsto e o teste que a prova
      - Mesma seção, "Dívida aceita — escrita sem filtro reabre a Ação
        restrita", com as três medições, o porquê de ter sido aceita, o recuo
        pronto e o teste que serve de marcador
- [x] 7.6 `MAPA-DE-DADOS.md`: `acoes.restrita_ao_grupo` com `arquivo:linha`
      - `MAPA-DE-DADOS.md`: as duas linhas da tabela "Quem vê o quê"
        reescritas (`acoes` e `confirmacoes_acao` deixaram de ser irrestritas),
        e parágrafo novo com `acoes.restrita_ao_grupo`
        (`20260813120000_acao_restrita_ao_grupo.sql:30`) e a constraint
        `acoes_restrita_exige_grupo` (`:35-37`)
- [x] 7.7 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela apontar
      - Rodada. 10 requisitos e 28 cenários verificados; 4 achados em
        `## Convergence 1` — 1 HIGH (falta a marca de restrita no cartão da
        lista), 1 MEDIUM (recusa de `update` é zero linha, não erro, e a tela
        não avisa), 2 LOW. Cinco hipóteses verificadas e derrubadas estão no
        relatório da passagem
- [x] 7.8 `graphify --update` antes de considerar a change fechada
      - **Feito para o código; pendente para os documentos, e o porquê fica aqui.**
      - A tarefa nomeava um comando inexistente: `--update` é flag da skill
        `/graphify`, não do binário. O binário só tem `query`, `path`,
        `explain`, `add`, `install`, `merge-graphs` e afins
      - `detect_incremental` acusou 655 arquivos alterados desde 05/08 — 344 de
        código, 276 de documento, 35 de imagem — e 2 apagados. É acúmulo de oito
        dias, não desta change
      - **Código: entrou.** AST sobre os 344 arquivos, mesclado com
        `build_merge`. `graph.json` foi de 5536 para **5640 nós** e de 6412 para
        **6596 arestas**; o diff traz 124 nós novos, entre eles
        `acao_restrita_presencas_test.dart`, `acao_restrita_tela_test.dart` e
        `asUser`. Diagnóstico de saúde limpo: 0 ponta solta, 0 ponta ausente,
        0 self-loop, 0 aresta colapsada
      - **Documentos: gastos e descartados, de propósito.** Os 276 documentos
        foram extraídos por 13 subagentes, a 1.868.352 tokens. `build_merge` faz
        *replace-on-re-extract*: os nós antigos de cada arquivo re-extraído são
        descartados antes da mescla. A extração nova saiu muito mais magra que a
        de 05/08 (`specs/` caía de 1937 para 571 nós, `openspec/` de 742 para
        285), e a mescla completa daria **3566 nós** — menos que os 5536 que já
        existiam. O guarda anti-encolhimento do próprio graphify (#479) recusaria
        a escrita, e com razão. Só o AST foi mesclado
      - **O cache semântico dessa rodada foi apagado** (263 arquivos), senão a
        próxima rodada reusaria a versão pobre em vez de re-extrair
      - **O manifesto omite 311 arquivos de propósito** — os 276 documentos e 35
        imagens alterados. Registrá-los como processados sem terem sido é a
        mentira que o guarda existe para evitar; assim eles voltam como
        pendentes no próximo `--update`
      - **Pendente, para uma sessão própria**: re-extrair os documentos com
        chunks de 8–10 arquivos por agente (~30 agentes) em vez de 22, para
        bater ou passar a densidade de 05/08, e então mesclar. Enquanto isso o
        grafo responde sobre o código desta change, mas não sobre os documentos
        dela
      - **Duas perdas do extrator, conhecidas e não minhas**: 11 arquivos de
        manifesto/configuração (`feature.json`, `claude.manifest.json`, …)
        produziram zero nós; e 13 nós Swift de iOS/macOS foram descartados por
        colisão de id (`Package.swift`, `AppDelegate.swift`/`SceneDelegate.swift`
        repetem nome em diretórios diferentes). O próprio graphify sugere
        `extract` por subpasta + `merge-graphs` para isso
- [x] C1 Marcar a Ação restrita **no cartão da lista** de `/acoes`, não só no
      detalhe — per requisito "Quem não participa do Grupo não vê a Ação
      restrita", cenário "Quem participa vê normalmente", que pede a Ação
      "com uma marca visível de que é restrita ao Grupo" (`partial`, HIGH).
      Evidência: `grep restrictedToGroup lib/features/action/presentation/action_list_page.dart`
      não devolve nada. O cartão já marca estado no mesmo lugar
      (`' · Cancelada'`, `action_list_page.dart:504` e `:624`), então é ali.
      Vale para a faixa de destaque e para a lista por período — quem participa
      vê a Ação nas duas. Julgar na largura de celular: o cartão já empilha
      Igreja, data e "Cancelada", e um quarto pedaço de texto é onde ele quebra
      - Lista por período: `' · Só do Grupo'` na linha que já traz data,
        local e "Cancelada" — ali cabe texto porque a linha quebra. Faixa de
        destaque: ícone `lock_outline` com `Tooltip`, porque a linha de data
        daquele cartão é `maxLines: 1` e mais texto comeria o local. O
        `Tooltip` também é o rótulo do leitor de tela
      - 4 testes verdes em `acao_restrita_destaque_test.dart`, com o caso
        negativo (Ação pública não ganha marca), julgados em 360x800
- [x] C2 Avisar quando a mudança de restrição não pegou — per requisito "Quem
      edita a Ação é quem restringe" (`partial`, MEDIUM). Recusa por RLS de
      `update` **não levanta erro, devolve zero linha**: medido em
      `test/integration/acao_restrita_quem_restringe_test.dart`, caso "quem não
      edita a Ação não muda a restrição, e não recebe erro" (`affectedRows == 0`,
      sem exceção). Hoje `ActionRepository.setRestrictedToGroup` descarta o
      retorno e `_setRestricted` (`action_detail_page.dart`) só trata `catch`,
      então o interruptor volta sozinho e a pessoa não sabe por quê. Fazer o
      `update` devolver a linha (`.select()`) e tratar resposta vazia como
      falha, com a mesma mensagem do `catch`. Teste de widget com repositório
      que devolve "nada mudou"
      - `setRestrictedToGroup` passou a `.select('id')` e a estourar
        `StateError` quando a resposta vem vazia. Ler o retorno é seguro nos
        dois sentidos: restringir só é possível para quem continua enxergando
        (senão o banco já estourou) e desmarcar deixa a linha mais visível —
        medido com `update ... returning` numa tabela de brinquedo
      - Teste de widget novo: a tela avisa em vez de deixar o interruptor
        voltar calado. `acao_restrita_tela_test.dart`, 5 testes verdes
- [x] C3 Teste que prove que `create_action_page.dart` não oferece restrição —
      per requisito "Só Ação de Grupo pode ser restrita", cenário "Criar Ação
      avulsa não oferece restrição" (`missing`, LOW). Hoje é verdade e nada
      trava: um controle acrescentado ali passaria por `flutter analyze`, pelos
      331 testes e pelos 249 de integração sem uma falha
      - Em `propor_candidata_restrita_test.dart`, 3 testes verdes
- [x] C4 **Decisão do dono, não desta change** (`unrequested`, LOW):
      `voting_round_repository.dart:53-64` remonta o `NewAction` em
      `proposeCandidate` e não copia `isMissionaryPair` nem `visitedGender` —
      candidata proposta como Dupla Missionária perde a marca antes do banco.
      É anterior a esta change; aparece aqui porque foi essa linha que ganhou
      `restrictedToGroup`. Levar para `PENDENCIAS.md` ou abrir change própria
      - Levado para `PENDENCIAS.md` § 2.8, com o `arquivo:linha`, as duas
        leituras possíveis do requisito e o aviso de não virar código antes de
        spec. Não é trabalho desta change