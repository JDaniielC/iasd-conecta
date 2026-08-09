# Data Model: Versão do texto aceito no consentimento

**Feature**: 017-versao-do-consentimento | **Date**: 2026-08-09

**Nenhuma entidade de domínio nova** (`CONTEXT.md` não muda). **Nenhum dado pessoal novo.**
`Perfil` ganha, ao lado de cada data de consentimento, a versão do texto aceito. Nasce uma
tabela de **referência** — o catálogo de versões publicadas — que não contém dado de pessoa
nenhuma.

---

## 1. `public.versoes_texto_legal` — catálogo de versões (tabela nova)

| Coluna | Tipo | Regra |
|---|---|---|
| `versao` | `text` | chave primária. É o mesmo número exibido nas páginas legais (`'1.1'`) |
| `vigente_desde` | `timestamptz` | `not null`. Instante a partir do qual a versão passa a ser a vigente |
| `created_at` | `timestamptz` | `not null default now()` |

**Conteúdo inicial**: uma linha — `('1.1', '2026-08-06 00:00:00-03')`. A 1.0 **não** é semeada:
não existe data de vigência documentada para ela no repositório, e inventar uma seria a mesma
espécie de chute que FR-007 proíbe (research D-006).

**Quem escreve**: só migration. `grant select` para `anon, authenticated`; **nenhum** grant de
`insert`/`update`/`delete` para ninguém além do dono. Publicar versão é evento de release.

**Versão vigente** = a linha de maior `vigente_desde` entre as que já venceram
(`vigente_desde <= now()`), desempatada por `versao` decrescente.
`public.versao_texto_legal_vigente()` devolve isso e **levanta exceção** quando não há nenhuma —
devolver `null` faria uma linha nova nascer indistinguível de um aceite antigo, destruindo o
único significado que `null` tem nesta feature.

---

## 2. `public.perfis` — duas colunas novas

| Coluna | Tipo | Nulo? | Par | Preenchida por |
|---|---|---|---|---|
| `consentimento_lgpd_versao` | `text` | **sim** | `consentimento_lgpd_aceito_em` (`not null`, feature 001) | gatilho |
| `consentimento_lgpd_igreja_versao` | `text` | **sim** | `consentimento_lgpd_igreja_aceito_em` (anulável, feature 002/IASD-01) | gatilho |

Ambas com chave estrangeira para `public.versoes_texto_legal(versao)`: é impossível gravar uma
versão que não foi publicada, inclusive por escrita direta na tabela.

**Nenhuma constraint de obrigatoriedade** — nem `not null`, nem `check ... not valid`. O motivo
está em research D-003 e no risco 1 do plano: um `check` `not valid` é verificado em todo
`UPDATE` da linha e tiraria de quem se cadastrou antes desta feature a capacidade de apagar a
conta (`excluir_minha_conta` termina num `update public.perfis`).

### O significado de `null`, que é exatamente um

`null` = **este aceite é anterior à feature 017 e não há como saber sob qual texto foi dado.**

Não significa "não aceitou" (o aceite é obrigatório e a data está lá), não significa "erro", e
nunca significa "linha nova sem versão" — porque `versao_texto_legal_vigente()` recusa em vez de
devolver nulo, e o gatilho carimba toda linha nova.

---

## 3. O carimbo — `public.perfis_carimbar_consentimento()`

Gatilho `before insert or update on public.perfis for each row`. Regra, escrita como a leitura
que ela quer produzir:

> **O cliente diz SE a pessoa aceitou. O banco diz QUANDO e SOB QUAL TEXTO.**

O cliente continua mandando `consentimento_lgpd_aceito_em` (e o de Igreja, quando houver): é o
sinal de que a caixa foi marcada, que é legitimamente informação do cliente. O **valor** desse
timestamp e a **versão** passam a ser do banco.

| Situação | `_aceito_em` fica | `_versao` fica |
|---|---|---|
| `INSERT` com aceite | `now()` do banco | versão vigente |
| `INSERT` sem aceite de Igreja (`null`) | `null` | `null` |
| `UPDATE` que muda o `_aceito_em` (novo aceite — ex.: Igreja escolhida depois, feature 016) | `now()` do banco | versão vigente **daquele instante** |
| `UPDATE` que zera o `_aceito_em` de Igreja (consentimento retirado) | `null` | `null` |
| `UPDATE` que **não** toca o `_aceito_em` (mudar nome, anonimizar) | valor antigo, restaurado | valor antigo, **restaurado** |

A última linha é a mais importante das cinco: é o `else` do gatilho que impede um cliente
autenticado de rodar `update perfis set consentimento_lgpd_versao = '1.1'` na própria linha
antiga e fabricar um backfill. **SC-002 é execução, não promessa.**

**Invariante de par**: `_versao` e `_aceito_em` são sempre gravados juntos e zerados juntos.
Nunca existe versão sem aceite; nunca existe aceite novo sem versão (US1, cenário 3).

**Interação com `excluir_minha_conta` (feature 009)**: aquele `update` zera `igreja_id` mas
**não** zera os `_aceito_em`. O gatilho, portanto, cai no ramo "não mudou" e preserva as duas
datas e as duas versões na linha anonimizada — de propósito: é a prova da base legal do
histórico que a feature 009 conserva. E, por não chamar
`versao_texto_legal_vigente()` nesse ramo, a exclusão de conta **não** passa a depender do
catálogo de versões.

