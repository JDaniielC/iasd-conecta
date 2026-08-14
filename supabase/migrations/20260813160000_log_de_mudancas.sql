-- Change log-de-mudancas-em-grupo-e-acao — o app passa a guardar histórico.
--
-- POR QUE ISTO EXISTE
-- Não havia histórico de nada. `acoes` tem nome, data_hora, local, detalhes,
-- limite_vagas e cancelada_em, e NENHUMA coluna de atualização
-- (20260723230639_acoes.sql:5-14); `grupos` idem. Um `update` sobrescrevia o
-- valor antigo e não deixava rastro em lugar nenhum.
--
-- O efeito para quem usa: a pessoa entrou no Grupo, confirmou presença, a Ação
-- mudou de horário, e não havia tela, aviso ou registro que dissesse isso. Ela
-- descobria aparecendo no lugar errado na hora errada.

-- ---------------------------------------------------------------------------
-- 1. A tabela
-- ---------------------------------------------------------------------------
-- Uma tabela, não uma por origem. A tela precisa dos eventos de Grupo e de Ação
-- INTERCALADOS em ordem de tempo; com tabelas separadas, todo carregamento
-- viraria `union all` + `order by` sobre o resultado, e nenhum índice cobriria
-- a ordenação final.
create table public.mudancas (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid references public.grupos(id) on delete cascade,
  acao_id uuid references public.acoes(id) on delete cascade,
  tipo text not null check (tipo in (
    'acao_criada',
    'acao_horario_alterado',
    'acao_local_alterado',
    'acao_cancelada',
    'participacao_entrou',
    'participacao_saiu',
    'confirmacao_confirmado',
    'confirmacao_fila',
    'confirmacao_cancelada',
    'grupo_arquivado'
  )),
  autor_id uuid references public.perfis(id),
  created_at timestamptz not null default now()
);

comment on table public.mudancas is
  'Registro cronológico de eventos de Grupo e de Ação. Escrito SÓ por gatilho — '
  'não há policy de insert/update/delete e não há grant de escrita. NÃO guarda '
  'valor anterior e valor novo de propósito: o registro diz QUE mudou, não de '
  'que para que. Guardar o par exigiria jsonb ou uma tabela por campo, e a tela '
  'não usaria. Change log-de-mudancas-em-grupo-e-acao.';

comment on column public.mudancas.autor_id is
  'Quem EXECUTOU a operação, por referência a perfis(id) e nunca por cópia do '
  'nome — assim a anonimização de exclusao_de_conta '
  '(20260806140000_exclusao_de_conta.sql:14-16) propaga sozinha. Anulável '
  'porque nem todo evento tem autor no momento do gatilho: remoção em cascata '
  'não tem auth.uid(). Onde é nulo, a tela escreve a frase sem sujeito.';

comment on column public.mudancas.grupo_id is
  'Evento de Ação que pertence a um Grupo grava AS DUAS chaves, copiando '
  'acoes.grupo_id no momento do gatilho. É o que faz o feed do Grupo ser um '
  'único `where grupo_id = ?` sem tocar em acoes. Se a Ação mudar de Grupo '
  'depois, os registros antigos continuam apontando para onde o evento '
  'aconteceu — que é o correto.';

-- Parciais, um por eixo de leitura. Precedente: `grupos_ativos`
-- (20260809230000_arquivar_grupo.sql:41).
create index mudancas_por_grupo on public.mudancas (grupo_id, created_at desc)
  where grupo_id is not null;
create index mudancas_por_acao on public.mudancas (acao_id, created_at desc)
  where acao_id is not null;

-- ---------------------------------------------------------------------------
-- 2. Leitura: HERDA a visibilidade da origem, não a copia
-- ---------------------------------------------------------------------------
-- `grant select` para os dois papéis: os fatos registrados já são públicos por
-- policy nas tabelas de origem, e a leitura precisa devolver LINHA FALTANDO,
-- nunca erro de permissão — a diferença entre "não aconteceu" e "não posso ver"
-- seria contável.
grant select on public.mudancas to anon, authenticated;

alter table public.mudancas enable row level security;

