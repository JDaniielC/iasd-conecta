-- Feature 021 — visibilidade do voto.
--
-- Fecha a leitura de public.votos. Antes desta migration a política era
-- `votos_select_public ... using (true)`, e com o grant de anon isso significa
-- que qualquer pessoa da internet, sem cadastro nenhum, lia a tabela inteira.
--
-- E a tabela é o par nominal (usuario_id, candidata_id), não um agregado.
-- Medido contra o ambiente local, com três requisições e só a chave pública:
--
--   GET  /rest/v1/votos?select=*                -> todos os pares
--   POST /rest/v1/rpc/perfil_publico            -> "Clara Demo"
--   GET  /rest/v1/acoes?select=id,nome          -> "Entrega de cestas"
--
-- Resultado legível por qualquer um: "Clara Demo votou em Entrega de cestas".
-- Numa comunidade de 15+ igrejas onde as pessoas se conhecem, isso é
-- constrangimento real, e ninguém decidiu que seria público — a Política de
-- Privacidade prometia visibilidade apenas "entre os participantes do Grupo".

-- ---------------------------------------------------------------------------
-- 1. Fora a política que mente
-- ---------------------------------------------------------------------------
-- O nome sai junto com a regra. Um `votos_select_public` que não é público
-- seria pior do que nome nenhum — é a mesma divergência entre descrição e
-- comportamento que esta migration existe para consertar. Trocar o nome também
-- faz qualquer referência antiga falhar visivelmente, em vez de continuar
-- apontando para algo com a semântica trocada por baixo.
drop policy if exists votos_select_public on public.votos;

-- ---------------------------------------------------------------------------
-- 2. A regra nova: só o próprio voto
-- ---------------------------------------------------------------------------
-- Vale só para `authenticated`. `anon` fica sem política de select e, com RLS
-- ligada, isso devolve conjunto vazio — não erro.
--
-- O `grant select on public.votos to anon` de
-- 20260724084300_rodada_votacao.sql:190 FICA COMO ESTÁ, de propósito. Revogá-lo
-- faria a API responder erro de permissão em vez de lista vazia, e a diferença
-- entre "não há votos" e "não posso ver" viraria um canal lateral: dá para
-- contar o que existe escondido só olhando qual resposta chega. Lista vazia não
-- conta nada.
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
-- a chave primária é (rodada_id, usuario_id) e o insert já exige
-- auth.uid() = usuario_id. Logo o `on conflict` alcança justamente a linha que
-- esta política continua deixando visível. Quem tenta sobrescrever voto alheio
-- recebe `new row violates row-level security policy for table "votos"`.

-- ---------------------------------------------------------------------------
-- 4. AVISO — a apuração depende de continuar `security definer`
-- ---------------------------------------------------------------------------
-- Este aviso está aqui, e não no arquivo da função, porque é ESTA migration que
-- cria a dependência.
--
-- public.fechar_rodada_se_devido conta os votos com
--   left join public.votos ... group by ... order by count(v.usuario_id) desc
-- (20260724084300_rodada_votacao.sql:168-175). Ela enxerga todos os votos
-- porque é `security definer` com dono `postgres`, e public.votos não tem
-- `force row level security` — RLS não se aplica ao dono da tabela.
--
-- ATÉ AQUI isso era irrelevante: com `using (true)`, definer e invoker contavam
-- igual. A PARTIR DAQUI, converter essa função para `security invoker` faz a
-- apuração contar SÓ OS VOTOS DE QUEM CHAMOU.
--
-- Medido, com 2 votos numa candidata e 1 noutra:
--   security definer                      -> X: 2 votos, Y: 1 voto   (correto)
--   security invoker chamada pela minoria -> Y: 1 voto               (minoria vence)
--
-- A candidata majoritária não aparece com zero — ela SOME da consulta. A Rodada
-- fecha, grava a vencedora errada e APAGA as candidatas perdedoras
-- (20260724084300_rodada_votacao.sql:177-179). Sem erro, sem rastro,
-- irreversível.
--
-- Se você veio até aqui para mexer nessa função:
-- test/integration/votos_visibilidade_test.dart tem um caso que falha quando a
-- apuração deixa de ver todos os votos. Se ele ficou vermelho, é isto.

-- ---------------------------------------------------------------------------
-- 5. O que esta migration NÃO faz
-- ---------------------------------------------------------------------------
-- - Não apaga nem altera nenhum voto. Muda leitura, não conteúdo.
-- - Não mexe em rodadas_votacao, acoes nem perfis.
-- - Não adiciona coluna, índice ou trigger.
-- - Não cria papel novo. A regra não menciona Dono do Grupo, Líder/Diretor nem
--   Administrador do distrito — nenhum deles tem motivo para ler voto alheio.
