# Data Model: Meu Perfil — o recorte que a tela faz sobre `perfis`

**Feature**: 016-meu-perfil | **Date**: 2026-08-09

**Nenhuma entidade nova, nenhuma coluna nova, nenhuma migration.** A spec já diz isso, e a
verificação está em [research.md](./research.md) D-001. Este arquivo não descreve uma entidade:
descreve **o que a tela lê, o que ela escreve e o que ela nunca toca**, coluna por coluna. É
onde moram as armadilhas da feature — sem ele, elas ficariam espalhadas em comentário.

O schema vigente é `supabase/migrations/20260723191202_perfis_igrejas.sql` (+
`20260724140000_consentimento_igreja_destacado.sql` e `20260806140000_exclusao_de_conta.sql`).
A fonte de verdade original é `specs/001-cadastro-usuario/contracts/schema.sql`.

## `public.perfis`, coluna a coluna

| Coluna (banco, português) | Campo Dart (inglês) | Exibida? | Editável? | Nota |
|---|---|---|---|---|
| `id` | — | não | **nunca** | `auth.uid()`. Escrevê-la é o que `perfis_update_own` impede (FR-013). |
| `nome` | `name` | sim | **sim** | Obrigatório, não pode ficar vazio. Passa por `nome_valido` no banco e por `NameModeration.cached` no cliente (FR-007, FR-008). |
| `apelido` | `nickname` | sim | **sim** | Opcional para maior; **obrigatório para menor** (`apelido_obrigatorio_menor`). Vazio grava `null`, nunca `''` (FR-007, FR-009, FR-010). |
| `igreja_id` | `churchId` | sim (nome da Igreja) | **sim** | Opcional. Escolher ou trocar exige a caixa destacada (FR-011). Ver a tabela de consentimento abaixo. |
| `telefone` | `phone` | sim | **sim** | Opcional. Vazio grava `null` (FR-007, FR-010). |
| `genero` | `gender` | **sim** | **não** | Exibido por FR-002; fora da edição por decisão da spec (research D-006 diz por quê). Nulo em Perfil anonimizado. |
| `idade` | `age` | **sim** | **não** | Idem. Nulo em Perfil anonimizado. |
| `consentimento_lgpd_aceito_em` | `lgpdConsentAcceptedAt` | **sim** | **não** | Registro de base legal. FR-002 pede exibir; reescrever seria falsificar. |
| `consentimento_lgpd_igreja_aceito_em` | `churchLgpdConsentAcceptedAt` | não | **sim, derivado** | Nunca é um campo de formulário: sai da caixa destacada, pela tabela abaixo. |
| `created_at` | — | não | **nunca** | — |
| `anonimizado_em` | — | não | **nunca** | Se estiver preenchido, a tela não deveria ser alcançável (não há sessão). |

**SC-001** ("100% dos campos pessoais guardados aparecem na tela") se lê direto desta tabela:
as sete linhas marcadas "Exibida? sim" são exatamente os campos pessoais de `perfis`. `id`,
`created_at` e `anonimizado_em` não são dado **sobre** a pessoa — são chave, carimbo de
criação e marcador de estado. `consentimento_lgpd_igreja_aceito_em` é exibida indiretamente,
pela presença da Igreja de origem.

## O que `Profile.toUpdateMap()` envia — e nada além disso

Cinco chaves, sempre as mesmas cinco:

```
'nome'                                 -> name.trim()
'apelido'                              -> nickname vazio/nulo vira null
'igreja_id'                            -> churchId (pode ser null)
'telefone'                             -> phone vazio/nulo vira null
'consentimento_lgpd_igreja_aceito_em'  -> ver tabela de consentimento
```

O contraste com `toInsertMap()` (`domain/profile.dart:61-74`) é a parte que importa:
`toInsertMap` envia **nove** chaves, incluindo `'id'`, `'genero'`, `'idade'` e
`'consentimento_lgpd_aceito_em'`. Reusá-lo no `UPDATE` reescreveria a data do consentimento
LGPD com `now()` a cada correção de telefone — apagando o registro da base legal. **Os dois
mapas são deliberadamente diferentes**, e há teste de unidade travando a diferença.

