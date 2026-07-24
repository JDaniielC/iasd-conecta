-- Contrato de schema: Dupla Missionária (007)
-- Fonte de verdade que a migration em supabase/migrations/ deve seguir.
-- Depende do schema das features 001 (perfis) e 003 (acoes,
-- confirmacoes_acao, confirmacoes_acao_decidir_status, promover_fila_acao)
-- já aplicado. Não cria tabela nem função nova — estende as duas funções
-- de 003 e adiciona colunas em acoes.

alter table public.acoes
  add column eh_dupla_missionaria boolean not null default false,
  add column genero_visitado text check (genero_visitado in ('masculino', 'feminino'));

-- FR-001/FR-002/FR-003: marca o tipo, exige gênero do visitado quando
-- marcada, e fixa limite_vagas em exatamente 2.
alter table public.acoes
  add constraint acoes_dupla_missionaria_check check (
    (eh_dupla_missionaria = false and genero_visitado is null)
    or
    (eh_dupla_missionaria = true and genero_visitado is not null
     and limite_vagas is not null and limite_vagas = 2)
  );

-- Substitui a função da feature 003: mesma decisão de capacidade
-- (confirmado/fila) + validação de composição de gênero quando a Ação é
-- Dupla Missionária (FR-004/FR-005/FR-006/FR-007).
-- SECURITY DEFINER: a validação de composição precisa ler o gênero de
-- QUEM JÁ ESTÁ CONFIRMADO (outro Usuário, não quem está chamando) em
-- perfis.genero — RLS de perfis só permite ler a própria linha
-- (perfis_select_own), então sem SECURITY DEFINER a leitura cruzada
-- retorna NULL silenciosamente e a validação nunca dispara (bug real
-- encontrado na validação empírica desta feature).
create or replace function public.confirmacoes_acao_decidir_status()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_cancelada timestamptz;
  v_limite integer;
  v_confirmados integer;
  v_eh_dupla boolean;
  v_genero_visitado text;
  v_genero_novo text;
  v_genero_restante text;
begin
  perform 1 from public.acoes where id = new.acao_id for update;

  select cancelada_em, limite_vagas, eh_dupla_missionaria, genero_visitado
    into v_cancelada, v_limite, v_eh_dupla, v_genero_visitado
  from public.acoes where id = new.acao_id;

  if v_cancelada is not null then
    raise exception 'ação cancelada, não é possível confirmar presença';
  end if;

  if v_limite is null then
    new.status := 'confirmado';
  else
    select count(*) into v_confirmados
    from public.confirmacoes_acao
    where acao_id = new.acao_id and status = 'confirmado';

    if v_confirmados < v_limite then
      new.status := 'confirmado';
    else
      new.status := 'fila';
    end if;
  end if;

  if v_eh_dupla and new.status = 'confirmado' then
    select genero into v_genero_novo from public.perfis where id = new.usuario_id;

    select p.genero into v_genero_restante
    from public.confirmacoes_acao c
    join public.perfis p on p.id = c.usuario_id
    where c.acao_id = new.acao_id and c.status = 'confirmado'
    limit 1;

    if v_genero_restante is not null
       and v_genero_restante = v_genero_novo
       and v_genero_novo <> v_genero_visitado then
      raise exception 'composição inválida para Dupla Missionária: dois(as) % visitando %',
        case v_genero_novo when 'masculino' then 'homens' else 'mulheres' end,
        case v_genero_visitado when 'masculino' then 'homem' else 'mulher' end;
    end if;
  end if;

  return new;
end;
$$;

-- Substitui a função da feature 003: mesma promoção da fila + pular quem
-- formaria composição inválida quando a Ação é Dupla Missionária (FR-009).
create or replace function public.promover_fila_acao()
returns trigger
language plpgsql
security definer
set search_path = public
as $$
declare
  v_eh_dupla boolean;
  v_genero_visitado text;
  v_genero_restante text;
  v_candidato record;
begin
  if old.status = 'confirmado' then
    select eh_dupla_missionaria, genero_visitado into v_eh_dupla, v_genero_visitado
    from public.acoes where id = old.acao_id;

    if v_eh_dupla then
      select p.genero into v_genero_restante
      from public.confirmacoes_acao c
      join public.perfis p on p.id = c.usuario_id
      where c.acao_id = old.acao_id and c.status = 'confirmado'
      limit 1;

      for v_candidato in
        select c.ctid as row_ctid, p.genero
        from public.confirmacoes_acao c
        join public.perfis p on p.id = c.usuario_id
        where c.acao_id = old.acao_id and c.status = 'fila'
        order by c.created_at
      loop
        if v_genero_restante is null
           or v_candidato.genero <> v_genero_restante
           or v_candidato.genero = v_genero_visitado then
          update public.confirmacoes_acao set status = 'confirmado'
          where ctid = v_candidato.row_ctid;
          return old;
        end if;
      end loop;

      return old;
    end if;

    update public.confirmacoes_acao
    set status = 'confirmado'
    where ctid = (
      select ctid from public.confirmacoes_acao
      where acao_id = old.acao_id and status = 'fila'
      order by created_at
      limit 1
    );
  end if;
  return old;
end;
$$;
