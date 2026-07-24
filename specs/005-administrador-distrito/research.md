# Research: Administrador do Distrito

## Papel modelado como tabela de associação, não coluna booleana

**Decision**: `administradores_distrito(usuario_id PK, promovido_por,
created_at)` — mesma forma de `participacoes_grupo`/`confirmacoes_acao`,
não um `perfis.eh_administrador boolean`.

**Rationale**: guarda de graça quem promoveu quem (auditoria mínima, útil
pra entender depois "quem trouxe esse Administrador pro papel"), e reusa o
padrão de tabela de associação já estabelecido no projeto (Princípio I —
consistência de convenção) em vez de inventar uma coluna solta.

**Alternatives considered**: `perfis.eh_administrador_distrito boolean`
(rejeitado — perde o histórico de quem promoveu, e cria um precedente
diferente de todas as outras associações já modeladas como tabela).

## "Precisa ter Conta" checado no banco via `auth.users`, não no client

**Decision**: o trigger de `administradores_distrito` lê
`auth.users.is_anonymous` diretamente. Precisa ser `SECURITY DEFINER` pra
isso — o papel `authenticated` não tem `GRANT` no schema `auth` (testado:
sem `SECURITY DEFINER`, a checagem falha com "permission denied for table
users"); o client também não tem acesso, porque `auth` não é exposto via
REST.

**Rationale**: mesma razão de `ContaGuard` na feature 001 já existir como
placeholder — a fonte de verdade de "tem Conta" é sempre
`auth.users.is_anonymous`, nunca uma cópia duplicada em `public`.

**Alternatives considered**: espelhar `is_anonymous` numa coluna em
`perfis` atualizada por trigger no próprio `auth.users` (rejeitado —
duplicaria estado que já existe, custo de manutenção sem necessidade,
Princípio V).

## Arquivar Igreja é `UPDATE`, nunca `DELETE`

**Decision**: `igrejas.arquivada_em timestamptz` nullable. Arquivar é só
`UPDATE igrejas SET arquivada_em = now()`. A `FK` de `perfis.igreja_id`,
`grupos.igreja_id` e `acoes.igreja_id` continuam apontando pra linha
intacta.

**Rationale**: já era a decisão registrada como Assumption na feature 002
("Igreja removida... Grupo existente mantém o vínculo antigo como
histórico") — esta feature só entrega o mecanismo (arquivar) que aquela
Assumption pressupunha existir um dia.

**Alternatives considered**: `DELETE` de verdade com `ON DELETE SET NULL`
nas FKs (rejeitado — perderia o nome da Igreja em vínculos históricos,
contradizendo a Assumption já registrada).

## Visibilidade de arquivadas: uma policy de `SELECT`, sem tabela espelho

**Decision**: a policy `igrejas_select_ativas_publico` substitui a
`igrejas_select_public` da feature 001: linha visível se `arquivada_em IS
NULL` OU o papel de quem consulta está em `administradores_distrito`.

**Rationale**: FR-007/FR-008 (Igreja arquivada some da lista pra
não-admin, mas admin continua vendo) resolvidos numa condição só, sem
precisar de uma view separada ou duplicar a tabela.

**Alternatives considered**: view `igrejas_ativas` separada pra uso público
(rejeitado — RLS já resolve isso numa linha, view seria uma camada extra
sem necessidade).

## Cancelar qualquer Ação: mais uma condição na policy já existente

**Decision**: a policy `acoes_update_criador_ou_dono_grupo` (da feature
004) ganha mais um `OR EXISTS (... administradores_distrito ...)`, virando
`acoes_update_criador_dono_grupo_ou_admin`.

**Rationale**: é a mesma técnica já usada quando a 004 estendeu a policy
original da 003 pra incluir o Dono do Grupo — cada feature que amplia
"quem pode cancelar" edita a mesma policy em vez de empilhar policies
paralelas (que o Postgres combinaria com `OR` de qualquer forma, mas
manter uma só deixa a regra legível num lugar).

**Alternatives considered**: policy adicional só pra admin, em paralelo à
existente (funcionalmente equivalente — Postgres faz `OR` entre policies
permissivas da mesma ação — mas espalha a regra de "quem cancela" em dois
lugares em vez de um).

## Promoção de Administrador: campo de ID, não busca por nome

**Decision**: a tela de promoção pede o ID (UUID) do Perfil a promover,
sem busca por nome.

**Rationale**: construir busca/diretório de Usuários por nome é uma
feature própria, não pedida no Input desta feature — adicionar isso agora
seria generalização especulativa (Princípio V). Administradores do
distrito são poucos e a promoção é uma operação rara; copiar um ID é
aceitável pro tamanho deste app.

**Alternatives considered**: tela de busca por nome usando
`perfil_publico` (rejeitado por ora — escopo maior que o pedido, vira
Assumption de melhoria futura se o usuário pedir).

## `Igreja` → `Church`: primeira tradução Dart sob a fronteira de idioma

**Decision**: `lib/features/perfil/domain/igreja.dart` vira `church.dart`
(classe `Church`, campo `nome`→`name`); `PerfilRepository.fetchIgrejas()`
vira `fetchChurches()`; `igrejasProvider` vira `churchesProvider`. Os
modelos `Perfil`/`Grupo`/`Acao` (e os campos `igrejaId` que carregam
dentro deles) não são tocados por esta feature e continuam em português.

**Rationale**: esta feature toca `Igreja` diretamente (adiciona
arquivamento) — é exatamente o gatilho que o Princípio I descreve pra
traduzir ("ao tocar um arquivo por outro motivo"). Cascatear a tradução
pra `Perfil`/`Grupo`/`Acao` só porque eles têm um campo `igrejaId`
inflaria o escopo desta feature sem necessidade (Princípio V) — a
tradução deles acontece quando (e se) uma feature futura os tocar por
outro motivo.

**Alternatives considered**: traduzir tudo de uma vez agora (rejeitado —
contradiz a cadência gradual já combinada com o usuário; blast radius
maior que o necessário pro que esta feature pede).
