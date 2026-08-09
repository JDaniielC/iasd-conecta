-- Feature 021 — visibilidade do voto.
--
-- CONTRATO PRETENDIDO. A migration real vai para
-- supabase/migrations/<timestamp>_votos_visibilidade.sql; este arquivo é o
-- desenho revisado, não o que roda.
--
-- FR-001..FR-006: fecha a leitura de public.votos para todo mundo menos a
-- própria pessoa. Hoje a política é `using (true)` — qualquer Visitante sem
-- cadastro lê o par (usuario_id, candidata_id) da tabela inteira, que é a lista
-- nominal de quem votou em quê.

-- ---------------------------------------------------------------------------
-- 1. Fora a política que mente
-- ---------------------------------------------------------------------------
-- O nome vai junto: um `votos_select_public` que não é público é pior que nome
-- nenhum, e é a mesma classe de divergência entre descrição e comportamento que
-- esta feature está consertando. Trocar o nome também faz qualquer referência
-- antiga falhar visivelmente em vez de apontar para algo com semântica trocada.
drop policy if exists votos_select_public on public.votos;

-- ---------------------------------------------------------------------------
-- 2. A regra nova: só o próprio voto
-- ---------------------------------------------------------------------------
-- Vale para `authenticated` apenas. `anon` fica sem política de select e, com
-- RLS ligada, isso significa conjunto vazio — não erro. Um Visitante recebe
-- lista vazia, sem conseguir distinguir "não há votos" de "não posso ver",
-- que é o que a invariante 5 do data-model exige.
--
-- O `grant select ... to anon` da migration original (rodada_votacao.sql:190)
-- fica como está: revogá-lo faria a API devolver erro de permissão em vez de
-- lista vazia, virando um canal lateral que conta o que existe escondido.
create policy votos_select_own
  on public.votos for select
  to authenticated
  using (auth.uid() = usuario_id);

-- ---------------------------------------------------------------------------
-- 3. Escrita: nada muda
-- ---------------------------------------------------------------------------
-- votos_insert_self e votos_update_self continuam como estão.
--
-- Verificado contra o Postgres local que o `upsert` de troca de voto sobrevive
-- à leitura apertada: a linha em conflito é sempre a da própria pessoa, porque
-- a primary key é (rodada_id, usuario_id) e o insert já exige
-- auth.uid() = usuario_id. Logo o `on conflict` alcança justamente a linha que
-- esta política continua deixando visível.
--
-- Também verificado que quem tenta sobrescrever voto alheio recebe
-- `new row violates row-level security policy for table "votos"`.

-- ---------------------------------------------------------------------------
-- 4. AVISO — a apuração depende de continuar `security definer`
-- ---------------------------------------------------------------------------
-- Este comentário está aqui, e não no arquivo da função, de propósito: é aqui
-- que a dependência nasce.
--
-- public.fechar_rodada_se_devido conta os votos com
--   left join public.votos ... group by ... order by count(v.usuario_id) desc
-- (rodada_votacao.sql:168-175). Ela enxerga todos os votos porque é
-- `security definer` com dono `postgres`, e public.votos não tem
-- `force row level security` — RLS não se aplica ao dono da tabela.
--
-- ATÉ ESTA MIGRATION isso era irrelevante: com `using (true)`, definer e
-- invoker contavam igual. A PARTIR DAQUI, converter a função para
-- `security invoker` faz a apuração contar SÓ OS VOTOS DE QUEM CHAMOU, e a
-- Rodada elege a candidata de quem a fechou.
--
-- Medido, com 2 votos numa candidata e 1 noutra:
--   security definer                   -> 4444: 2 votos, 5555: 1 voto   (correto)
--   security invoker chamada pela minoria -> 5555: 1 voto               (minoria vence)
--
-- A candidata majoritária não aparece com zero — ela SOME da consulta. A Rodada
-- fecha, grava a vencedora errada e APAGA as candidatas perdedoras
-- (rodada_votacao.sql:177-179). Sem erro, sem rastro, irreversível.
--
-- Se você veio até aqui para mexer nessa função: test/integration/
-- votos_visibilidade_test.dart falha quando a apuração deixa de ver todos os
-- votos. Se ele ficou vermelho, é isto.

-- ---------------------------------------------------------------------------
-- 5. O que esta migration NÃO faz
-- ---------------------------------------------------------------------------
-- - Não apaga nem altera nenhum voto. Muda leitura, não conteúdo.
-- - Não mexe em rodadas_votacao, acoes nem perfis.
-- - Não adiciona coluna, índice ou trigger.
-- - Não cria papel novo. A regra não menciona Dono do Grupo, Líder/Diretor nem
--   Administrador do distrito — nenhum deles tem motivo para ler voto alheio.
