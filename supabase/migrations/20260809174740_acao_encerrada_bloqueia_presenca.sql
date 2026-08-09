-- Feature 011 — Ação encerrada bloqueia presença.
-- Ver specs/011-acoes-titulo-e-encerramento/contracts/schema.sql (fonte de
-- verdade) e research.md D-003.
--
-- POR QUE ISTO EXISTE
-- FR-007 promete que ninguém é promovido da fila de espera depois que a Ação
-- encerra. Esconder o botão na tela é promessa; política de acesso é execução.
-- `confirmacoes_acao_promover_fila` é AFTER DELETE, então bloquear o DELETE é
-- o que cumpre a promessa.
--
-- POR QUE POLÍTICA E NÃO TRIGGER  (ler antes de "simplificar" isto)
-- `public.excluir_minha_conta` (feature 009) faz
-- `delete from public.confirmacoes_acao` para apagar a conta do Usuário. Um
-- `trigger before delete` genérico bloquearia esse delete para quem tivesse
-- confirmação em Ação encerrada, e a pessoa ficaria SEM CONSEGUIR APAGAR A
-- CONTA — bug de LGPD criado por uma feature de UX. Política não tem esse
-- efeito: função `security definer` não passa por RLS.
--
-- PREMISSAS VERIFICADAS EM 2026-08-09 CONTRA O BANCO LOCAL (T001):
--   public.excluir_minha_conta ... prosecdef = true
--   public.confirmacoes_acao ..... relrowsecurity = true, relforcerowsecurity = false
--   public.acoes ................. relrowsecurity = true, relforcerowsecurity = false
-- Se qualquer uma mudar, este desenho para de valer.
--
-- DUPLICAÇÃO DECLARADA
-- O limiar de 4 horas existe duas vezes: aqui (`interval '4 hours'`) e no Dart
-- (`defaultActionDuration`, lib/features/action/domain/action.dart). Não há como
-- derivar um do outro sem ir ao servidor a cada render. Ao mudar um, mudar o
-- outro — e rodar os dois testes de fronteira (unit + integration).

-- Predicado único, para os dois lados não divergirem entre si.
-- `stable`, não `immutable`: depende de now().
create or replace function public.acao_encerrada(p_acao_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = ''
as $$
  select now() > a.data_hora + interval '4 hours'
  from public.acoes a
  where a.id = p_acao_id;
$$;

comment on function public.acao_encerrada(uuid) is
  'Ação encerrada = passou de data_hora + 4h. Gêmea de defaultActionDuration no '
  'Dart (lib/features/action/domain/action.dart) — mudar as duas juntas. '
  'Feature 011, FR-001.';

grant execute on function public.acao_encerrada(uuid) to anon, authenticated;

-- FR-005: confirmar presença em Ação encerrada é recusado.
drop policy if exists confirmacoes_acao_insert_self on public.confirmacoes_acao;
create policy confirmacoes_acao_insert_self
  on public.confirmacoes_acao for insert
  to authenticated
  with check (
    auth.uid() = usuario_id
    and not public.acao_encerrada(acao_id)
  );

-- FR-005 + FR-007: desistir em Ação encerrada é recusado, e é isso que impede
-- `confirmacoes_acao_promover_fila` (AFTER DELETE) de promover alguém depois do
-- encerramento. A fila congela como estava (FR-006).
drop policy if exists confirmacoes_acao_delete_self on public.confirmacoes_acao;
create policy confirmacoes_acao_delete_self
  on public.confirmacoes_acao for delete
  to authenticated
  using (
    auth.uid() = usuario_id
    and not public.acao_encerrada(acao_id)
  );

-- INTOCADA de propósito: `confirmacoes_acao_select_public` (using (true)) é o
-- que deixa a contagem de confirmados ser visível a Visitante (FR-014).
--
-- FORA DO BLOQUEIO, de propósito: cancelar uma Ação encerrada continua
-- permitido. FR-005 só manda não OFERECER o botão; cancelar algo que já passou
-- é inofensivo, e bloquear seria mais uma regra para manter.
