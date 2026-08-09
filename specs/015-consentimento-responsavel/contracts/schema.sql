-- Contrato de banco da feature 015 — Consentimento de responsável para menor de idade.
--
-- Este arquivo é o CONTRATO, não a migration. A migration vai em
-- supabase/migrations/<timestamp>_autorizacao_responsavel.sql.
--
-- POR QUE CHECK CONSTRAINT, E NÃO GATILHO NEM POLÍTICA  (ler antes de "melhorar" isto)
--   A regra é uma invariante de UMA LINHA: olha `idade` e quatro colunas da mesma linha.
--   - Gatilho faria o mesmo com mais código e mensagem de erro que o cliente teria de
--     reconhecer por texto; `profile_signup_page.dart:102-113` já casa erro por NOME de
--     constraint, que é o padrão da casa.
--   - Política RLS não serve: vale por papel, e um insert por service_role, pelo painel do
--     Supabase ou por migration não passa por RLS nenhuma. FR-009 diz "por nenhum caminho".
--   Precedente direto: `apelido_obrigatorio_menor` (20260723191202_perfis_igrejas.sql:38).
--
-- O QUE FOI MEDIDO NO BANCO LOCAL ANTES DE ESCREVER ISTO (ver research.md)
--   1. ADD CONSTRAINT sem NOT VALID, com um cadastro antigo de menor violando:
--        ERROR: check constraint ... of relation "perfis" is violated by some row
--      -> a migration FALHARIA. NOT VALID é obrigatório, não é otimização.
--   2. Com NOT VALID: ALTER TABLE, convalidated = f. Insert novo de menor sem autorização
--      continua sendo recusado -> FR-009 cumprido.
--   3. UPDATE de campo NÃO relacionado (telefone) na linha antiga que viola: RECUSADO.
--      Cadastro antigo de menor vira somente-leitura. Consequência real; ver DEFERRED no fim.
--   4. Anonimização da feature 009 (idade = null) na linha antiga: UPDATE 1, passou.
--      A exclusão de conta continua funcionando para esses cadastros.


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
  -- PENDENTE(/speckit-clarify): valor provisório. A Política fala em "criança (até 12
  -- anos)" — inclusivo, seria 13 aqui — e REVISAO-JURIDICA.md:93 propõe "menor que 12" —
  -- exclusivo, seria 12 aqui. São regras DIFERENTES para quem tem 12 anos, e a spec
  -- (Assumptions) deixou a escolha para o clarify de propósito. Trocar só esta linha
  -- basta; a constante Dart `childAgeThreshold` precisa acompanhar, e um teste de
  -- integração compara as duas para elas nunca divergirem.
  select 12
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
-- 5. A anonimização precisa aprender as colunas novas (Princípio II)
-- =====================================================================
-- É o único ponto em que esta feature pode violar o Princípio II sem que nada grite.
-- excluir_minha_conta() anonimiza uma lista EXPLÍCITA de colunas
-- (20260806140000_exclusao_de_conta.sql:142-150), escrita antes destas existirem. Sem
-- isto: a conta da criança é excluída, o Perfil dela é anonimizado, e o nome e o telefone
-- da mãe continuam no banco — dado de terceiro que não tem conta, não tem tela e não tem
-- como pedir exclusão.
--
-- O gatilho da seção 4 bloquearia este update mesmo rodando como dono: gatilho não é RLS,
-- e SECURITY DEFINER não pula gatilho. Daí o bypass, no mesmo formato que
-- fechar_rodada_se_devido usa com app.bypass_acoes_protecao.
--
-- As constraints da seção 3 não atrapalham: o mesmo update zera `idade`, as duas
-- resultam em NULL e passam (medido: UPDATE 1).
--
-- IMPORTANTE: a migration deve reescrever a função INTEIRA com CREATE OR REPLACE, a
-- partir do texto atual em 20260806140000_exclusao_de_conta.sql — não é um patch. O
-- trecho abaixo é só a parte que muda.

--   perform set_config('app.bypass_autorizacao_responsavel', 'true', true);
--   update public.perfis set
--     nome = 'Membro removido',
--     apelido = null,
--     telefone = null,
--     igreja_id = null,
--     genero = null,
--     idade = null,
--     responsavel_nome = null,              -- feature 015: dado de TERCEIRO
--     responsavel_contato = null,           -- feature 015: dado de TERCEIRO
--     autorizacao_responsavel_em = null,
--     autorizacao_responsavel_versao = null,
--     anonimizado_em = now()
--   where id = v_uid;
--   perform set_config('app.bypass_autorizacao_responsavel', 'false', true);


-- =====================================================================
-- 6. O que NÃO está aqui, de propósito
-- =====================================================================
-- Nenhuma política nova, nenhuma RPC nova, nenhum grant novo sobre perfis.
--
-- Não é esquecimento: o acesso já era fechado, e abrir para depois fechar seria mais
-- superfície pelo mesmo resultado. Medido:
--   - outro authenticated fazendo select na linha da criança: 0 linhas (perfis_select_own)
--   - \dp public.perfis, privilégios de anon: `anon=Dxtm/postgres` — SEM `r`. anon não tem
--     select em perfis, nem com RLS desligada.
--   - perfil_publico(uuid) devolve `id, nome_exibido, igreja_id` — projeção FIXA, coluna
--     nomeada uma a uma. Não existe caminho dela até as colunas novas.
-- perfil_publico() fica INALTERADA. É ela que impede o vazamento; mexer nela é o jeito
-- mais rápido de quebrar SC-004.


-- =====================================================================
-- DEFERRED — o que fica em aberto, e por quê
-- =====================================================================
-- 1. NUNCA rodar `alter table public.perfis validate constraint
--    autorizacao_responsavel_crianca` sem decisão de produto. Um dia alguém vai ver
--    convalidated = f e querer "arrumar". Se houver cadastro antigo de menor, FALHA; se
--    não houver, terá mudado em silêncio a política que a spec deixou em aberto
--    (Assumptions: "a feature NÃO os corrige retroativamente nem os bloqueia").
--
-- 2. Cadastro antigo de menor sem autorização vira SOMENTE-LEITURA. Medido: update de
--    telefone naquela linha é recusado. Hoje é inofensivo — não existe tela de editar
--    perfil (MAPA-DE-DADOS.md:117-122). Na FEATURE 016 vira erro de banco na cara do
--    usuário, e é lá que precisa ser tratado. A exclusão de conta continua funcionando
--    (idade vira null e as constraints passam), então o direito do art. 18 VI está a
--    salvo.
--
-- 3. O valor de limiar_crianca() é PENDENTE de /speckit-clarify. Ver seção 1.
