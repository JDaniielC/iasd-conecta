-- Feature 013 — Foto de capa de Grupo e de Ação.
--
-- ===================================================================
-- O QUE A VERIFICAÇÃO DE D-004 MUDOU NESTE ARQUIVO
-- ===================================================================
-- O contrato proibia escrever esta migration antes de responder duas
-- perguntas em fonte primária. As duas foram respondidas em 2026-08-10, e as
-- duas vieram desfavoráveis (trechos literais em research.md D-004):
--
-- 1. "Deleting objects via a SQL query will not remove the object from the
--    bucket and will result in the object being orphaned."
--    => Apagar a linha em storage.objects NÃO apaga o binário. Um gatilho que
--       fizesse só isso produziria exatamente o órfão que SC-005 existe para
--       impedir, e em silêncio. A remoção precisa CHAMAR a API de armazenamento.
--
-- 2. "It can take up to 60 seconds for the CDN cache to be invalidated."
--    => Objeto público removido continua acessível por até 60s a quem já tem o
--       endereço. O responsável pelo app escolheu aceitar essa janela
--       (2026-08-10), avaliando risco baixo para um app que existe para
--       convidar pessoas a encontros. FR-012 e SC-004 foram reescritos na spec
--       para dizer isso, e a Política vai ter de dizer também.
--
-- ===================================================================
-- POR QUE A REMOÇÃO É ENFILEIRADA, E NÃO FEITA NO GATILHO
-- ===================================================================
-- Chamar a API de armazenamento de dentro do gatilho põe uma requisição de
-- rede DENTRO da transação que apaga a linha. Uma dessas transações é
-- public.excluir_minha_conta. Uma falha de rede abortaria a exclusão de conta
-- — trocaria vazamento de imagem por perda do direito do art. 18, VI da LGPD,
-- que é a mesma classe de erro que as features 015 e 017 tiveram de desarmar.
--
-- Então o gatilho só ENFILEIRA, o que é atômico e não pode falhar por rede. A
-- chamada à API acontece depois, fora da transação, drenando a fila. O
-- contrato "apagar a linha faz o arquivo sumir" continua valendo; o que muda é
-- que ele passa a valer com um atraso de segundos, não instantaneamente.
--
-- A fila é também o que torna SC-005 verificável: órfão vira "linha na fila
-- que ninguém drenou", que é visível, em vez de "arquivo no bucket que
-- ninguém referencia", que não é.

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
  'INSERT, nunca UPDATE do caminho — é o DELETE que enfileira a limpeza do '
  'arquivo antigo.';

comment on column public.fotos_capa.enviada_por is
  'Prestação de contas e regra de exclusão de conta (FR-024). NÃO decide '
  'permissão: quem controla a capa é quem administra o Grupo/Ação hoje '
  '(FR-003), não quem enviou.';

-- =====================================================================
-- 2. A fila de remoção — o núcleo da feature
-- =====================================================================
--
-- Cascade de banco apaga LINHA, não apaga ARQUIVO. Sem isto, todo caminho de
-- exclusão deixa órfão invisível — e o pior deles não passa por tela nenhuma:
-- fechar_rodada_se_devido apaga as candidatas perdedoras com um
-- `delete from public.acoes` (20260724084300_rodada_votacao.sql:178).
--
-- Enfileirar no gatilho faz com que TODO caminho que apaga a linha marque o
-- arquivo para remoção, inclusive os que ainda não existem.

create table public.capas_a_remover (
  caminho text primary key,
  enfileirado_em timestamptz not null default now(),
  removido_em timestamptz,
  tentativas integer not null default 0,
  ultimo_erro text
);

comment on table public.capas_a_remover is
  'Arquivos de capa cuja linha já sumiu e que ainda precisam sair do bucket. '
  'Linha com removido_em nulo há muito tempo é um órfão em potencial — e é '
  'isso que torna SC-005 verificável por consulta, em vez de exigir varrer o '
  'bucket. Feature 013.';

create index capas_a_remover_pendentes on public.capas_a_remover (enfileirado_em)
  where removido_em is null;

create function public.fotos_capa_enfileirar_remocao()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  -- Só insere na fila. Nada de rede aqui: esta função roda dentro da
  -- transação de quem apagou a linha, e uma dessas transações é a exclusão
  -- de conta.
  insert into public.capas_a_remover (caminho)
  values (old.caminho)
  on conflict (caminho) do nothing;
  return old;
end;
$$;

create trigger fotos_capa_enfileirar_remocao
  after delete on public.fotos_capa
  for each row
  execute function public.fotos_capa_enfileirar_remocao();

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

-- A fila não é assunto de ninguém no app.
alter table public.capas_a_remover enable row level security;
revoke all on public.capas_a_remover from anon, authenticated;

-- =====================================================================
-- 3b. Os GRANTs — sem eles, tudo acima é código morto
-- =====================================================================
--
-- Política RLS não concede acesso: ela FILTRA um acesso que o grant já deu.
-- A primeira versão desta migration não tinha grant nenhum, e o resultado
-- medido foi `permission denied for table fotos_capa` para `authenticated` —
-- ou seja, a feature não funcionaria na primeira tentativa de uso, com todas
-- as políticas acima escritas e corretas. Pego por revisão de segurança
-- automatizada.
grant select on public.fotos_capa to anon, authenticated;
grant insert, delete on public.fotos_capa to authenticated;

-- Sem `update`, de propósito: trocar a capa é DELETE + INSERT, e não existe
-- policy de update. Conceder o privilégio sem policy seria deixar uma porta
-- que só não abre por causa de outra tranca.

