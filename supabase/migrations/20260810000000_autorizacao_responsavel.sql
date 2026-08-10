-- Feature 015 — autorização do responsável para cadastro de Criança.
--
-- Art. 14 da LGPD: dado de criança exige consentimento específico e destacado de um dos
-- pais ou do responsável legal. Criança é quem tem menos de 13 (0 a 12); adolescente
-- (13 a 17) não exige.
--
-- O limiar foi decidido pelo dono do app em 2026-08-09 e vive em UM lugar:
-- public.limiar_crianca(). O espelho em Dart é childAgeThreshold, e um teste de
-- integração compara os dois.
--
-- A regra vale NO BANCO, não na tela: sem isto, a tela é teatro e um insert direto
-- cadastra criança sem autorização nenhuma.

-- =====================================================================
-- 1. O limiar de criança — o único número que a decisão de produto move
-- =====================================================================
-- A comparação é SEMPRE `idade < limiar_crianca()`. O lado do limiar está absorvido no
-- número: "até 12 anos inclusive" se escreve como 13; "menor que 12" se escreve como 12.
--
-- Trocar o limiar é UMA LINHA — `create or replace` desta função. Verificado no banco:
-- com a constraint já criada, replace de 12 para 6 mudou o comportamento na hora, sem
-- recriar constraint nenhuma.
--
-- Função dentro de CHECK é padrão da casa: `perfis.nome` já é check (nome_valido(nome)),
-- e nome_valido é STABLE e lê outra tabela. Esta é IMMUTABLE, sem leitura e sem parâmetro.

create function public.limiar_crianca()
returns integer
language sql
immutable
as $$
  -- RESOLVIDO em 2026-08-09 pelo dono do app: criança é quem tem MENOS DE 13.
  -- Ou seja, 0 a 12 inclusive — exatamente o recorte do art. 14 da LGPD, que
  -- exige consentimento de um dos pais ou do responsável legal para criança, e
  -- não para adolescente (13 a 17).
  --
  -- A comparação é sempre `idade < limiar_crianca()`, então "até 12 inclusive"
  -- se escreve 13. Trocar o valor é uma linha aqui; `childAgeThreshold` em
  -- profile.dart precisa acompanhar, e um teste de integração compara os dois
  -- para nunca divergirem.
  select 13
$$;

comment on function public.limiar_crianca() is
  'Idade abaixo da qual o cadastro exige autorização de Responsável (feature 015). '
  'A comparação é sempre idade < limiar_crianca(): o lado do limiar está absorvido no '
  'número. Espelhada em Dart por childAgeThreshold (profile.dart).';

grant execute on function public.limiar_crianca() to anon, authenticated;


-- =====================================================================
-- 2. As quatro colunas
-- =====================================================================
-- Ficam em `perfis` e não numa tabela própria porque Responsável não é entidade: a spec
-- o define como "um conjunto de campos no registro do menor", sem cadastro próprio, e o
-- Princípio V manda preferir o mais simples que atende. Mesmo arranjo de
-- consentimento_lgpd_aceito_em e consentimento_lgpd_igreja_aceito_em.

alter table public.perfis
  add column responsavel_nome text,
  add column responsavel_contato text,
  add column autorizacao_responsavel_em timestamptz,
  add column autorizacao_responsavel_versao text;

comment on column public.perfis.responsavel_nome is
  'Nome de quem autorizou o cadastro de uma criança. DADO PESSOAL DE TERCEIRO — a pessoa '
  'não é usuária do app. Autodeclarado, NÃO verificado (FR-006). Legível só pela própria '
  'linha (perfis_select_own) e por service_role; nunca sai em perfil_publico(). '
  'Feature 015.';

comment on column public.perfis.responsavel_contato is
  'E-mail ou telefone do Responsável. É REGISTRO, NÃO CANAL: o app nunca escreve para '
  'este endereço. Autodeclarado, não verificado. Mesma regra de leitura de '
  'responsavel_nome. Feature 015.';

comment on column public.perfis.autorizacao_responsavel_em is
  'Quando a autorização foi dada (FR-007). Junto com a versão, é o que dá valor '
  'probatório ao consentimento — o ônus da prova é do controlador (LGPD art. 8º §2º).';

comment on column public.perfis.autorizacao_responsavel_versao is
  'Versão do texto legal vigente no aceite (FR-007). Hoje vem de LegalMetadata.version. '
  'A feature 017 unifica a forma de gravar versão para os três consentimentos.';


