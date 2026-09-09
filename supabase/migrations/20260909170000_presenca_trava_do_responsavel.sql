-- Change `presenca-em-acao`, correção do achado C-1 da convergência 1.
--
-- O DEFEITO, MEDIDO EM 2026-09-09
-- `pode_registrar_presenca` olhava só `consentimento_lgpd_versao`. Para menor de
-- `limiar_crianca()` (13 anos), quem consente pelo tratamento NÃO é a criança —
-- é o responsável, e a autorização dele tem versão própria,
-- `autorizacao_responsavel_versao`.
--
-- A consequência era esta, e ela foi reproduzida antes da correção: uma criança
-- de 10 anos, cujo responsável autorizou o texto 1.10, tocava "Aceitar" no aviso
-- da Home; o gatilho carimbava `consentimento_lgpd_versao = '1.11'`; a
-- autorização do responsável continuava em '1.10'; e a coleta de presença sobre
-- ela passava a ser permitida. Uma criança destravando, sozinha, o tratamento
-- que só o responsável dela pode autorizar.
--
-- LGPD art. 14, §1º: tratamento de dado de criança depende de consentimento
-- ESPECÍFICO E EM DESTAQUE dado por um dos pais ou responsável. Um toque da
-- própria criança não é isso, por definição.
--
-- E A AUTORIZAÇÃO NÃO TEM COMO SER ATUALIZADA, o que muda o que "recusar"
-- significa aqui. `perfis_protege_autorizacao_responsavel`
-- (`20260810000000:160-176`) levanta exceção em qualquer mudança nas quatro
-- colunas do responsável — a coluna é imutável depois de escrita. Então isto
-- NÃO é um atraso que o reaceite resolve: criança cadastrada sob texto anterior
-- fica permanentemente fora do registro de comparecimento.
--
-- Isso está certo, e é deliberado. A feature 015 recusou de propósito construir
-- autorização retroativa, porque ela envolve COMO FALAR COM UMA CRIANÇA sobre
-- pedir autorização a um responsável, e isso não se improvisa numa migration. O
-- caminho, quando alguém decidir pagá-lo, é uma change própria — não uma
-- exceção aqui.

create or replace function public.pode_registrar_presenca(
  p_acao_id uuid,
  p_usuario_id uuid
)
returns boolean
language sql
security definer
stable
set search_path = ''
as $$
  select exists (
    select 1
    from public.acoes a
    join public.confirmacoes_acao c
      on c.acao_id = a.id and c.usuario_id = p_usuario_id
    join public.perfis p
      on p.id = p_usuario_id
    where a.id = p_acao_id
      -- Autoridade: só quem criou a Ação pergunta.
      and a.criador_id = (select auth.uid())
      -- Consentimento da própria pessoa, para qualquer idade.
      and p.consentimento_lgpd_versao = public.versao_texto_legal_vigente()
      -- E, abaixo do limiar de criança, TAMBÉM a autorização do responsável.
      -- `idade is null` é o Perfil anonimizado por `excluir_minha_conta`: sem
      -- idade não há como afirmar que o responsável autorizou, e não afirmar é
      -- o lado certo de errar.
      and (
        p.idade is not null
        and p.idade >= public.limiar_crianca()
        or p.autorizacao_responsavel_versao
             = public.versao_texto_legal_vigente()
      )
  );
$$;

comment on function public.pode_registrar_presenca(uuid, uuid) is
  'Diz se quem chama (o criador da Ação) pode registrar comparecimento desta '
  'pessoa. Exige a versão vigente no aceite da própria pessoa E, abaixo de '
  'limiar_crianca(), também em autorizacao_responsavel_versao — quem consente '
  'pelo tratamento de criança é o responsável, e um toque da própria criança '
  'no aviso de reaceite não é isso (LGPD art. 14, §1º). Como a autorização é '
  'imutável depois de escrita, criança cadastrada sob texto anterior fica '
  'permanentemente fora do registro, e isso é deliberado: autorização '
  'retroativa é change própria, recusada de propósito pela feature 015. '
  'Devolve só booleano. Achado C-1 da convergência 1 da change '
  'presenca-em-acao.';
