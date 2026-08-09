-- Contrato de banco da feature 013 — Foto de capa de Grupo e de Ação.
--
-- Este arquivo é o CONTRATO, não a migration. A migration vai em
-- supabase/migrations/<timestamp>_foto_de_capa.sql.
--
-- ⚠️ NÃO ESCREVER ESTA MIGRATION ANTES DE RESPONDER research.md D-004.
-- Duas afirmações sobre o comportamento do fornecedor sustentam o desenho
-- abaixo, e nenhuma delas pode ser assumida de memória:
--   1. Apagar o registro do objeto no schema de armazenamento remove mesmo o
--      binário, ou deixa órfão invisível?
--   2. Objeto público removido continua servível por cache de borda por
--      quanto tempo, e há invalidação síncrona?
-- A resposta a (1) decide se o gatilho abaixo basta. A resposta a (2) decide
-- o TEXTO de FR-012 na Política de Privacidade — o documento descreve o que o
-- sistema garante, não o que se queria garantir. Se a janela de cache for
-- inaceitável para foto de menor, vale o plano alternativo de D-004 (endereço
-- assinado de vida curta em vez de objeto público).

-- =====================================================================
-- 1. Foto de capa
-- =====================================================================

create table public.fotos_capa (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid references public.grupos(id) on delete cascade,
  acao_id uuid references public.acoes(id) on delete cascade,
  caminho text not null unique,
  enviada_por uuid not null references public.perfis(id),
  created_at timestamptz not null default now(),

  -- Exatamente um dono. Restrição, não disciplina de código.
  constraint fotos_capa_um_dono check (
    (grupo_id is not null and acao_id is null)
    or (grupo_id is null and acao_id is not null)
  )
);

-- FR-001: no máximo uma capa por Grupo e uma por Ação.
create unique index fotos_capa_grupo_unica on public.fotos_capa (grupo_id)
  where grupo_id is not null;
create unique index fotos_capa_acao_unica on public.fotos_capa (acao_id)
  where acao_id is not null;

comment on table public.fotos_capa is
  'Imagem de capa de Grupo ou Ação (feature 013). Trocar a capa é DELETE + '
  'INSERT, nunca UPDATE do caminho — é o DELETE que dispara a limpeza do '
  'arquivo antigo.';

comment on column public.fotos_capa.enviada_por is
  'Prestação de contas e regra de exclusão de conta (FR-024). NÃO decide '
  'permissão: quem controla a capa é quem administra o Grupo/Ação hoje '
  '(FR-003), não quem enviou.';

-- =====================================================================
-- 2. Limpeza do arquivo — o núcleo da feature
-- =====================================================================
--
-- Cascade de banco apaga LINHA, não apaga ARQUIVO. Sem este gatilho, todo
-- caminho de exclusão deixa órfão invisível — e o pior deles não passa por
-- tela nenhuma: `fechar_rodada_se_devido` apaga as candidatas perdedoras com
-- `delete from public.acoes` (20260724084300_rodada_votacao.sql:178).
--
-- Pôr a limpeza aqui faz com que TODO caminho que apaga a linha apague o
-- arquivo, inclusive os que ainda não existem — como "apagar Grupo", que hoje
-- não existe no app (ver plan.md, achado 1).

