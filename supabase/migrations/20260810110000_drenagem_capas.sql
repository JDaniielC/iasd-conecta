-- Feature 013 — quem acorda a drenagem da fila de capas.
--
-- A fila (20260810100000) garante que nenhum caminho de exclusão esqueça o
-- arquivo. Esta migration garante que alguém a esvazie.
--
-- Desenho: pg_cron acorda o banco de minuto em minuto, pg_net chama a Edge
-- Function `drenar-capas`, e ela usa a chave de serviço que o próprio Supabase
-- injeta no ambiente dela. Nenhum segredo é guardado no banco, no repositório
-- ou em arquivo de configuração.
--
-- ---------------------------------------------------------------------
-- A LIMITAÇÃO CONHECIDA, ESCRITA PARA NÃO SER DESCOBERTA DEPOIS
-- ---------------------------------------------------------------------
-- pg_cron roda DENTRO do Postgres. Projeto no plano Free é pausado após uma
-- semana sem atividade, e com o banco pausado o cron para junto.
--
-- Isso morde exatamente onde dói: o que espera na fila são os arquivos que
-- alguém pediu para remover, inclusive foto denunciada como imprópria. O
-- período de menor uso do app é justamente quando a remoção mais demoraria.
--
-- Por isso a drenagem tem DOIS gatilhos, e não um: este cron, e uma chamada
-- feita pelo app quando ele é usado (ver CoverPhotoRepository). Se o projeto
-- acordou, é porque alguém está usando — e a fila drena junto. Um cobre o
-- outro.

create extension if not exists pg_cron;
create extension if not exists pg_net;

-- ---------------------------------------------------------------------
-- Onde a função mora — é URL, não segredo
-- ---------------------------------------------------------------------
-- O endereço muda entre ambiente local e produção, então não pode ser literal
-- na migration. Fica numa tabela de uma linha, sem RLS para o app e sem grant
-- para ninguém: quem lê é o cron, rodando como postgres.
create table public.configuracao_drenagem (
  id boolean primary key default true check (id),
  url_funcao text not null,
  atualizado_em timestamptz not null default now()
);

comment on table public.configuracao_drenagem is
  'Endereço da Edge Function que drena capas_a_remover. É URL, não credencial '
  '— a chave de serviço vive no ambiente da função, nunca aqui. Uma linha só, '
  'garantida pelo primary key booleano. Feature 013.';

alter table public.configuracao_drenagem enable row level security;
revoke all on public.configuracao_drenagem from anon, authenticated;

-- Valor do ambiente local. Em produção, um UPDATE nesta linha aponta para
-- https://<projeto>.supabase.co/functions/v1/drenar-capas
insert into public.configuracao_drenagem (url_funcao)
values ('http://host.docker.internal:54321/functions/v1/drenar-capas');

-- ---------------------------------------------------------------------
-- A chamada
-- ---------------------------------------------------------------------
create function public.drenar_capas_a_remover()
returns bigint
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_url text;
  v_request_id bigint;
begin
  -- Nada a fazer é o caso comum: não vale acordar a rede por isso.
  if not exists (
    select 1 from public.capas_a_remover where removido_em is null
  ) then
    return null;
  end if;

  select url_funcao into v_url from public.configuracao_drenagem;

  -- pg_net é assíncrono de propósito. Uma chamada síncrona aqui devolveria o
  -- problema que a fila resolve: rede dentro de transação.
  select net.http_post(url := v_url, body := '{}'::jsonb)
    into v_request_id;

  return v_request_id;
end;
$$;

comment on function public.drenar_capas_a_remover() is
  'Pede à Edge Function que esvazie capas_a_remover. Assíncrona: devolve o id '
  'da requisição, não o resultado. Chamada pelo cron e pelo app. Feature 013.';

revoke all on function public.drenar_capas_a_remover() from public;
grant execute on function public.drenar_capas_a_remover() to authenticated;

-- ---------------------------------------------------------------------
-- O agendamento
-- ---------------------------------------------------------------------
-- De minuto em minuto. Casa com a janela de cache de 60 segundos que o
-- responsável pelo app aceitou: não adianta remover o arquivo em 5 segundos se
-- a borda continua servindo por 60.
select cron.schedule(
  'drenar-capas-a-remover',
  '* * * * *',
  $$select public.drenar_capas_a_remover()$$
);
