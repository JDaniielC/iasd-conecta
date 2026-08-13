## 1. Banco — tabela, RLS e índices

- [ ] 1.1 Migration nova com `public.mudancas` (`id`, `grupo_id`, `acao_id`,
      `tipo`, `autor_id`, `created_at`), ambas as FKs `on delete cascade`,
      `autor_id` referenciando `perfis(id)` sem cascade, e `check` de `tipo`
      com os dez valores do design
- [ ] 1.2 RLS ligado, uma policy só: `mudancas_select_conforme_origem` para
      `anon, authenticated` com
      `using (acao_id is null or exists (select 1 from public.acoes a where
      a.id = acao_id))`. **Não** `using (true)`: a subconsulta faz o registro
      herdar a visibilidade de `acoes` em vez de copiá-la, e é o que impede o
      vazamento do par nominal `(acao_id, autor_id)` quando
      `acao-direcionada-a-grupo` entrar. Enquanto `acoes` for público o
      comportamento é idêntico, então esta change não depende daquela. Nenhuma
      policy de `insert`, `update` ou `delete` — a ausência é o mecanismo, não
      um esquecimento; deixar comentário na migration dizendo as duas coisas
- [ ] 1.3 Índices parciais `mudancas_por_grupo (grupo_id, created_at desc)
      where grupo_id is not null` e `mudancas_por_acao (acao_id, created_at
      desc) where acao_id is not null`
- [ ] 1.4 `comment on table` e `comment on column` explicando por que não há
      valor anterior/novo e por que `autor_id` é anulável — padrão de
      `grupos.arquivado_em` (`20260809230000:32-38`)

## 2. Banco — gatilhos

- [ ] 2.1 Gatilho em `acoes`: `after insert` grava `acao_criada` só quando
      `new.grupo_id is not null`; `after update` grava `acao_horario_alterado`
      e/ou `acao_local_alterado` comparando `old`/`new`, e `acao_cancelada` só
      na transição de `cancelada_em` nulo para não nulo. `grupo_id` do
      registro é copiado de `acoes.grupo_id`
- [ ] 2.2 Gatilho em `participacoes_grupo`: `after insert` grava
      `participacao_entrou`, `after delete` grava `participacao_saiu`, com
      `autor_id = auth.uid()`. O `after delete` confirma que o Grupo ainda
      existe antes de inserir (defesa contra cascata — ver design, Risks)
- [ ] 2.3 Gatilho em `confirmacoes_acao`: `after insert`, lendo `new.status` já
      decidido por `confirmacoes_acao_decidir_status()`, grava
      `confirmacao_confirmado` ou `confirmacao_fila`; `after delete` grava
      `confirmacao_cancelada`, sem olhar `old.status`. Preenche `acao_id` e
      também `grupo_id` quando a Ação pertence a um Grupo. **Não alterar** a
      função existente
- [ ] 2.4 Gatilho em `grupos`: `after update` grava `grupo_arquivado` só na
      transição de `arquivado_em` nulo para não nulo
- [ ] 2.5 Nenhuma das quatro funções captura exceção. Confirmar que não existe
      `exception when others` em nenhuma delas — o rollback é o requisito

## 3. Prova no banco (test/integration)

- [ ] 3.1 Teste: `update` em `acoes.data_hora` cria exatamente 1 registro
      `acao_horario_alterado`; `update` que muda data e local na mesma
      operação cria exatamente 2 registros com o mesmo `created_at`
- [ ] 3.2 Teste: `update` que toca só `detalhes`, `nome` ou `limite_vagas`
      cria 0 registros
- [ ] 3.3 Teste: cancelar uma Ação cria 1 `acao_cancelada`; um segundo
      `update` na Ação já cancelada mantém a contagem em 1
- [ ] 3.4 Teste: Ação criada com `grupo_id` cria 1 `acao_criada`; Ação avulsa
      cria 0
- [ ] 3.5 Teste: criar Grupo gera 1 `participacao_entrou` (o dono, via
      `criar_participacao_do_dono`); sair gera 1 `participacao_saiu`
- [ ] 3.6 Teste: confirmação dentro do limite gera `confirmacao_confirmado`;
      confirmação além do limite gera `confirmacao_fila`, não `confirmado`;
      confirmação recusada (Ação cancelada) gera 0 registros
- [ ] 3.6a Teste: desconfirmar presença gera 1 `confirmacao_cancelada`; sair da
      fila gera o mesmo tipo, não um segundo tipo
