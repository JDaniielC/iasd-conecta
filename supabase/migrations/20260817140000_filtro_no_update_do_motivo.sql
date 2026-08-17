-- Change filtro-e-intervalo-de-mensagem, Convergence 3 — o filtro do `motivo`
-- valia só na inserção.
--
-- MEDIDO EM 2026-08-17, como `authenticated`, pelo caminho de verdade: o dono
-- de um Grupo pegou uma denúncia com motivo limpo e reescreveu o `motivo` para
-- uma palavra da lista. O banco **ACEITOU**.
--
--   update public.denuncias_mensagem set motivo = 'seu <palavra>' where id = ...
--   -> ACEITO
--
-- `denuncias_mensagem_filtro_de_palavra_trigger` era `before INSERT` e mais
-- nada (um único gatilho na tabela, conferido em `pg_trigger`), e
-- `authenticated` tem `update` na coluna `motivo`
-- (`information_schema.column_privileges`), liberado pela policy
-- `denuncias_mensagem_update_autoridade`.
--
-- O CONTRASTE é o que torna isto nítido: a mesma tentativa em `mensagens.texto`
-- foi RECUSADA no mesmo ensaio, porque `mensagens_so_remove` guarda as colunas
-- uma a uma. A tabela irmã nunca ganhou o equivalente — ver PENDENCIAS.md 2.24
-- para a parte que continua aberta e não é desta change.
--
-- `WHEN (new.motivo is distinct from old.motivo)` NÃO É OTIMIZAÇÃO. Sem ele,
-- `ChatRepository.resolveReport` — que toca só `estado` e `resolvida_em` —
-- reavaliaria um `motivo` que ninguém pediu para mudar. Uma denúncia gravada
-- ANTES de a palavra entrar na lista passaria a ser IMPOSSÍVEL DE RESOLVER: o
-- moderador clicaria em "improcedente" e levaria PT422 sobre um texto que não
-- escreveu e não pode editar. A moderação travaria justamente nos casos mais
-- velhos, que são os que mais precisam de desfecho.
--
-- DOIS GATILHOS E NÃO UM `insert or update`, e não é gosto: o Postgres recusa
-- `when` que cite `OLD` num gatilho que também dispare em `insert`, porque ali
-- `OLD` não existe. Medido ao escrever esta migration:
--
--   ERROR: 42P17 ... when (new.motivo is distinct from old.motivo)
--
-- Então o de `insert` fica como estava — sem `when`, porque toda linha nova
-- precisa passar — e o de `update` ganha a guarda.
--
-- A FUNÇÃO é a mesma nos dois: ela lê `new.motivo` e nada mais, então serve aos
-- dois momentos sem uma linha de diferença. Duplicá-la seria criar a cópia que
-- diverge.
create trigger denuncias_mensagem_filtro_de_palavra_no_update
  before update on public.denuncias_mensagem
  for each row
  when (new.motivo is distinct from old.motivo)
  execute function public.denuncias_mensagem_filtro_de_palavra();
