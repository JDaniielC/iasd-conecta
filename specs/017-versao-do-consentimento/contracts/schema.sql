-- Contrato de banco da feature 017 — versão do texto aceito no consentimento.
--
-- Este arquivo é o CONTRATO, não a migration. A migration de verdade vai em
-- supabase/migrations/<timestamp>_versao_do_consentimento.sql com este mesmo
-- conteúdo.
--
-- O QUE ESTE DELTA FAZ
--   1. Cria o catálogo de versões publicadas (`versoes_texto_legal`), escrito
--      só por migration, e a função que diz qual está vigente agora.
--   2. Acrescenta a `perfis` duas colunas de versão, ANULÁVEIS, uma ao lado de
--      cada coluna de data de consentimento que já existe.
--   3. Cria o gatilho que carimba data e versão — e que restaura o valor antigo
--      quando o aceite não mudou.
--   4. Cria a consulta agregada por versão, restrita ao Administrador do distrito.
--
-- A REGRA QUE RESUME O DESENHO (FR-004)
--   O cliente diz SE a pessoa aceitou. O banco diz QUANDO e SOB QUAL TEXTO.
--   Nenhum valor de versão mandado pelo cliente sobrevive ao gatilho.
--
-- DUPLICAÇÃO DECLARADA (ler antes de "simplificar" isto)
--   O número da versão existe em dois lugares: aqui, na linha semeada de
--   `versoes_texto_legal`, e no Dart, em `LegalMetadata.version`
--   (lib/features/legal/legal_metadata.dart:11). Não dá para derivar um do
--   outro: o TEXTO legal está compilado no binário do app, e a versão é
--   metadado dele. Ao publicar texto novo, mudar OS DOIS no mesmo commit — o
--   teste test/integration/versao_texto_legal_registro_test.dart falha se
--   divergirem. Mesmo padrão do limiar de 4 horas da feature 011
--   (specs/011-acoes-titulo-e-encerramento/contracts/schema.sql:27-31).
--
-- O QUE ESTE DELTA DELIBERADAMENTE NÃO FAZ
--   - NÃO preenche nenhuma linha existente (FR-007, SC-002). Aceite anterior a
--     esta migration fica com versão NULL, que quer dizer "desconhecida" e mais
--     nada.
--   - NÃO cria constraint de obrigatoriedade. Ver o aviso ao fim do bloco 2 —
--     é a armadilha desta feature.
--   - NÃO toca perfil_publico(), nem as políticas de perfis, nem
--     excluir_minha_conta(). A versão nunca é exposta a outro Usuário.

-- ---------------------------------------------------------------------------
-- 1. Catálogo de versões publicadas
-- ---------------------------------------------------------------------------
-- Uma linha por versão do texto legal. Escrita só por migration: publicar
-- versão é evento de release, não ação de runtime — por isso não há grant de
-- insert/update/delete para ninguém.

create table public.versoes_texto_legal (
  versao text primary key,
  vigente_desde timestamptz not null,
  created_at timestamptz not null default now()
);

comment on table public.versoes_texto_legal is
  'Catálogo das versões publicadas dos textos legais (Política de Privacidade '
  'e Termos de Uso). Gêmeo de LegalMetadata.version no Dart '
  '(lib/features/legal/legal_metadata.dart) — publicar texto novo muda os dois '
  'no mesmo commit. Feature 017.';

-- A 1.0 NÃO é semeada de propósito: não há data de vigência documentada para
-- ela no repositório, e inventar uma seria a mesma espécie de chute que FR-007
-- proíbe. Ninguém carrega '1.0' — os aceites daquele período ficam NULL.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.1', timestamptz '2026-08-06 00:00:00-03');

grant select on public.versoes_texto_legal to anon, authenticated;

alter table public.versoes_texto_legal enable row level security;

create policy versoes_texto_legal_select_public
  on public.versoes_texto_legal for select
  to anon, authenticated
  using (true);

-- Versão vigente = maior vigente_desde que já venceu.
--
-- LEVANTA EXCEÇÃO quando não há nenhuma, em vez de devolver null. Se
-- devolvesse null, uma linha nova nasceria com versão nula e ficaria
-- indistinguível de um aceite anterior a esta feature — o null perderia o
-- único significado que FR-007 lhe dá. Recusar o cadastro é melhor do que
-- gravar um registro ambíguo.
--
-- `stable` (não `immutable`): depende de now().
-- `security invoker`: a policy de select acima já deixa anon/authenticated
-- lerem o catálogo, então não há motivo para escalar privilégio.
create function public.versao_texto_legal_vigente()
returns text
language plpgsql
stable
security invoker
set search_path = ''
as $$
declare
  v_versao text;
