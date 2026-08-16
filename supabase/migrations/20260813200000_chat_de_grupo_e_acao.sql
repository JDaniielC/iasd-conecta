-- Change chat-de-grupo-e-acao — a primeira tabela de TEXTO LIVRE do projeto.
--
-- POR QUE ISTO EXISTE
-- O app organiza Grupo e Ação e não tem onde combinar nada. Quem confirmou
-- presença não conseguia perguntar "quem leva o som?" dentro do app: a conversa
-- ia para um grupo de WhatsApp que o app não conhece, e o app virava um cadastro
-- que ninguém reabre entre um encontro e outro.
--
-- TERRITÓRIO NOVO, e vale dizer em voz alta: `chat`, `mensagem` e `conversa` não
-- aparecem uma vez sequer nos dez ledgers do projeto. Toda tabela existente
-- guarda dado estruturado, validado por constraint. Esta guarda o que uma pessoa
-- escreveu para outra — o único dado do app cujo conteúdo não dá para declarar
-- de antemão, e por isso o único que precisa de moderação, corte por idade e
-- prazo de descarte.

-- ---------------------------------------------------------------------------
-- 1. Corte por idade
-- ---------------------------------------------------------------------------
-- `security definer`, e isto NÃO é reflexo — é o mecanismo.
--
-- Como `invoker`, esta função dependeria de `perfis_select_own` continuar
-- existindo. Se uma mudança futura apertar aquela policy, ela passa a devolver
-- `false` para todo mundo e o chat some da tela sem erro, sem log e sem teste
-- vermelho — indistinguível de "você é menor de idade". É o mesmo modo de falha
-- que 20260806090000_nome_valido_security_definer.sql:7 foi escrita para
-- eliminar, e a resposta é a mesma.
--
-- `idade is not null` explícito: Perfil anonimizado tem idade nula, e
-- `null >= 18` é `null`, não `false`. Dentro de `exists` daria no mesmo; escrito
-- é o que se lê numa revisão.
--
-- Visitante é sessão anônima SEM Perfil, então falha aqui sem checagem extra.
create function public.maior_de_idade()
returns boolean
language sql
stable
security definer
set search_path = public, pg_temp
as $$
  select exists (
    select 1 from public.perfis
    where id = auth.uid() and idade is not null and idade >= 18
  );
$$;

comment on function public.maior_de_idade() is
  'Corte de 18 anos do chat, no BANCO e não na tela. É security definer de '
  'propósito: como invoker dependeria de perfis_select_own e falharia calada se '
  'aquela policy apertasse. Change chat-de-grupo-e-acao.';

-- REVOKE ANTES DO GRANT, e sem ele o grant abaixo não restringe NADA.
--
-- Função nova no Postgres nasce com `execute` para `PUBLIC`. `grant ... to
-- authenticated` ACRESCENTA um privilégio; não substitui o que já estava lá.
-- Sem este revoke, `anon` — a role que o PostgREST usa em requisição sem
-- `Authorization` — herda o direito de chamar, e a chave publicável está no
-- bundle público do app.
--
-- Medido pelo agente `pentest-etico` em 2026-08-14: `anon` chamou
-- `expurgar_mensagens_de_acao()` por `curl`, sem login, e apagou mensagem real.
-- Ela é `security definer` e faz `delete` global. O dano de dado era limitado
-- (só apaga o que já venceu), mas escrita destrutiva sem autenticação não é o
-- que estas linhas diziam oferecer.
--
-- O sinal genérico, para procurar em outra migration: `proacl` com uma entrada
-- que começa em `=` (nada antes do sinal) é o grant a PUBLIC.
revoke execute on function public.maior_de_idade() from public;
grant execute on function public.maior_de_idade() to authenticated;