A conversão "vazio vira `null`" não é cosmética: `apelido_obrigatorio_menor` checa
`apelido is not null`, e `''` **não** é nulo. Se o cliente gravasse string vazia, um menor
conseguiria ficar sem Apelido de fato com o banco achando que tem — FR-009 quebrado sem nada
reclamar. `toInsertMap()` já faz a conversão certa; `toUpdateMap()` usa a mesma.

## `consentimento_lgpd_igreja_aceito_em`: a única coluna com regra

Constraint vigente (`20260724140000:9-11`):

```sql
check (igreja_id is null or consentimento_lgpd_igreja_aceito_em is not null)
```

| Situação | `igreja_id` | `consentimento_lgpd_igreja_aceito_em` |
|---|---|---|
| escolhe Igreja onde não havia, ou troca de Igreja | id novo | `DateTime.now().toUtc()` |
| mantém a mesma Igreja | inalterado | **inalterado** (não recarimbar) |
| remove a Igreja | `null` | **`null`** |

A terceira linha é escolha nossa, não do banco: a constraint aceitaria manter a data com a
igreja nula. Ver research D-005 para o porquê (revogação — LGPD art. 8º, §5º).

**Quando a feature 017 entrar**, um aceite dado aqui também precisa registrar a versão do
texto — e o FR-004 dela exige que a versão venha do banco, não do cliente. Se for `default`
ou trigger, `toUpdateMap()` não muda.

## Invariantes que o banco garante no `UPDATE` (não o cliente)

O cliente espelha as três primeiras para dar feedback imediato; quem garante é o banco, e é
por isso que elas ganham teste de integração e não só de widget.

| Invariante | Mecanismo | Requisito |
|---|---|---|
| Nome não passa pela moderação | `check (nome_valido(nome))` — `20260723191202:29`, função `security definer` desde `20260806090000` | FR-008 |
| Menor sem Apelido | `constraint apelido_obrigatorio_menor` — `20260723191202:38` | FR-009 |
| Igreja sem consentimento destacado | `constraint consentimento_igreja_destacado` — `20260724140000:10` | FR-011 |
| Perfil de outra pessoa | `policy perfis_update_own` — `20260723191202:76-79`; sem `with check` explícito, o `using` vale também para a linha nova | FR-013, SC-004 |
| Nada pela metade | **uma instrução `UPDATE` só**. Postgres aplica um `UPDATE` de forma atômica: ou todas as colunas mudam, ou nenhuma. Não há transação a abrir, nem RPC, nem passo intermediário no cliente | FR-012, SC-005 |

A última linha é a resposta a FR-012, e ela é curta de propósito: a atomicidade não é
construída, é **consequência de não orquestrar nada**. O risco real de "Perfil pela metade"
seria o cliente fazer duas chamadas (ex.: uma para os dados, outra para o consentimento de
Igreja) e a segunda falhar. Por isso `toUpdateMap()` devolve **um** mapa com as cinco chaves,
e `updateMyProfile` faz **uma** chamada.

## Leitura

`ProfileRepository.fetchMyProfile()` faz `select()` em `perfis` filtrando por
`auth.currentUser!.id`. O filtro é redundante com `perfis_select_own` — e é assim de
propósito: o filtro explícito documenta a intenção no código, e a policy garante o resultado
mesmo se o filtro for removido numa refatoração. `maybeSingle()`, como `hasProfile()`
(`data/profile_repository.dart:17-25`) já faz.

**Nunca** via `perfil_publico`: aquela RPC é a projeção para **terceiros** e esconde idade e
telefone de propósito (`data/profile_repository.dart:8-11`). Usá-la aqui deixaria o titular
sem ver os próprios dados — o oposto do FR-001.
