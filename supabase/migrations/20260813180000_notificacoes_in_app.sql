-- Change notificacoes-in-app — aviso dirigido a uma pessoa, dentro do app.
--
-- POR QUE ISTO EXISTE
-- `convite-para-acao` deixou um buraco declarado no próprio design: o convite
-- só aparece se a pessoa resolver abrir a tela de convites por conta própria.
-- Convite que ninguém vê é o mesmo que não ter convidado, e quem convidou não
-- descobria a resposta em lugar nenhum.
--
-- SEM FORNECEDOR NOVO. Não há Firebase no pubspec, o SMTP está comentado no
-- config.toml, e não existia nenhuma forma de aviso no app. A leitura adotada é
-- "nada fora do que a stack já tem": aviso dentro do app, atualizado por
-- Realtime, que já vem ligado (`config.toml:87-88`). Push de navegador e e-mail
-- ficam para change própria — e esta tabela já nasce no formato que eles
-- consomem.

-- ---------------------------------------------------------------------------
-- 1. A tabela
-- ---------------------------------------------------------------------------
-- Genérica desde o primeiro dia: `tipo` é `text` com `check`, no padrão de
-- `confirmacoes_acao.status` e `perfis.genero`. Um `enum` do Postgres exigiria
-- `alter type` para crescer, e esta tabela VAI crescer em tipos — é o motivo de
-- ela ser genérica. Convite é o primeiro assunto; log de mudanças e chat entram
-- depois sem tabela nova.
--
-- NÃO CONFUNDIR COM `mudancas`. Aquela é registro POR ESPAÇO — de um Grupo ou
-- de uma Ação —, sem destinatário e sem estado de lida: quem alcança o espaço
-- lê o registro inteiro. Esta é DIRIGIDA e PRIVADA, e duas pessoas do mesmo
-- Grupo veem listas diferentes. Derivar uma da outra exigiria recalcular, a
-- cada leitura, PARA QUEM cada evento é relevante — que é o trabalho que
-- `destinatario_id`, gravado uma vez pelo gatilho, faz de graça.
create table public.notificacoes (
  id uuid primary key default gen_random_uuid(),
  destinatario_id uuid not null references public.perfis(id),
  tipo text not null check (tipo in (
    'convite_recebido',
    'convite_aceito',
    'convite_recusado'
  )),
  ator_id uuid references public.perfis(id),
  acao_id uuid references public.acoes(id) on delete cascade,
  grupo_id uuid references public.grupos(id) on delete cascade,
  lida_em timestamptz,
  created_at timestamptz not null default now()
);

comment on table public.notificacoes is
  'Aviso dirigido a uma pessoa. Escrito SÓ por gatilho: não há grant de insert '
  'nem de delete para ninguém. O cliente escreve UMA coluna, lida_em, por '
  'grant de coluna. Change notificacoes-in-app.';

comment on column public.notificacoes.lida_em is
  'A única coluna que o cliente pode escrever. O recorte é por COLUNA e não só '
  'por policy: policy filtra linha, e sem o recorte a pessoa reescreveria tipo, '
  'ator_id ou destinatario_id na própria linha com a policy achando que está '
  'tudo bem — a lição de 20260811160000_grant_update_perfis_por_coluna.sql.';

comment on column public.notificacoes.ator_id is
  'Quem provocou o aviso, por referência a perfis(id) e nunca por cópia do '
  'nome, para a anonimização de exclusao_de_conta propagar sozinha. Anulável '
  'porque tipo futuro pode não ter autor humano.';

-- O aviso de aceite NÃO guarda se a pessoa entrou como confirmado ou em fila.
-- Quem estava na fila é promovido depois por `promover_fila_acao`, e um aviso
-- com o status congelado passaria a mentir. A tela lê `confirmacoes_acao` na
-- hora de renderizar e diz o estado de agora.

-- Parcial para o contador, completo para a lista.
create index notificacoes_nao_lidas
  on public.notificacoes (destinatario_id, created_at desc)
  where lida_em is null;
create index notificacoes_por_destinatario
  on public.notificacoes (destinatario_id, created_at desc);