- [ ] 3.7 Teste: arquivar Grupo gera 1 `grupo_arquivado`
- [ ] 3.8 Teste de RLS, como `authenticated`: `insert`, `update` e `delete` em
      `mudancas` são todos recusados — inclusive sendo dono do Grupo, criador
      da Ação e Administrador do distrito. Três papéis, três operações
- [ ] 3.9 Teste: `select` em `mudancas` como `anon` devolve as mesmas linhas
      que como `authenticated`, para Ação pública — o lado que impede a policy
      nova de esconder o que não devia
- [ ] 3.9a Teste: com uma Ação tornada ilegível para a sessão que lê, os
      registros dela (`acao_criada`, `acao_horario_alterado`,
      `confirmacao_confirmado`) **não** vêm, nem para `anon` nem para
      autenticado de fora; a resposta é conjunto vazio, não erro de permissão.
      Enquanto `acao-direcionada-a-grupo` não estiver aplicada, montar o caso
      revogando a leitura de `acoes` na própria sessão de teste — a policy tem
      de ser provada agora, não quando a outra change chegar
- [ ] 3.9b Teste: no mesmo Grupo do caso acima, `participacao_entrou` e
      `participacao_saiu` continuam vindo para `anon` — a policy filtra por
      `acao_id`, não por Grupo
- [ ] 3.10 Teste: remoção física de Grupo por superusuário não deixa registro
      órfão nem levanta erro de FK
- [ ] 3.11 Teste: depois de `excluir_conta` sobre um Perfil que gerou
      registros, os registros continuam existindo e `autor_id` aponta para o
      Perfil anonimizado

## 4. Dart — modelo e repositório

- [ ] 4.1 `lib/features/change_log/domain/change_log_entry.dart`: modelo com o
      `tipo` como enum Dart em inglês mapeado para as chaves em português, e o
      Perfil autor anulável. Um `tipo` desconhecido vindo do banco não pode
      derrubar a lista — decidir e testar o comportamento (ignorar a linha)
- [ ] 4.2 `lib/features/change_log/data/change_log_repository.dart`: duas
      consultas, por `grupo_id` e por `acao_id`, ordenadas por `created_at
      desc` com `limit` de 21 (20 exibidos + 1 para saber que há mais)
- [ ] 4.3 Providers da feature, no padrão dos existentes em
      `lib/features/news/news_providers.dart`

## 5. Dart — tela

- [ ] 5.1 Widget de seção "Mudanças recentes": lista, estado vazio com o texto
      de que o registro começa agora, estado de erro, e indicação de "há mais"
      quando vierem 21
- [ ] 5.2 Frase de cada tipo em português, com e sem autor. Dez tipos × dois
      casos (autor presente / nulo) — a frase sem sujeito precisa ler bem
- [ ] 5.3 Perfil anonimizado renderiza com a mesma identidade anonimizada que
      o resto do app usa; não inventar rótulo novo
- [ ] 5.4 Encaixar a seção em `group_detail_page.dart` e em
      `action_detail_page.dart` sem mudar contrato de nenhum widget existente

## 6. Prova no cliente (test/widget, test/unit)

- [ ] 6.1 Teste de unidade: mapeamento dos dez tipos, ida e volta, mais o
      tipo desconhecido
- [ ] 6.2 Teste de widget: seção vazia mostra o texto de "começa agora" e não
      quebra a tela
- [ ] 6.3 Teste de widget: 21 registros mostram 20 e a indicação de "há mais"
- [ ] 6.4 Teste de widget: registro com autor nulo renderiza a frase sem
      sujeito, sem `null` na tela

## 7. Ledger e fechamento

- [ ] 7.1 `MAPA-DE-DADOS.md` ganha `public.mudancas` com `arquivo:linha`,
      declarando que `autor_id` é referência e não cópia, e por quê
- [ ] 7.2 `PENDENCIAS.md` registra a dívida conhecida: retenção de `mudancas`
      (ver design, Risks)
- [ ] 7.3 Gates, com números reais anotados: `flutter analyze` (0 issues),
      `flutter test test/unit test/widget` (contagem), `dart test
      test/integration` com `supabase start` (contagem), `flutter build web
      --release` (sucesso)
- [ ] 7.4 Rodar a skill `openspec-converge` sobre esta change e resolver o que
      ela achar antes de arquivar
