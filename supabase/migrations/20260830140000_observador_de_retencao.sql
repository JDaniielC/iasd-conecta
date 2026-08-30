-- Change observador-de-retencao — a promessa de prazo ganha um rastro.
--
-- POR QUE ISTO EXISTE
-- `expurgar_mensagens_de_acao()` funciona e está provado nos dois lados da
-- fronteira (`chat_expurgo_test.dart`). O problema é outro: ninguém no sistema
-- sabe dizer se ela RODOU. Os dois executores falham calados, cada um do seu
-- jeito — o app engole toda exceção e joga fora a contagem que a função
-- devolve; o `pg_cron` em produção pode nem existir (confirmado na tarefa 0.3:
-- a migration que o cria nunca foi empurrada). Somando os dois: não há tabela
-- de última execução, nem `/health`, nem alerta. A única forma de conferir se
-- a promessa foi cumprida ontem é ir ao banco à mão.
--
-- Junto vem `public.mudancas` (`log-de-mudancas-em-grupo-e-acao`,
-- PENDENCIAS.md 2.10): a única tabela do app que só cresce, sem prazo e sem
-- job. O registro é dado pessoal (`autor_id`), e a Política fala de prazos.
--
-- NÃO MUDA o que é apagado, nem quando. O prazo de 30 dias da conversa de
-- Ação, a exceção da fixada e o teto de 3 continuam exatamente como estão.

-- ---------------------------------------------------------------------------
-- 1. A tabela do rastro
-- ---------------------------------------------------------------------------
-- `faxina` é TEXTO e não enum: uma faxina nova (a próxima é
-- `denuncia-como-registro`) não deveria exigir `alter type`. O valor gravado é
-- o nome da função que a executa — `expurgar_mensagens_de_acao`,
-- `expurgar_mudancas`, `expurgar_rastro` — porque é a chave que já existe e
-- não precisa de um segundo dicionário para traduzir uma pra outra.
--
-- `disparada_por` é o PONTO da change: sem ela, o app disparando esconde a
-- ausência do cron atrás de uma linha que parece dizer "está tudo bem". `cron`
-- e `app` são os dois únicos executores que existem hoje — outros são
-- decisão futura, não valor aceito por engano.
create table public.execucoes_de_faxina (
  id uuid primary key default gen_random_uuid(),
  faxina text not null,
  quando timestamptz not null default now(),
  quantas integer not null,
  disparada_por text not null check (disparada_por in ('cron', 'app'))
);

comment on table public.execucoes_de_faxina is
  'Rastro de execução das faxinas de retenção do app — quando rodou, quanto '
  'apagou, qual faxina foi e quem a disparou. Responde "a promessa de prazo '
  'foi cumprida ontem?" sem ir ao banco à mão, e separa "rodou e não havia '
  'nada a apagar" de "não rodou". NENHUM dado pessoal: não guarda quem foi '
  'afetado, só a contagem. Escrito só por registrar_faxina(), security '
  'definer — sem policy de escrita. Change observador-de-retencao.';

comment on column public.execucoes_de_faxina.disparada_por is
  'cron ou app. SEM esta coluna, o segundo gatilho do app (que existe para '
  'compensar um cron que pode não rodar no plano gratuito) escreveria uma '
  'linha idêntica à do cron e a ausência dele ficaria invisível atrás dela — '
  'exatamente o defeito que motivou esta change. Inferir por current_user foi '
  'recusado: pg_cron e PostgREST podem chegar com o mesmo papel, e uma '
  'inferência que às vezes acerta é pior que uma coluna que sempre diz.';

-- A leitura da tela é sempre "a(s) mais recente(s) de cada faxina" — o índice
-- serve exatamente essa consulta.
create index execucoes_de_faxina_por_faxina
  on public.execucoes_de_faxina (faxina, quando desc);

grant select on public.execucoes_de_faxina to authenticated;

alter table public.execucoes_de_faxina enable row level security;

-- Um braço só: o rastro é informação de operação, não de conversa, e não é
-- dado pessoal — mas ainda assim é do Administrador do distrito decidir se a
-- faxina está em dia, e mais ninguém precisa saber volume de apagamento do
-- app. `anon` fica sem grant nenhum (disciplina de fechar-superficie-anon).
create policy execucoes_de_faxina_select_admin
  on public.execucoes_de_faxina for select
  to authenticated
  using (
    exists (
      select 1 from public.administradores_distrito
      where usuario_id = auth.uid()
    )
  );

