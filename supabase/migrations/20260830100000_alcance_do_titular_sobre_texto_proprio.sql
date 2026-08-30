-- Change alcance-do-titular-sobre-texto-proprio.
--
-- POR QUE ISTO EXISTE
-- `mensagem-fixada` (20260817160000) já declara, em `mensagens_so_remove`, que
-- o AUTOR sempre desfixa a própria mensagem, mesmo sem autoridade no espaço —
-- `pode_moderar_mensagem` aceita `auth.uid() = autor_id` como um dos braços.
-- Medido em 2026-08-17 (`PENDENCIAS.md` 2.28) que a promessa FALHA na prática:
-- quem sai do Grupo, desiste da Ação ou perde o corte de idade não alcança
-- mais a linha nenhuma, porque no Postgres um `UPDATE ... WHERE` só enxerga o
-- que a policy de `SELECT` deixa a sessão ler — e `pode_ver_chat_grupo` /
-- `pode_ver_chat_acao` passaram a devolver `false` para ela.
--
-- A causa não é a policy de `update` (`mensagens_update_autor_ou_autoridade`),
-- que acerta. É ALCANCE, não permissão — e a única forma de resolver alcance
-- sem alargar quem LÊ o quê é uma função `security definer` estreita: recebe
-- só o id da mensagem, confere `auth.uid() = autor_id` como predicado inteiro
-- (autoridade já tem o caminho de dentro da conversa) e toca só as duas
-- colunas de fixação. Ver design.md da change para as alternativas recusadas.
--
-- O gatilho `mensagens_so_remove` CONTINUA rodando por cima deste `update` — a
-- função não o contorna, e é por isso que ela não precisa reimplementar a
-- regra de desfixe.

-- ---------------------------------------------------------------------------
-- 1. desfixar_minha_mensagem — alcança a linha, não reimplementa a regra
-- ---------------------------------------------------------------------------
create function public.desfixar_minha_mensagem(p_mensagem_id uuid)
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_linhas integer;
begin
  update public.mensagens
  set fixada_em = null, fixada_por = null
  where id = p_mensagem_id
    and autor_id = auth.uid();
  get diagnostics v_linhas = row_count;
  return v_linhas;
end;
$$;

revoke execute on function public.desfixar_minha_mensagem(uuid) from public;
grant execute on function public.desfixar_minha_mensagem(uuid) to authenticated;

comment on function public.desfixar_minha_mensagem(uuid) is
  'Alcança a própria mensagem fixada de FORA da conversa: um UPDATE só '
  'enxerga linha que a policy de SELECT deixa a sessão ler, e quem saiu do '
  'Grupo, desistiu da Ação ou perdeu o corte de idade não lê mais a conversa '
  'onde escreveu. Predicado auth.uid() = autor_id, INTEIRO e sem braço de '
  'autoridade — quem modera tem o caminho de dentro da conversa, este não é '
  'para ela. Devolve quantas linhas mudou: 0 distingue "não era sua" de "não '
  'estava fixada". O gatilho mensagens_so_remove continua rodando sobre este '
  'UPDATE — esta função não contorna a regra de desfixe, só alcança a linha. '
  'Change alcance-do-titular-sobre-texto-proprio.';

-- ---------------------------------------------------------------------------
-- 2. minhas_mensagens_fixadas — a lista, pelo mesmo motivo de alcance
-- ---------------------------------------------------------------------------
-- SEM fixada_por: quem fixou é dado sobre OUTRA pessoa, e saber que alguém
-- com autoridade fixou já basta para a titular decidir desfixar. Devolve o
-- nome do espaço (Grupo ou Ação) para a pessoa saber de onde é, já que ela
-- pode não alcançar mais aquela conversa para descobrir sozinha.
create function public.minhas_mensagens_fixadas()
returns table (
  id uuid,
  texto text,
  fixada_em timestamptz,
  grupo_id uuid,
  acao_id uuid,
  nome_espaco text
)
language sql
stable
security definer
set search_path = ''
as $$
  select
    m.id,
    m.texto,
    m.fixada_em,
    m.grupo_id,
    m.acao_id,
    coalesce(g.nome, a.nome)
  from public.mensagens m
  left join public.grupos g on g.id = m.grupo_id
  left join public.acoes a on a.id = m.acao_id
  where m.autor_id = auth.uid()
    and m.fixada_em is not null
  order by m.fixada_em desc;
$$;

revoke execute on function public.minhas_mensagens_fixadas() from public;
grant execute on function public.minhas_mensagens_fixadas() to authenticated;

comment on function public.minhas_mensagens_fixadas() is
  'As próprias mensagens fixadas, de QUALQUER conversa — inclusive das que a '
  'sessão já não lê (mesmo alcance de desfixar_minha_mensagem). Sem '
  'fixada_por: quem fixou é dado sobre outra pessoa. Nunca traz mensagem de '
  'outro autor, mesmo da mesma conversa — o predicado é autor_id = auth.uid(), '
  'não o espaço. Change alcance-do-titular-sobre-texto-proprio.';
