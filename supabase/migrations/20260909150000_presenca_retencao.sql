-- Change `presenca-em-acao`, parte 6 — o prazo de guarda.
--
-- Dois anos para a linha nominal, contados da Ação. O prazo é folgado de
-- propósito: a métrica que vai consumir esta coleta compara meses de histórico
-- contra meses anteriores, e um prazo apertado esvaziaria a janela antes de ela
-- encher.
--
-- O QUE NÃO VENCE: `acoes.presentes_no_fechamento`. A quantidade agregada deixa
-- de ser dado pessoal assim que perde o nome, e é ela que serve de histórico ao
-- ministério — "naquele sábado vieram doze" sobrevive à faxina.

-- ---------------------------------------------------------------------------
-- A faxina
-- ---------------------------------------------------------------------------
--
-- ZERA AS COLUNAS, NÃO APAGA A LINHA (design D-007). Apagar a linha de
-- `confirmacoes_acao` levaria junto a INTENÇÃO, que é dado de outra finalidade
-- e de outro prazo — quem confirmou continua sendo um fato do evento. Zerar
-- devolve a linha ao estado "não registrado", que esta change já define e que o
-- resto do sistema já sabe tratar.
--
-- A contestação vencida vai inteira: ela só existe para equilibrar uma
-- afirmação que, a partir daqui, não existe mais.
--
-- O rastro segue a capability `observador-de-retencao`: toda execução se
-- registra, inclusive a que não apagou nada — "rodou e não havia nada" e "não
-- rodou" são fatos diferentes. E um registro que falha NÃO desfaz o expurgo,
-- que já aconteceu antes do bloco.

create function public.expurgar_presenca_vencida(p_disparada_por text default 'app')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  -- A propagação de contestação é a única porta que escreve `contestada_em`, e
  -- a faxina precisa dela para limpar a coluna: sem isto,
  -- `confirmacoes_acao_carimbar_presenca` restauraria o valor antigo e a marca
  -- de contestação sobreviveria ao dado que ela qualificava.
  perform set_config('app.propagando_contestacao', 'true', true);

  update public.confirmacoes_acao c
  set compareceu_em = null,
      marcado_por = null,
      contestada_em = null
  from public.acoes a
  where c.acao_id = a.id
    and now() > a.data_hora + interval '2 years'
    and (
      c.compareceu_em is not null
      or c.marcado_por is not null
      or c.contestada_em is not null
    );
  get diagnostics v_apagadas = row_count;

  perform set_config('app.propagando_contestacao', 'false', true);

  delete from public.contestacoes_presenca ct
  using public.acoes a
  where ct.acao_id = a.id
    and now() > a.data_hora + interval '2 years';

  begin
    perform public.registrar_faxina(
      'expurgar_presenca_vencida', v_apagadas, p_disparada_por
    );
  exception when others then
    -- A faxina não deixa de acontecer por causa do rastro. As linhas vencidas
    -- já foram zeradas antes deste bloco começar.
    null;
  end;

  return v_apagadas;
end;
$$;

comment on function public.expurgar_presenca_vencida(text) is
  'Zera comparecimento, autor da marca e marca de contestação dois anos depois '
  'de acoes.data_hora, e apaga a contestação correspondente. NÃO apaga a linha '
  'de confirmacoes_acao: a intenção é dado de outra finalidade e de outro '
  'prazo. NÃO toca acoes.presentes_no_fechamento, que é agregado e deixou de '
  'ser dado pessoal. Cada execução se registra em execucoes_de_faxina, '
  'inclusive a que não apaga nada. Change presenca-em-acao, '
  'observador-de-retencao.';

revoke execute on function public.expurgar_presenca_vencida(text) from public;
grant execute on function public.expurgar_presenca_vencida(text) to authenticated;

-- SEM segundo gatilho no app, mesmo precedente de `expurgar_mudancas`: atraso
-- aqui é atraso de faxina, não defeito de correção. Nenhum requisito depende de
-- a presença sumir no dia exato — ao contrário da conversa de Ação, cujo
-- conteúdo é indeterminado.
select cron.unschedule(jobid)
  from cron.job where jobname = 'expurgar-presenca-vencida';

select cron.schedule(
  'expurgar-presenca-vencida',
  '47 3 * * *',
  $$select public.expurgar_presenca_vencida(p_disparada_por => 'cron')$$
);
