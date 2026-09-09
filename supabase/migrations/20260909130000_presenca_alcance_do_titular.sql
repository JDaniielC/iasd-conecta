-- Change `presenca-em-acao`, parte 4 — o alcance do titular sobre a afirmação
-- feita sobre ele.
--
-- O DEFEITO, MEDIDO ANTES DA CORREÇÃO
-- `confirmacoes_acao_select_conforme_acao` (20260813120000:165-173) devolve a
-- confirmação apenas quando a Ação correspondente é legível, e a subconsulta
-- roda sob a RLS de `acoes`. Ação restrita some para quem saiu do Grupo — e a
-- confirmação da pessoa some junto. Medido nesta change, em
-- `presenca_alcance_titular_test.dart`:
--
--   Expected: ['e5000000-0000-0000-0000-000000000002']
--     Actual: []
--
-- E o efeito não para na leitura. No Postgres, um `UPDATE ... WHERE` só enxerga
-- a linha que a policy de `SELECT` deixa a sessão ler, e o `exists` da policy
-- de contestação também roda sob a RLS de quem chama. Sem este braço, quem sai
-- do Grupo perde o direito de contestar a afirmação que outra pessoa fez sobre
-- ele — justamente quando mais precisa.
--
-- É o mesmo defeito que `PENDENCIAS.md` 2.28 mediu na fixação de mensagem e que
-- a change `alcance-do-titular-sobre-texto-proprio` corrigiu. Aqui ele nasceria
-- de novo, por herança, se a policy não fosse alargada junto com a feature.
--
-- O BRAÇO É ESTREITO DE PROPÓSITO: `auth.uid() = usuario_id`, e só. Ele devolve
-- A PRÓPRIA linha, nunca a Ação inteira. Alargá-lo para a Ação abriria a Ação
-- restrita pela porta dos fundos, e há teste afirmando que a confirmação alheia
-- continua invisível.

alter policy confirmacoes_acao_select_conforme_acao
  on public.confirmacoes_acao
  using (
    auth.uid() = usuario_id
    or exists (
      select 1 from public.acoes a
      where a.id = confirmacoes_acao.acao_id
    )
  );

comment on policy confirmacoes_acao_select_conforme_acao
  on public.confirmacoes_acao is
  'A confirmação é legível quando a Ação é legível, MAIS a própria linha da '
  'pessoa, sempre. O segundo braço não é conveniência de tela: sem ele o '
  'titular perde o alcance para contestar a marca de comparecimento feita '
  'sobre si assim que sai do Grupo de uma Ação restrita — um UPDATE só enxerga '
  'o que o SELECT permite. Mesmo defeito de PENDENCIAS.md 2.28. Changes '
  'acao-direcionada-a-grupo, presenca-em-acao.';
