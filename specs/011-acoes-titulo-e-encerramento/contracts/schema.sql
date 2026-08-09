-- Contrato de banco da feature 011 — Ação encerrada bloqueia presença.
--
-- Este arquivo é o CONTRATO, não a migration. A migration de verdade vai em
-- supabase/migrations/<timestamp>_acao_encerrada_bloqueia_presenca.sql com
-- este mesmo conteúdo.
--
-- O QUE ESTE DELTA FAZ
-- Aperta duas políticas existentes de `confirmacoes_acao` para que confirmar
-- presença e desistir sejam impossíveis depois que a Ação encerra.
-- Desistir é o que importa: `confirmacoes_acao_promover_fila` é AFTER DELETE,
-- então bloquear o delete é o que cumpre FR-007 ("ninguém é promovido da fila
-- depois do encerramento"). Sem isso, FR-007 seria só um botão escondido na
-- UI — promessa sem execução.
--
-- POR QUE POLÍTICA E NÃO TRIGGER  (ler antes de "simplificar" isto)
-- `public.excluir_minha_conta` (feature 009, migration 20260806140000) faz
-- `delete from public.confirmacoes_acao` para apagar a conta do Usuário. Um
-- `trigger before delete` genérico bloquearia esse delete para quem tivesse
-- confirmação em Ação encerrada, e o Usuário ficaria SEM CONSEGUIR APAGAR A
-- CONTA — bug de LGPD criado por uma feature de UX. Política de acesso não
-- tem esse efeito, porque função `security definer` não passa por RLS.
--
-- PREMISSAS A VERIFICAR ANTES DE APLICAR (se alguma cair, ver research.md D-003, plano B)
--   1. `public.excluir_minha_conta` é `security definer`.
--   2. `public.confirmacoes_acao` NÃO está com `force row level security`.
--
-- DUPLICAÇÃO DECLARADA
-- O limiar de 4 horas existe duas vezes: aqui (`interval '4 hours'`) e no Dart
-- (`defaultActionDuration` em lib/features/action/domain/action.dart). Não há como
-- derivar um do outro sem ir ao servidor a cada render. Ao mudar um, mudar o
-- outro — e rodar os dois testes de fronteira (unit + integration).

-- Predicado único, para os dois lados não divergirem entre si.
-- `stable` (não `immutable`): depende de now().
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
-- `confirmacoes_acao_promover_fila` (AFTER DELETE) de promover alguém depois
-- do encerramento. A fila congela como estava (FR-006).
drop policy if exists confirmacoes_acao_delete_self on public.confirmacoes_acao;
create policy confirmacoes_acao_delete_self
  on public.confirmacoes_acao for delete
  to authenticated
  using (
    auth.uid() = usuario_id
    and not public.acao_encerrada(acao_id)
  );

-- INTOCADA de propósito: é ela que deixa a contagem de confirmados ser
-- visível a Visitante sem cadastro (FR-014). Repetida aqui só como
-- lembrete de que o delta NÃO a altera.
--
--   create policy confirmacoes_acao_select_public
--     on public.confirmacoes_acao for select
--     to anon, authenticated
--     using (true);
--
-- E a leitura da contagem no cliente projeta SOMENTE (acao_id, status).
-- `usuario_id` nunca sai do banco para desenhar um número — ver
-- data-model.md, invariante de privacidade.

-- FORA DO BLOQUEIO, de propósito:
-- cancelar uma Ação encerrada continua permitido. FR-005 só manda não OFERECER
-- o botão; cancelar algo que já passou é inofensivo, e bloquear seria mais uma
-- regra para manter sem ninguém pedir.