-- SEM policy de insert/update/delete: com RLS ligada e nenhuma, o Postgres
-- recusa por padrão — é o requisito "o registro é escrito só pelo banco", não
-- esquecimento. Quem escreve é registrar_faxina(), security definer, que roda
-- como dono da tabela e não passa pela RLS.

-- ---------------------------------------------------------------------------
-- 2. `registrar_faxina` — chamada pelas próprias funções de expurgo
-- ---------------------------------------------------------------------------
-- SEM GRANT a `authenticated`: ninguém no cliente chama isto diretamente, só
-- as funções de expurgo, que a alcançam por serem donas do mesmo objeto (mesmo
-- raciocínio de `mensagem_teto_de_fixadas()`, 20260817160000).
create function public.registrar_faxina(
  p_faxina text,
  p_quantas integer,
  p_disparada_por text default 'app'
)
returns void
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.execucoes_de_faxina (faxina, quantas, disparada_por)
  values (p_faxina, p_quantas, p_disparada_por);
end;
$$;

comment on function public.registrar_faxina(text, integer, text) is
  'Grava uma execução de faxina de retenção. Chamada só pelas funções de '
  'expurgo, sempre dentro de um bloco que engole exceção — a promessa é o '
  'descarte, e o rastro serve à promessa, nunca o contrário. '
  'Change observador-de-retencao.';

revoke execute on function public.registrar_faxina(text, integer, text)
  from public;

-- ---------------------------------------------------------------------------
-- 3. `expurgar_mensagens_de_acao` ganha `disparada_por` e passa a se registrar
-- ---------------------------------------------------------------------------
-- DROP antes do CREATE: acrescentar parâmetro via `create or replace` não
-- troca a função de zero argumentos — cria uma SEGUNDA, e a chamada sem
-- argumento que o app já faz (`ChatRepository.purgeExpiredActionMessages`)
-- passaria a ser ambígua entre as duas. O `drop` é seguro: nada no Postgres
-- referencia esta função por FK — `cron.job.command` é só texto, e o app chama
-- por RPC.
drop function public.expurgar_mensagens_de_acao();

-- O `where` de exclusão de fixada (`and m.fixada_em is null`,
-- 20260817160000) NÃO muda. O único acréscimo real é o registro, depois do
-- `delete`, dentro de `exception when others then null` — a ordem é a
-- decisão: registrar ANTES seria contar tentativa como execução, e a pergunta
-- que a tabela existe para responder é sobre o que ACONTECEU.
create function public.expurgar_mensagens_de_acao(p_disparada_por text default 'app')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.mensagens m
  using public.acoes a
  where m.acao_id = a.id
    and now() > a.data_hora + interval '30 days'
    and m.fixada_em is null;
  get diagnostics v_apagadas = row_count;

  begin
    perform public.registrar_faxina(
      'expurgar_mensagens_de_acao', v_apagadas, p_disparada_por
    );
  exception when others then
    -- A faxina não deixa de acontecer por causa do rastro. As linhas vencidas
    -- já foram apagadas antes deste bloco começar.
    null;
  end;

  return v_apagadas;
end;
$$;

comment on function public.expurgar_mensagens_de_acao(text) is
  'Apaga mensagem de Ação 30 dias depois de acoes.data_hora, exceto a fixada '
  '(20260817160000). O prazo é PROMESSA na Política de Privacidade, e tem '
  'dois gatilhos: este job de pg_cron (disparada_por => ''cron'') e uma '
  'chamada do app ao abrir um chat (padrão ''app''). Desde '
  'observador-de-retencao, cada execução se registra em execucoes_de_faxina — '
  'um registro que falha NÃO desfaz o delete acima. Change '
  'chat-de-grupo-e-acao, observador-de-retencao.';

revoke execute on function public.expurgar_mensagens_de_acao(text) from public;
grant execute on function public.expurgar_mensagens_de_acao(text) to authenticated;

-- Atualiza o job existente em vez de duplicar: `unschedule` por jobid é
-- não-operação se o job não existir (produção não tem — tarefa 0.3), e
-- `schedule` recria com o comando novo, agora dizendo QUEM está chamando.
select cron.unschedule(jobid)
  from cron.job where jobname = 'expurgar-mensagens-de-acao';

select cron.schedule(
  'expurgar-mensagens-de-acao',
  '43 3 * * *',
  $$select public.expurgar_mensagens_de_acao(p_disparada_por => 'cron')$$
);