---

## 4. `public.consentimentos_por_versao()` — a resposta da US2

`security definer`, `stable`. Recusa quem não estiver em `public.administradores_distrito`.

| Coluna devolvida | Tipo | Conteúdo |
|---|---|---|
| `tipo` | `text` | `'lgpd'` ou `'igreja'` |
| `versao` | `text` | a versão, ou `null` para os aceites **desconhecidos** (FR-006) |
| `quantidade` | `bigint` | contagem |

**Invariante de privacidade (Princípio II)**: nenhuma coluna de identidade sai — sem `id`, sem
`nome`, sem `apelido`. Quem pergunta recebe números, não pessoas. A distinção por pessoa existe
no dado (é uma coluna por linha) e é alcançável pelo controlador via `service_role`/painel, que
é o acesso apropriado a um pedido individual de titular; o app responde só o agregado.

**Perfil anonimizado (`anonimizado_em is not null`) não entra na contagem** — não é mais uma
pessoa rastreada, e contá-lo inflaria a resposta.

**Linhas de `'igreja'`** contam apenas quem de fato deu o consentimento de Igreja
(`consentimento_lgpd_igreja_aceito_em is not null`); quem nunca escolheu Igreja não é "versão
desconhecida", é ausência de aceite, e misturar as duas coisas seria mentir de um jeito novo.

---

## 5. Fronteira de idioma — os dois lados, nome a nome

A regra da constituição (Princípio I) e de `CONTEXT.md`: **banco em português, identificador
Dart em inglês, chave de `map[...]` em português, string de UI em português**. Os dois lados
coexistem de propósito. Esta é a tabela de tradução desta feature — nenhum nome novo fora dela.

| Conceito | Banco (**português**) | Dart (**inglês**) | Chave de `map[...]` |
|---|---|---|---|
| Catálogo de versões | tabela `versoes_texto_legal` | — (não é lido pelo app) | — |
| Versão vigente | função `versao_texto_legal_vigente()` | `LegalMetadata.version` (espelho de exibição) | — |
| Versão do texto aceito (LGPD) | coluna `consentimento_lgpd_versao` | campo `consentedVersion` | `map['versao']` |
| Versão do texto aceito (Igreja) | coluna `consentimento_lgpd_igreja_versao` | campo `consentedVersion` do `ConsentTally` de `ConsentKind.church` | `map['versao']` |
| Carimbo do consentimento | função/gatilho `perfis_carimbar_consentimento` | — (não existe no cliente, por decisão) | — |
| Consulta por versão | função `consentimentos_por_versao()` | `ConsentRepository.fetchConsentTally()` | — |
| Tipo de consentimento | valores `'lgpd'` / `'igreja'` | enum `ConsentKind { lgpd, church }`, com `dbValue` | `map['tipo']` |
| Linha da contagem | — | classe `ConsentTally` | — |
| Contagem | coluna devolvida `quantidade` | campo `count` | `map['quantidade']` |
| Versão desconhecida | `null` | `bool get isVersionUnknown` | — |
| Provider da consulta | — | `consentTallyProvider` | — |
| Repositório | — | `ConsentRepository` / `consentRepositoryProvider` | — |
| Página (US2) | — | `ConsentVersionsPage`, arquivo `consent_versions_page.dart` | — |

**Nos testes vale o mesmo**: helper, variável, parâmetro e constante em inglês (`asUser`,
`seedLegacyProfile`, `currentVersion`, `adminUid`). A **única** exceção é o **nome do arquivo**
de teste, que continua em português (`consentimento_versao_carimbada_test.dart`), pela decisão
registrada na feature 012.

### Modelo de leitura em Dart

```
enum ConsentKind { lgpd('lgpd'), church('igreja') }   // dbValue em português

class ConsentTally {
  final ConsentKind kind;        // de map['tipo']
  final String? consentedVersion; // de map['versao'] — null = desconhecida
  final int count;                // de map['quantidade']
  bool get isVersionUnknown => consentedVersion == null;
}
```

`Profile` (`lib/features/profile/domain/profile.dart`) **não ganha campo de versão**, e
`toInsertMap` **não ganha chave nenhuma** — mandar a versão é justamente o que FR-004 proíbe. A
única alteração ali é um comentário dizendo isso, para que uma refatoração futura não "conserte"
a ausência.

---

## 6. O que explicitamente NÃO muda

- `consentimento_lgpd_aceito_em` continua `not null`; `consentimento_lgpd_igreja_aceito_em`
  continua anulável. A constraint `consentimento_igreja_destacado` fica intacta.
- `perfil_publico()`, `perfis_select_own`, `perfis_insert_own`, `perfis_update_own`: intactas. A
  versão nunca é exposta a outro Usuário nem a Visitante.
- `excluir_minha_conta()`: **nenhuma linha alterada**. Ela continua funcionando sobre Perfil de
  versão conhecida e de versão desconhecida — e há teste de integração para os dois.
- Tela de cadastro (`profile_signup_page.dart`): nenhum campo, nenhum passo, nenhum texto novo
  (SC-004).
- Fila de espera, desempate por sorteio, revogação de voto, descarte de candidatas, Dupla
  Missionária: nada disso encosta em `perfis`. Os **127** testes de integração existentes devem
  passar **sem edição**.
