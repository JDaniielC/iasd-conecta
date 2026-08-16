-- Change fechar-superficie-anon, parte 2 de 2 — a leitura de tabela.
--
-- A DISTINÇÃO QUE FAZ ESTA MIGRATION SER BARATA, e ler antes de reverter:
--
--   Visitante NÃO é `anon`.
--
-- O app faz `signInAnonymously` no arranque (`lib/core/supabase_client.dart`),
-- então TODO Visitante — inclusive quem nunca criou Perfil — chega ao banco
-- como `authenticated`. Confundir os dois já produziu defeito medido: a
-- denúncia de imagem de quem não tem cadastro não acontecia, porque o código
-- usava o id da sessão anônima como se fosse ausência de Perfil
-- (`image_report_repository.dart:15-22`).
--
-- `anon` só aparece em duas situações:
--   1. requisição sem `Authorization` — `curl` com a chave publicável;
--   2. o arranque em que `signInAnonymously` FALHOU. Ali o app abre com a Home
--      estática, por decisão registrada em `supabase_client.dart:41-51`, e a
--      Home estática não consulta o banco.
--
-- Logo: estreitar de `to anon, authenticated` para `to authenticated` não muda
-- uma tela. O `using` de cada policy fica INALTERADO — quem tem sessão continua
-- vendo exatamente o que via.
--
-- SE VOCÊ VEIO ATÉ AQUI PARA REVERTER porque leu em `visibilidade-de-acao` que
-- "Ação é pública por padrão — todo mundo, inclusive sem login": "sem login"
-- ali significa sem Perfil e sem Conta, que é o Visitante. Ele continua vendo
-- tudo. A distinção está escrita como requirement em
-- `openspec/specs/superficie-sem-login/spec.md`, e não como comentário aqui,
-- justamente porque comentário de migration não aparece quando alguém lê a
-- spec.
--
-- POR QUE OS NOMES `_select_public` NÃO MUDAM
-- 20260813120000 renomeou `acoes_select_public` para `acoes_select_visivel`
-- porque o `using` daquela policy deixou de ser `true` — o nome passou a
-- mentir sobre o PREDICADO. Aqui nenhum `using` muda; muda o papel a quem a
-- policy é endereçada. `grupos_select_public` continua querendo dizer "toda
-- linha, sem filtro por dono", e continua sendo verdade.

-- ---------------------------------------------------------------------------
-- 1. As policies deixam de endereçar `anon`
-- ---------------------------------------------------------------------------
-- ORDEM IMPORTA, e o bloco 2 vem depois deste de propósito — ver lá.
--
-- As três primeiras são o motivo prático desta change: elas dizem o que uma
-- pessoa identificável FAZ, e a chave publicável está no bundle.

-- Quem participa de qual Grupo/Ministério. `using (true)`, e com uma linha
-- semeada `anon` enxergava 1 — medido em 2026-08-16.
alter policy participacoes_grupo_select_public
  on public.participacoes_grupo to authenticated;

-- Quem manda no distrito, por nome.
alter policy administradores_distrito_select_public
  on public.administradores_distrito to authenticated;

-- Quem vai a qual encontro.
alter policy confirmacoes_acao_select_conforme_acao
  on public.confirmacoes_acao to authenticated;

-- As demais não expõem pessoa, e fecham pelo mesmo critério: ninguém precisa
-- delas sem sessão, e o que não tem motivo escrito não fica aberto.
alter policy acoes_select_visivel on public.acoes to authenticated;
alter policy acoes_sugeridas_select_public on public.acoes_sugeridas to authenticated;
alter policy categorias_grupo_select_public on public.categorias_grupo to authenticated;
alter policy fotos_capa_select_public on public.fotos_capa to authenticated;
alter policy grupos_select_public on public.grupos to authenticated;
alter policy igrejas_select_ativas_publico on public.igrejas to authenticated;
alter policy liderancas_select_confirmada_propria_ou_admin
  on public.liderancas to authenticated;
alter policy mudancas_select_conforme_origem on public.mudancas to authenticated;
alter policy rodadas_votacao_select_public on public.rodadas_votacao to authenticated;
alter policy versoes_texto_legal_select_public
  on public.versoes_texto_legal to authenticated;

-- ---------------------------------------------------------------------------
-- 2. O `grant` de tabela, DEPOIS da policy
-- ---------------------------------------------------------------------------
-- A ordem é o ponto, e inverter é um defeito de verdade.
--
-- Com a policy já fechada, `anon` consulta e recebe ZERO LINHAS — resposta
-- indistinguível de "não há nada aqui". Revogando o `select` da tabela ANTES,
-- haveria uma janela em que a resposta seria `42501 permission denied`, e
-- `42501` diz que a tabela EXISTE.
--
-- Não é preciosismo: `SECURITY-AUDIT.md` registra, na seção "O que resistiu",
-- o teste de oráculo por forma de resposta — "conversa inexistente" e "conversa
-- que você não pode ver" dão o mesmo `[]` HTTP 200 de propósito. O mesmo vale
-- aqui.
--
-- As duas barreiras juntas, e não uma: a policy diz o que se vê, o `grant` diz
-- se a tabela é alcançável. Fechar só uma deixa a outra como o único obstáculo.
revoke select on table public.acoes from anon;
revoke select on table public.acoes_sugeridas from anon;
revoke select on table public.administradores_distrito from anon;
revoke select on table public.categorias_grupo from anon;
revoke select on table public.confirmacoes_acao from anon;
revoke select on table public.fotos_capa from anon;
revoke select on table public.grupos from anon;
revoke select on table public.igrejas from anon;
revoke select on table public.liderancas from anon;
revoke select on table public.mudancas from anon;
revoke select on table public.participacoes_grupo from anon;
revoke select on table public.rodadas_votacao from anon;
revoke select on table public.versoes_texto_legal from anon;

-- `votos` é DEFESA EM PROFUNDIDADE, não conserto de vazamento.
--
-- Ela tinha `grant select` a `anon` e NENHUMA policy de select que alcançasse
-- `anon` — a RLS já barrava, e `20260809200000_votos_visibilidade.sql` provou
-- isso com teste. O grant era resto da feature 004, de quando o voto era
-- público.
--
-- Fica registrado como o que é: nada estava saindo por aqui. O grant sozinho
-- não lê nada com a RLS ligada, mas ele é a metade de um par, e a outra metade
-- é uma linha de policy que alguém pode escrever daqui a um ano sem lembrar
-- deste arquivo.
revoke select on table public.votos from anon;
