-- Feature 013 — Denúncia de imagem (US3).
--
-- O caso que motivou esta feature: uma mãe **sem cadastro** vê a foto da filha
-- numa capa. Exigir que ela se cadastre para pedir a retirada seria exigir que
-- ela entregue os próprios dados para retirar os da filha — o oposto do que o
-- Princípio II defende. Por isso `denunciante_id` é anulável e `anon` insere.

create table public.denuncias_imagem (
  id uuid primary key default gen_random_uuid(),
  foto_id uuid not null references public.fotos_capa(id) on delete cascade,
  motivo text not null check (length(trim(motivo)) > 0),
  denunciante_id uuid references public.perfis(id),   -- NULO: Visitante sem Perfil
  estado text not null default 'pendente'
    check (estado in ('pendente', 'imagem_removida', 'improcedente')),
  created_at timestamptz not null default now(),
  resolvida_em timestamptz
);

comment on column public.denuncias_imagem.denunciante_id is
  'NULO quando quem denuncia é Visitante sem Perfil (FR-015). Quem precisa '
  'pedir a retirada da foto de um filho não deve ter que se cadastrar para '
  'isso. NUNCA exposto a quem enviou a imagem (FR-020).';

comment on table public.denuncias_imagem is
  'FR-019: o cascade em foto_id encerra as denúncias quando a imagem some '
  'por qualquer caminho — remoção, cancelamento de Ação, descarte de '
  'candidata, exclusão de conta. Sem isso o Administrador acumula pendências '
  'sobre imagens que não existem mais, e a lista perde credibilidade em '
  'poucas semanas.';

create index denuncias_imagem_pendentes on public.denuncias_imagem (foto_id)
  where estado = 'pendente';

alter table public.denuncias_imagem enable row level security;

-- FR-015: qualquer pessoa denuncia, inclusive sem Perfil.
--
-- O `with check` impede o único abuso que importa aqui: assinar a denúncia com
-- o nome de outra pessoa. Ou a denúncia é anônima, ou é sua.
create policy denuncias_imagem_insert_qualquer
  on public.denuncias_imagem for insert
  to anon, authenticated
  with check (
    denunciante_id is null or denunciante_id = auth.uid()
  );

-- FR-016 + FR-020: só o Administrador do distrito lê. Ninguém mais vê quem
-- denunciou — nem quem enviou a imagem, nem Usuário comum. Note que NÃO existe
-- política de select para quem denunciou ver a própria denúncia: seria uma
-- porta a mais para correlacionar denúncia com pessoa, e ninguém pediu.
create policy denuncias_imagem_select_admin
  on public.denuncias_imagem for select
  to authenticated
  using (exists (
    select 1 from public.administradores_distrito d where d.usuario_id = auth.uid()));

-- FR-017: só o Administrador resolve.
--
-- O `with check` é gêmeo do `using` de propósito: sem ele, a linha poderia sair
-- do alcance de quem a editou — e, pior, `foto_id` e `motivo` seriam
-- reescrevíveis. Uma denúncia com o motivo reescrito não é mais uma denúncia,
-- é um registro adulterado.
create policy denuncias_imagem_update_admin
  on public.denuncias_imagem for update
  to authenticated
  using (exists (
    select 1 from public.administradores_distrito d where d.usuario_id = auth.uid()))
  with check (exists (
    select 1 from public.administradores_distrito d where d.usuario_id = auth.uid()));

-- =====================================================================
-- Os GRANTs — e o TRUNCATE
-- =====================================================================
--
-- Política RLS não concede acesso: ela FILTRA um acesso que o grant já deu. O
-- contrato desta feature (contracts/schema.sql § 4) não tem grant nenhum, pelo
-- mesmo descuido que a revisão de segurança pegou na tabela `fotos_capa` — lá
-- o resultado medido foi `permission denied for table`, ou seja, a feature não
-- funcionaria na primeira tentativa de uso, com todas as políticas escritas e
-- corretas.
--
-- `anon` recebe insert e mais nada: quem denuncia sem cadastro não pode ler a
-- própria denúncia nem a de ninguém.
grant insert on public.denuncias_imagem to anon, authenticated;
grant select, update on public.denuncias_imagem to authenticated;

-- Sem `delete` para ninguém: denúncia não se apaga, se resolve. A única forma
-- de uma linha sumir é o cascade de `foto_id`, que é o encerramento de FR-019.
--
-- E o TRUNCATE, que é o que faz este bloco importar: `anon` e `authenticated`
-- herdam TRUNCATE, REFERENCES e TRIGGER do default do fornecedor. TRUNCATE
-- **ignora RLS**. Sem este revoke, qualquer pessoa autenticada apagaria a fila
-- inteira de denúncias com uma instrução — inclusive as pendentes sobre a
-- própria imagem. Ver PENDENCIAS.md §2.2: as outras tabelas do schema
-- continuam com o mesmo problema.
revoke truncate, references, trigger on public.denuncias_imagem from anon, authenticated;
