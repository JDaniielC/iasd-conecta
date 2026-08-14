-- Change convite-para-acao — chamar alguém para uma Ação por dentro do app.
--
-- POR QUE ISTO EXISTE
-- Não havia como chamar ninguém: a única escrita possível em confirmacoes_acao
-- é sobre si mesmo (`confirmacoes_acao_insert_self`,
-- 20260723230639_acoes.sql:143-146). Quem criava uma Ação confirmava a própria
-- presença e mais nada — chamar as pessoas acontecia no WhatsApp, e quem não
-- estava naquele grupo de WhatsApp não ficava sabendo.
--
-- E não havia agenda. `perfis_select_own` restringe a leitura de `perfis` a
-- auth.uid() = id (20260723191202_perfis_igrejas.sql:66-69); o nome de outra
-- pessoa só sai por `perfil_publico(uuid)`, UMA POR CHAMADA. O substituto
-- honesto e já modelado são os Grupos: quem divide um Grupo comigo é quem eu
-- posso chamar.

-- ---------------------------------------------------------------------------
-- 1. A tabela
-- ---------------------------------------------------------------------------
-- NÃO EXISTE COLUNA DE ACEITE, e isso é decisão, não esquecimento.
-- Aceitar já tem tabela: aceitar é confirmar presença, e isso é
-- `confirmacoes_acao`. Uma coluna `status = 'aceito'` seria a segunda fonte de
-- verdade sobre a mesma coisa, e as duas divergiriam no primeiro `desistir`.
-- "Em aberto" é derivado: a linha existe, `recusado_em` é nulo, a pessoa não
-- está em confirmacoes_acao, e a Ação não está cancelada nem encerrada.
create table public.convites_acao (
  acao_id uuid not null references public.acoes(id) on delete cascade,
  convidado_id uuid not null references public.perfis(id),
  grupo_id uuid not null references public.grupos(id) on delete cascade,
  convidante_id uuid not null references public.perfis(id),
  created_at timestamptz not null default now(),
  recusado_em timestamptz,
  primary key (acao_id, convidado_id, grupo_id)
);

comment on table public.convites_acao is
  'Convite para uma Ação, feito por dentro de um Grupo. Não tem coluna de '
  'aceite de propósito: aceitar é confirmar presença, e isso é '
  'confirmacoes_acao. O convite APONTA, não reserva vaga. Change '
  'convite-para-acao.';

comment on column public.convites_acao.grupo_id is
  'O Grupo pelo qual o convite foi feito — aquele em cuja seção a pessoa foi '
  'escolhida. Está na chave primária: a mesma pessoa convidada para a mesma '
  'Ação pelo Grupo Jovens e pelo Grupo Música são dois convites, e é por este '
  'campo que quem recebeu filtra.';

comment on column public.convites_acao.recusado_em is
  'Existe porque recusar precisa de algum lugar. Sem ele, convite ignorado e '
  'convite recusado ficam indistinguíveis e a lista nunca esvazia.';

-- As FKs de Perfil são DELIBERADAMENTE sem `on delete cascade`: o Perfil é
-- anonimizado, não apagado (20260806140000_exclusao_de_conta.sql:14-16). O
-- convite referencia perfis(id) e NUNCA copia o nome — nome desnormalizado
-- sobreviveria à anonimização e a exclusão de Conta deixaria de ser exclusão.

create index convites_acao_por_convidado
  on public.convites_acao (convidado_id, created_at desc);
create index convites_acao_por_acao
  on public.convites_acao (acao_id, convidante_id);

-- ---------------------------------------------------------------------------
-- 2. Privilégios — a AUSÊNCIA é o mecanismo
-- ---------------------------------------------------------------------------
-- CRIAR convite não tem grant, e isso não é esquecimento: passa pela RPC
-- `convidar_para_acao`, porque uma das três regras ("quem convida tem Conta")
-- exige ler `auth.users.is_anonymous`, fora do alcance de qualquer policy. Com
-- uma das regras já precisando de `security definer`, pôr as outras duas numa
-- policy espalharia a mesma decisão por dois lugares com sintaxes diferentes.
--
-- RECUSAR é o caso oposto e por isso tem tratamento oposto: quem recusa é a
-- própria pessoa convidada, sobre a própria linha, sem nenhuma regra que exija
-- ler `auth.users`. Uma policy resolve inteira, e o recorte é POR COLUNA —
-- mesmo precedente de `20260811160000_grant_update_perfis_por_coluna.sql`, onde
-- a linha era protegida e a coluna não era. Assim `recusado_em` é a única coisa
-- que a pessoa consegue escrever: tentar mexer em `convidante_id` ou
-- `grupo_id` recusa com `permission denied`, sem depender de a policy lembrar
-- de proibir.
--
-- `anon` não recebe nada: convite não é público. Isto é diferente do caso de
-- `acoes`, onde o grant de anon FICA para a linha escondida virar lista vazia
-- em vez de erro — ali `anon` tem o que ler legitimamente; aqui, nada.
grant select on public.convites_acao to authenticated;
grant update (recusado_em) on public.convites_acao to authenticated;

