-- Contrato de banco da feature 018 — declaração de Líder/Diretor pendente ou
-- rejeitada deixa de ser pública.
--
-- Conteúdo integral de specs/018-visibilidade-de-liderancas/contracts/schema.sql.
-- Os comentários vêm junto de propósito: o porquê mora aqui, onde quem for
-- mexer na política vai ler, e não numa mensagem de commit que ninguém abre.
--
-- Premissas verificadas contra o banco local antes de aplicar (T001):
--   liderancas | rls=t | force=f
--   anon, authenticated -> SELECT (nenhum INSERT/UPDATE/DELETE)
--   administradores_distrito_select_public presente
--
-- Vazamento reproduzido antes do fix (T002): como `set role anon`, um select em
-- public.liderancas devolveu as 3 linhas do Grupo semeado — confirmada,
-- PENDENTE e REJEITADA.
--
-- O QUE ESTE DELTA FAZ
-- Substitui `liderancas_select_public` (20260724100000_leadership.sql:73-76),
-- que era `using (true)` — sem filtro nenhum. Com ela, qualquer Visitante sem
-- cadastro lia a tabela inteira via PostgREST, incluindo declarações PENDENTES
-- e REJEITADAS. A tela de Grupo esconde (só renderiza `confirmado_em`
-- preenchido, group_detail_page.dart:126-140), mas esconder não é proteger:
-- o cliente Supabase fala PostgREST, e a mesma requisição sem o filtro do Dart
-- traz tudo.
--
-- O DANO CONCRETO (é por isso que a feature existe, não por higiene)
-- Num distrito de 15+ igrejas onde as pessoas se conhecem, "Fulano se declarou
-- Líder do Ministério Jovem e o Administrador do distrito rejeitou" é
-- constrangimento real sobre uma pessoa real. Ninguém decidiu tornar isso
-- público — foi consequência de uma policy escrita com `using (true)`.
-- Constituição, Princípio II.
--
-- O LIMITE DO QUE PODE VAZAR, PALAVRA POR PALAVRA
-- CONTEXT.md, entrada Ministério: "Identificação do Líder é pública na página
-- do Ministério — visível até pra Visitante sem cadastro." Identificação do
-- LÍDER. Não a lista de quem tentou e não conseguiu. O 1º disjunto abaixo é
-- exatamente essa promessa, e nada além dela.
--
-- POR QUE POLÍTICA E NÃO FILTRO NO DART  (ler antes de "simplificar" isto)
-- Filtrar no repositório é o que já existe (leadership_repository.dart:36) e é
-- literalmente o que falhou. FR-004 exige a garantia no banco. Não é trigger
-- (não há escrita a bloquear — a feature é sobre leitura) nem view (mudaria os
-- três pontos de leitura do Dart sem ganhar nada).
--
-- PREMISSAS A VERIFICAR ANTES DE APLICAR (se alguma cair, ver research.md D-009)
--   1. `public.liderancas` NÃO está com `force row level security` — senão
--      `public.excluir_minha_conta` (feature 009, 20260806140000:137, que faz
--      `delete from public.liderancas where usuario_id = v_uid`) passaria a ser
--      filtrado por esta política e a exclusão de conta deixaria de apagar a
--      declaração. Mesma armadilha que a feature 011 documentou.
--   2. Não existe `grant insert/update/delete` em `public.liderancas` para
--      `anon`/`authenticated` — só `grant select` (leadership.sql:65). Toda
--      escrita continua pelas funções `security definer`.
--   3. `public.administradores_distrito` continua com `select` liberado a
--      `anon, authenticated` (district_admin.sql:44,52-55). Se apertar, o 3º
--      disjunto para de enxergar a linha do admin e a tela de pendências
--      esvazia.
--
-- PREDICADO DUPLICADO, DECLARADO
-- `confirmado_em is not null and rejeitado_em is null` existe aqui e no Dart
-- (`fetchCurrentLeaders`, lib/features/leadership/data/leadership_repository.dart).
-- Ao mudar um, mudar o outro. Se divergirem, o sintoma é silencioso: a linha
-- some da tela sem erro nenhum, porque a RLS remove antes de o Dart ver.
--
-- INTERAÇÃO COM A FEATURE 014 (arquivar Grupo) — não é descuido, é escopo
-- Depois desta feature, uma declaração CONFIRMADA de um Grupo ARQUIVADO
-- continua legível por `anon`. A 014 decidiu, na data-model dela
-- (specs/014-arquivar-grupo/data-model.md:82,105), que `liderancas` não é
-- tocada pelo arquivamento — é histórico de quem foi responsável perante a
-- igreja — e que esconder é papel da exibição (tasks.md:101, T018). A 018 não
-- reverte decisão de outra feature. As duas mexem no mesmo `fetchCurrentLeaders`
-- do Dart, e em nada uma da outra no banco.

