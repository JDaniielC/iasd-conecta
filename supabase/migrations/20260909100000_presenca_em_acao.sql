-- Change `presenca-em-acao`, parte 1 de 3 — o esqueleto.
--
-- Só as colunas, a tabela de contestação e a view que define o que conta.
-- NENHUMA policy de escrita: sem policy, a RLS nega, e todo `update` de
-- `authenticated` afeta zero linhas.
--
-- A DIVISÃO EM TRÊS MIGRATIONS EXISTE PELO VERMELHO, e não por estética.
-- Com tudo junto, o primeiro `dart test` falha com `column ... does not exist`
-- em todos os casos — obstáculo, não requisito. Um vermelho desses fica verde
-- assim que a coluna nasce, com a regra ainda por escrever. Com o esqueleto
-- primeiro, o vermelho passa a ser `Expected: 1 Actual: 0` no caminho feliz:
-- contagem errada, que é o vermelho que a constituição (Princípio IV) exige.
--
-- POR QUE COLUNA EM `confirmacoes_acao`, E NÃO TABELA NOVA (design D-001)
-- A PK `(acao_id, usuario_id)` já é exatamente "esta pessoa nesta Ação". Uma
-- tabela `presencas` repetiria a chave e abriria a possibilidade de presença
-- sem confirmação — que a spec proíbe de propósito: criar confirmação em nome
-- de terceiro seria afirmar sobre ele um ato que ele não praticou.

-- ---------------------------------------------------------------------------
-- 1. Comparecimento
-- ---------------------------------------------------------------------------

alter table public.confirmacoes_acao
  add column compareceu_em timestamptz,
  add column marcado_por uuid references public.perfis(id),
  add column contestada_em timestamptz;

comment on column public.confirmacoes_acao.compareceu_em is
  'Instante em que quem criou a Ação afirmou que esta pessoa esteve nela. '
  'NULO SIGNIFICA NÃO REGISTRADO, NUNCA AUSENTE — a ausência só existe depois '
  'de acoes.presenca_fechada_em, e nada converte um pelo outro por decurso de '
  'prazo. Mesma doutrina de perfis.consentimento_lgpd_versao, onde nulo é '
  'desconhecida e nunca um palpite. Change presenca-em-acao.';

comment on column public.confirmacoes_acao.marcado_por is
  'Quem afirmou o comparecimento. Carimbado por gatilho a partir de auth.uid() '
  'e NUNCA concedido ao cliente: com grant, quem marca poderia atribuir a '
  'outra pessoa a afirmação que ele mesmo fez. Referencia perfis(id) para '
  'herdar a anonimização de excluir_minha_conta, como fixada_por e '
  'removida_por. Change presenca-em-acao.';

comment on column public.confirmacoes_acao.contestada_em is
  'Instante da primeira contestação sobre esta linha. Escrito por gatilho e '
  'NUNCA limpo — nem quando a contestação é negada. É redundante com '
  'contestacoes_presenca de propósito (design D-003): a regra "linha '
  'contestada nunca conta" vive em consultas que ainda não foram escritas, e '
  'com a coluna a exclusão é um `where contestada_em is null` que se escreve '
  'por reflexo. Change presenca-em-acao.';

-- ---------------------------------------------------------------------------
-- 2. Fechamento da lista
-- ---------------------------------------------------------------------------

alter table public.acoes
  add column presenca_fechada_em timestamptz,
  add column presentes_no_fechamento integer;

comment on column public.acoes.presenca_fechada_em is
  'Instante em que quem criou a Ação fechou a lista de comparecimento. É o ATO '
  'que converte o que não foi marcado em ausência. Sem ele, a Ação fica fora '
  'de numerador E denominador de qualquer contagem de envolvimento. Não há '
  'fechamento automático por prazo: máquina nenhuma converte desconhecido em '
  'ausente. Change presenca-em-acao.';

comment on column public.acoes.presentes_no_fechamento is
  'Quantas pessoas constavam como presentes NO MOMENTO DO FECHAMENTO. É fato '
  'datado, não consulta: gravado pelo gatilho de fechamento para que o '
  'histórico do ministério sobreviva à faxina de retenção que apaga as linhas '
  'nominais dois anos depois. Change presenca-em-acao.';