alter table public.convites_acao enable row level security;

create policy convites_acao_select_partes
  on public.convites_acao for select
  to authenticated
  using (auth.uid() in (convidado_id, convidante_id));

-- Só quem foi convidado recusa. Quem convidou NÃO retira o convite: retirar em
-- silêncio confundiria mais do que ajudaria, mesmo raciocínio que a spec usa
-- para sair do Grupo não apagar convite.
create policy convites_acao_update_convidado
  on public.convites_acao for update
  to authenticated
  using (auth.uid() = convidado_id)
  with check (auth.uid() = convidado_id);

-- ---------------------------------------------------------------------------
-- 3. A lista de contatos, numa chamada só
-- ---------------------------------------------------------------------------
-- `security definer` porque `perfis` é fechado. Mas o ponto perigoso é outro:
-- ela entrega VÁRIOS NOMES DE UMA VEZ. Um a um o nome de exibição já é público
-- hoje; em lote e sem checagem, isto viraria um despejo de nomes do distrito
-- inteiro para qualquer sessão, inclusive anônima.
--
-- Por isso NÃO EXISTE parâmetro de Grupo. O filtro é por auth.uid() POR DENTRO.
-- Aceitar `p_grupo_id` do cliente numa função definer seria exatamente o
-- despejo. Em sessão anônima auth.uid() é nulo, `meus` sai vazio, e a função
-- devolve vazio sozinha — sem `if` especial.
--
-- `nome_exibido` usa `coalesce(apelido, nome)`, a MESMA expressão de
-- `perfil_publico` (20260723191202_perfis_igrejas.sql:47) e não outra: duas
-- definições de "nome que aparece" divergiriam, e a que protege menor de idade
-- é essa.
create function public.contatos_para_convite(p_acao_id uuid)
returns table (
  grupo_id uuid,
  grupo_nome text,
  usuario_id uuid,
  nome_exibido text,
  ja_convidado boolean,
  ja_confirmou boolean
)
language sql
stable
security definer
set search_path = public, auth
as $$
  with meus as (
    select g.id as gid, g.nome as gnome
    from public.grupos g
    join public.participacoes_grupo pg
      on pg.grupo_id = g.id and pg.usuario_id = auth.uid()
    where g.arquivado_em is null
  ),
  alvo as (
    select a.restrita_ao_grupo as restrita, a.grupo_id as gid
    from public.acoes a
    where a.id = p_acao_id
  ),
  -- Ação restrita ao Grupo (change acao-direcionada-a-grupo): convidar por
  -- outro Grupo entregaria um convite para algo que a pessoa não consegue
  -- abrir, e ainda revelaria que a Ação existe. Só a seção do Grupo dono sai.
  visiveis as (
    select m.gid, m.gnome
    from meus m, alvo t
    where t.restrita is false or m.gid = t.gid
  )
  select v.gid, v.gnome, pf.id, coalesce(pf.apelido, pf.nome),
         exists (
           select 1 from public.convites_acao c
           where c.acao_id = p_acao_id
             and c.convidado_id = pf.id
             and c.grupo_id = v.gid
         ),
         -- Quem já confirmou presença. Fecha a segunda metade de "quem
         -- convidou acompanha os próprios convites": sem isto, a tela diria
         -- "já convidado" para sempre e quem convidou não saberia se a pessoa
         -- respondeu. Aqui, e não na tela da Ação — lá a spec proíbe qualquer
         -- lista de convidados, para QUALQUER pessoa, inclusive quem convidou.
         exists (
           select 1 from public.confirmacoes_acao ca
           where ca.acao_id = p_acao_id and ca.usuario_id = pf.id
         )
  from visiveis v
  join public.participacoes_grupo pg2 on pg2.grupo_id = v.gid
  join public.perfis pf on pf.id = pg2.usuario_id
  where pf.id is distinct from auth.uid()
  order by v.gnome, coalesce(pf.apelido, pf.nome);
$$;

