# Phase 1 — Data Model: visibilidade do voto

**Feature**: 021-visibilidade-do-voto | **Data**: 2026-08-09

## Nenhuma entidade nova, nenhuma coluna nova

A feature não adiciona, remove nem renomeia nada. A tabela
(`20260724084300_rodada_votacao.sql:21-27`) continua exatamente assim:

```sql
create table public.votos (
  rodada_id    uuid not null references public.rodadas_votacao(id) on delete cascade,
  usuario_id   uuid not null references public.perfis(id)          on delete cascade,
  candidata_id uuid not null references public.acoes(id)           on delete cascade,
  updated_at   timestamptz not null default now(),
  primary key (rodada_id, usuario_id)
);
```

O que muda é uma linha de política. Este documento existe para registrar **o que a
estrutura já significa**, porque é isso que torna o vazamento grave.

## Por que estes três campos juntos são dado sensível

A chave primária `(rodada_id, usuario_id)` garante **um voto por pessoa por Rodada**. Isso é
o que faz a revogabilidade funcionar por `upsert` — e é também o que faz cada linha ser um
fato completo sobre uma pessoa identificada.

`usuario_id` referencia `perfis(id)`, e `perfis` tem nome. `candidata_id` referencia
`acoes(id)`, e Ação candidata tem nome e quem a propôs. Uma linha de `votos` não é um dado
técnico: lida junto com as duas tabelas que ela referencia, ela diz **"Fulana escolheu a
proposta de Beltrana, e não a sua"** — dentro de um Grupo de gente que se conhece.

Nenhum agregado protege isso: a tabela não guarda contagem, guarda o par nominal.

## Estados

`votos` não tem máquina de estados. Uma linha só existe ou não existe, e seu
`candidata_id` é substituído quando a pessoa troca de voto. O ciclo de vida completo:

| Evento | Efeito na linha |
|---|---|
| Pessoa vota pela primeira vez | Linha criada |
| Pessoa troca de candidata | `candidata_id` e `updated_at` substituídos, mesma linha |
| Rodada fecha | Nada. A linha permanece |
| Candidata perdedora é descartada (`rodada_votacao.sql:177-179`) | Linha some por `on delete cascade` de `acoes` |
| Pessoa exclui a conta | Votos de Rodadas em aberto são apagados pela feature 009; os demais permanecem apontando para um Perfil anonimizado |

**Consequência que importa para esta feature**: depois que a Rodada fecha, sobram na tabela
os votos da candidata **vencedora** — os das perdedoras foram em cascata. Ou seja, o que
resta legível é "quem votou na vencedora", que é justamente a informação que identifica
quem **não** votou nela por ausência. A visibilidade precisa valer depois do fechamento
(FR-006), não só durante.

## Matriz de acesso — antes e depois

| Quem | Hoje | Depois |
|---|---|---|
| Visitante sem cadastro | Lê **todos** os votos de **todas** as Rodadas | Nenhum |
| Usuário cadastrado, fora do Grupo | Todos | Nenhum |
| Usuário cadastrado, participante do Grupo | Todos | Só o próprio |
| A própria pessoa | O próprio (entre todos) | Só o próprio |
| Apuração (`fechar_rodada_se_devido`) | Todos | **Todos** — roda como `postgres`, fora da RLS |

A última linha é a que sustenta o Princípio IV. Ela não depende de política nenhuma, e a
research.md registra a medição que prova isso.

## Escrita — sem alteração

| Operação | Política | Muda? |
|---|---|---|
| Inserir voto | `votos_insert_self` — `with check (auth.uid() = usuario_id)` | Não |
| Trocar de voto | `votos_update_self` — `using` e `with check (auth.uid() = usuario_id)` | Não |
| Apagar voto | Sem política e sem `grant`; só via cascade ou `security definer` | Não |

Verificado que a escrita sobrevive à leitura apertada, incluindo o `upsert` de troca de
voto e a rejeição de quem tenta sobrescrever voto alheio (`ERROR: new row violates
row-level security policy for table "votos"`). Medições em research.md, Decisão 4.

## Invariantes que a implementação não pode quebrar

1. Uma pessoa lê a própria linha em qualquer momento — antes, durante e depois do
   fechamento da Rodada.
2. Ninguém lê linha alheia, em nenhum momento, por nenhum caminho que passe pela RLS.
3. A apuração conta **todas** as linhas da Rodada, independentemente de quem chamou.
4. Trocar de voto substitui a linha existente; só a última escolha conta.
5. Uma resposta vazia não revela, por tamanho nem por erro, quantas linhas foram escondidas
   — o filtro de RLS devolve conjunto vazio, não erro de permissão.
