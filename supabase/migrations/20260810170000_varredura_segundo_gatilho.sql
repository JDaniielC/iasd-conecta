-- Feature 013 — a varredura ganha o segundo gatilho que a drenagem já tinha.
--
-- ---------------------------------------------------------------------
-- POR QUE O CRON SOZINHO NÃO CUMPRE O PRAZO
-- ---------------------------------------------------------------------
-- SC-010 declara um número: arquivo sem nenhum registro que o referencie
-- deixa de existir em **no máximo 24 horas**.
--
-- `varrer_capas_orfas()` nasceu agendada só no `pg_cron`, de hora em hora. Com
-- o cron de pé, o pior caso é ~2 horas (1 de carência + 1 de espera) — dentro
-- do prazo. Mas `pg_cron` roda DENTRO do Postgres, e projeto no plano gratuito
-- é pausado depois de uma semana sem atividade; com o banco pausado o cron
-- para junto, e o prazo vira ilimitado. A escolha do plano gratuito é decisão
-- registrada na feature 019, então isto não é hipótese.
--
-- É a mesma lição que a drenagem já tinha aprendido: quem acorda o banco é
-- quem usa o app, então o app precisa ser o segundo gatilho. A varredura
-- herdara a limitação sem herdar a mitigação.
--
-- ---------------------------------------------------------------------
-- POR QUE A VARREDURA VEM ANTES DA SAÍDA ANTECIPADA, E NÃO DEPOIS
-- ---------------------------------------------------------------------
-- A função saía cedo quando a fila estava vazia — "nada a fazer é o caso
-- comum". Só que a fila vazia é EXATAMENTE o estado do órfão que a varredura
-- procura: o arquivo que nunca teve linha nunca entrou na fila. Varrer depois
-- da saída antecipada seria não varrer nunca, justo no caso que motivou a
-- varredura.
--
-- O custo é uma consulta em `storage.objects` filtrada por bucket a cada
-- remoção ou troca de capa. O volume deste distrito é de dezenas de arquivos.
create or replace function public.drenar_capas_a_remover()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_request_id bigint;
begin
  -- Primeiro a varredura: ela pode ser a única coisa que há para fazer, e é
  -- invisível para a checagem de fila logo abaixo.
  perform public.varrer_capas_orfas();

  -- Nada a fazer é o caso comum: não vale acordar a rede por isso.
  if not exists (
    select 1 from public.capas_a_remover where removido_em is null
  ) then
    return null;
  end if;

  select url_funcao into v_url from public.configuracao_drenagem;

  -- A recusa ruidosa. Sem ela, a fila cresceria calada e a Política estaria
  -- afirmando a titulares uma remoção que nunca acontece.
  if v_url is null or v_url = '' then
    raise exception
      'Drenagem de capas não configurada: public.configuracao_drenagem está '
      'vazia. Há % arquivo(s) esperando remoção. Ver INFRA-PRODUCAO.md.',
      (select count(*) from public.capas_a_remover where removido_em is null);
  end if;

  -- pg_net é assíncrono de propósito. Uma chamada síncrona aqui devolveria o
  -- problema que a fila resolve: rede dentro de transação.
  select net.http_post(url := v_url, body := '{}'::jsonb)
    into v_request_id;

  return v_request_id;
end;
$$;

comment on function public.drenar_capas_a_remover() is
  'Varre órfãos e pede à Edge Function que esvazie capas_a_remover. '
  'Assíncrona: devolve o id da requisição, não o resultado. Chamada pelo cron '
  'e pelo app — o app é o segundo gatilho, que é o que faz SC-010 valer no '
  'plano gratuito. Feature 013.';
