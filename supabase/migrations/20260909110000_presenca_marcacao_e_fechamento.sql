-- Change `presenca-em-acao`, parte 2 de 3 — quem marca, quem fecha, e o que
-- "não marcado" significa.
--
-- A parte 1 deixou as colunas com `grant` e SEM policy, de propósito: o
-- vermelho medido foi `Expected: <1> Actual: <0>` no caminho feliz, com as seis
-- recusas passando de graça. Esta parte faz o caminho feliz funcionar sem
-- soltar as recusas.

-- ---------------------------------------------------------------------------
-- 1. Quem pode marcar comparecimento
-- ---------------------------------------------------------------------------
--
-- `confirmacoes_acao` não tinha NENHUMA policy de `update` antes desta change,
-- então aqui a RLS é a barreira inteira e toda recusa é linha ausente —
-- `affectedRows = 0`, nunca exceção.
--
-- Quatro condições, e cada uma existe por um motivo diferente:
--   criador       — comparecimento é afirmação sobre outra pessoa; quem
--                   organizou o encontro é quem esteve em posição de observar.
--   já aconteceu  — presença futura não é fato, é previsão.
--   não cancelada — encontro que não houve não produz presença.
--   não fechada   — depois do fechamento a lista é registro; o caminho de
--                   correção passa a ser a contestação, não a reescrita.

create policy confirmacoes_acao_update_presenca
  on public.confirmacoes_acao for update
  to authenticated
  using (
    exists (
      select 1 from public.acoes a
      where a.id = confirmacoes_acao.acao_id
        and a.criador_id = auth.uid()
        and a.data_hora <= now()
        and a.cancelada_em is null
        and a.presenca_fechada_em is null
    )
  );

-- ---------------------------------------------------------------------------
-- 2. O cliente diz SE; o banco diz QUANDO e QUEM
-- ---------------------------------------------------------------------------
--
-- Mesmo contrato de `perfis_carimbar_consentimento`, e pelo mesmo motivo: um
-- registro que valesse o que o cliente afirma não demonstraria nada. Aqui é
-- pior do que lá — sem o carimbo, quem marca poderia gravar `marcado_por` de
-- OUTRA pessoa e atribuir a ela a afirmação que ele mesmo fez.
--
-- `marcado_por` e `contestada_em` não estão no `grant` da parte 1, então o
-- caminho normal já não os alcança. O `else` aqui é a segunda barreira, para o
-- dia em que alguém acrescentar uma coluna ao `grant` sem ler isto.

create function public.confirmacoes_acao_carimbar_presenca()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Nunca vem do cliente, em nenhuma hipótese.
  new.contestada_em := old.contestada_em;

  if new.compareceu_em is distinct from old.compareceu_em then
    if new.compareceu_em is not null then
      new.compareceu_em := now();
      new.marcado_por := (select auth.uid());
    else
      -- Desmarcar apaga a afirmação inteira: sem instante, sem autor.
      new.marcado_por := null;
    end if;
  else
    new.marcado_por := old.marcado_por;
  end if;

  return new;
end;
$$;

create trigger confirmacoes_acao_carimbar_presenca_trigger
  before update on public.confirmacoes_acao
  for each row execute function public.confirmacoes_acao_carimbar_presenca();

-- ---------------------------------------------------------------------------
-- 3. Fechamento — e por que ele precisa de gatilho, não só de policy
-- ---------------------------------------------------------------------------
--
-- LER ANTES DE "SIMPLIFICAR" ISTO.
--
-- `acoes` tem `grant update` de TABELA INTEIRA para `authenticated`
-- (20260723230639:114) e a policy `acoes_update_criador_dono_grupo_ou_admin`
-- (20260724092132:95-110) aceita criador OU dono do Grupo OU Administrador do
-- distrito. Quer dizer: a RLS existente já deixaria o dono do Grupo e o
-- Administrador fecharem a lista de uma Ação que não criaram — e a spec diz que
-- só quem criou fecha.
--
-- Recortar a policy de `acoes` para resolver isso quebraria a edição de Ação,
-- que é o que ela existe para permitir. Então a autoridade sobre ESTA coluna
-- vive num gatilho.
--
-- A RECUSA AQUI É EXCEÇÃO, E NÃO LINHA AUSENTE, ao contrário do resto desta
-- change. É consequência de a policy já ter deixado a linha visível: devolver
-- `affectedRows = 0` seria mentira, e uma tela que lesse zero como "não havia o
-- que fechar" afirmaria o oposto do que aconteceu.

create function public.acoes_checar_fechamento_de_presenca()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.presenca_fechada_em is not distinct from old.presenca_fechada_em then
    -- Nada a ver com presença: é uma edição comum de Ação. Sai do caminho.
    new.presentes_no_fechamento := old.presentes_no_fechamento;
    return new;
  end if;

  if old.presenca_fechada_em is not null then
    raise exception 'a lista de presença desta Ação já foi fechada e não reabre';
  end if;

  if new.presenca_fechada_em is null then
    raise exception 'a lista de presença desta Ação já foi fechada e não reabre';
  end if;

  if (select auth.uid()) is distinct from old.criador_id then
    raise exception 'só quem criou a Ação fecha a lista de presença dela';
  end if;

  if old.data_hora > now() then
    raise exception 'a lista de presença só fecha depois de a Ação acontecer';
  end if;

  if old.cancelada_em is not null then
    raise exception 'Ação cancelada não tem lista de presença para fechar';
  end if;

  new.presenca_fechada_em := now();

  -- A CONTAGEM É CONGELADA AQUI, e não calculada quando a faxina apagar as
  -- linhas nominais dois anos depois. Entre um momento e outro a quantidade
  -- mudaria — exclusão de conta, cascade de Ação — e o histórico do ministério
  -- passaria a depender de quando a faxina rodou. Congelada, é fato datado:
  -- "no fechamento, eram doze".
  select count(*) into new.presentes_no_fechamento
  from public.confirmacoes_acao c
  where c.acao_id = old.id and c.compareceu_em is not null;

  return new;
end;
$$;

create trigger acoes_checar_fechamento_de_presenca_trigger
  before update on public.acoes
  for each row execute function public.acoes_checar_fechamento_de_presenca();

comment on function public.acoes_checar_fechamento_de_presenca() is
  'Autoridade sobre acoes.presenca_fechada_em, que a RLS de `acoes` não '
  'consegue dar: a policy existente aceita criador, dono do Grupo e '
  'Administrador, e a spec exige só o criador. Recusa por EXCEÇÃO de '
  'propósito — a policy já deixou a linha visível, então affectedRows = 0 '
  'seria mentira. Congela presentes_no_fechamento no ato. Change '
  'presenca-em-acao.';