-- ---------------------------------------------------------------------------
-- 3. Contestação — append-only, no padrão de `denuncia-como-registro`
-- ---------------------------------------------------------------------------

create table public.contestacoes_presenca (
  acao_id uuid not null references public.acoes(id) on delete cascade,
  usuario_id uuid not null references public.perfis(id) on delete cascade,
  contestada_em timestamptz not null default now(),
  decisao text check (decisao in ('mantida', 'desfeita')),
  decidida_em timestamptz,
  decidida_por uuid references public.perfis(id),
  primary key (acao_id, usuario_id)
);

comment on table public.contestacoes_presenca is
  'Contestação do titular sobre a afirmação de comparecimento feita por outra '
  'pessoa. Comparecimento é o PRIMEIRO dado deste app escrito por terceiro '
  'sobre o titular — mensagens.texto é do autor, denuncias_mensagem.motivo é '
  'de quem denuncia — e esta tabela existe para equilibrar isso. Nem a '
  'contestação nem a decisão se apagam ou se reescrevem: registro não se '
  'reescreve (change denuncia-como-registro). O efeito na métrica NÃO depende '
  'da decisão: linha contestada sai da contagem para sempre, tenha o criador '
  'mantido ou desfeito a marca. Change presenca-em-acao.';

alter table public.contestacoes_presenca enable row level security;

grant select on public.contestacoes_presenca to authenticated;

-- ---------------------------------------------------------------------------
-- 4. A view que define o que conta (design D-009)
-- ---------------------------------------------------------------------------
--
-- NÃO É MÉTRICA. Não agrega, não classifica ninguém, não sabe o que é
-- afastamento. É a definição de "esta linha conta", num lugar só, para que a
-- change que construir a métrica não precise reescrever a regra — e não possa
-- reescrevê-la errado.
--
-- `security_invoker` como `notificacoes_ativas`: quem lê vê o que a RLS de
-- `confirmacoes_acao` já lhe permite. Sem isso a view ignoraria a RLS da
-- tabela base. Quem decide quem vê métrica é a change que criar a métrica.

create view public.presencas_computaveis
with (security_invoker = true) as
  select
    c.acao_id,
    c.usuario_id,
    c.compareceu_em is not null as presente
  from public.confirmacoes_acao c
  join public.acoes a on a.id = c.acao_id
  where a.presenca_fechada_em is not null
    and c.contestada_em is null;

comment on view public.presencas_computaveis is
  'As linhas de comparecimento que CONTAM: só de Ação com a lista fechada, e '
  'só as nunca contestadas. Ação não fechada fica fora do numerador E do '
  'denominador — não é que ninguém tenha faltado, é que ninguém sabe. Change '
  'presenca-em-acao, design D-009.';

grant select on public.presencas_computaveis to authenticated;

-- ---------------------------------------------------------------------------
-- 5. O grant, recortado por coluna. A POLICY VEM NA PARTE 2.
-- ---------------------------------------------------------------------------
--
-- `grant` e policy são as DUAS barreiras, e nesta migration só a primeira
-- existe: `authenticated` pode citar `compareceu_em` na cláusula SET, e a RLS
-- nega a linha porque não há policy de `update`. O efeito é `affectedRows = 0`
-- em todo caminho — inclusive no feliz, que é o vermelho que a parte 2 vai
-- resolver.
--
-- `marcado_por` e `contestada_em` ficam de fora do grant DE PROPÓSITO, e não
-- por esquecimento: quem escreve os dois é gatilho. Conceder `marcado_por`
-- deixaria quem marca atribuir a outra pessoa a afirmação que ele mesmo fez —
-- o mesmo defeito que perfis_carimbar_consentimento evita do outro lado, ao
-- descartar a versão que o cliente manda.
--
-- O `grant` restringe a cláusula SET inteira, coisa que uma policy com
-- `with check` não faz. Padrão de 20260811160000_grant_update_perfis_por_coluna
-- e 20260817120000_mensagens_insert_por_coluna.

grant update (compareceu_em) on public.confirmacoes_acao to authenticated;

grant update (presenca_fechada_em) on public.acoes to authenticated;

grant insert (acao_id, usuario_id) on public.contestacoes_presenca
  to authenticated;

grant update (decisao) on public.contestacoes_presenca to authenticated;