create function public.fotos_capa_limpar_arquivo()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- O mecanismo exato depende da resposta a D-004 pergunta 1.
  -- Forma pretendida: remover o objeto correspondente a old.caminho do
  -- bucket 'fotos-capa'. Se a verificação mostrar que isso não remove o
  -- binário de fato, este corpo muda — o CONTRATO ("apagar a linha apaga o
  -- arquivo") não muda.
  perform public.remover_objeto_capa(old.caminho);
  return old;
end;
$$;

create trigger fotos_capa_limpar_arquivo
  after delete on public.fotos_capa
  for each row
  execute function public.fotos_capa_limpar_arquivo();

-- =====================================================================
-- 3. Políticas de acesso — fotos_capa
-- =====================================================================

alter table public.fotos_capa enable row level security;

-- FR-008: capa é pública, como o Grupo e a Ação já são.
create policy fotos_capa_select_public
  on public.fotos_capa for select
  to anon, authenticated
  using (true);

-- FR-003: só quem administra. Administrador do distrito entra pelo OR final.
create policy fotos_capa_insert_admin
  on public.fotos_capa for insert
  to authenticated
  with check (
    auth.uid() = enviada_por
    and (
      (grupo_id is not null and exists (
        select 1 from public.grupos g where g.id = grupo_id and g.dono_id = auth.uid()))
      or (acao_id is not null and exists (
        select 1 from public.acoes a where a.id = acao_id and a.criador_id = auth.uid()))
      or exists (
        select 1 from public.administradores_distrito d where d.usuario_id = auth.uid())
    )
  );

-- FR-011: Administrador remove qualquer uma. Dono/criador remove a sua.
create policy fotos_capa_delete_admin
  on public.fotos_capa for delete
  to authenticated
  using (
    (grupo_id is not null and exists (
      select 1 from public.grupos g where g.id = grupo_id and g.dono_id = auth.uid()))
    or (acao_id is not null and exists (
      select 1 from public.acoes a where a.id = acao_id and a.criador_id = auth.uid()))
    or exists (
      select 1 from public.administradores_distrito d where d.usuario_id = auth.uid())
  );

-- Sem policy de UPDATE, de propósito: trocar a capa é DELETE + INSERT, para o
-- gatilho de limpeza disparar. UPDATE do caminho deixaria o arquivo antigo
-- órfão sem nenhum aviso.

-- =====================================================================
-- 4. Denúncia de imagem
-- =====================================================================

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
  'sobre imagens que não existem mais.';

alter table public.denuncias_imagem enable row level security;

-- FR-015: qualquer pessoa denuncia, inclusive sem Perfil.
create policy denuncias_imagem_insert_qualquer
  on public.denuncias_imagem for insert
  to anon, authenticated
  with check (
    denunciante_id is null or denunciante_id = auth.uid()
  );

-- FR-016 + FR-020: só o Administrador do distrito lê. Ninguém mais vê quem
-- denunciou — nem quem enviou a imagem, nem Usuário comum.
create policy denuncias_imagem_select_admin
  on public.denuncias_imagem for select
  to authenticated
  using (exists (
    select 1 from public.administradores_distrito d where d.usuario_id = auth.uid()));

-- FR-017: só o Administrador resolve.
create policy denuncias_imagem_update_admin
  on public.denuncias_imagem for update
  to authenticated
  using (exists (
    select 1 from public.administradores_distrito d where d.usuario_id = auth.uid()));

-- =====================================================================
-- 5. Exclusão de conta — uma instrução a mais em excluir_minha_conta
-- =====================================================================
--
-- FR-024: capas de Ação avulsa de quem sai são apagadas.
-- FR-025: capa de Grupo herdado FICA — o Grupo continua existindo, com outro
--         Dono, e a capa ilustra o Grupo, não a pessoa.
--
-- Nota que precisa estar escrita, porque parece bug e não é: `excluir_minha_conta`
-- NÃO apaga as Ações de quem sai — anonimiza o Perfil e deixa `acoes.criador_id`
-- apontando pra ele, de propósito (histórico, feature 009). Então a Ação
-- continua existindo, sem capa, com criador "Membro removido". É a regra.
--
-- Inserir dentro de public.excluir_minha_conta(), ANTES do UPDATE que anonimiza
-- o Perfil, na mesma seção dos outros deletes de vínculo vivo:
--
--   delete from public.fotos_capa f
--   using public.acoes a
--   where f.acao_id = a.id
--     and a.grupo_id is null          -- só Ação avulsa
--     and f.enviada_por = v_uid;
--
-- O gatilho da seção 2 apaga os arquivos.

-- =====================================================================
-- 6. Cancelamento de Ação — ato explícito, não cascade
-- =====================================================================
--
-- FR-022. `ActionRepository.cancelAction` faz UPDATE em `cancelada_em`; a linha
-- da Ação NÃO some, então nenhum cascade dispara. A capa precisa ser apagada
-- explicitamente. Gatilho na própria `acoes`, para valer também quando o
-- cancelamento vier de outro caminho que não a tela:
--
--   after update of cancelada_em on public.acoes
--   when (old.cancelada_em is null and new.cancelada_em is not null)
--   → delete from public.fotos_capa where acao_id = new.id;
--
-- O gatilho da seção 2 cuida do arquivo.

-- =====================================================================
-- 7. Bucket
-- =====================================================================
--
-- Bucket 'fotos-capa': leitura pública (FR-008), escrita só por quem a policy
-- de fotos_capa autoriza, caminho único por envio e NUNCA reaproveitado
-- (research D-001) — caminho reaproveitado com cache de borda serve a imagem
-- antiga, que é o modo mais silencioso de FR-012 falhar.
--
-- A configuração exata (incluindo cache-control) depende de D-004 pergunta 2.
