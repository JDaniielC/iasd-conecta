-- Change `presenca-em-acao`, parte 3 — a contestação do titular.
--
-- Comparecimento é o PRIMEIRO dado deste app escrito por terceiro sobre o
-- titular: `mensagens.texto` é do autor, `denuncias_mensagem.motivo` é de quem
-- denuncia. A contestação existe para equilibrar isso.
--
-- O EQUILÍBRIO NÃO DEPENDE DE VENCER A DISPUTA. Linha contestada sai da
-- contagem para sempre, tenha o criador mantido ou desfeito a marca. Se a
-- decisão dele devolvesse a linha, a contestação seria desabafo sem efeito: o
-- membro reclama, o criador nega, o número segue igual. E software não tem como
-- arbitrar se alguém esteve ou não num culto.

-- ---------------------------------------------------------------------------
-- 1. Quem contesta
-- ---------------------------------------------------------------------------
--
-- Só o titular, e só onde existe afirmação a contestar. Contestar o que ninguém
-- afirmou não é um direito exercido — é uma linha sem referente.
--
-- RECUSA DE `insert` LEVANTA EXCEÇÃO, e isso não contraria "recusa de RLS é
-- ausência, não erro" do CLAUDE.md: aquela regra é sobre `update` e `delete`,
-- onde a policy FILTRA linhas existentes e o comando volta com sucesso sobre
-- nada. Em `insert` não há linha a filtrar, e o Postgres recusa com
-- `42501 new row violates row-level security policy`. A tela precisa tratar as
-- duas formas, e é por isso que isto está escrito aqui.

create policy contestacoes_presenca_insert_titular
  on public.contestacoes_presenca for insert
  to authenticated
  with check (
    auth.uid() = usuario_id
    and exists (
      select 1 from public.confirmacoes_acao c
      where c.acao_id = contestacoes_presenca.acao_id
        and c.usuario_id = contestacoes_presenca.usuario_id
        and c.compareceu_em is not null
    )
  );

-- Quem lê: as duas partes. O titular, porque é sobre ele; quem criou a Ação,
-- porque é quem decide.
create policy contestacoes_presenca_select_partes
  on public.contestacoes_presenca for select
  to authenticated
  using (
    auth.uid() = usuario_id
    or exists (
      select 1 from public.acoes a
      where a.id = contestacoes_presenca.acao_id
        and a.criador_id = auth.uid()
    )
  );

-- Quem decide: só quem criou a Ação, e só uma vez. Decisão tomada não se troca
-- — registro não se reescreve.
-- O `with check` É EXPLÍCITO DE PROPÓSITO, e não é redundância.
--
-- Numa policy de `update`, o Postgres reusa o `using` como `with check` quando
-- este não é declarado. Com `decisao is null` no `using`, a linha DEPOIS da
-- escrita tem decisão preenchida, o `with check` herdado falha, e a decisão
-- recusa a si mesma — medido aqui com
-- `42501 new row violates row-level security policy`.
--
-- `using` responde "esta linha pode ser alcançada?" e olha o estado ANTERIOR;
-- `with check` responde "o resultado pode existir?" e olha o POSTERIOR. São
-- perguntas diferentes, e só a primeira depende de a decisão ainda não ter sido
-- tomada.
create policy contestacoes_presenca_update_criador
  on public.contestacoes_presenca for update
  to authenticated
  using (
    decisao is null
    and exists (
      select 1 from public.acoes a
      where a.id = contestacoes_presenca.acao_id
        and a.criador_id = auth.uid()
    )
  )
  with check (
    exists (
      select 1 from public.acoes a
      where a.id = contestacoes_presenca.acao_id
        and a.criador_id = auth.uid()
    )
  );

-- SEM policy e SEM grant de `delete`, de propósito. A tabela é o registro do
-- caso, inclusive quando ele termina em discordância.

