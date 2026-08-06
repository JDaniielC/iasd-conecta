-- Feature 009: exclusão de conta com anonimização do Perfil e herança de posse.
-- Ver specs/009-exclusao-de-conta/contracts/schema.sql (fonte de verdade),
-- spec.md (o quê e por quê) e research.md (alternativas descartadas).
--
-- O problema: apagar o auth.users de quem é Dono de Grupo, criador de Ação,
-- abriu Rodada, é Administrador do distrito ou tem declaração de Líder/Diretor
-- falha por violação de chave estrangeira — 8 colunas referenciam perfis(id)
-- com ON DELETE NO ACTION. Na prática, o direito de exclusão do art. 18, VI da
-- LGPD não é cumprível hoje para esses usuários, e a Política de Privacidade
-- admite isso.
--
-- A saída não é cascatear (destruiria Grupo de terceiros) nem bloquear até a
-- pessoa transferir tudo na mão (condicionar um direito do titular a uma
-- tarefa dele é obstáculo ao art. 18). É anonimizar o Perfil — o art. 16
-- dispensa a exclusão quando o dado está anonimizado — e transferir para o
-- Administrador do distrito mais antigo apenas o que exige alguém capaz de
-- agir: posse de Grupo e Rodada de votação ainda aberta.

-- ---------------------------------------------------------------------------
-- 1. O Perfil precisa sobreviver ao fim do login
-- ---------------------------------------------------------------------------
-- perfis.id referencia auth.users(id) com ON DELETE CASCADE. Enquanto essa FK
-- existir, apagar o login apaga a linha de perfis — e a linha anonimizada é
-- justamente a âncora do histórico de terceiros. Nenhuma variação de ON DELETE
-- resolve: SET NULL é impossível (a coluna é PK) e NO ACTION bloquearia a
-- exclusão do próprio login.
--
-- Consequência aceita: perfis deixa de ter garantia referencial contra
-- auth.users, e passa a existir legitimamente linha de perfis sem auth.users
-- correspondente — que é exatamente o estado "anonimizado". A única escrita em
-- perfis.id continua sendo o cadastro, que grava auth.uid().

alter table public.perfis drop constraint perfis_id_fkey;

-- ---------------------------------------------------------------------------
-- 2. Anonimização de verdade exige gênero e idade nulos
-- ---------------------------------------------------------------------------
-- Num distrito pequeno, gênero + idade + quais Grupos a pessoa participava
-- reidentifica. Como o art. 16 só dispensa a exclusão quando o dado está
-- anonimizado, deixar esses dois campos tornaria frágil a base para conservar
-- a linha. Os check constraints existentes toleram nulo: no Postgres um CHECK
-- que resulta em NULL passa, então apelido_obrigatorio_menor
-- (idade >= 18 or apelido is not null) não bloqueia idade nula.

alter table public.perfis alter column genero drop not null;
alter table public.perfis alter column idade drop not null;
alter table public.perfis add column anonimizado_em timestamptz;

-- ---------------------------------------------------------------------------
-- 3. A operação inteira, numa transação só
-- ---------------------------------------------------------------------------
-- SECURITY DEFINER com search_path fixo (precedente:
-- 20260806090000_nome_valido_security_definer.sql). Roda como o dono, que tem
-- BYPASSRLS — necessário porque `votos` não tem policy de DELETE e `perfis` só
-- tem policy de select para o próprio dono.
--
-- A ordem não é livre: `confirmacoes_acao_promover_fila` é AFTER DELETE e
-- promove a fila de espera sozinho, então não há uma linha de lógica de fila
-- aqui de propósito.

create or replace function public.excluir_minha_conta()
returns void
language plpgsql
security definer
set search_path = public, pg_temp
as $$
declare
  v_uid uuid := auth.uid();
  v_herdeiro uuid;
  v_tem_heranca boolean;
begin
  if v_uid is null then
    raise exception 'é preciso estar autenticado para excluir a própria conta';
  end if;

  if not exists (select 1 from public.perfis where id = v_uid) then
    raise exception 'não há Perfil para excluir';
  end if;

  -- Herdeiro: Administrador do distrito mais antigo entre os que ficam. O
  -- desempate por usuario_id existe só pra a eleição ser determinística quando
  -- dois Administradores nascem no mesmo instante (bootstrap).
  select usuario_id into v_herdeiro
  from public.administradores_distrito
  where usuario_id <> v_uid
  order by created_at, usuario_id
  limit 1;

  v_tem_heranca :=
    exists (select 1 from public.grupos where dono_id = v_uid)
    or exists (
      select 1 from public.rodadas_votacao
      where aberta_por = v_uid and fechada_em is null
    );

  if v_herdeiro is null then
    -- Recusa mesmo sem nada a herdar: sem Administrador nenhum, o distrito
    -- fica sem quem cadastre Igreja e sem quem promova outro Administrador, e
    -- administradores_distrito_checar_regras exige um admin pré-existente pra
    -- promover — só a migration de bootstrap sairia desse buraco.
    if exists (select 1 from public.administradores_distrito where usuario_id = v_uid) then
      raise exception 'você é o único Administrador do distrito; promova outro Administrador antes de excluir sua conta';
    end if;
    if v_tem_heranca then
      raise exception 'não há Administrador do distrito para receber seus Grupos e Rodadas de votação abertas';
    end if;
  end if;

  -- Transferência: participação primeiro, senão grupos_dono_deve_participar
  -- (BEFORE UPDATE) recusa o update. grupos_dono_vira_participante só cobre
  -- INSERT, então não adianta esperar que ela apareça sozinha.
  if v_tem_heranca then
    insert into public.participacoes_grupo (grupo_id, usuario_id)
    select g.id, v_herdeiro
    from public.grupos g
    where g.dono_id = v_uid
    on conflict do nothing;

    update public.grupos set dono_id = v_herdeiro where dono_id = v_uid;

    update public.rodadas_votacao set aberta_por = v_herdeiro
    where aberta_por = v_uid and fechada_em is null;
  end if;

  -- Vínculos vivos: somem. Vínculos históricos (acoes.criador_id, rodadas
  -- fechadas, liderancas.confirmado_por, confirmações de Ações passadas)
  -- continuam apontando pro Perfil anonimizado, de propósito.
  delete from public.votos v
  using public.rodadas_votacao r
  where v.usuario_id = v_uid and v.rodada_id = r.id and r.fechada_em is null;

  delete from public.confirmacoes_acao c
  using public.acoes a
  where c.usuario_id = v_uid and c.acao_id = a.id and a.data_hora > now();

  delete from public.participacoes_grupo where usuario_id = v_uid;
  delete from public.liderancas where usuario_id = v_uid;
  delete from public.administradores_distrito where usuario_id = v_uid;

  -- 'Membro removido' passa em nome_valido(); apelido nulo faz
  -- perfil_publico() (coalesce(apelido, nome)) exibir exatamente isso.
  update public.perfis set
    nome = 'Membro removido',
    apelido = null,
    telefone = null,
    igreja_id = null,
    genero = null,
    idade = null,
    anonimizado_em = now()
  where id = v_uid;

  -- Encerra o login. O JWT já emitido continua válido até expirar, então o
  -- cliente precisa chamar signOut() logo após esta função retornar.
  delete from auth.users where id = v_uid;
end;
$$;

revoke all on function public.excluir_minha_conta() from public;
grant execute on function public.excluir_minha_conta() to authenticated;
