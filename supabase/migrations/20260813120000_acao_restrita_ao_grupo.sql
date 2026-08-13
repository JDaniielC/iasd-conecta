-- Change acao-direcionada-a-grupo — Ação de Grupo pode ser restrita ao Grupo.
--
-- POR QUE ISTO EXISTE
-- Toda Ação deste app era pública para o mundo: `acoes_select_public` era
-- `to anon, authenticated using (true)` (20260723230639_acoes.sql:121-124).
-- Reunião de liderança, visita de Dupla Missionária com `genero_visitado`
-- marcado, encontro interno de Ministério — tudo aparecia igual para quem
-- abrisse /acoes sem login. `acoes.grupo_id` existe desde a feature 004, mas
-- não filtrava nada.
--
-- O PADRÃO CONTINUA PÚBLICO, DE PROPÓSITO
-- A coluna nasce `default false`. Nenhuma Ação existente muda de visibilidade
-- no dia desta migration. Isto NÃO é BREAKING: esta migration só permite
-- fechar, nunca fecha sozinha.
--
-- O RISCO AQUI É O INVERSO DO USUAL
-- Uma policy escrita errado esconde Ação PÚBLICA de todo mundo. Os dois
-- sentidos têm teste de integração contra o banco de verdade
-- (test/integration/acoes_select_publico_test.dart continua provando que o
-- público segue público). Um lado sozinho não prova nada.

-- ---------------------------------------------------------------------------
-- 1. A coluna, amarrada ao Grupo pelo banco
-- ---------------------------------------------------------------------------
-- Booleano, não enum de níveis. Existem dois estados reais — público e restrito
-- ao Grupo. Um enum de dois valores custa o mesmo hoje e convida a inventar um
-- terceiro nível antes de alguém pedir; quando um terceiro aparecer de verdade,
-- booleano -> enum é migration mecânica com o requisito na mão.
alter table public.acoes
  add column restrita_ao_grupo boolean not null default false;

-- É ISTO que faz "Ação avulsa não pode ser restrita" ser verdade. A tela
-- esconder o controle é conveniência; sem `grupo_id` não há a quem restringir,
-- e uma Ação restrita sem Grupo ficaria invisível para todo mundo, para sempre.
alter table public.acoes
  add constraint acoes_restrita_exige_grupo
  check (restrita_ao_grupo = false or grupo_id is not null);

comment on column public.acoes.restrita_ao_grupo is
  'Ação visível só para quem participa do Grupo dela. Exige grupo_id '
  '(constraint acoes_restrita_exige_grupo). O default false é deliberado: Ação '
  'é pública por padrão, e nenhuma Ação existente mudou de visibilidade quando '
  'esta coluna entrou. Change acao-direcionada-a-grupo.';

-- ---------------------------------------------------------------------------
-- 2. O índice que sustenta a policy nova
-- ---------------------------------------------------------------------------
-- A PK de participacoes_grupo é (grupo_id, usuario_id)
-- (20260723220703_grupos.sql:21-26) e nenhum índice servia busca por
-- usuario_id — verificado com \d antes desta migration. A policy abaixo
-- percorre exatamente a direção contrária à PK, uma vez por linha de `acoes`
-- avaliada, na tela mais aberta do app. Sem este índice, cada leitura de
-- /acoes vira varredura de participacoes_grupo.
create index participacoes_grupo_por_usuario
  on public.participacoes_grupo (usuario_id, grupo_id);

-- ---------------------------------------------------------------------------
-- 3. O limiar de encerramento, agora num lugar só
-- ---------------------------------------------------------------------------
-- Sobrecarga que recebe o instante em vez do id. Existe por um motivo de
-- segurança, não de estilo: `acao_encerrada(uuid)` é `security invoker` e lê
-- `public.acoes`, então passa pela RLS de quem chamou. A partir desta migration
-- existe linha de `acoes` invisível para quem escreve nela (ver seção 5), e
-- para essa pessoa a versão por id devolveria NULL — `not null` é NULL, o `if`
-- do gatilho não dispararia, e a trava de "encerrada não muda" falharia calada
-- exatamente na Ação restrita.
--
-- O gatilho da seção 4 já tem a linha na mão (OLD). Passar `data_hora` direto
-- não lê nada, não passa por RLS, e mantém as 4 horas definidas UMA vez.
create or replace function public.acao_encerrada(p_data_hora timestamptz)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select now() > p_data_hora + interval '4 hours';
$$;

comment on function public.acao_encerrada(timestamptz) is
  'Encerrada = passou de data_hora + 4h. Definição única do limiar; a versão '
  'por uuid delega para esta. Gêmea de defaultActionDuration no Dart '
  '(lib/features/action/domain/action.dart) — mudar as duas juntas.';

grant execute on function public.acao_encerrada(timestamptz) to anon, authenticated;