-- =====================================================================
-- 3. As duas invariantes — a regra vale NO BANCO (FR-009)
-- =====================================================================
-- NOT VALID nas duas. Cuidado com o que NOT VALID significa: é "não confira as linhas
-- que já estão aqui", NÃO é "só vale para linhas novas". Insert e update passam a ser
-- verificados normalmente, para todo mundo, inclusive service_role e postgres.
--
-- O `idade is null` na frente é a linha anonimizada da feature 009 passando. Poderia ser
-- omitido (NULL >= limiar dá NULL, e CHECK que resulta em NULL passa — é assim que
-- apelido_obrigatorio_menor já tolera a anonimização, ver
-- 20260806140000_exclusao_de_conta.sql:41-43), mas escrito explicitamente ele documenta a
-- intenção em vez de depender de quem lê saber lógica de três valores.

-- 3a. Abaixo do limiar: nome, contato, data e versão são obrigatórios.
--     FR-001, FR-004, FR-007, FR-009, SC-001.
alter table public.perfis
  add constraint autorizacao_responsavel_crianca
  check (
    idade is null
    or idade >= public.limiar_crianca()
    or (
      responsavel_nome is not null
      and responsavel_contato is not null
      and autorizacao_responsavel_em is not null
      and autorizacao_responsavel_versao is not null
    )
  )
  not valid;

-- 3b. Acima do limiar: os quatro campos ficam vazios. FR-008, SC-002.
--     NÃO é redundante com 3a. Sem esta, nada impede um adulto de gravar nome de
--     responsável — por bug de tela, por insert direto, ou por um formulário que não
--     limpou o estado quando a idade subiu acima do limiar. O mesmo cuidado já existe no
--     consentimento de Igreja (profile_signup_page.dart:178-181, trocar a Igreja zera o
--     consentimento anterior); esta constraint é a rede embaixo dele.
--
--     ATENÇÃO — é ESTA constraint que amarra a decisão sobre adolescentes. Ela impede o
--     cenário que REVISAO-JURIDICA.md:102-105 sugere para 12-17 anos (exigir contato do
--     responsável quando "Igreja de origem" for preenchida). A spec decidiu, em
--     Assumptions, que adolescente segue apenas RECOMENDADO — então isto está alinhado
--     com a spec de hoje. Se essa decisão mudar, é aqui que se mexe.
alter table public.perfis
  add constraint autorizacao_responsavel_so_para_crianca
  check (
    idade is null
    or idade < public.limiar_crianca()
    or (
      responsavel_nome is null
      and responsavel_contato is null
      and autorizacao_responsavel_em is null
      and autorizacao_responsavel_versao is null
    )
  )
  not valid;


-- =====================================================================
-- 4. O registro não se altera depois de gravado (US2)
-- =====================================================================
-- A constraint garante que a autorização EXISTA. Não garante que ela continue sendo o que
-- foi. Medido no banco, com o JWT da própria criança:
--     update public.perfis set responsavel_nome = 'Fulano Inventado' where id = <uid>;
--     --> UPDATE 1, e o valor virou 'Fulano Inventado'.
-- Porque perfis_update_own é `using (auth.uid() = id)` SEM with check (confirmado em
-- \dp public.perfis): ela confere QUEM mexe na linha, nunca O QUÊ muda.
--
-- Endurecer a política não resolve: WITH CHECK só enxerga a linha NOVA, não existe OLD em
-- política RLS. Gatilho é o único lugar onde OLD existe.
--
-- Mesmo bug e mesmo remédio do BUG 3 da auditoria de 2026-07-24
-- (20260724130000_fix_rls_security_bugs.sql:53-85), inclusive o escape por GUC.

create function public.perfis_protege_autorizacao_responsavel()
returns trigger
language plpgsql
as $$
begin
  if current_setting('app.bypass_autorizacao_responsavel', true) = 'true' then
    return new;
  end if;

  if new.responsavel_nome is distinct from old.responsavel_nome
     or new.responsavel_contato is distinct from old.responsavel_contato
     or new.autorizacao_responsavel_em is distinct from old.autorizacao_responsavel_em
     or new.autorizacao_responsavel_versao is distinct from old.autorizacao_responsavel_versao then
    raise exception 'a autorização do responsável não pode ser alterada depois de registrada';
  end if;

  return new;
end;
$$;

create trigger perfis_protege_autorizacao_responsavel_trigger
  before update on public.perfis
  for each row
  execute function public.perfis_protege_autorizacao_responsavel();