-- NENHUMA policy de insert, update ou delete. Com RLS ligada e sem policy, o
-- Postgres recusa a operação, e isso É o requisito "o registro é escrito só
-- pelo banco" — não é esquecimento. Os gatilhos abaixo são `security definer`
-- e por isso rodam como o dono da tabela, para quem RLS não se aplica.
--
-- POR QUE NÃO `using (true)`. Uma versão anterior deste desenho era pública,
-- justificada por "espelha a visibilidade das quatro tabelas de origem". Essa
-- frase deixou de ser verdadeira quando `acao-direcionada-a-grupo` entrou:
--   - acao_criada/acao_horario_alterado/acao_cancelada carregam grupo_id, e sem
--     filtro qualquer pessoa da internet leria que o Grupo X tem encontro
--     marcado e que ele mudou de hora — exatamente o que a reunião de liderança
--     queria esconder;
--   - pior, confirmacao_confirmado guarda o par nominal (acao_id, autor_id), o
--     mesmo formato de vazamento que a feature 021 fechou em `votos`
--     (20260809200000_votos_visibilidade.sql:8-17).
--
-- A subconsulta roda sob a RLS de `acoes` para a mesma sessão, então a regra de
-- visibilidade de Ação continua existindo NUM LUGAR SÓ. Duplicar aqui a
-- condição de participação seria a segunda cópia que fica para trás na primeira
-- mudança.
--
-- Linha com grupo_id e sem acao_id (participacao_*, grupo_arquivado) continua
-- pública, porque participacoes_grupo e grupos continuam públicas. Apertar essas
-- sem apertar a origem seria teatro: o mesmo fato seguiria legível lá.
--
-- `acoes` tem `on delete cascade` para cá, então `exists` falso significa
-- ESCONDIDA, nunca APAGADA — a linha de origem some junto com o registro.
create policy mudancas_select_conforme_origem
  on public.mudancas for select
  to anon, authenticated
  using (
    acao_id is null
    or exists (select 1 from public.acoes a where a.id = mudancas.acao_id)
  );

-- ---------------------------------------------------------------------------
-- 3. Gatilhos
-- ---------------------------------------------------------------------------
-- Todos `after`, na mesma transação, e NENHUM captura exceção. Se a gravação do
-- registro falhar, a transação inteira volta atrás e a operação de origem falha
-- junto. Registro com buraco é pior que operação recusada: quem lê passa a
-- confiar num histórico incompleto sem nenhum sinal de que está incompleto —
-- o modo de falha que 20260806090000_nome_valido_security_definer.sql:7 chama
-- de "o pior modo de falhar".
--
-- Todos entram AO LADO dos gatilhos existentes, sem reescrever nenhum:
-- `confirmacoes_acao_decidir_status` continua sendo quem decide confirmado vs
-- fila, e este aqui só LÊ `new.status` já decidido.

-- Resolve o autor, ou nulo.
--
-- `autor_id` referencia `perfis(id)`, e nem todo `auth.uid()` tem Perfil: a
-- sessão existe em `auth.users` desde o login, e o Perfil é criado depois. Sem
-- esta resolução o gatilho estoura com violação de FK e — como ele não captura
-- exceção, de propósito — derruba a operação de origem junto. Uma pessoa sem
-- Perfil não conseguiria entrar num Grupo.
--
-- Nulo aqui não é perda: é exatamente o caso que a coluna foi feita anulável
-- para cobrir, e a tela escreve a frase sem sujeito.
create function public.autor_de_mudanca()
returns uuid
language sql
stable
security definer
set search_path = ''
as $$
  select p.id from public.perfis p where p.id = auth.uid();
$$;

create function public.registrar_mudanca_acao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    -- Ação avulsa não tem Grupo onde o registro apareceria.
    if new.grupo_id is not null then
      insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
      values (new.grupo_id, new.id, 'acao_criada', public.autor_de_mudanca());
    end if;
    return null;
  end if;

  if new.data_hora is distinct from old.data_hora then
    insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
    values (new.grupo_id, new.id, 'acao_horario_alterado', public.autor_de_mudanca());
  end if;

  if new.local is distinct from old.local then
    insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
    values (new.grupo_id, new.id, 'acao_local_alterado', public.autor_de_mudanca());
  end if;

  -- Só na TRANSIÇÃO. Um segundo update numa Ação já cancelada não repete o
  -- registro.
  if old.cancelada_em is null and new.cancelada_em is not null then
    insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
    values (new.grupo_id, new.id, 'acao_cancelada', public.autor_de_mudanca());
  end if;

  return null;