-- ---------------------------------------------------------------------------
-- 2. A marca irreversível na confirmação
-- ---------------------------------------------------------------------------
--
-- POR QUE ESTA REDUNDÂNCIA EXISTE (design D-003), e ler antes de removê-la.
--
-- "Linha contestada nunca conta" é a regra mais fácil de perder: ela vive em
-- consultas que ainda não foram escritas, numa change que ainda não existe. Se
-- dependesse de `join` com `contestacoes_presenca`, a primeira consulta que
-- esquecesse o `join` traria a linha de volta em silêncio. Com a coluna, a
-- exclusão é um `where contestada_em is null` que se escreve por reflexo — e é
-- o que `presencas_computaveis` faz.
--
-- O GUC existe porque `confirmacoes_acao_carimbar_presenca` restaura
-- `contestada_em` a cada update, para que o cliente nunca a escreva. Sem uma
-- porta declarada, o gatilho legítimo bateria na própria trava. Mesmo padrão de
-- `app.bypass_acoes_protecao` na feature de Rodada.

create function public.contestacoes_presenca_marcar_confirmacao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  perform set_config('app.propagando_contestacao', 'true', true);

  update public.confirmacoes_acao
  set contestada_em = now()
  where acao_id = new.acao_id
    and usuario_id = new.usuario_id
    and contestada_em is null;

  perform set_config('app.propagando_contestacao', 'false', true);
  return new;
end;
$$;

create trigger contestacoes_presenca_marcar_confirmacao_trigger
  after insert on public.contestacoes_presenca
  for each row execute function public.contestacoes_presenca_marcar_confirmacao();

-- Abre a porta declarada no gatilho de carimbo.
create or replace function public.confirmacoes_acao_carimbar_presenca()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  -- Só a propagação de contestação escreve esta coluna. Nem o cliente (que não
  -- a tem no `grant`), nem qualquer outro caminho.
  if coalesce(
       current_setting('app.propagando_contestacao', true), 'false'
     ) <> 'true' then
    new.contestada_em := old.contestada_em;
  end if;

  if new.compareceu_em is distinct from old.compareceu_em then
    if new.compareceu_em is not null then
      new.compareceu_em := now();
      new.marcado_por := (select auth.uid());
    else
      new.marcado_por := null;
    end if;
  else
    new.marcado_por := old.marcado_por;
  end if;

  return new;
end;
$$;

-- ---------------------------------------------------------------------------
-- 3. A decisão — carimbada pelo banco, e sem efeito sobre a contagem
-- ---------------------------------------------------------------------------
--
-- `decidida_em` e `decidida_por` não estão no `grant` (só `decisao` está), e o
-- gatilho os carimba. `contestada_em` é restaurada aqui pelo mesmo motivo de
-- sempre: o instante do registro é do banco.
--
-- NADA AQUI LIMPA `confirmacoes_acao.contestada_em`. Nem `mantida`, nem
-- `desfeita`. É a única linha de código que a regra "para sempre" precisa — e a
-- ausência dela é o defeito que este arquivo existe para prevenir.

create function public.contestacoes_presenca_decidir()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  new.contestada_em := old.contestada_em;

  if new.decisao is distinct from old.decisao and new.decisao is not null then
    new.decidida_em := now();
    new.decidida_por := (select auth.uid());

    if new.decisao = 'desfeita' then
      -- A marca deixa de afirmar comparecimento. A linha continua fora da
      -- contagem de qualquer forma, porque `contestada_em` permanece.
      update public.confirmacoes_acao
      set compareceu_em = null
      where acao_id = new.acao_id and usuario_id = new.usuario_id;
    end if;
  else
    new.decidida_em := old.decidida_em;
    new.decidida_por := old.decidida_por;
  end if;

  return new;
end;
$$;

create trigger contestacoes_presenca_decidir_trigger
  before update on public.contestacoes_presenca
  for each row execute function public.contestacoes_presenca_decidir();

comment on function public.contestacoes_presenca_decidir() is
  'Carimba decidida_em/decidida_por a partir do banco e, em `desfeita`, apaga '
  'a afirmação de comparecimento. NÃO limpa confirmacoes_acao.contestada_em em '
  'nenhum ramo: a linha sai da contagem para sempre, decida o criador o que '
  'decidir. security definer porque a marca costuma estar em Ação já fechada, '
  'que a policy de update de presença não alcança. Change presenca-em-acao.';