-- Usos legítimos do bypass, e só eles:
--   1. excluir_minha_conta(), na seção 5 abaixo.
--   2. Correção pedida pelo próprio Responsável (US3, LGPD art. 18 III), feita à mão pelo
--      responsável pelo app. Bypass explícito deixa rastro; ausência de proteção não.




-- =====================================================================
-- 5. A anonimização aprende as colunas novas (Princípio II)
-- =====================================================================
-- Função reescrita INTEIRA a partir do texto atual de
-- 20260806140000_exclusao_de_conta.sql — não é patch. Ela anonimiza por lista
-- EXPLÍCITA de colunas, escrita antes destas existirem, e é o único ponto onde esta
-- feature poderia violar o Princípio II sem nada gritar.

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
  -- O bypass existe porque o gatilho da seção 4 bloquearia este update mesmo
  -- rodando como dono: gatilho não é RLS, e SECURITY DEFINER não pula gatilho.
  -- Mesmo formato que fechar_rodada_se_devido usa com app.bypass_acoes_protecao.
  perform set_config('app.bypass_autorizacao_responsavel', 'true', true);
  update public.perfis set
    nome = 'Membro removido',
    apelido = null,
    telefone = null,
    igreja_id = null,
    genero = null,
    idade = null,
    -- Feature 015. Estas duas são dado pessoal de TERCEIRO: a pessoa não tem
    -- conta, não tem tela e não tem como pedir exclusão. Se ficassem aqui, o
    -- app teria excluído a conta da criança e guardado o nome e o telefone da
    -- mãe — exatamente a promessa que a tela de exclusão faz e não cumpriria.
    responsavel_nome = null,
    responsavel_contato = null,
    autorizacao_responsavel_em = null,
    autorizacao_responsavel_versao = null,
    anonimizado_em = now()
  where id = v_uid;
  perform set_config('app.bypass_autorizacao_responsavel', 'false', true);

  -- Encerra o login. O JWT já emitido continua válido até expirar, então o
  -- cliente precisa chamar signOut() logo após esta função retornar.
  delete from auth.users where id = v_uid;
end;
$$;

-- =====================================================================
-- 5b. A versão nova do texto legal entra no catálogo
-- =====================================================================
-- Regra da feature 017: publicar texto novo muda LegalMetadata.version E semeia
-- a linha correspondente, no mesmo commit. A seção de crianças da Política
-- passou a descrever a autorização do responsável, que antes não existia, então
-- o texto mudou de verdade — e desta vez a mudança ADICIONA um tratamento (nome
-- e contato de um terceiro), não só reduz exposição.
--
-- test/integration/versao_texto_legal_registro_test.dart falha se as duas
-- divergirem.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.3', timestamptz '2026-08-10 00:00:00-03');

-- =====================================================================
-- 6. O que NÃO está aqui, de propósito
-- =====================================================================
-- Nenhuma política nova, nenhuma RPC nova, nenhum grant novo sobre perfis. O acesso já
-- era fechado, e abrir para depois fechar seria mais superfície pelo mesmo resultado:
-- perfis_select_own restringe a leitura à própria linha, anon não tem select em perfis, e
-- perfil_publico() devolve projeção FIXA (id, nome_exibido, igreja_id) — não há caminho
-- dela até as colunas novas. perfil_publico() fica INALTERADA: é ela que impede o
-- vazamento, e mexer nela é o jeito mais rápido de quebrar SC-004.

-- =====================================================================
-- DEFERRED — o que fica em aberto, e por quê
-- =====================================================================
-- 1. NUNCA rodar `alter table public.perfis validate constraint
--    autorizacao_responsavel_crianca` sem decisão de produto. Um dia alguém vai ver
--    convalidated = f e querer "arrumar". Se houver cadastro antigo de criança, FALHA; se
--    não houver, terá mudado em silêncio a política que a spec deixou em aberto.
--
-- 2. Cadastro antigo de criança sem autorização vira SOMENTE-LEITURA — qualquer update
--    naquela linha é recusado pela constraint 3a. Quando o contrato foi escrito isso era
--    inofensivo, porque não existia tela de editar perfil. **A feature 016 entrou desde
--    então**, e agora isso vira erro na cara da pessoa. Tratado em
--    profile_error_message.dart, que traduz esta constraint para uma frase que diz o que
--    fazer. A exclusão de conta continua funcionando (idade vira null e as duas
--    constraints passam), então o direito do art. 18 VI está a salvo.