-- A versão por id passa a delegar. Comportamento idêntico ao de
-- 20260809174740_acao_encerrada_bloqueia_presenca.sql:41-46 — continua
-- `security invoker`, continua devolvendo NULL para linha que o chamador não
-- enxerga. As duas policies de confirmacoes_acao que dependem dela não mudam.
create or replace function public.acao_encerrada(p_acao_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select public.acao_encerrada(a.data_hora)
  from public.acoes a
  where a.id = p_acao_id;
$$;

-- ---------------------------------------------------------------------------
-- 4. Encerrada não muda de visibilidade
-- ---------------------------------------------------------------------------
-- Regra irmã da de 20260809174740: depois que a Ação encerra, a fila congela e
-- a presença trava. Deixar a visibilidade mudar depois disso permitiria expor
-- retroativamente quem esteve num encontro interno — ou esconder de quem
-- participou o registro do que participou.
create or replace function public.acoes_restricao_apos_encerrada()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.restrita_ao_grupo is distinct from old.restrita_ao_grupo
     and public.acao_encerrada(old.data_hora) then
    raise exception 'não é permitido mudar a restrição de uma Ação encerrada';
  end if;
  return new;
end;
$$;

create trigger acoes_restricao_apos_encerrada_trigger
  before update on public.acoes
  for each row
  execute function public.acoes_restricao_apos_encerrada();

-- ---------------------------------------------------------------------------
-- 5. A regra de leitura
-- ---------------------------------------------------------------------------
-- O nome sai junto com a regra, pelo motivo que a feature 021 registrou
-- (20260809200000_votos_visibilidade.sql:21-27): uma `acoes_select_public` que
-- não é mais pública seria pior do que nome nenhum, e trocar o nome faz
-- qualquer referência antiga falhar visivelmente em vez de continuar apontando
-- para algo com a semântica trocada por baixo.
drop policy if exists acoes_select_public on public.acoes;

-- Em sessão `anon`, auth.uid() é nulo, o `exists` é falso, e a Ação restrita
-- some — sem `if` especial e sem erro, só linha a menos.
create policy acoes_select_visivel
  on public.acoes for select
  to anon, authenticated
  using (
    restrita_ao_grupo = false
    or exists (
      select 1 from public.participacoes_grupo p
      where p.grupo_id = acoes.grupo_id
        and p.usuario_id = auth.uid()
    )
  );

-- Esconder a Ação e deixar a lista de presença aberta seria vazamento por porta
-- lateral: `confirmacoes_acao` devolve o par nominal (acao_id, usuario_id), que
-- revela a existência da Ação e quem estará lá.
--
-- A condição aqui é SÓ a existência da Ação. A subconsulta roda sob a RLS de
-- `acoes` para a mesma sessão, então a regra de visibilidade existe num lugar
-- só e a lista de presença acompanha sozinha se aquela condição mudar.
-- NÃO duplicar aqui o `exists` de participação: seria a segunda cópia, e é a
-- segunda cópia que fica para trás.
drop policy if exists confirmacoes_acao_select_public on public.confirmacoes_acao;

create policy confirmacoes_acao_select_conforme_acao
  on public.confirmacoes_acao for select
  to anon, authenticated
  using (
    exists (
      select 1 from public.acoes a
      where a.id = confirmacoes_acao.acao_id
    )
  );

-- ---------------------------------------------------------------------------
-- 6. Os grants de anon FICAM COMO ESTÃO
-- ---------------------------------------------------------------------------
-- `grant select on public.acoes to anon` e o de confirmacoes_acao continuam.
-- Revogá-los faria a API responder erro de permissão em vez de lista vazia, e a
-- diferença entre "não existe" e "não posso ver" viraria canal lateral: dá para
-- contar o que está escondido só olhando qual resposta chega. Ação escondida é
-- LINHA AUSENTE, nunca erro. Mesmo raciocínio de
-- 20260809200000_votos_visibilidade.sql:36-41.

-- ---------------------------------------------------------------------------
-- 7. AVISO — quem escreve a restrição não é quem a enxerga
-- ---------------------------------------------------------------------------
-- A escrita em `acoes` é de `acoes_update_criador_dono_grupo_ou_admin`
-- (20260724092132_district_admin.sql): criador, Dono do Grupo OU Administrador
-- do distrito. Esta migration NÃO divide essa policy, e `restrita_ao_grupo` NÃO
-- entra na lista protegida de `acoes_protege_campos_internos` — decisão da
-- change: a restrição é configuração da Ação como qualquer outra, e partir a
-- permissão em duas cria a segunda regra que diverge da primeira.
--
-- CONSEQUÊNCIA MEDIDA, não suposta.
--
-- O lado de FECHAR o próprio Postgres barra, e de graça: a policy de `select`
-- vale também como `with check` implícito do `update`, então ninguém empurra
-- uma linha para fora da própria visibilidade.
--
--   update ... set restrita_ao_grupo = true   -- por quem não participa
--   -> ERROR: new row violates row-level security policy for table "acoes"
--
-- Restringir é possível só para quem participa do Grupo, e quem participa
-- continua vendo. Nenhuma linha de código foi precisa para isso.
--
-- O lado de ABRIR é o que fica em aberto, porque desmarcar deixa a linha MAIS
-- visível e o `with check` implícito não barra:
--
--   update ... set restrita_ao_grupo = false where id = <invisível>  -> 0 linhas
--   update ... set restrita_ao_grupo = false   -- sem filtro         -> alcança
--
-- A policy de update do Administrador não recorta por linha (vale para toda
-- Ação). Logo um Administrador do distrito reabre ao público TODA Ação restrita
-- do distrito com uma escrita sem filtro, inclusive as que nunca pôde ler.
-- Pelo id, não alcança. Com o Dono do Grupo o caminho existe e é inofensivo:
-- a policy dele já recorta pelos Grupos dele.
--
-- Dívida aceita e registrada em SECURITY-AUDIT.md, com o recuo pronto
-- (acrescentar a coluna a acoes_protege_campos_internos com condição de
-- criador). test/integration/acao_restrita_admin_assimetria_test.dart existe
-- para isto ser conhecido, não descoberto em produção — se ele ficou vermelho,
-- alguém mudou este desenho sem ler esta seção.
