# Research: Ação Avulsa

## Status confirmado/fila decidido no banco, não no client

**Decision**: `confirmacoes_acao` tem coluna `status` (`confirmado`/`fila`)
preenchida por um trigger `BEFORE INSERT`, nunca enviada pelo client. O
trigger conta quantos `confirmado` já existem pra aquela Ação; se
`limite_vagas` for nulo ou a contagem for menor que o limite, status vira
`confirmado`; senão, `fila`.

**Rationale**: SC-005 ("0% das Ações passam do limite") precisa ser verdade
mesmo se o client tiver um bug ou alguém chamar a API direto — decisão de
capacidade não pode confiar em o client contar certo.

**Alternatives considered**: contar no client antes de inserir (rejeitado —
sujeito a corrida: dois clients podem contar a mesma vaga livre ao mesmo
tempo).

## Trava de concorrência: `SELECT ... FOR UPDATE` na Ação

**Decision**: o trigger de status faz `PERFORM 1 FROM acoes WHERE id =
NEW.acao_id FOR UPDATE` antes de contar confirmados. Isso serializa
confirmações concorrentes pra mesma Ação — a segunda transação espera a
primeira commitar antes de contar, evitando estourar o limite por corrida.

**Rationale**: sem essa trava, duas confirmações simultâneas pra última
vaga poderiam ambas ler "ainda cabe" e ambas virarem `confirmado`,
violando SC-005. Travar a linha pai (`acoes`) é o padrão padrão do Postgres
pra serializar inserts filhos que dependem de uma contagem agregada.

**Alternatives considered**: `SERIALIZABLE` isolation level pra toda
transação (rejeitado — muda o comportamento de toda a aplicação por causa
de uma tabela; a trava pontual resolve só o necessário, Princípio V).

**Nota de teste**: a trava é validada estruturalmente (existe no código,
revisada por leitura), mas testar uma corrida de verdade (dois inserts
simultâneos) exigiria orquestrar duas conexões concorrentes num teste —
fora do escopo dos testes automatizados desta feature. O que É testado
automaticamente é o comportamento sequencial correto (lotar, novo vira
fila, desistência promove o próximo).

## Criador vira confirmado automático (mesmo padrão de Grupo)

**Decision**: trigger `AFTER INSERT ON acoes` insere
`confirmacoes_acao (acao_id, usuario_id=criador_id)` — reaproveita
exatamente o padrão `grupos_dono_vira_participante` da feature 002.

**Rationale**: decisão de clarify (Q1) — consistência com o precedente já
estabelecido, sem inventar um mecanismo novo.

**Alternatives considered**: nenhuma — decisão já fechada no clarify.

## Promoção da fila: `SECURITY DEFINER`, porque mexe na linha de outro Usuário

**Decision**: o trigger `AFTER DELETE ON confirmacoes_acao` que promove o
próximo da fila (`UPDATE confirmacoes_acao SET status = 'confirmado' WHERE
acao_id = old.acao_id AND status = 'fila' ORDER BY created_at LIMIT 1`) é
`SECURITY DEFINER`. Sem isso, o `UPDATE` afetaria a linha de outra pessoa
(quem está na fila), e não há (nem deve haver) um `GRANT UPDATE` amplo em
`confirmacoes_acao` pra qualquer `authenticated` mexer na fila de qualquer
um.

**Rationale**: mesmo raciocínio de `perfil_publico()` na feature 001 —
`SECURITY DEFINER` é o jeito correto de um efeito colateral do sistema
(promoção automática) tocar dado de outro Usuário sem abrir uma brecha de
RLS genérica pra isso.

**Alternatives considered**: `GRANT UPDATE ON confirmacoes_acao TO
authenticated` com policy permissiva (rejeitado — abriria a porta pra
qualquer Usuário autenticado editar o status de qualquer confirmação de
qualquer um, muito mais amplo do que o necessário).

## Cancelamento não some com o histórico

**Decision**: `acoes.cancelada_em timestamptz` nullable. Cancelar é só
`UPDATE acoes SET cancelada_em = now()`. Nenhuma linha de
`confirmacoes_acao` é apagada.

**Rationale**: decisão já fechada na spec (Assumptions) — histórico de
quem confirmou antes do cancelamento continua consultável.

**Alternatives considered**: soft-delete com coluna booleana simples em vez
de timestamp (rejeitado — timestamp já dá "quando" de graça, mesmo custo).