-- ---------------------------------------------------------------------------
-- 4. `expurgar_mudancas` — o prazo que faltava em `public.mudancas`
-- ---------------------------------------------------------------------------
-- 90 dias, decidido com o dono do app (tarefa 0.1, REVISAO-JURIDICA.md § 4-F):
-- mesmo prazo de `notificacoes`. NÃO é o prazo da conversa (30 dias) —
-- `mudancas` é histórico ESTRUTURAL (por que um Grupo/Ação mudou), não
-- conteúdo de conversa, e apagar no mesmo ritmo tiraria contexto
-- administrativo que ninguém pediu para perder mais cedo.
--
-- SEM segundo gatilho no app, mesmo precedente de `expurgar_notificacoes_lidas`
-- (20260813180000) e pela mesma razão: atraso aqui é ATRASO DE FAXINA, não
-- defeito de correção — nenhum requisito depende do histórico sumir no dia
-- certo, ao contrário da conversa de Ação (cujo conteúdo é indeterminado).
create function public.expurgar_mudancas(p_disparada_por text default 'app')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.mudancas
  where created_at < now() - interval '90 days';
  get diagnostics v_apagadas = row_count;

  begin
    perform public.registrar_faxina(
      'expurgar_mudancas', v_apagadas, p_disparada_por
    );
  exception when others then
    null;
  end;

  return v_apagadas;
end;
$$;

comment on function public.expurgar_mudancas(text) is
  'Apaga registro de public.mudancas 90 dias depois de created_at — mesmo '
  'prazo de notificacoes (REVISAO-JURIDICA.md § 4-F). Dado pessoal '
  '(autor_id), então o prazo está declarado na Política de Privacidade. SEM '
  'segundo gatilho no app: atraso aqui é atraso de faxina, não defeito de '
  'correção, mesmo raciocínio de expurgar_notificacoes_lidas. Registra a '
  'própria execução como as demais faxinas de retenção. Change '
  'observador-de-retencao.';

revoke execute on function public.expurgar_mudancas(text) from public;

select cron.schedule(
  'expurgar-mudancas',
  '30 4 * * *',
  $$select public.expurgar_mudancas(p_disparada_por => 'cron')$$
);

-- ---------------------------------------------------------------------------
-- 5. `expurgar_rastro` — o rastro tem prazo próprio
-- ---------------------------------------------------------------------------
-- 30 dias — mesmo número já em uso no app (tarefa 0.2), decisão de
-- consistência e não de medição. Sem dado pessoal, então não é matéria da
-- Política; a decisão mora só no tasks.md desta change.
--
-- A LINHA MAIS RECENTE DE CADA FAXINA NÃO EXPIRA, e é a exceção inversa da que
-- `mensagem-fixada` declarou: lá a exceção CONSERVA CONTEÚDO; aqui ela
-- conserva a única linha que distingue "parada há muito tempo" de "nunca
-- rodou". Apagá-la seria a limpeza destruir exatamente a informação que a
-- change existe para dar.
create function public.expurgar_rastro(p_disparada_por text default 'app')
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.execucoes_de_faxina
  where quando < now() - interval '30 days'
    and id not in (
      select distinct on (faxina) id
      from public.execucoes_de_faxina
      order by faxina, quando desc
    );
  get diagnostics v_apagadas = row_count;

  -- A execução do próprio expurgo do rastro se registra DEPOIS do delete
  -- acima, então a linha nova nunca é candidata a apagar a si mesma — e ela
  -- passa a ser, de imediato, "a mais recente de expurgar_rastro" para a
  -- próxima passagem.
  begin
    perform public.registrar_faxina(
      'expurgar_rastro', v_apagadas, p_disparada_por
    );
  exception when others then
    null;
  end;

  return v_apagadas;
end;
$$;

comment on function public.expurgar_rastro(text) is
  'Apaga execucoes_de_faxina com mais de 30 dias, PRESERVANDO a mais recente '
  'de cada faxina — sem essa exceção, uma faxina parada há muito tempo '
  'ficaria indistinguível de uma que nunca rodou, que é a pergunta que esta '
  'change existe para responder. Sem dado pessoal, sem segundo gatilho no '
  'app pelo mesmo motivo de expurgar_mudancas. Change observador-de-retencao.';

revoke execute on function public.expurgar_rastro(text) from public;

select cron.schedule(
  'expurgar-rastro',
  '45 4 * * *',
  $$select public.expurgar_rastro(p_disparada_por => 'cron')$$
);