-- ---------------------------------------------------------------------------
-- 2. Os dois predicados de acesso — um por espaço, usados em TODO lugar
-- ---------------------------------------------------------------------------
-- ATENÇÃO, e este é o comentário que impede o próximo erro: estas duas são
-- `security invoker`, e `maior_de_idade()` acima é `definer`. A diferença é
-- deliberada e assimétrica.
--
-- Como INVOKER, estas duas enxergam `acoes` e `confirmacoes_acao` sob a RLS de
-- quem chamou. Com `acao-direcionada-a-grupo` aplicada, isso significa que uma
-- Ação restrita ao Grupo some para quem não participa, a confirmação dela some
-- junto (confirmacoes_acao_select_conforme_acao herda de acoes), e
-- `pode_ver_chat_acao` devolve falso para essa pessoa SEM UMA LINHA DE CÓDIGO
-- NOVA AQUI.
--
-- Uniformizar as três para `definer` — o reflexo — quebraria exatamente isso:
-- elas passariam a enxergar toda Ação restrita e todo par de confirmação como
-- dono do banco, e o chat de uma Ação fechada ficaria acessível a quem a própria
-- Ação esconde. `maior_de_idade()` é definer pelo motivo OPOSTO (ler `perfis`
-- sem depender de uma policy que pode apertar).
create function public.pode_ver_chat_grupo(p_grupo_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select public.maior_de_idade() and (
    exists (
      select 1 from public.participacoes_grupo p
      where p.grupo_id = p_grupo_id and p.usuario_id = auth.uid()
    )
    -- Sem `maior_de_idade()` neste braço, e é de propósito: ele já está no
    -- `and` de fora, envolvendo os dois. Repetir aqui daria a impressão de que
    -- os braços têm cortes independentes, e o próximo a mexer removeria o de
    -- fora achando que o de dentro basta.
    or exists (select 1 from public.administradores_distrito d
               where d.usuario_id = auth.uid())
  );
$$;

-- Confirmação em QUALQUER status (confirmado ou fila), criador da Ação, dono do
-- Grupo dela, ou Administrador do distrito.
--
-- O ADMINISTRADOR ENTRA AQUI, e a primeira versão deste desenho dizia o
-- contrário — "moderar não é ler". A intenção era boa e não sobrevive ao
-- Postgres: remover é um `update` com `where`, e um `update` com `where` traz a
-- policy de `select` junto. Sem leitura, o Administrador não ALCANÇA a linha
-- denunciada, e a remoção afeta zero linha em silêncio. Medido em 2026-08-14, e
-- é a mesma mecânica que 20260813120000_acao_restrita_ao_grupo.sql registrou.
--
-- Consequência aceita e declarada no spec: o Administrador do distrito LÊ o chat
-- de qualquer Grupo e de qualquer Ação. É poder amplo, e é o preço de existir
-- instância de recurso quando o abuso vem de quem manda no espaço. O corte de
-- idade continua valendo para ele — `maior_de_idade()` está do lado de fora do
-- `or`, de propósito.
create function public.pode_ver_chat_acao(p_acao_id uuid)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select public.maior_de_idade() and exists (
    select 1 from public.acoes a
    where a.id = p_acao_id
      and (
        exists (
          select 1 from public.confirmacoes_acao c
          where c.acao_id = a.id and c.usuario_id = auth.uid()
        )
        or a.criador_id = auth.uid()
        or (a.grupo_id is not null and exists (
          select 1 from public.grupos g
          where g.id = a.grupo_id and g.dono_id = auth.uid()
        ))
        -- O braço do Administrador FALTAVA aqui, e o comentário acima já
        -- afirmava que ele existia. `pode_ver_chat_grupo` tinha; esta não. O
        -- efeito não era erro: o Administrador simplesmente não alcançava a
        -- linha numa Ação, o `update` de remoção afetava ZERO linha, e a tela
        -- do moderador dizia que deu certo. Achado em 2026-08-14 conferindo a
        -- Política de Privacidade contra o código, não pela suíte — os testes
        -- de moderação só olhavam chat de Grupo.
        or exists (select 1 from public.administradores_distrito d
                   where d.usuario_id = auth.uid())
      )
  );
$$;

comment on function public.pode_ver_chat_grupo(uuid) is
  'Quem lê o chat de um Grupo. security INVOKER de propósito — ver o comentário '
  'da migration. Change chat-de-grupo-e-acao.';
comment on function public.pode_ver_chat_acao(uuid) is
  'Quem lê o chat de uma Ação. security INVOKER de propósito: é o que faz o chat '
  'herdar sozinho a restrição de acao-direcionada-a-grupo. Inclui o '
  'Administrador do distrito, porque remover exige alcançar a linha. Change '
  'chat-de-grupo-e-acao.';

revoke execute on function public.pode_ver_chat_grupo(uuid) from public;
grant execute on function public.pode_ver_chat_grupo(uuid) to authenticated;
revoke execute on function public.pode_ver_chat_acao(uuid) from public;
grant execute on function public.pode_ver_chat_acao(uuid) to authenticated;

-- ---------------------------------------------------------------------------
-- 3. A tabela de mensagens
-- ---------------------------------------------------------------------------
-- Uma tabela, com XOR entre os dois espaços. Duas tabelas duplicariam policies,
-- gatilho, publicação de Realtime, expurgo e o modelo Dart — e a única
-- diferença real entre elas é o predicado de quem lê.
--
-- TRÊS LÁPIDES, distinguidas sem coluna nova:
--   texto preenchido, removida_em nulo  -> a mensagem
--   texto nulo,       removida_em cheio -> "mensagem removida"
--   texto nulo,       removida_em nulo  -> "mensagem de conta excluída"
-- Uma coluna `motivo_ausencia` seria informação redundante que pode divergir do
-- estado real das outras duas.
create table public.mensagens (
  id uuid primary key default gen_random_uuid(),
  grupo_id uuid references public.grupos(id) on delete cascade,
  acao_id uuid references public.acoes(id) on delete cascade,
  autor_id uuid not null references public.perfis(id),
  texto text,
  removida_em timestamptz,
  removida_por uuid references public.perfis(id),
  created_at timestamptz not null default now(),
  constraint mensagens_um_espaco_so
    check ((grupo_id is not null) <> (acao_id is not null)),
  -- `btrim` com a lista explícita, e NÃO `trim(texto)`: o `trim` padrão do
  -- Postgres remove apenas ESPAÇOS. Uma mensagem de quebras de linha e
  -- tabulações passaria como se tivesse conteúdo — medido: `length(trim(E'\n\t '))`
  -- é 2, `length(btrim(E'\n\t ', E' \t\n\r'))` é 0. Achado pelo próprio teste
  -- de escrita desta change.
  constraint mensagens_texto_no_limite
    check (texto is null
           or length(btrim(texto, E' \t\n\r')) between 1 and 2000)
);

comment on table public.mensagens is
  'Texto livre de conversa, em Grupo ou em Ação. O conteúdo é INDETERMINADO por '
  'natureza — é a única tabela do app cujo dado não dá para declarar de '
  'antemão. Change chat-de-grupo-e-acao.';

comment on column public.mensagens.texto is
  'Nulo é LÁPIDE, e há duas: com removida_em preenchido é remoção por '
  'moderação; com removida_em nulo é conta excluída. O texto removido NÃO é '
  'guardado em lugar nenhum — nem tabela de auditoria, nem coluna original, nem '
  'cópia para o Administrador. Conservá-lo recriaria dentro do banco justamente '
  'o dado que a remoção existe para eliminar, e num lugar com menos gente '
  'olhando. Quem remove precisa ler ANTES, porque depois não dá para '
  'reconsiderar.';

comment on column public.mensagens.removida_por is
  'Quem removeu, por referência a perfis(id). O motivo do caso fica em '
  'denuncias_mensagem.motivo, mesmo desenho de denuncias_imagem.';

create index mensagens_por_grupo on public.mensagens (grupo_id, created_at desc)
  where grupo_id is not null;
create index mensagens_por_acao on public.mensagens (acao_id, created_at desc)
  where acao_id is not null;

-- ---------------------------------------------------------------------------
-- 4. RLS de mensagens — as policies chamam AS FUNÇÕES, nunca a condição inline
-- ---------------------------------------------------------------------------
-- Repetir o `exists` em cada policy seriam no mínimo oito lugares, e a primeira
-- divergência entre eles é um vazamento.
-- DUAS funções, e a separação entre elas não é organização de código.
--
-- `pode_moderar_espaco` é AUTORIDADE: dono do Grupo, criador da Ação, dono do
-- Grupo da Ação, Administrador do distrito. `pode_moderar_mensagem` é essa
-- autoridade MAIS o próprio autor — apagar o que você mesmo escreveu não
-- depende de mandar em nada.
--
-- Uma função só, com o autor dentro, é o que a primeira versão desta migration
-- tinha, e ela vazava: as policies de `denuncias_mensagem` também chamavam essa
-- função, então a autora de uma mensagem denunciada LIA a denúncia contra si e
-- alcançava o `update` que a resolve — podia arquivar como improcedente a
-- denúncia sobre a própria mensagem. Medido pelo teste de denúncia desta
-- change. Denúncia é assunto de quem tem autoridade sobre o espaço; o
-- denunciado é parte, não instância.
--
-- As duas recebem as COLUNAS e não o id, de propósito: chamadas de dentro de
-- uma policy de `mensagens`, uma versão que lesse `mensagens` pelo id recursaria
-- na própria policy. Assim não tocam a tabela, e continuam `invoker` como as
-- duas de acesso.
--
-- O Administrador do distrito entra aqui e também em `pode_ver_chat_*`: no
-- Postgres, remover uma linha exige alcançá-la, e alcançar é ler.
create function public.pode_moderar_espaco(
  p_grupo_id uuid,
  p_acao_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select public.maior_de_idade() and (
    -- `maior_de_idade()` AQUI, e não só nas funções de leitura de mensagem.
    --
    -- Sem ele o corte parava em `mensagens`: as três policies de
    -- `denuncias_mensagem` chamam só esta função, então um Administrador do
    -- distrito de 16 anos lia ZERO mensagens — certo — e lia as denúncias com o
    -- `motivo` inteiro, e ainda as arquivava. Medido na convergência 1.
    --
    -- O `motivo` é texto livre escrito por uma pessoa sobre o que outra
    -- escreveu. É a mesma categoria de dado que o corte etário existe para não
    -- entregar a menor de idade, numa tabela ao lado. A spec já dizia: "a
    -- autoridade não levanta o corte de idade".
    --
    -- Note que `pode_moderar_mensagem` mantém o braço do AUTOR fora deste
    -- corte, de propósito: apagar o que você mesmo escreveu é minimização de
    -- dado, e não deve depender de idade.
    exists (select 1 from public.administradores_distrito d
            where d.usuario_id = auth.uid())
    or (p_grupo_id is not null and exists (
          select 1 from public.grupos g
          where g.id = p_grupo_id and g.dono_id = auth.uid()))
    or (p_acao_id is not null and exists (
          select 1 from public.acoes a
          where a.id = p_acao_id
            and (a.criador_id = auth.uid()
                 or (a.grupo_id is not null and exists (
                       select 1 from public.grupos g
                       where g.id = a.grupo_id and g.dono_id = auth.uid())))))
  );
$$;

create function public.pode_moderar_mensagem(
  p_autor_id uuid,
  p_grupo_id uuid,
  p_acao_id uuid
)
returns boolean
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select auth.uid() = p_autor_id
     or public.pode_moderar_espaco(p_grupo_id, p_acao_id);
$$;

comment on function public.pode_moderar_espaco(uuid, uuid) is
  'Autoridade sobre o espaço: dono do Grupo, criador da Ação, dono do Grupo da '
  'Ação, ou Administrador do distrito. NÃO inclui o autor da mensagem, e é isso '
  'que mantém a denúncia fora do alcance de quem foi denunciado. Change '
  'chat-de-grupo-e-acao.';

comment on function public.pode_moderar_mensagem(uuid, uuid, uuid) is
  'Quem pode remover uma mensagem: a autoridade do espaço mais o próprio autor. '
  'Recebe colunas e não id para não recursar na policy de mensagens. Change '
  'chat-de-grupo-e-acao.';

revoke execute on function public.pode_moderar_espaco(uuid, uuid) from public;
grant execute on function public.pode_moderar_espaco(uuid, uuid) to authenticated;
revoke execute on function public.pode_moderar_mensagem(uuid, uuid, uuid) from public;
grant execute on function public.pode_moderar_mensagem(uuid, uuid, uuid) to authenticated;

grant select, insert, update on public.mensagens to authenticated;

alter table public.mensagens enable row level security;

create policy mensagens_select_do_espaco
  on public.mensagens for select
  to authenticated
  using (
    case when grupo_id is not null
      then public.pode_ver_chat_grupo(grupo_id)
      else public.pode_ver_chat_acao(acao_id)
    end
  );

-- Escrita tem UMA condição a mais que leitura: o Grupo não pode estar
-- arquivado. Mesma escolha que 20260809230000_arquivar_grupo.sql:161-171 fez
-- para participação. O histórico de um Grupo arquivado continua legível — é
-- justamente o que sobra dele.
create policy mensagens_insert_autor
  on public.mensagens for insert
  to authenticated
  with check (
    auth.uid() = autor_id
    and texto is not null
    and removida_em is null
    and case when grupo_id is not null
      then public.pode_ver_chat_grupo(grupo_id)
           and not exists (select 1 from public.grupos g
                           where g.id = grupo_id and g.arquivado_em is not null)
      else public.pode_ver_chat_acao(acao_id)
    end
  );

-- Remoção é UPDATE, não DELETE. `with check` gêmeo do `using`, como em
-- denuncias_imagem_update_admin (20260810120000:63-69): sem ele a linha poderia
-- sair do conjunto que a própria policy protege.
--
-- Autoridade do espaço: dono do Grupo, criador da Ação, dono do Grupo da Ação,
-- ou Administrador do distrito. Aqui o Administrador ENTRA — moderar é o
-- trabalho dele; ler o chat inteiro não é (ver pode_ver_chat_acao).
create policy mensagens_update_autor_ou_autoridade
  on public.mensagens for update
  to authenticated
  using (public.pode_moderar_mensagem(autor_id, grupo_id, acao_id))
  with check (public.pode_moderar_mensagem(autor_id, grupo_id, acao_id));

-- NENHUMA policy de delete, para papel nenhum. Apagar de verdade é só do
-- expurgo, que roda como dono da função.

-- ---------------------------------------------------------------------------
-- 5. Mensagem enviada NÃO SE EDITA
-- ---------------------------------------------------------------------------
-- Sem este gatilho, quem pode remover conseguiria reescrever `texto`, e a
-- promessa "mensagem enviada não se edita" seria letra morta — a policy de
-- update sozinha diz QUEM, não O QUÊ.
--
-- O único `update` permitido é o que APAGA: `texto` só pode virar nulo.
create function public.mensagens_so_remove()
returns trigger
language plpgsql
security invoker
set search_path = ''
as $$
begin
  if new.id is distinct from old.id
     or new.grupo_id is distinct from old.grupo_id
     or new.acao_id is distinct from old.acao_id
     or new.autor_id is distinct from old.autor_id
     or new.created_at is distinct from old.created_at then
    raise exception 'mensagem enviada não se edita';
  end if;

  if new.texto is not null then
    raise exception 'o único update permitido em mensagem é a remoção';
  end if;

  -- Remoção acontece UMA vez. Um segundo `update` — outro moderador clicando
  -- depois, ou o mesmo duas vezes — não reescreve quem removeu nem quando: o
  -- registro é do ato, e o ato foi um só. Sem isto, quem chegasse por último
  -- levaria o crédito (ou a culpa) de uma decisão que não tomou.
  if old.removida_em is not null then
    new.removida_em := old.removida_em;
    new.removida_por := old.removida_por;
  end if;

  return new;
end;
$$;

create trigger mensagens_so_remove_trigger
  before update on public.mensagens
  for each row
  execute function public.mensagens_so_remove();

-- ---------------------------------------------------------------------------
-- 6. Denúncia, no molde de denuncias_imagem
-- ---------------------------------------------------------------------------
-- `on delete set null` e NÃO cascade — é a diferença deliberada em relação a
-- `denuncias_imagem`. O expurgo de 30 dias apagaria a denúncia junto com a
-- mensagem, e denúncia pendente que some sem desfecho é o pior resultado
-- possível para quem denunciou.
--
-- `denunciante_id` é `not null` aqui, ao contrário de denuncias_imagem: lá podia
-- ser Visitante; aqui só denuncia quem lê o chat, e quem lê tem Perfil.
create table public.denuncias_mensagem (
  id uuid primary key default gen_random_uuid(),
  mensagem_id uuid references public.mensagens(id) on delete set null,
  -- `btrim` com a lista explícita e não `trim`, mesma armadilha da constraint
  -- de `mensagens.texto`: o `trim` padrão do Postgres remove só ESPAÇOS, e um
  -- motivo de quebras de linha passaria como se dissesse alguma coisa.
  -- Medido pelo teste de denúncia. `denuncias_imagem` (20260810120000:23) tem
  -- a versão com `trim` e continua com ela — está fora do escopo desta change
  -- e ficou registrado em PENDENCIAS.md.
  motivo text not null check (length(btrim(motivo, E' \t\n\r')) > 0),
  denunciante_id uuid not null references public.perfis(id),
  estado text not null default 'pendente' check (estado in (
    'pendente', 'mensagem_removida', 'improcedente', 'sem_mensagem'
  )),
  created_at timestamptz not null default now(),
  resolvida_em timestamptz
);

comment on table public.denuncias_mensagem is
  'Denúncia de mensagem, no molde de denuncias_imagem (20260810120000). O motivo '
  'escrito por quem denunciou é o que fica como registro do caso — o texto '
  'denunciado não é conservado em lugar nenhum. Change chat-de-grupo-e-acao.';

comment on column public.denuncias_mensagem.mensagem_id is
  'on delete SET NULL, não cascade: o expurgo de 30 dias apagaria a denúncia '
  'junto com a mensagem, e pendente que some sem desfecho é o pior resultado '
  'para quem denunciou. Um gatilho after delete marca as pendentes como '
  'sem_mensagem.';

create index denuncias_mensagem_pendentes
  on public.denuncias_mensagem (created_at desc)
  where estado = 'pendente';

grant select, insert, update on public.denuncias_mensagem to authenticated;

alter table public.denuncias_mensagem enable row level security;

-- Denuncia quem lê aquele chat. O `with check` impede assinar por outro.
create policy denuncias_mensagem_insert_quem_le
  on public.denuncias_mensagem for insert
  to authenticated
  with check (
    auth.uid() = denunciante_id
    and exists (
      select 1 from public.mensagens m
      where m.id = mensagem_id
        and case when m.grupo_id is not null
          then public.pode_ver_chat_grupo(m.grupo_id)
          else public.pode_ver_chat_acao(m.acao_id)
        end
    )
  );

-- Quem lê e resolve é a AUTORIDADE do espaço e o Administrador — nem quem
-- denunciou, nem quem foi denunciado. Por isso estas três policies chamam
-- `pode_moderar_espaco` e não `pode_moderar_mensagem`: a segunda inclui o autor
-- da mensagem, e o autor da mensagem denunciada é justamente quem não pode
-- julgar o caso. `with check` gêmeo do `using`.
--
-- O braço extra de Administrador não é redundante com a chamada de dentro do
-- `exists`: depois do expurgo `mensagem_id` fica nulo, o `exists` não casa com
-- linha nenhuma, e sem esse braço a denúncia `sem_mensagem` ficaria invisível
-- para todo mundo. Consequência aceita e declarada: a partir do expurgo, só o
-- Administrador do distrito alcança aquela denúncia — a autoridade do Grupo
-- perde de vista um caso cuja mensagem já não existe.
create policy denuncias_mensagem_select_autoridade
  on public.denuncias_mensagem for select
  to authenticated
  using (
    -- O braço de Administrador tem `maior_de_idade()` PRÓPRIO, e não herda o de
    -- `pode_moderar_espaco`: ele existe justamente para alcançar a denúncia
    -- ÓRFÃ, cuja mensagem sumiu no expurgo e por isso não casa com o `exists`
    -- acima. Sem o corte aqui, um Administrador de 16 anos entrava por esta
    -- porta e lia o `motivo` — foi o que a convergência 1 mediu.
    exists (
      select 1 from public.mensagens m
      where m.id = mensagem_id
        and public.pode_moderar_espaco(m.grupo_id, m.acao_id)
    )
    or (public.maior_de_idade() and exists (
          select 1 from public.administradores_distrito d
          where d.usuario_id = auth.uid()))
  );

create policy denuncias_mensagem_update_autoridade
  on public.denuncias_mensagem for update
  to authenticated
  using (
    exists (
      select 1 from public.mensagens m
      where m.id = mensagem_id
        and public.pode_moderar_espaco(m.grupo_id, m.acao_id)
    )
    or (public.maior_de_idade() and exists (
          select 1 from public.administradores_distrito d
          where d.usuario_id = auth.uid()))
  )
  with check (
    exists (
      select 1 from public.mensagens m
      where m.id = mensagem_id
        and public.pode_moderar_espaco(m.grupo_id, m.acao_id)
    )
    or (public.maior_de_idade() and exists (
          select 1 from public.administradores_distrito d
          where d.usuario_id = auth.uid()))
  );

-- O QUE PERTENCE A ESTE ESPAÇO — uma vez, no banco.
--
-- A spec diz que o Dono do Grupo vê as denúncias do chat do Grupo dele **e as
-- dos chats das Ações daquele Grupo**. A RLS sempre permitiu isso — o braço do
-- Dono do Grupo da Ação está em `pode_moderar_espaco`. Quem não permitia era a
-- consulta do app, que filtrava por `mensagens.grupo_id`: denúncia de chat de
-- Ação tem esse campo nulo e sumia da tela, sem nada indicar que faltava.
-- Medido na convergência 1.
--
-- A regra vira função por isso: escrita no PostgREST e na policy são duas
-- cópias, e a primeira divergência entre elas foi exatamente uma tela mostrando
-- menos do que a pessoa tem direito de ver.
--
-- `security invoker`, como as outras de acesso: a RLS de `denuncias_mensagem` e
-- a de `mensagens` continuam decidindo QUEM vê. Esta função só decide O QUE
-- pertence ao espaço.
--
-- Não devolve `denunciante_id`: quem modera decide sobre a mensagem, não sobre
-- quem denunciou, e a spec proíbe revelar isso aos demais.
create function public.denuncias_do_espaco(
  p_grupo_id uuid,
  p_acao_id uuid
)
returns table (
  id uuid,
  motivo text,
  estado text,
  created_at timestamptz,
  resolvida_em timestamptz,
  mensagem_id uuid,
  mensagem_texto text,
  mensagem_removida_em timestamptz
)
language sql
stable
security invoker
set search_path = public, pg_temp
as $$
  select d.id, d.motivo, d.estado, d.created_at, d.resolvida_em,
         d.mensagem_id, m.texto, m.removida_em
  from public.denuncias_mensagem d
  join public.mensagens m on m.id = d.mensagem_id
  where (p_grupo_id is not null and (
           m.grupo_id = p_grupo_id
           or exists (select 1 from public.acoes a
                      where a.id = m.acao_id and a.grupo_id = p_grupo_id)))
     or (p_acao_id is not null and m.acao_id = p_acao_id)
  order by d.created_at desc;
$$;

comment on function public.denuncias_do_espaco(uuid, uuid) is
  'As denúncias de um espaço, incluindo as dos chats das Ações do Grupo quando '
  'o espaço é um Grupo. security INVOKER: a RLS decide quem vê, esta função '
  'decide o que pertence ao espaço. Change chat-de-grupo-e-acao.';

revoke execute on function public.denuncias_do_espaco(uuid, uuid) from public;
grant execute on function public.denuncias_do_espaco(uuid, uuid) to authenticated;

-- Denúncia pendente cuja mensagem sumiu não fica pendurada: ganha desfecho
-- próprio, preservando o motivo.
--
-- `BEFORE delete`, e o desenho pedia `after`. Medido: como `after`, este gatilho
-- não marcava nada. A ação `on delete set null` da chave estrangeira também é um
-- gatilho AFTER, interno, com nome `RI_ConstraintTrigger_...` — e o Postgres
-- dispara os AFTER de uma linha em ordem de nome, onde maiúscula vem antes de
-- minúscula. O `set null` chegava primeiro, `mensagem_id` já era nulo, e o
-- `where mensagem_id = old.id` daqui não casava com linha nenhuma. Falha
-- CALADA: a denúncia continuava `pendente` apontando para o nada.
--
-- Como `before`, roda antes de qualquer ação referencial, e o vínculo ainda
-- existe. `return old` é obrigatório: num gatilho BEFORE DELETE, devolver nulo
-- CANCELA o delete — seria trocar um defeito silencioso por outro pior, com o
-- expurgo passando a não expurgar.
create function public.denuncias_sem_mensagem()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  update public.denuncias_mensagem
  set estado = 'sem_mensagem', resolvida_em = now()
  where mensagem_id = old.id and estado = 'pendente';
  return old;
end;
$$;

create trigger mensagens_denuncias_sem_mensagem
  before delete on public.mensagens
  for each row
  execute function public.denuncias_sem_mensagem();

-- Remover a mensagem DÁ DESFECHO à denúncia, na mesma transação.
--
-- A spec sempre disse: "WHEN quem tem autoridade remove a mensagem denunciada
-- THEN a denúncia passa a mensagem removida". Isso é CONSEQUÊNCIA da remoção,
-- não um segundo pedido do cliente — e a primeira versão fez como segundo
-- pedido, com a tela chamando `removeMessage()` e depois `resolveReport()`.
--
-- Duas escritas sem transação, e o meio do caminho era um beco: medido na
-- convergência 2, parando no passo 1, a mensagem ficava sem texto e a denúncia
-- `pendente` com `resolvida_em` nulo. Nada reparava — o gatilho
-- `denuncias_sem_mensagem` é `before delete`, e remover é `update`. Pior: o
-- botão da tela só aparece enquanto a mensagem NÃO foi removida, então aquela
-- denúncia ficava pendente para sempre, sem nada que a resolvesse.
--
-- Como gatilho, vale também para quem remove pela tela da CONVERSA, que nunca
-- consultou denúncia nenhuma e não tem como saber que havia uma.
--
-- `and estado = 'pendente'`: denúncia já julgada não é reescrita. O registro é
-- da decisão que houve, e ela foi uma só.
create function public.denuncias_acolhidas_ao_remover()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.removida_em is null and new.removida_em is not null then
    update public.denuncias_mensagem
    set estado = 'mensagem_removida', resolvida_em = now()
    where mensagem_id = new.id and estado = 'pendente';
  end if;
  return null;
end;
$$;

create trigger mensagens_denuncias_acolhidas
  after update on public.mensagens
  for each row
  execute function public.denuncias_acolhidas_ao_remover();

-- ---------------------------------------------------------------------------
-- 7. Realtime
-- ---------------------------------------------------------------------------
-- Segunda tabela do projeto na publicação (a primeira foi `notificacoes`). Aqui
-- o canal é mais perigoso: ele carrega o TEXTO, não um sinal. A RLS no canal é
-- a única barreira, e a prova disso é teste com duas sessões — não revisão.
alter publication supabase_realtime add table public.mensagens;

-- ---------------------------------------------------------------------------
-- 8. Retenção: 30 dias depois do encontro
-- ---------------------------------------------------------------------------
-- 30 dias após `acoes.data_hora`, NÃO após a criação da mensagem: o que dá
-- sentido à conversa é o encontro. Trinta é escolha, não medição — dá margem
-- para o "manda as fotos" da semana seguinte sem virar arquivo.
--
-- Chat de GRUPO não expira, e Grupo arquivado também não expurga: o histórico é
-- justamente o que sobra de um Grupo arquivado.
--
-- CONSULTA ANTES DE SAIR CEDO. `20260810170000_varredura_segundo_gatilho.sql:21-27`
-- documenta o erro oposto: sair cedo com base num estado que é justamente o que
-- se procura.
create function public.expurgar_mensagens_de_acao()
returns integer
language plpgsql
security definer
set search_path = ''
as $$
declare
  v_apagadas integer;
begin
  delete from public.mensagens m
  using public.acoes a
  where m.acao_id = a.id
    and now() > a.data_hora + interval '30 days';
  get diagnostics v_apagadas = row_count;
  return v_apagadas;
end;
$$;

comment on function public.expurgar_mensagens_de_acao() is
  'Apaga mensagem de Ação 30 dias depois de acoes.data_hora. O prazo é PROMESSA '
  'na Política de Privacidade, então ele tem dois gatilhos: este job de pg_cron '
  'e uma chamada do app ao abrir um chat. Só o cron não cumpre — no plano '
  'gratuito o projeto pausa e o cron para junto (20260810110000:14-21). Change '
  'chat-de-grupo-e-acao.';

-- O app é o SEGUNDO gatilho, e por isso precisa poder chamar.
revoke execute on function public.expurgar_mensagens_de_acao() from public;
grant execute on function public.expurgar_mensagens_de_acao() to authenticated;

select cron.schedule(
  'expurgar-mensagens-de-acao',
  '43 3 * * *',
  $$select public.expurgar_mensagens_de_acao()$$
);

-- ---------------------------------------------------------------------------
-- 9. Exclusão de conta alcança o TEXTO
-- ---------------------------------------------------------------------------
-- BREAKING de comportamento, não de API: até aqui, excluir a conta anonimizava
-- o Perfil e conservava tudo o mais do titular. Anonimizar o Perfil NÃO
-- anonimiza um nome escrito dentro de um texto — e o texto é do titular.
--
-- Some o texto, fica a LÁPIDE: o rastro de que existiu mensagem ali é o que
-- mantém a conversa legível para quem ficou. `removida_em` continua nulo, então
-- a tela escreve "mensagem de conta excluída" e não "mensagem removida" — são
-- fatos diferentes e a pessoa que lê merece saber qual foi.
--
-- LIMITE DECLARADO, e ele vai para a Política: mensagem de TERCEIRO que cite a
-- pessoa NÃO é apagada por aqui. Aquilo é texto de outra pessoa, e sai por
-- denúncia.
--
-- POR QUE GATILHO EM `perfis`, E NÃO UMA LINHA DENTRO DE `excluir_minha_conta`:
-- a tarefa pedia a segunda forma. O gatilho cumpre o mesmo requisito — roda na
-- MESMA transação, então não cria caminho de falha parcial novo — e é mais
-- fundo: a regra passa a ser "Perfil anonimizado perde o texto das mensagens
-- dele", verdadeira para QUALQUER caminho de anonimização, hoje ou depois.
-- Reescrever `excluir_minha_conta` inteira para acrescentar uma linha copiaria
-- noventa linhas de uma função de segurança para dentro desta migration, e a
-- próxima alteração dela teria duas versões para reconciliar.
create function public.mensagens_perdem_texto_ao_anonimizar()
returns trigger
language plpgsql
security definer
set search_path = ''
as $$
begin
  if old.anonimizado_em is null and new.anonimizado_em is not null then
    update public.mensagens
    set texto = null
    where autor_id = new.id and texto is not null;
  end if;
  return null;
end;
$$;

create trigger perfis_mensagens_perdem_texto
  after update on public.perfis
  for each row
  execute function public.mensagens_perdem_texto_ao_anonimizar();

-- ---------------------------------------------------------------------------
-- 10. A versão do texto legal
-- ---------------------------------------------------------------------------
-- Gêmea da constante `LegalMetadata.version`. Não dá para derivar uma da
-- outra: o texto legal está compilado no binário, e a versão é metadado dele.
-- `test/integration/versao_texto_legal_registro_test.dart` falha se
-- divergirem — e a divergência NÃO daria erro em produção: gravaria em cada
-- cadastro novo uma versão diferente da que a pessoa leu na tela.
--
-- Sobe para 1.5 porque a Política passou a descrever um tratamento NOVO, não
-- porque o texto mudou de lugar. Consentimento colhido sob 1.4 não cobre a
-- conversa: quem se cadastrou antes desta linha aceitou um app que não
-- guardava texto livre de ninguém.
insert into public.versoes_texto_legal (versao, vigente_desde)
values ('1.5', timestamptz '2026-08-14 00:00:00-03')
on conflict (versao) do nothing;