comment on function public.contatos_para_convite(uuid) is
  'Contatos convidáveis, agrupados por Grupo, numa chamada só. NÃO aceita '
  'parâmetro de Grupo de propósito: o filtro é por auth.uid() por dentro. '
  'Substitui o N+1 de perfil_publico por membro. Change convite-para-acao.';

-- ---------------------------------------------------------------------------
-- 4. Convidar — em lote, classificando cada pessoa
-- ---------------------------------------------------------------------------
-- Devolve UMA LINHA POR PESSOA PEDIDA. `RETURNING` sozinho não serviria: com
-- `on conflict do nothing`, quem já tinha sido convidado não volta no
-- RETURNING, e a tela leria isso como falha — mostrando erro para uma operação
-- que deu certo.
create function public.convidar_para_acao(
  p_acao_id uuid,
  p_grupo_id uuid,
  p_convidados uuid[]
)
returns table (usuario_id uuid, resultado text)
language plpgsql
security definer
set search_path = public, auth
as $$
declare
  v_uid uuid := auth.uid();
  v_eh_anonimo boolean;
  v_cancelada timestamptz;
  v_data_hora timestamptz;
  v_restrita boolean;
  v_grupo_da_acao uuid;
begin
  if v_uid is null then
    raise exception 'é preciso estar em sessão para convidar';
  end if;

  -- Mesma checagem de Conta que declarar_lideranca faz
  -- (20260724100000_leadership.sql:26-31). Policy não alcança auth.users.
  select u.is_anonymous into v_eh_anonimo from auth.users u where u.id = v_uid;
  if v_eh_anonimo is distinct from false then
    raise exception 'usuário precisa ter Conta para convidar para uma Ação';
  end if;

  if not exists (
    select 1 from public.participacoes_grupo p
    where p.grupo_id = p_grupo_id and p.usuario_id = v_uid
  ) then
    raise exception 'só participante do Grupo convida por ele';
  end if;

  select a.cancelada_em, a.data_hora, a.restrita_ao_grupo, a.grupo_id
    into v_cancelada, v_data_hora, v_restrita, v_grupo_da_acao
  from public.acoes a where a.id = p_acao_id;

  if not found then
    raise exception 'Ação não encontrada';
  end if;
  if v_cancelada is not null then
    raise exception 'Ação cancelada não aceita convite';
  end if;
  -- Sobrecarga por timestamptz, não por id: a versão por uuid é
  -- `security invoker` e lê `acoes`, e a linha em mão já tem a data.
  if public.acao_encerrada(v_data_hora) then
    raise exception 'Ação encerrada não aceita convite';
  end if;
  if v_restrita and v_grupo_da_acao is distinct from p_grupo_id then
    raise exception 'Ação restrita ao Grupo só aceita convite pelo Grupo dela';
  end if;

  return query
  with pedidos as (
    select distinct u as uid from unnest(p_convidados) u
  ),
  elegiveis as (
    select pe.uid
    from pedidos pe
    join public.participacoes_grupo pg
      on pg.grupo_id = p_grupo_id and pg.usuario_id = pe.uid
  ),
  inseridos as (
    insert into public.convites_acao (acao_id, convidado_id, grupo_id, convidante_id)
    select p_acao_id, e.uid, p_grupo_id, v_uid from elegiveis e
    on conflict (acao_id, convidado_id, grupo_id) do nothing
    returning convites_acao.convidado_id as uid
  )
  select pe.uid,
         case
           when not exists (select 1 from elegiveis e where e.uid = pe.uid)
             then 'nao_participa'
           when exists (select 1 from inseridos i where i.uid = pe.uid)
             then 'criado'
           else 'ja_convidado'
         end
  from pedidos pe;
end;
$$;

comment on function public.convidar_para_acao(uuid, uuid, uuid[]) is
  'Cria convites em lote e devolve uma linha por pessoa pedida, classificada em '
  'criado/ja_convidado/nao_participa. É o ÚNICO caminho de escrita em '
  'convites_acao — não existe grant de insert. Change convite-para-acao.';

-- ---------------------------------------------------------------------------
-- 5. Execução
-- ---------------------------------------------------------------------------
-- Só `authenticated`. `anon` não convida e não lista contatos.
revoke all on function public.contatos_para_convite(uuid) from public;
revoke all on function public.convidar_para_acao(uuid, uuid, uuid[]) from public;
grant execute on function public.contatos_para_convite(uuid) to authenticated;
grant execute on function public.convidar_para_acao(uuid, uuid, uuid[]) to authenticated;