-- FR-001/FR-002/FR-003/FR-004/FR-005: três leitores, três disjuntos.
--
--   1) confirmada  -> pública, inclusive a Visitante sem cadastro (FR-001, FR-006).
--                     É a "identificação do Líder" do glossário.
--   2) a própria   -> a pessoa vê a SUA em qualquer estado, porque precisa saber
--                     se foi confirmada, rejeitada, ou se ainda espera (FR-002, FR-008).
--   3) Administrador do distrito -> vê todas, porque é ele quem decide (FR-003, FR-007).
--
-- Tudo que não cai em nenhum dos três é negado por default — que é o
-- comportamento de RLS e o que FR-005 pede.
--
-- Por que `rejeitado_em is null` no 1º disjunto, se `decidir_lideranca` já zera
-- o campo oposto (leadership.sql:55-62)? Porque a tabela NÃO tem `check`
-- impedindo os dois preenchidos (leadership.sql:3-13). Hoje a combinação é
-- inalcançável pelos caminhos com grant, mas o custo de escrever a conjunção é
-- uma linha, e o custo de errar é o dado que esta feature existe pra proteger.
-- Ver research.md D-001.
--
-- Forma copiada de `igrejas_select_ativas_publico`
-- (20260724092132_district_admin.sql:66-75): mesma estrutura
-- "condição pública `or` exists-admin", mesmo `to anon, authenticated`, já em
-- uso. Com role `anon`, `auth.uid()` é null, então os disjuntos 2 e 3 nunca
-- viram `true`.

drop policy if exists liderancas_select_public on public.liderancas;

create policy liderancas_select_confirmada_propria_ou_admin
  on public.liderancas for select
  to anon, authenticated
  using (
    (confirmado_em is not null and rejeitado_em is null)
    or usuario_id = auth.uid()
    or exists (
      select 1 from public.administradores_distrito
      where usuario_id = auth.uid()
    )
  );

comment on table public.liderancas is
  'Declaração de Líder/Diretor de Ministério, com título anual. Só a declaração '
  'confirmada é pública (CONTEXT.md, entrada Ministério: "Identificação do Líder '
  'é pública na página do Ministério"). Pendente e rejeitada são legíveis apenas '
  'pela própria pessoa e pelo Administrador do distrito — policy '
  'liderancas_select_confirmada_propria_ou_admin. Feature 018.';

-- INTOCADO de propósito, repetido aqui só como lembrete de que o delta NÃO mexe:
--
--   * `grant select on public.liderancas to anon, authenticated` — continua. É a
--     RLS que filtra, não o grant; tirar o grant derrubaria a página do Ministério.
--   * `declarar_lideranca` e `decidir_lideranca` — quem declara e quem confirma é
--     regra da feature 006 e não muda (Assumptions da spec: "a restrição vale para
--     leitura, não para escrita"). Funções `security definer` não passam por RLS,
--     então esta política não as afeta.
--   * Nada sobre `ano`. A expiração anual do título é comparação preguiçosa no
--     cliente (leadership_providers.dart:13-14 e leadership_declaration.dart:34-36),
--     não estado no banco — não há job nem coluna. A política ser cega para `ano` é
--     o que faz FR-009 ("a expiração NÃO DEVE ser alterada") ser verdade por
--     omissão: uma confirmada de 2025 continua legível em 2026, como a spec assume.
--     Ver research.md D-005.
--   * Nenhuma coluna nova, nenhum backfill, nada apagado. Declaração rejeitada
--     continua gravada; só deixa de ser legível por quem não tem motivo.
