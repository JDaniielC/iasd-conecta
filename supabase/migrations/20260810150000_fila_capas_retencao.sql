-- Feature 013 — o que acontece com as linhas já drenadas de capas_a_remover.
--
-- Decisão: **elas ficam.** Uma linha por imagem já removida, para sempre.
--
-- Por quê, e por que isso não vira dívida:
--
-- 1. O volume é desprezível. É um distrito de 15+ igrejas; são dezenas a
--    poucas centenas de imagens por ano, uma linha curta cada. Um `pg_cron`
--    de expurgo seria mais peça do que o Princípio V justifica para isso.
--
-- 2. A consulta que importa **não enxerga** as linhas drenadas. O índice
--    `capas_a_remover_pendentes` é PARCIAL, `where removido_em is null`, então
--    a checagem de fila parada de INFRA-PRODUCAO.md § 3 continua rápida por
--    mais que a tabela cresça. Crescimento aqui não degrada nada.
--
-- 3. Não há dado pessoal. O caminho é `grupo/<uuid>/<arquivo>` ou
--    `acao/<uuid>/<arquivo>` — identificador de Grupo/Ação, nunca de pessoa.
--    A coluna `enviada_por` fica em `fotos_capa`, que **é** apagada; a fila
--    nunca soube quem enviou.
--
-- O que fica registrado é a decisão, não o silêncio: sem esta nota, quem ler a
-- tabela daqui a um ano não sabe se a permanência é desenho ou esquecimento.
-- Se um dia o volume incomodar, expurgar `where removido_em < now() - interval
-- 'N days'` é seguro — nenhuma outra coisa lê essas linhas.

comment on table public.capas_a_remover is
  'Arquivos de capa cuja linha já sumiu e que ainda precisam sair do bucket. '
  'Linha com removido_em nulo há muito tempo é um órfão em potencial — é isso '
  'que torna SC-005 verificável por consulta, em vez de exigir varrer o '
  'bucket; a consulta está em INFRA-PRODUCAO.md § 3. Linhas já drenadas NÃO '
  'são expurgadas, por decisão: o volume é desprezível, o índice de pendentes '
  'é parcial (o crescimento não afeta a consulta) e não há dado pessoal aqui. '
  'Feature 013.';

comment on column public.capas_a_remover.tentativas is
  'Quantas vezes a drenagem tentou e a API NÃO confirmou a remoção deste '
  'caminho. Incrementada uma a uma, por linha: é a diferença entre as '
  'contagens que denuncia o arquivo que falha desde sempre no meio de falhas '
  'transitórias. Contagem alta e parada significa que este caminho não sai — '
  'bucket errado, ou objeto que já não existe.';
