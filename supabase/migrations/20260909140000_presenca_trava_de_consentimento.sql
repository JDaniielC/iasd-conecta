-- Change `presenca-em-acao`, parte 5 — o consentimento trava a COLETA.
--
-- Medir comparecimento é finalidade nova, e a Política vigente promete que "o
-- aceite dado numa versão não cobre finalidade nova que só a versão seguinte
-- passe a ter" (`privacy_policy_page.dart`). Sem esta trava, o vermelho medido
-- foi `Expected: <0> Actual: <1>`: quem nunca consentiu com a finalidade era
-- marcado normalmente.
--
-- A TRAVA É NA ESCRITA, E NÃO NA CONSULTA. Gravar primeiro e filtrar na hora de
-- medir guardaria por dois anos um dado provavelmente sensível do art. 5º, II
-- sobre quem não consentiu. Filtrar depois protege o relatório; não protege a
-- pessoa.

-- ---------------------------------------------------------------------------
-- 1. A checagem
-- ---------------------------------------------------------------------------
--
-- `security definer` POR NECESSIDADE, não por escolha: `perfis_select_own`
-- impede quem organiza a Ação de ler `consentimento_lgpd_versao` de quem
-- participa, e sem essa leitura não há como decidir.
--
-- Dentro de `security definer` a RLS não se aplica, então o que precisa de
-- checagem explícita é a AUTORIDADE DE QUEM CHAMOU (CLAUDE.md). Os dois braços
-- abaixo existem para isso, e sem eles a função vira um oráculo geral de
-- "fulano está com o aceite atrasado" para qualquer pessoa que crie uma Ação
-- qualquer.
--
-- VAZAMENTO RESIDUAL, DECLARADO E ACEITO (design D-004)
-- Mesmo com os dois braços, quem cria a Ação descobre que alguém do PRÓPRIO
-- evento está com o aceite defasado. É um bit sobre um conjunto que essa pessoa
-- já conhece, e não há como travar a coleta sem consultá-lo. Fica registrado
-- aqui para não ser redescoberto como achado de auditoria.
--
-- Devolve BOOLEANO e nada mais. Nunca a versão, nunca a data, nunca o motivo:
-- "não pôde marcar" não pode virar "esta pessoa aceitou a 1.9".

create function public.pode_registrar_presenca(
  p_acao_id uuid,
  p_usuario_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.acoes a
    join public.confirmacoes_acao c
      on c.acao_id = a.id and c.usuario_id = p_usuario_id
    join public.perfis p
      on p.id = p_usuario_id
    where a.id = p_acao_id
      -- Autoridade: só quem criou a Ação pergunta.
      and a.criador_id = (select auth.uid())
      -- Escopo: só sobre quem tem confirmação nesta Ação.
      -- (garantido pelo join com confirmacoes_acao)
      -- Consentimento: exatamente a versão vigente. Versão anterior e versão
      -- desconhecida (NULL) ficam de fora, e o NULL de fora é o lado certo de
      -- errar — são os aceites colhidos entre 2026-07-23 e 2026-08-09, quando o
      -- app só gravava a data.
      and p.consentimento_lgpd_versao = public.versao_texto_legal_vigente()
  );
$$;

comment on function public.pode_registrar_presenca(uuid, uuid) is
  'Diz se quem chama (o criador da Ação) pode registrar comparecimento desta '
  'pessoa, considerando a versão do texto legal que ela aceitou. Devolve só '
  'booleano — nunca a versão, nunca a data. security definer porque '
  'perfis_select_own impede o criador de ler o aceite alheio; por isso os dois '
  'braços de autoridade (é o criador daquela Ação; a pessoa tem confirmação '
  'nela) são obrigatórios. Change presenca-em-acao.';

revoke execute on function public.pode_registrar_presenca(uuid, uuid) from public;
grant execute on function public.pode_registrar_presenca(uuid, uuid)
  to authenticated;

-- ---------------------------------------------------------------------------
-- 2. A trava entra na policy — e DESMARCAR continua sempre possível
-- ---------------------------------------------------------------------------
--
-- O segundo braço do `or` não é conveniência: quando uma versão nova entra em
-- vigor, todo mundo fica defasado de um dia para o outro. Sem ele, quem
-- organiza perderia o alcance para REMOVER marcas já gravadas — o consentimento
-- passaria a travar também o apagamento, que é o oposto do que ele protege.
--
-- Marcar de novo depois de remover não passa: a linha volta a `compareceu_em is
-- null` e sai do alcance na mesma hora.

alter policy confirmacoes_acao_update_presenca
  on public.confirmacoes_acao
  using (
    exists (
      select 1 from public.acoes a
      where a.id = confirmacoes_acao.acao_id
        and a.criador_id = auth.uid()
        and a.data_hora <= now()
        and a.cancelada_em is null
        and a.presenca_fechada_em is null
    )
    and (
      public.pode_registrar_presenca(
        confirmacoes_acao.acao_id, confirmacoes_acao.usuario_id
      )
      or confirmacoes_acao.compareceu_em is not null
    )
  );

-- ---------------------------------------------------------------------------
-- 3. O reaceite precisa de um `grant` que ainda não existia
-- ---------------------------------------------------------------------------
--
-- `20260811160000_grant_update_perfis_por_coluna.sql:43-45` concede `nome`,
-- `apelido`, `igreja_id`, `telefone` e `consentimento_lgpd_igreja_aceito_em` —
-- e não `consentimento_lgpd_aceito_em`. Quer dizer que, até aqui, a única forma
-- de "retirar o consentimento" que a Política menciona era excluir a conta.
--
-- Nenhuma máquina nova é necessária: `perfis_carimbar_consentimento` já trata
-- `UPDATE` desde a feature 017 — muda o `_aceito_em` para um valor não nulo
-- distinto do anterior e ele carimba `now()` e `versao_texto_legal_vigente()`.
-- O ramo `else` continua impedindo backfill fabricado pelo cliente.

grant update (consentimento_lgpd_aceito_em) on public.perfis to authenticated;