-- ---------------------------------------------------------------------
-- E o TRUNCATE, que é o que faz este bloco importar de verdade
-- ---------------------------------------------------------------------
-- `anon` e `authenticated` herdam TRUNCATE, REFERENCES e TRIGGER do default
-- do fornecedor, em todas as tabelas do schema. Medido: como `authenticated`,
-- `truncate public.fotos_capa` FUNCIONA.
--
-- E TRUNCATE **ignora RLS** e **não dispara gatilho `after delete`**. Ou seja:
-- uma única instrução apagaria todas as linhas de capa sem enfileirar nada, e
-- **todos os arquivos do bucket virariam órfãos de uma vez** — exatamente o
-- que a fila da seção 2 existe para impedir. O desenho inteiro da feature cai
-- por uma porta que nem foi aberta por ela.
--
-- Aqui isto é fechado para as duas tabelas desta feature. As outras 14 tabelas
-- do schema continuam com o mesmo problema — está registrado em
-- PENDENCIAS.md §2.2 como achado que precisa de spec própria, porque mexer no
-- grant de todas exige teste provando que nada legítimo quebrou.
revoke truncate, references, trigger on public.fotos_capa from anon, authenticated;
revoke truncate, references, trigger on public.capas_a_remover from anon, authenticated;

-- =====================================================================
-- 4. Bucket
-- =====================================================================
--
-- Público (FR-008), como o Grupo e a Ação já são. A escolha de objeto público
-- em vez de endereço assinado é a decisão do responsável pelo app registrada
-- no topo, e é ela que traz a janela de 60 segundos.
--
-- Caminho único por envio e NUNCA reaproveitado (research D-001): caminho
-- reaproveitado com cache de borda serve a imagem ANTIGA no endereço novo, que
-- é o jeito mais silencioso de FR-012 falhar.

insert into storage.buckets (id, name, public, file_size_limit, allowed_mime_types)
values (
  'fotos-capa',
  'fotos-capa',
  true,
  5242880,  -- 5 MB; o limite é informado ao Usuário ANTES do envio (FR-009)
  array['image/jpeg', 'image/png', 'image/webp']
)
on conflict (id) do nothing;

-- O CAMINHO CARREGA O DONO, e a política confere.
--
-- A primeira versão desta política tinha só `bucket_id = 'fotos-capa'`, com um
-- comentário afirmando que "a escrita segue a mesma regra da tabela". Era
-- falso: a política não conferia nada. Qualquer pessoa autenticada podia subir
-- arquivo arbitrário para um bucket PÚBLICO, sem vínculo com Grupo nenhum — e
-- sem linha em fotos_capa a fila de remoção nem detectaria, porque ela só
-- conhece arquivos que um dia tiveram linha. Pego por revisão de segurança
-- automatizada, e é a mesma classe de erro que a feature 018 consertou:
-- comentário prometendo uma garantia que o código não dá.
--
-- Formato exigido do caminho: `grupo/<uuid>/<arquivo>` ou `acao/<uuid>/<arquivo>`.
-- Sem isso, "quem administra" não teria a que se referir — conferir que a
-- pessoa é dona de ALGUM Grupo deixaria o dono de um Grupo subir arquivo no
-- prefixo de outro.
create policy fotos_capa_objetos_insert
  on storage.objects for insert
  to authenticated
  with check (
    bucket_id = 'fotos-capa'
    and array_length(storage.foldername(name), 1) >= 2
    and (
      (
        (storage.foldername(name))[1] = 'grupo'
        and exists (
          select 1 from public.grupos g
          where g.id::text = (storage.foldername(name))[2]
            and g.dono_id = auth.uid()
        )
      )
      or (
        (storage.foldername(name))[1] = 'acao'
        and exists (
          select 1 from public.acoes a
          where a.id::text = (storage.foldername(name))[2]
            and a.criador_id = auth.uid()
        )
      )
      or exists (
        select 1 from public.administradores_distrito d
        where d.usuario_id = auth.uid()
      )
    )
  );

create policy fotos_capa_objetos_select
  on storage.objects for select
  to anon, authenticated
  using (bucket_id = 'fotos-capa');

-- Sem policy de DELETE nem de UPDATE em storage.objects, de propósito: a
-- remoção do arquivo é da fila (seção 2), que roda com credencial de serviço
-- fora da transação. Dar delete ao cliente reabriria o caminho de apagar o
-- arquivo sem apagar a linha — órfão ao contrário, com a tela mostrando uma
-- capa que não existe mais.

-- =====================================================================
-- 5. A versão nova do texto legal entra no catálogo
-- =====================================================================
-- Regra da feature 017: publicar texto novo muda `LegalMetadata.version` E
-- semeia a linha correspondente, no mesmo commit.
--
-- Aqui o texto mudou de verdade e a mudança ADICIONA um tratamento: o app
-- passou a hospedar imagem enviada por Usuário, visível a qualquer pessoa na
-- internet, inclusive sem cadastro. Quem se cadastrar a partir de agora aceita
-- algo diferente de quem se cadastrou antes — que é exatamente a distinção que
-- a feature 017 passou a registrar.
--
-- A Política também passou a DECLARAR o que o app não faz: não solicita nem
-- verifica autorização de responsável para imagem de menor, e não analisa o
-- conteúdo do que é enviado. Omitir isso deixaria subentendido um controle
-- inexistente, que é a divergência entre promessa e execução que a
-- constituição proíbe.
--
-- test/integration/versao_texto_legal_registro_test.dart falha se as duas
-- divergirem.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.4', timestamptz '2026-08-10 00:00:00-03')
on conflict (versao) do nothing;
