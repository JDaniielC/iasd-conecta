# Data Model: Consentimento de responsável para menor de idade

**Feature**: 015-consentimento-responsavel | **Date**: 2026-08-09

Nenhuma entidade nova, nenhuma tabela nova. **Perfil** ganha quatro colunas, e o domínio ganha
um termo — **Responsável** — que existe só como esses campos, nunca como linha própria.

---

## 1. Perfil — quatro colunas novas em `public.perfis`

| Coluna (banco, português) | Tipo | Regra | Identificador Dart (inglês) |
|---|---|---|---|
| `responsavel_nome` | `text`, nulo | Nome de quem autorizou. Autodeclarado, **não verificado** (FR-006) | `guardianName` |
| `responsavel_contato` | `text`, nulo | E-mail ou telefone. Autodeclarado, **não verificado**. É **registro, não canal** — o app nunca escreve para lá | `guardianContact` |
| `autorizacao_responsavel_em` | `timestamptz`, nulo | **Quando** a autorização foi dada (FR-007) | `guardianAuthorizedAt` |
| `autorizacao_responsavel_versao` | `text`, nulo | Versão do texto legal vigente no momento — hoje `LegalMetadata.version` (`'1.1'`) (FR-007) | `guardianAuthorizationVersion` |

**Por que quatro colunas em `perfis` e não uma tabela `autorizacoes_responsavel`**: a spec
define Responsável como "um conjunto de campos no registro do menor", sem cadastro próprio, e o
Princípio V manda preferir o caminho mais simples que atende. Uma tabela separada obrigaria um
`join` em toda leitura de Perfil e abriria a pergunta "e se houver duas autorizações?", que
ninguém fez. As quatro colunas espelham o padrão que já existe: `consentimento_lgpd_aceito_em`
e `consentimento_lgpd_igreja_aceito_em` também moram na própria linha.

---

## 2. O limiar de criança

```
public.limiar_crianca()  ->  integer     (banco, é quem executa)
const childAgeThreshold                  (lib/features/profile/domain/profile.dart, é quem
                                          dá o feedback na tela)
```

**A comparação é sempre `idade < limiar`.** O lado do limiar está absorvido no número: "até 12
anos inclusive" se escreve como **13**; "menor que 12" se escreve como **12**. Isso existe para
que a resposta do `/speckit-clarify` seja uma edição de duas linhas e nada mais.

> **PENDENTE — `/speckit-clarify`**: o valor. Fica **12** provisoriamente, marcado como
> pendente nos dois lugares. Nenhum teste usa idade literal: todos leem o limiar e calculam
> `limiar - 1` (é criança) e `limiar` (não é), então a troca do número não pede edição de
> teste nenhum.

Duas fontes para o mesmo número é deliberado — é o mesmo arranjo de `_ageOfMajority` (Dart) e
`apelido_obrigatorio_menor` (banco) que já vive no projeto desde a feature 001. O que impede a
divergência é um teste (T008) que lê `select public.limiar_crianca()` e compara com a constante.

---

## 3. As duas invariantes, e o que cada uma responde

### `autorizacao_responsavel_crianca` — abaixo do limiar, tem que ter tudo

```
idade is null
  or idade >= public.limiar_crianca()
  or (responsavel_nome is not null
      and responsavel_contato is not null
      and autorizacao_responsavel_em is not null
      and autorizacao_responsavel_versao is not null)
```

Responde **FR-001, FR-004, FR-007 e FR-009**. Vale em `insert` e em `update`, para qualquer
papel — inclusive `service_role` e `postgres`, que não passam por RLS. É isso que faz SC-001
("verificado tanto pela tela quanto por tentativa direta no banco") ser verdade.

`idade is null` na frente é a linha anonimizada da feature 009 passando. Poderia ser omitida —
`NULL >= limiar` já daria `NULL`, e `CHECK` que resulta em `NULL` passa —, mas escrita
explicitamente ela documenta a intenção em vez de depender de quem lê saber lógica de três
valores.

### `autorizacao_responsavel_so_para_crianca` — acima do limiar, tem que estar vazio

```
idade is null
  or idade < public.limiar_crianca()
  or (responsavel_nome is null
      and responsavel_contato is null
      and autorizacao_responsavel_em is null
      and autorizacao_responsavel_versao is null)
```

Responde **FR-008**. Não é redundante com a primeira: sem ela, nada impede um adulto de gravar
nome de responsável — por bug de tela, por `insert` direto, ou por um formulário que não limpou
o estado quando a idade subiu acima do limiar. O formulário atual já tem esse cuidado no
consentimento de Igreja (`profile_signup_page.dart:178-181`, trocar a Igreja zera o
consentimento); esta constraint é a rede embaixo do mesmo cuidado, para os campos novos.

**As duas entram `not valid`** — ver research D-003. `not valid` **não** é "só para linhas
novas": é "não confira as que já estão aqui". Linha antiga que viola sobrevive, mas fica
somente-leitura.

---

## 4. O gatilho — o registro não se altera depois de gravado

`perfis_protege_autorizacao_responsavel`, `before update`, recusa alteração das quatro colunas.

Existe porque `perfis_update_own` é `using (auth.uid() = id)` **sem `with check`** — ela confere
quem mexe na linha, não o que muda. Reproduzido no banco: a própria criança trocou
`'Maria Mae'` por `'Fulano Inventado'` com um `update`, e passou (research D-005).