begin
  select v.versao into v_versao
  from public.versoes_texto_legal v
  where v.vigente_desde <= now()
  order by v.vigente_desde desc, v.versao desc
  limit 1;

  if v_versao is null then
    raise exception
      'nenhuma versão de texto legal vigente em public.versoes_texto_legal';
  end if;

  return v_versao;
end;
$$;

comment on function public.versao_texto_legal_vigente() is
  'Versão do texto legal vigente agora. Fonte do carimbo de consentimento '
  '(FR-002, FR-004). Feature 017.';

-- ---------------------------------------------------------------------------
-- 2. As duas colunas de versão, ao lado das datas que já existem
-- ---------------------------------------------------------------------------
-- ANULÁVEIS. A FK garante que só versão publicada pode ser gravada, inclusive
-- por escrita direta na tabela.

alter table public.perfis
  add column consentimento_lgpd_versao text
    references public.versoes_texto_legal(versao),
  add column consentimento_lgpd_igreja_versao text
    references public.versoes_texto_legal(versao);

comment on column public.perfis.consentimento_lgpd_versao is
  'Versão do texto legal vigente quando o consentimento LGPD do cadastro foi '
  'dado. NULL = aceite anterior à feature 017, versão DESCONHECIDA — nunca um '
  'palpite (FR-007). Gravada pelo gatilho perfis_carimbar_consentimento, '
  'nunca pelo cliente (FR-004).';

comment on column public.perfis.consentimento_lgpd_igreja_versao is
  'Idem, para o consentimento destacado de Igreja de origem (LGPD art. 11 I). '
  'Segue consentimento_lgpd_igreja_aceito_em: os dois são gravados juntos e '
  'zerados juntos.';

-- ###########################################################################
-- AVISO — A ARMADILHA DESTA FEATURE. NÃO ACRESCENTAR ISTO:
--
--   alter table public.perfis
--     add constraint consentimento_lgpd_versao_obrigatoria
--     check (consentimento_lgpd_versao is not null) not valid;
--
-- Parece perfeito: `not valid` deixa as linhas antigas em paz (FR-007) e
-- obriga toda linha nova (SC-001). MAS uma constraint `not valid` passa a ser
-- verificada em todo UPDATE da linha, inclusive UPDATE que nem menciona a
-- coluna. Perfil antigo (versão NULL) deixaria de poder ser atualizado — e
-- public.excluir_minha_conta (feature 009, 20260806140000) termina em
-- `update public.perfis set nome = 'Membro removido', ...`. Resultado: quem se
-- cadastrou antes desta feature PERDERIA O DIREITO DE APAGAR A CONTA (LGPD
-- art. 18, VI). A feature 016 (Meu Perfil) bateria no mesmo muro.
--
-- A garantia de "linha nova sempre tem versão" vem do gatilho abaixo, e é
-- provada por teste de integração — inclusive um caso de excluir_minha_conta
-- sobre Perfil de versão desconhecida.
-- ###########################################################################

-- ---------------------------------------------------------------------------
-- 3. O carimbo
-- ---------------------------------------------------------------------------
-- O cliente manda o `_aceito_em` como SINAL de que a caixa foi marcada — isso
-- é legitimamente informação dele. O VALOR do instante e a versão passam a ser
-- do banco, para que os dois saiam do mesmo relógio (US1, cenário 3).
--
-- Gatilho, e não `default` de coluna: `default` só entra quando o cliente OMITE
-- a coluna; quem mencionar a coluna sobrescreve o default sem resistência.
-- Gatilho `before` é incondicional.
--
-- O RAMO `else` É TÃO IMPORTANTE QUANTO O `if`: quando o `_aceito_em` não
-- mudou, o gatilho RESTAURA os valores antigos. É isso que impede um cliente
-- autenticado de rodar
--   update public.perfis set consentimento_lgpd_versao = '1.1' where id = auth.uid()
-- na própria linha antiga e fabricar um backfill (SC-002).