-- ---------------------------------------------------------------------------
-- 2. Privilégios e RLS
-- ---------------------------------------------------------------------------
-- NADA para `anon`: aviso não é público. E aqui NÃO vale o argumento de canal
-- lateral que fez a feature 021 manter o `grant` de `votos` — ninguém descobre
-- a existência de um aviso alheio por diferença de resposta, porque não há id
-- de aviso circulando fora do dono.
--
-- Nenhum `grant insert` e nenhum `grant delete` para ninguém: com RLS ligada e
-- sem policy, o Postgres recusa, e isso É o mecanismo, não esquecimento. Quem
-- escreve são os três gatilhos abaixo, `security definer`.
grant select on public.notificacoes to authenticated;
grant update (lida_em) on public.notificacoes to authenticated;

alter table public.notificacoes enable row level security;

create policy notificacoes_select_propria
  on public.notificacoes for select
  to authenticated
  using (auth.uid() = destinatario_id);

create policy notificacoes_update_propria
  on public.notificacoes for update
  to authenticated
  using (auth.uid() = destinatario_id)
  with check (auth.uid() = destinatario_id);

-- O VALOR de lida_em é do servidor, não do cliente.
--
-- Sem isto, o `grant update (lida_em)` acima vira um caminho de EXCLUSÃO pela
-- porta que esta migration diz ter fechado: `expurgar_notificacoes_lidas` apaga
-- pela idade de `lida_em`, e quem escreve `lida_em` era o relógio do celular.
-- Um `update ... set lida_em = now() - interval '91 days'` — relógio errado,
-- fuso mal resolvido, ou chamada REST direta — faria o aviso sumir na madrugada
-- seguinte. O contrário também: data no futuro nunca expurgaria.
--
-- Marcar como lida continua sendo uma escrita do cliente; o que ele não escolhe
-- é QUANDO. Desmarcar (voltar para null) segue permitido.
create function public.notificacoes_lida_em_do_servidor()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  new.lida_em := case when new.lida_em is null then null else now() end;
  return new;
end;
$$;

create trigger notificacoes_lida_em_do_servidor_trigger
  before update on public.notificacoes
  for each row
  execute function public.notificacoes_lida_em_do_servidor();

-- ---------------------------------------------------------------------------
-- 3. Os três gatilhos
-- ---------------------------------------------------------------------------
-- Entram AO LADO dos existentes. `confirmacoes_acao_decidir_status()` e
-- `promover_fila_acao()` não são tocadas.
create function public.notificar_convite_recebido()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notificacoes
    (destinatario_id, tipo, ator_id, acao_id, grupo_id)
  values (new.convidado_id, 'convite_recebido', new.convidante_id,
          new.acao_id, new.grupo_id);
  return null;
end;
$$;

-- Idempotência sai de graça: convite repetido pelo mesmo Grupo não gera linha
-- nova em `convites_acao` (o `on conflict do nothing` de convidar_para_acao),
-- então este gatilho nem dispara.
create trigger convites_acao_notificar_recebido
  after insert on public.convites_acao
  for each row
  execute function public.notificar_convite_recebido();

create function public.notificar_convite_recusado()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notificacoes
    (destinatario_id, tipo, ator_id, acao_id, grupo_id)
  values (new.convidante_id, 'convite_recusado', new.convidado_id,
          new.acao_id, new.grupo_id);
  return null;
end;
$$;

create trigger convites_acao_notificar_recusado
  after update on public.convites_acao
  for each row
  when (old.recusado_em is null and new.recusado_em is not null)
  execute function public.notificar_convite_recusado();

-- `after`, nunca `before`: precisa rodar depois do gatilho que decide
-- confirmado/fila. E é `insert`, não `update`, então a promoção de fila (que é
-- update) não gera aviso duplicado.
--
-- Um aviso POR CONVITE existente para (acao_id, usuario_id): quem não foi
-- convidado não gera nada, e duas pessoas que convidaram recebem cada uma o seu.
create function public.notificar_convite_aceito()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  insert into public.notificacoes
    (destinatario_id, tipo, ator_id, acao_id, grupo_id)
  select c.convidante_id, 'convite_aceito', new.usuario_id,
         c.acao_id, c.grupo_id
  from public.convites_acao c
  where c.acao_id = new.acao_id and c.convidado_id = new.usuario_id;
  return null;