**Escape**: `set_config('app.bypass_autorizacao_responsavel', 'true', true)` dentro da
transação. Dois usos legítimos, e só eles:

| Uso | Quem liga o bypass |
|---|---|
| Anonimização na exclusão de conta | `excluir_minha_conta()`, ao redor do `update` que zera tudo |
| Correção pedida pelo próprio responsável (US3, LGPD art. 18 III) | O responsável pelo app, à mão, ligando o bypass de propósito — o que deixa rastro |

Mesmo desenho de `acoes_protege_campos_internos` + `app.bypass_acoes_protecao`
(`20260724130000_fix_rls_security_bugs.sql:57-85`).

---

## 5. Quem lê o quê

| | Visitante (`anon`) | Outro Usuário | O próprio titular | Responsável pelo app (`service_role`) |
|---|---|---|---|---|
| `responsavel_nome` / `responsavel_contato` | ❌ **sem `select` em `perfis`** (`anon=Dxtm`, sem `r`) | ❌ `0 linhas` — `perfis_select_own` | ✅ a própria linha | ✅ painel do Supabase |
| `autorizacao_responsavel_em` / `_versao` | ❌ | ❌ | ✅ | ✅ |
| `perfil_publico(uuid)` | devolve `id, nome_exibido, igreja_id` — **projeção fixa**, nenhuma coluna nova aparece | idem | idem | idem |

**Nenhuma política, RPC ou `grant` novo foi criado** (research D-006). O acesso já era fechado;
abrir e depois fechar seria mais superfície pelo mesmo resultado. SC-004 é verdadeiro por
construção — e mesmo assim ganha teste, porque "verdadeiro por construção" é exatamente o tipo
de afirmação que a feature 016 pode invalidar sem querer.

**O titular lê os dados do próprio responsável**, e isso é intencional: a criança consegue ver
quem autorizou o cadastro dela. Não é exposição a terceiro.

---

## 6. Modelo Dart

`Profile` (`lib/features/profile/domain/profile.dart`) ganha:

```
final String? guardianName;
final String? guardianContact;

bool get isChild                    => age < childAgeThreshold;
bool get needsGuardianAuthorization => isChild;
bool get readyToSubmit              => ... && (!needsGuardianAuthorization
                                              || guardianAuthorizationAccepted
                                                 && guardianName/-Contact preenchidos)
```

`toInsertMap` grava as quatro chaves **em português** (`'responsavel_nome'`,
`'responsavel_contato'`, `'autorizacao_responsavel_em'`, `'autorizacao_responsavel_versao'`) —
são o contrato com o banco, não se traduzem —, e grava `null` nas quatro quando não é criança,
para satisfazer FR-008 pelo caminho da tela também, não só pelo da constraint.

`guardianAuthorizationAccepted` é o estado da caixa marcada, como
`churchLgpdConsentAccepted` já é. `guardianAuthorizedAt` e `guardianAuthorizationVersion` não
são campos do formulário: são derivados no `toInsertMap` (`DateTime.now().toUtc()` e
`LegalMetadata.version`), exatamente como `consentimento_lgpd_igreja_aceito_em` já é hoje
(`profile.dart:71-72`).

---

## 7. O passo novo na tela

Aparece **só** quando `age < childAgeThreshold`, entre o Apelido e a caixa de consentimento
geral:

| Elemento | Regra |
|---|---|
| Campo "Nome do responsável" | Obrigatório (FR-001) |
| Campo "E-mail ou telefone do responsável" | Obrigatório (FR-001) |
| Caixa de autorização, **em `Container` com borda**, separada da caixa LGPD comum | Recusável sozinha (FR-002) — mesmo desenho do consentimento de Igreja, `profile_signup_page.dart:186-203` |

**O texto da caixa** (FR-003, FR-006) diz, em português direto, quem autoriza, o que é
autorizado, e que a identidade de quem marca não é verificada. Ele e a Política precisam dizer
a mesma coisa — a divergência entre os dois é o que originou esta feature.

**Acima do limiar, nada disso existe** (FR-005, SC-003): mesmo número de campos e de caixas que
hoje.

---

## 8. O que explicitamente NÃO muda

- **Nenhuma tabela nova, nenhuma RPC nova, nenhuma política nova, nenhum papel novo.**
- `perfil_publico()`: **inalterada**. É a projeção fixa que impede o vazamento.
- `apelido_obrigatorio_menor`, `consentimento_igreja_destacado`, `nome_valido()`: intactas. O
  Apelido continua obrigatório abaixo de **18** — que é uma régua **diferente** do limiar de
  criança, e as duas convivem: uma criança de 8 anos precisa de Apelido **e** de autorização;
  um adolescente de 15 precisa só de Apelido.
- **Nenhuma das cinco regras do Princípio IV é tocada** — fila de espera, desempate, revogação,
  descarte de candidatas, Dupla Missionária. Os **127** testes de integração passam sem edição
  de asserção; se algum precisar mudar, a feature vazou do escopo.
- **Cadastros de menor que já existem não são corrigidos nem apagados.** Ficam como estão, e
  passam a ser somente-leitura — consequência medida, não escolhida (research D-003).
- **Ninguém é notificado.** O contato do responsável é registro, não canal: o app não manda
  e-mail nem SMS para lá. Está em Assumptions da spec.
- **A identidade do responsável não é verificada** (FR-006). É autodeclaração, e a Política
  passa a dizer isso.