create function public.perfis_carimbar_consentimento()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Consentimento LGPD do cadastro (obrigatório desde a feature 001).
  if tg_op = 'INSERT'
     or new.consentimento_lgpd_aceito_em
        is distinct from old.consentimento_lgpd_aceito_em then
    new.consentimento_lgpd_aceito_em := now();
    new.consentimento_lgpd_versao := public.versao_texto_legal_vigente();
  else
    new.consentimento_lgpd_aceito_em := old.consentimento_lgpd_aceito_em;
    new.consentimento_lgpd_versao := old.consentimento_lgpd_versao;
  end if;

  -- Consentimento destacado de Igreja de origem: opcional, e pode ser dado
  -- depois do cadastro (feature 016) ou retirado junto com a Igreja.
  if tg_op = 'INSERT'
     or new.consentimento_lgpd_igreja_aceito_em
        is distinct from old.consentimento_lgpd_igreja_aceito_em then
    if new.consentimento_lgpd_igreja_aceito_em is null then
      -- Versão sem aceite correspondente seria lixo: some junto.
      new.consentimento_lgpd_igreja_versao := null;
    else
      new.consentimento_lgpd_igreja_aceito_em := now();
      new.consentimento_lgpd_igreja_versao := public.versao_texto_legal_vigente();
    end if;
  else
    new.consentimento_lgpd_igreja_aceito_em := old.consentimento_lgpd_igreja_aceito_em;
    new.consentimento_lgpd_igreja_versao := old.consentimento_lgpd_igreja_versao;
  end if;

  return new;
end;
$$;

comment on function public.perfis_carimbar_consentimento() is
  'FR-001/FR-003/FR-004: data e versão de cada consentimento são gravadas pelo '
  'banco, nunca pelo valor que o cliente envia. O ramo else preserva o que não '
  'mudou — é ele que impede backfill retroativo por cliente (SC-002). '
  'Feature 017.';

create trigger perfis_carimbar_consentimento_trigger
  before insert or update on public.perfis
  for each row
  execute function public.perfis_carimbar_consentimento();

-- NOTA sobre excluir_minha_conta (feature 009): aquele UPDATE zera igreja_id
-- mas NÃO zera os `_aceito_em`, então o gatilho cai nos ramos `else` e
-- preserva as duas datas e as duas versões na linha anonimizada. É intencional
-- — é a prova da base legal do histórico que a feature 009 conserva. E, por
-- não chamar versao_texto_legal_vigente() nesse caminho, a exclusão de conta
-- NÃO passa a depender do catálogo de versões.

-- ---------------------------------------------------------------------------
-- 4. A consulta de conformidade (US2)
-- ---------------------------------------------------------------------------
-- `security definer` porque perfis_select_own restringe o select à própria
-- linha — sem isso a pergunta da US2 é irrespondível de dentro do app.
--
-- Devolve CONTAGEM, nunca identidade (Princípio II): sem id, sem nome, sem
-- apelido. A distinção por pessoa existe no dado (uma coluna por linha) e
-- continua alcançável pelo controlador via service_role/painel, que é o acesso
-- apropriado a um pedido individual de titular.

create function public.consentimentos_por_versao()
returns table (tipo text, versao text, quantidade bigint)
language plpgsql
stable
security definer
set search_path = ''
as $$
begin
  if not exists (
    select 1 from public.administradores_distrito
    where usuario_id = auth.uid()
  ) then
    raise exception
      'só Administrador do distrito consulta as versões de consentimento';
  end if;

  return query
  -- Perfil anonimizado (feature 009) sai da contagem: não é mais uma pessoa
  -- rastreada, e contá-lo inflaria a resposta.
  select 'lgpd'::text,
         p.consentimento_lgpd_versao,
         count(*)
  from public.perfis p
  where p.anonimizado_em is null
  group by p.consentimento_lgpd_versao

  union all

  -- Só quem de fato deu o consentimento de Igreja. Quem nunca escolheu Igreja
  -- não é "versão desconhecida" — é ausência de aceite, e misturar as duas
  -- coisas seria mentir de um jeito novo.
  select 'igreja'::text,
         p.consentimento_lgpd_igreja_versao,
         count(*)
  from public.perfis p
  where p.anonimizado_em is null
    and p.consentimento_lgpd_igreja_aceito_em is not null
  group by p.consentimento_lgpd_igreja_versao

  order by 1, 2 nulls last;
end;
$$;

comment on function public.consentimentos_por_versao() is
  'FR-005/FR-006: quantos aceites por versão, com os de versão desconhecida '
  '(NULL) contados à parte. Só Administrador do distrito. Devolve contagem, '
  'nunca identidade. Feature 017.';

revoke all on function public.consentimentos_por_versao() from public;
grant execute on function public.consentimentos_por_versao() to authenticated;