end;
$$;

create trigger confirmacoes_acao_notificar_aceito
  after insert on public.confirmacoes_acao
  for each row
  execute function public.notificar_convite_aceito();

-- ---------------------------------------------------------------------------
-- 4. A view — contador e lista com o MESMO filtro
-- ---------------------------------------------------------------------------
-- O contador e a lista PRECISAM bater; é requisito. Dois `where` escritos duas
-- vezes divergem na primeira mudança, uma view não.
--
-- `security_invoker = true` é OBRIGATÓRIO e é a linha mais perigosa desta
-- change: sem ele a view roda com os privilégios de quem a criou e IGNORA a RLS
-- de `notificacoes`, entregando aviso alheio. Tem teste próprio.
create view public.notificacoes_ativas with (security_invoker = true) as
  select n.*, a.nome as acao_nome
  from public.notificacoes n
  left join public.acoes a on a.id = n.acao_id
  where n.acao_id is null
     -- `acao_encerrada(a.data_hora)` e não `(a.id)`: a linha de `acoes` já está
     -- aqui pelo `left join`, e a versão por uuid faria um SEGUNDO acesso a
     -- `acoes` por linha — reavaliando `acoes_select_visivel`, que tem um
     -- `exists` sobre `participacoes_grupo` dentro. A sobrecarga por timestamptz
     -- foi criada em 20260813120000_acao_restrita_ao_grupo.sql exatamente para
     -- este caso, e o limiar de 4h continua definido num lugar só.
     or (a.cancelada_em is null and not public.acao_encerrada(a.data_hora));

grant select on public.notificacoes_ativas to authenticated;

comment on view public.notificacoes_ativas is
  'Avisos ainda válidos. O contador e a lista leem daqui, nunca da tabela crua '
  '— é o que impede os dois números de divergirem. security_invoker = true é '
  'obrigatório: sem ele a view ignora a RLS de notificacoes. Expõe acao_nome '
  'para o app não pedir um embed de acoes que juntaria a tabela uma TERCEIRA '
  'vez, reavaliando a policy de novo.';

-- ---------------------------------------------------------------------------
-- 5. Realtime — a estreia
-- ---------------------------------------------------------------------------
-- Até esta migration NENHUMA tabela estava na publicação `supabase_realtime`.
-- Esta é a primeira, e por isso o teste de isolamento do canal com duas sessões
-- é obrigatório, não opcional.
--
-- O app usa o canal como SINAL, nunca como fonte de dado: ao receber qualquer
-- evento ele RECONSULTA a contagem e a lista. Três motivos, nessa ordem: o
-- filtro de "aviso ainda válido" depende de `acoes` e não cabe num payload de
-- linha; não depender do payload respeitar RLS reduz o estrago se a
-- configuração do canal estiver errada; e reconsultar torna "a conexão caiu"
-- recuperável sem código de reconciliação.
alter publication supabase_realtime add table public.notificacoes;

-- ---------------------------------------------------------------------------
-- 6. Retenção — 90 dias depois de LIDA
-- ---------------------------------------------------------------------------
-- Não lido nunca é apagado: se ninguém viu, o prazo não começou.
--
-- Herdando o aviso de 20260810110000_drenagem_capas.sql: com o projeto pausado
-- no plano Free o cron para junto. Aqui isso é ATRASO DE FAXINA, não defeito de
-- correção — nenhum requisito depende de o aviso ter sumido no dia certo. Por
-- isso, diferente da drenagem de capas, aqui NÃO se justifica o segundo gatilho
-- no app.
create function public.expurgar_notificacoes_lidas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.notificacoes
  where lida_em is not null
    and lida_em < now() - interval '90 days';
  get diagnostics v_apagadas = row_count;
  return v_apagadas;
end;
$$;

revoke all on function public.expurgar_notificacoes_lidas() from public;

select cron.schedule(
  'expurgar-notificacoes-lidas',
  '17 4 * * *',
  $$select public.expurgar_notificacoes_lidas()$$
);