end;
$$;

create trigger acoes_registrar_mudanca
  after insert or update on public.acoes
  for each row
  execute function public.registrar_mudanca_acao();

create function public.registrar_mudanca_participacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if tg_op = 'INSERT' then
    insert into public.mudancas (grupo_id, tipo, autor_id)
    values (new.grupo_id, 'participacao_entrou', public.autor_de_mudanca());
    return null;
  end if;

  -- Defesa contra cascata: se o Grupo está sendo removido, a linha de origem
  -- some junto e não há onde pendurar o registro. Hoje não existe caminho de
  -- remoção física (não há policy `for delete` em `grupos`), mas o dia em que
  -- houver não pode depender da ordem de processamento da cascata.
  if exists (select 1 from public.grupos g where g.id = old.grupo_id) then
    insert into public.mudancas (grupo_id, tipo, autor_id)
    values (old.grupo_id, 'participacao_saiu', public.autor_de_mudanca());
  end if;
  return null;
end;
$$;

create trigger participacoes_grupo_registrar_mudanca
  after insert or delete on public.participacoes_grupo
  for each row
  execute function public.registrar_mudanca_participacao();

create function public.registrar_mudanca_confirmacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_grupo_id uuid;
  v_acao_id uuid := coalesce(new.acao_id, old.acao_id);
begin
  select a.grupo_id into v_grupo_id from public.acoes a where a.id = v_acao_id;
  -- `not found` aqui é a Ação sumindo por cascata; sem linha de origem, não há
  -- registro a gravar.
  if not found then
    return null;
  end if;

  if tg_op = 'INSERT' then
    -- `new.status` já foi decidido por confirmacoes_acao_decidir_status(), que
    -- é `before insert`. Este gatilho não reimplementa aquela regra: lê o
    -- resultado dela.
    insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
    values (v_grupo_id, v_acao_id,
            case new.status when 'confirmado' then 'confirmacao_confirmado'
                            else 'confirmacao_fila' end,
            (select p.id from public.perfis p where p.id = new.usuario_id));
    return null;
  end if;

  if tg_op = 'UPDATE' then
    -- PROMOÇÃO DA FILA. `confirmacoes_acao_promover_fila` é `after delete` e
    -- sobe a próxima pessoa por `update`. Sem registrar isso, a última palavra
    -- do registro sobre quem foi promovido continuaria sendo
    -- `confirmacao_fila`, e a seção diria "entrou na fila" para alguém que já
    -- tem vaga — o mesmo defeito que justificou existir
    -- `confirmacao_cancelada`: registro que afirma o contrário do estado atual
    -- é pior que registro nenhum, porque ninguém desconfia dele.
    --
    -- Reusa `confirmacao_confirmado` em vez de criar um décimo primeiro tipo: o
    -- fato para quem lê é o mesmo ("agora tem vaga"), e a tela renderizaria os
    -- dois com a mesma frase.
    if old.status = 'fila' and new.status = 'confirmado' then
      insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
      values (v_grupo_id, v_acao_id, 'confirmacao_confirmado',
              (select p.id from public.perfis p where p.id = new.usuario_id));
    end if;
    return null;
  end if;

  -- `old.status` NÃO entra no tipo: sair da fila e desconfirmar presença são o
  -- mesmo fato para quem lê ("não vem mais"), e distinguir criaria dois tipos
  -- que a tela renderizaria com a mesma frase.
  insert into public.mudancas (grupo_id, acao_id, tipo, autor_id)
  values (v_grupo_id, v_acao_id, 'confirmacao_cancelada',
          (select p.id from public.perfis p where p.id = old.usuario_id));
  return null;
end;
$$;

create trigger confirmacoes_acao_registrar_mudanca
  after insert or update or delete on public.confirmacoes_acao
  for each row
  execute function public.registrar_mudanca_confirmacao();

create function public.registrar_mudanca_grupo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.arquivado_em is null and new.arquivado_em is not null then
    insert into public.mudancas (grupo_id, tipo, autor_id)
    values (new.id, 'grupo_arquivado', public.autor_de_mudanca());
  end if;
  return null;
end;
$$;

create trigger grupos_registrar_mudanca
  after update on public.grupos
  for each row
  execute function public.registrar_mudanca_grupo();
