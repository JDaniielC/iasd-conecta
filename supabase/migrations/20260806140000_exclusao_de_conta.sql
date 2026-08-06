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
begin
  if v_uid is null then
    raise exception 'é preciso estar autenticado para excluir a própria conta';
  end if;

  if not exists (select 1 from public.perfis where id = v_uid) then
    raise exception 'não há Perfil para excluir';
  end if;

  -- GUARDA TEMPORÁRIA: a herança de posse chega na próxima fatia da feature
  -- (US2). Sem ela, quem é Dono de Grupo sairia deixando o Grupo com um dono
  -- anonimizado, que ninguém consegue operar.
  if exists (select 1 from public.grupos where dono_id = v_uid)
     or exists (
       select 1 from public.rodadas_votacao
       where aberta_por = v_uid and fechada_em is null
     ) then
    raise exception 'ainda não é possível excluir a conta de quem é Dono de Grupo ou tem Rodada de votação aberta';
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
