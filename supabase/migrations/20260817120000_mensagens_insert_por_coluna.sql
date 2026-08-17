-- Change filtro-e-intervalo-de-mensagem, Convergence 1 — o limite de ritmo era
-- contornável mandando `created_at`.
--
-- MEDIDO EM 2026-08-16, pela API real (PostgREST, sessão `authenticated` de
-- verdade, não `set request.jwt.claims`): **30 mensagens inseridas em segundos,
-- ZERO recusas**, bastando acrescentar ao corpo do `insert`:
--
--   {"grupo_id": "...", "autor_id": "...", "texto": "flood",
--    "created_at": "2020-01-01T00:00:00Z"}
--
-- POR QUE FUNCIONAVA. `mensagens_ritmo_de_envio` conta `max(created_at)` e
-- `count(*)` das linhas que JÁ EXISTEM dentro da janela. Uma linha gravada com
-- data antiga nasce fora da janela, então a próxima checagem não a vê — nem o
-- intervalo de 3 s nem o teto de 20 por 5 minutos voltam a enxergar coisa
-- alguma. O limite existia e não valia.
--
-- Isto contradiz a requirement em letra: "O limite vale no banco, não na tela.
-- Uma chamada direta à API, sem passar pela tela, NÃO DEVE conseguir
-- ultrapassar o limite."
--
-- CAUSA. `20260813200000:328` deu `grant select, insert, update on
-- public.mensagens to authenticated` — a tabela inteira, sem recorte. Medido em
-- `information_schema.column_privileges`: `authenticated` tinha `insert` nas
-- OITO colunas, `created_at`, `id` e `removida_por` inclusive. O grant é de
-- `chat-de-grupo-e-acao` e nunca teve recorte; até esta change, forjar
-- `created_at` só bagunçava a ordem da conversa. Foi o limite de ritmo que
-- transformou uma forja cosmética em contorno de controle.
--
-- POR QUE GRANT DE COLUNA E NÃO POLICY. Uma policy com `with check` decide
-- sobre a LINHA RESULTANTE, e a linha resultante de um `created_at` forjado é
-- perfeitamente válida — não há predicado que a distinga de uma legítima sem
-- comparar com `now()`, e comparar com `now()` recusaria também a restauração
-- de dump. `grant insert (colunas)` restringe a cláusula de colunas do próprio
-- `insert`: mandar `created_at` vira `42501 permission denied for table
-- mensagens`, antes de qualquer policy rodar. Mesmo raciocínio, e mesmo
-- precedente, de `20260811160000_grant_update_perfis_por_coluna.sql`.
--
-- ALTERNATIVA RECUSADA: carimbar `new.created_at := now()` no gatilho. Ela
-- fecharia o buraco e traz dois problemas. Reescrever em silêncio um valor que
-- alguém mandou é pior do que recusar — quem mandou não fica sabendo que foi
-- ignorado. E impediria semear histórico como superusuário, que é como a suíte
-- monta cenário de conversa antiga (`chat_helper.seedMessage`) e como uma
-- restauração de dump funciona.
--
-- O APP NÃO MUDA. `ChatRepository.send` (`chat_repository.dart:162-167`) já
-- manda exatamente estas quatro colunas. O `revoke` vem ANTES do `grant` pela
-- armadilha de 20260816120000: `grant` ACRESCENTA privilégio, não substitui o
-- que já estava lá.
revoke insert on public.mensagens from authenticated;

grant insert (grupo_id, acao_id, autor_id, texto)
  on public.mensagens to authenticated;

comment on column public.mensagens.created_at is
  'Carimbado pelo DEFAULT now(). NÃO é gravável pelo cliente, e isto é '
  'controle e não arrumação: o limite de ritmo (mensagens_ritmo_de_envio) '
  'conta a janela por esta coluna, e quem pudesse escrevê-la ultrapassaria o '
  'limite mandando data antiga — medido em 2026-08-16, 30 mensagens em '
  'segundos e nenhuma recusa. O recorte é grant de COLUNA, em '
  '20260817120000.';

-- `update` continua com a tabela inteira, e é de propósito: lá quem protege é o
-- gatilho `mensagens_so_remove`, que recusa mudança em `id`, `grupo_id`,
-- `acao_id`, `autor_id` e `created_at` uma a uma, com mensagem que diz o que
-- aconteceu. Recortar o grant de update trocaria essa mensagem por um
-- `permission denied` genérico, sem ganhar barreira nenhuma — o gatilho já
-- cobre exatamente as mesmas colunas. Conferido, não presumido:
-- `20260813200000`, função `mensagens_so_remove`.
