-- Feature 013 — a drenagem para de sair configurada errado.
--
-- =====================================================================
-- O DEFEITO QUE ESTA MIGRATION FECHA
-- =====================================================================
-- 20260810110000_drenagem_capas.sql semeava `configuracao_drenagem.url_funcao`
-- com `http://host.docker.internal:54321/...`, o endereço do Docker LOCAL, e a
-- única instrução para trocar em produção era um comentário dentro daquela
-- migration — que ninguém relê depois de aplicá-la.
--
-- Consequência em produção: o cron dispara de minuto em minuto contra um
-- endereço que não resolve, a fila NUNCA drena, e toda imagem removida fica no
-- bucket para sempre. Inclusive a que alguém pediu para tirar do ar.
--
-- E falha em SILÊNCIO: nada aparece em tela, nenhum erro chega a ninguém, e o
-- único sintoma é uma tabela crescendo onde ninguém olha. FR-012 ("sai da
-- origem imediatamente") e SC-005 ("0 imagens órfãs") ficariam falsos sem que
-- um único teste percebesse.
--
-- =====================================================================
-- O CONSERTO: NENHUM VALOR PADRÃO, EM AMBIENTE NENHUM
-- =====================================================================
-- A tentação era detectar o ambiente e escolher a URL. Não dá: o Postgres não
-- vê variável de ambiente, e `current_database()` é 'postgres' nos dois lados.
-- Qualquer heurística acertaria hoje e erraria calada amanhã — que é
-- exatamente o modo de falha que se está consertando.
--
-- Então: a migration **não semeia nada**, e a função **recusa em voz alta**
-- enquanto a URL não estiver configurada. Quem configura o local é
-- `supabase/seed.sql`, que roda em `supabase db reset` e **nunca em produção**.
-- Produção configura uma vez, e a instrução mora em INFRA-PRODUCAO.md, que é o
-- lugar canônico do que produção precisa desde a feature 019.
--
-- O barulho é o ponto. Fila parada em silêncio é o defeito; erro no log do cron
-- de minuto em minuto é o sintoma que se quer ter.

delete from public.configuracao_drenagem
where url_funcao = 'http://host.docker.internal:54321/functions/v1/drenar-capas';

comment on table public.configuracao_drenagem is
  'Endereço da Edge Function que esvazia capas_a_remover. NÃO tem valor padrão, '
  'de propósito: cada ambiente configura o seu. O local vem de '
  'supabase/seed.sql; produção, de um update manual documentado em '
  'INFRA-PRODUCAO.md. Linha única, garantida pelo primary key booleano. '
  'Feature 013.';

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
  'Pede à Edge Function que esvazie capas_a_remover. Assíncrona: devolve o id '
  'da requisição, não o resultado. Chamada pelo cron e pelo app. Levanta '
  'exceção se o ambiente não tiver configurado a URL — silêncio aqui é imagem '
  'que nunca sai do bucket. Feature 013.';
