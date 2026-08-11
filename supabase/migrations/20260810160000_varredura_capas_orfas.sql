-- Feature 013 — a varredura que fecha o último caminho de órfão invisível.
--
-- ---------------------------------------------------------------------
-- O QUE ESTAVA ABERTO
-- ---------------------------------------------------------------------
-- A fila de `capas_a_remover` tem UM alimentador: o gatilho
-- `fotos_capa_enfileirar_remocao`, que dispara quando uma LINHA de capa é
-- apagada. Isso cobre todo caminho de exclusão — inclusive os que não passam
-- por tela nenhuma, que é a razão de a fila existir.
--
-- Mas não cobre o arquivo que NUNCA TEVE LINHA. E ele é alcançável: o app sobe
-- o arquivo primeiro e grava a linha depois (é a ordem que falha melhor — se o
-- upload falhar, nada mudou). Se a gravação da linha falhar DEPOIS do upload —
-- rede caindo, ou duas pessoas que administram o mesmo Grupo enviando ao mesmo
-- tempo e batendo no índice único — o arquivo fica no bucket público sem linha
-- em `fotos_capa` e sem linha em `capas_a_remover`.
--
-- E aí ele é invisível. Medido em 2026-08-10: com um objeto assim no bucket, a
-- consulta de saúde de INFRA-PRODUCAO.md § 3 não se move — ela lê a fila, e o
-- arquivo nunca entrou nela. O único sinal que o projeto tem não o enxerga.
--
-- ---------------------------------------------------------------------
-- POR QUE UMA VARREDURA, E NÃO UMA COMPENSAÇÃO NO APP
-- ---------------------------------------------------------------------
-- A correção óbvia seria o app apagar o que acabou de subir quando a gravação
-- falha. Ela não serve, por duas razões:
--
-- 1. O app não tem como. `capas_a_remover` não tem grant para `authenticated`
--    (é alimentada só pelo gatilho, que é security definer), e `storage.objects`
--    não tem policy de delete para o app. Dar qualquer um dos dois abre porta
--    maior do que a que fecha.
-- 2. Mesmo que tivesse, a compensação roda no mesmo cliente que acabou de
--    falhar. O caso mais comum de falha é justamente aquele em que o cliente
--    não consegue mais falar com o servidor.
--
-- A varredura não depende do cliente e cobre qualquer causa — inclusive as que
-- ninguém previu. É a mesma escolha que fez a remoção morar num gatilho de
-- banco e não numa tela.

-- ---------------------------------------------------------------------
-- A carência de uma hora — o detalhe que decide se isto ajuda ou destrói
-- ---------------------------------------------------------------------
-- Um arquivo recém-enviado passa alguns instantes exatamente no estado que a
-- varredura procura: no bucket, sem linha. É a janela normal entre o upload e
-- o insert. Varrer sem carência apagaria a capa de quem acabou de enviá-la.
--
-- Uma hora não é um número afinado: é uma ordem de grandeza acima da janela
-- real (segundos) e muito abaixo do prazo em que um arquivo esquecido importa.
create function public.varrer_capas_orfas()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_enfileirados integer;
begin
  insert into public.capas_a_remover (caminho)
  select o.name
  from storage.objects o
  where o.bucket_id = 'fotos-capa'
    and o.created_at < now() - interval '1 hour'
    and not exists (
      select 1 from public.fotos_capa f where f.caminho = o.name
    )
    and not exists (
      select 1 from public.capas_a_remover q where q.caminho = o.name
    )
  on conflict (caminho) do nothing;

  get diagnostics v_enfileirados = row_count;
  return v_enfileirados;
end;
$$;

comment on function public.varrer_capas_orfas() is
  'Enfileira arquivos do bucket fotos-capa que não têm linha em fotos_capa nem '
  'na fila. Fecha o caminho de órfão que o gatilho não cobre: o arquivo que '
  'nunca chegou a ter linha. Carência de 1 hora para não apagar upload em '
  'andamento. Feature 013.';

revoke all on function public.varrer_capas_orfas() from public;
-- Sem grant para `anon` nem `authenticated`: quem chama é o cron, como
-- postgres. O app não tem o que fazer com isto — e a carência de uma hora
-- tornaria qualquer chamada dele inútil de qualquer forma.

-- De hora em hora. Não precisa ser mais rápido do que a própria carência, e
-- vale a mesma limitação conhecida do outro agendamento: `pg_cron` roda dentro
-- do Postgres, e projeto pausado no plano gratuito para o cron junto. Aqui
-- isso incomoda menos — o que espera é arquivo que ninguém referencia, e que
-- portanto ninguém está vendo.
select cron.schedule(
  'varrer-capas-orfas',
  '0 * * * *',
  $$select public.varrer_capas_orfas()$$
);
