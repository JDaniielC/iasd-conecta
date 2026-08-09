# Implementation Plan: Consentimento de responsável para menor de idade

**Branch**: `015-consentimento-responsavel` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/015-consentimento-responsavel/spec.md`

## Summary

O cadastro ganha um passo condicional: quando a idade informada fica **abaixo do limiar de
criança**, o app pede nome do responsável, contato do responsável e uma **autorização
destacada** — caixa separada, recusável sozinha, exatamente como o consentimento de Igreja de
origem já faz hoje (`profile_signup_page.dart:186-203`). O registro guarda quem autorizou, o
contato, **quando** e **sob qual versão** do texto legal.

O eixo técnico foi decidido por experimento, não por preferência. FR-009 exige a regra **no
banco**; o precedente natural é uma `check constraint`, como `apelido_obrigatorio_menor`
(`20260723191202_perfis_igrejas.sql:38`). Rodei a constraint contra o banco local e ela serve —
com três ajustes que só apareceram no experimento:

1. **`not valid` é obrigatório.** Sem ele, `ADD CONSTRAINT` falha na hora se existir um único
   cadastro antigo de menor sem autorização. Confirmado: `ERROR: check constraint
   "autorizacao_responsavel_crianca" of relation "perfis" is violated by some row`.
2. **O limiar mora numa função de banco**, `public.limiar_crianca()`, não num literal dentro da
   constraint. Trocar o número passa a ser um `create or replace` de uma linha, sem recriar
   constraint nenhuma — verificado (ver [research.md](./research.md) D-002).
3. **A constraint sozinha não basta para a US2.** A política `perfis_update_own` só confere
   identidade, então a própria pessoa cadastrada consegue reescrever o nome do responsável
   depois. Reproduzido: `'Maria Mae'` virou `'Fulano Inventado'` com um `update`. Um gatilho
   `before update` protege o registro, no mesmo padrão de `acoes_protege_campos_internos`.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: `supabase_flutter ^2.8.0`, `flutter_riverpod ^3.3.2`. **Nenhuma
nova.**

**Storage**: PostgreSQL via Supabase. **Quatro colunas novas** em `public.perfis`, **duas check
constraints**, **uma função** de limiar e **um gatilho** de proteção. Nenhuma tabela nova.

**Testing**: `flutter_test` + `mocktail` (unit/widget), `dart test test/integration` contra o
Postgres local (`db_test_helper.dart`). Gates de `.github/workflows/ci.yml`.

**Target Platform**: Flutter web (deploy atual) + Android/iOS.

**Project Type**: app Flutter por feature, com a regra de domínio no banco.

**Performance Goals**: irrelevante. Quatro colunas num `insert` que já existe.

**Constraints**:

- A regra vale **no banco**, por nenhum caminho (FR-009, SC-001) — não é validação de tela com
  espelho no cliente, é o contrário: a tela é o espelho.
- Fluxo de maior de idade **idêntico** ao de hoje: mesmo número de campos e de caixas (FR-005,
  SC-003).
- Nome e contato do responsável **nunca** saem para outro Usuário nem para Visitante (SC-004).
- A migration **não pode falhar** nem travar num banco que já tenha cadastro antigo de menor.

**Scale/Scope**: 4 colunas, 2 constraints, 1 função, 1 gatilho, 1 função existente alterada
(`excluir_minha_conta`), 2 arquivos Dart de produção tocados, 4 documentos, ~5 arquivos de
teste.

**NEEDS CLARIFICATION — 1 item, deliberadamente em aberto**: o **valor do limiar de criança**.
A spec deixou em Assumptions e não invento número aqui. O plano foi desenhado para que a
resposta do `/speckit-clarify` seja uma edição de **duas linhas** (uma no banco, uma no Dart) —
ver research D-002 e a seção "A decisão que falta", abaixo.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|---|---|---|
| **I. Linguagem Ubíqua** | ⚠️ PASS condicionado | Dois termos **novos** — **Responsável** e **Criança** — entram em `CONTEXT.md` **antes** de qualquer código (FR-013, T001). Há uma **colisão real a resolver**: `CONTEXT.md:155` hoje lista "responsável" no `_Avoid_` de **Líder/Diretor**, e a partir desta feature "Responsável" passa a ser um termo próprio — a entrada de Líder/Diretor precisa ser reescrita como "responsável pelo Ministério" na mesma tarefa, senão o glossário passa a se contradizer. Identificadores Dart em inglês: `guardianName`, `guardianContact`, `guardianAuthorizedAt`, `guardianAuthorizationVersion`, `isChild`, `needsGuardianAuthorization`, `childAgeThreshold`. Banco em português: `responsavel_nome`, `responsavel_contato`, `autorizacao_responsavel_em`, `autorizacao_responsavel_versao`, `limiar_crianca()`. **Inclui código de teste** — helper, mock, variável local e parâmetro em inglês; só o nome do arquivo de teste fica em português |
| **II. Privacidade e LGPD** | ⚠️ PASS com dever adicional | A feature **acrescenta** dado pessoal, e de **terceiro** — o responsável não é usuário do app. A spec já declara dado/finalidade/quem vê/consentimento, como o Princípio II exige. Quem pode ler: **só a própria linha** (`perfis_select_own`) e o responsável pelo app via `service_role`. Verificado no banco: outro `authenticated` lê **0 linhas**; `anon` **não tem `select`** em `perfis` (`anon=Dxtm`, sem `r`); `perfil_publico()` devolve só `id, nome_exibido, igreja_id`. **O dever adicional**: `excluir_minha_conta()` (feature 009) anonimiza o Perfil mas **não conhece as colunas novas** — sem T005, o nome e o contato de uma mãe sobreviveriam à exclusão da conta da filha. Isso é o Princípio II falhando em silêncio, e vira tarefa obrigatória |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com pendência declarada | Spec escrita. **`/speckit-clarify` é obrigatório antes de implementar** e está pendente: o valor do limiar é decisão de regra de negócio, e o Princípio III proíbe decidi-la ad-hoc no código. O plano não a resolve — isola-a em dois pontos e segue. Não bloqueia a Fase 1 (design), bloqueia a Fase 2 (código) |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS | Nenhuma das cinco regras centrais é tocada: a feature não encosta em fila de espera, desempate, revogação, descarte de candidatas nem Dupla Missionária. A spec declara isso ("Comportamento de borda de Ação/Grupo/Rodada: nenhum"), e o quickstart cobra a prova: os **127** testes de integração atuais passam **sem edição de asserção** |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | **Nenhum papel novo** — a spec é explícita: Responsável não tem login, não tem permissão, não aparece em tela. São quatro colunas no cadastro de um menor. Nenhuma tabela nova, nenhuma dependência nova, nenhuma RPC nova. O gatilho de proteção é a **única** adição além do texto literal da spec, e está justificada abaixo |

**Complexity Tracking**: nenhuma violação a justificar. O gatilho de proteção não é violação de
princípio — é o que faz a US2 significar alguma coisa —, mas é a única peça que a spec não pede
com todas as letras, então está registrada aqui em vez de aparecer de surpresa no código:

| Adição | Por que é necessária | Alternativa mais simples, e por que foi recusada |
|---|---|---|
| Gatilho `perfis_protege_autorizacao_responsavel` | A US2 pede autorização **verificável**. Sem o gatilho, quem segura o aparelho reescreve nome, contato, data e versão da autorização por `update` direto — reproduzido no banco local: `'Maria Mae'` → `'Fulano Inventado'`. Um registro que o próprio titular edita não prova nada | *Não proteger*: recusada porque esvazia a US2 inteira. *Endurecer `perfis_update_own` com `WITH CHECK`*: impossível — `WITH CHECK` não enxerga `OLD`, então não consegue dizer "este campo não pode mudar". O gatilho é o mesmo remédio que a auditoria de 2026-07-24 já aplicou no BUG 3 (`20260724130000_fix_rls_security_bugs.sql:57-85`) |

## Project Structure

### Documentation (this feature)

```text
specs/015-consentimento-responsavel/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 7 decisões, 4 delas medidas no banco
├── data-model.md        # Fase 1 — as quatro colunas, quem lê, o que não muda
├── contracts/
│   └── schema.sql       # Fase 1 — colunas, constraints, função de limiar, gatilho
├── quickstart.md        # Fase 1 — validação, com os números de baseline
├── checklists/
│   └── requirements.md  # (já existe)
└── tasks.md             # Fase 2
```

### Source Code (repository root)

```text
lib/features/profile/
├── domain/profile.dart                    # ALTERADO: + 4 campos, childAgeThreshold,
│                                          #   isChild, needsGuardianAuthorization,
│                                          #   readyToSubmit, toInsertMap
└── presentation/profile_signup_page.dart  # ALTERADO: o passo condicional + a caixa
                                           #   destacada + a mensagem de erro do banco

supabase/migrations/
└── <timestamp>_autorizacao_responsavel.sql   # NOVO — a feature inteira do lado do banco

CONTEXT.md                                 # ALTERADO: 2 termos novos — PRIMEIRO
MAPA-DE-DADOS.md                           # ALTERADO: as 4 colunas (FR-011)
REVISAO-JURIDICA.md                        # ALTERADO: deixa de dizer "não implementada" (FR-012)
lib/features/legal/presentation/privacy_policy_page.dart   # ALTERADO (FR-010)

test/
├── unit/autorizacao_responsavel_test.dart              # NOVO
├── widget/autorizacao_responsavel_test.dart            # NOVO
├── widget/cadastro_perfil_page_test.dart               # ALTERADO: SC-003
└── integration/
    ├── autorizacao_responsavel_test.dart               # NOVO — a constraint (FR-009)
    ├── autorizacao_responsavel_privacidade_test.dart   # NOVO — SC-004
    └── account_deletion_test.dart                      # ALTERADO: anonimização limpa
                                                        #   os dados do responsável
```

**Structure Decision**: tudo dentro de `lib/features/profile/`, que já existe. Não há feature
nova — Responsável é um conjunto de campos no cadastro, não uma entidade com vida própria (a
spec e o Princípio V dizem isso com todas as letras). Nenhum arquivo Dart **novo** de produção:
os quatro campos cabem em `Profile`, e o passo condicional cabe na página que já tem outro
passo condicional (o Apelido).

## O levantamento que decidiu o desenho

Quatro fatos, cada um medido no Postgres local (`supabase_db_iasd`), não deduzidos:

| Fato medido | Saída real | O que decide |
|---|---|---|
| `ADD CONSTRAINT` com uma linha antiga violando | `ERROR: ... is violated by some row` | A constraint **precisa** de `not valid`, senão a migration falha |
| `ADD CONSTRAINT ... NOT VALID` com a mesma linha | `ALTER TABLE`, `convalidated = f` | A migration passa e o cadastro antigo é preservado — é o que a spec pede |
| `update` de campo **não relacionado** (telefone) na linha antiga que viola | `ERROR: new row ... violates check constraint` | **Cadastro antigo de menor vira somente-leitura.** Consequência real, não teórica — impacta a feature 016 |
| Anonimização da feature 009 na linha antiga (`idade = null`) | `UPDATE 1` | A exclusão de conta **continua funcionando** para os cadastros antigos, porque `CHECK` que resulta em `NULL` passa |

E dois fatos sobre quem lê:

| Fato medido | Saída real |
|---|---|
| Outro `authenticated` faz `select` na linha da criança | `0 linhas` (`perfis_select_own`) |
| `anon` em `public.perfis` | `anon=Dxtm/postgres` — **sem `r`**, não tem `select` nenhum |
| `perfil_publico()` da criança | `id, nome_exibido, igreja_id` — não existe caminho para as colunas novas |
| A **própria** criança faz `update` no nome do responsável | `UPDATE 1` — passou. É o buraco que o gatilho fecha |

## A decisão que falta, e por que ela não trava o desenho

O limiar de criança está em aberto de propósito (spec, Assumptions). A Política fala em
"criança (**até** 12 anos)" — inclusivo — e `REVISAO-JURIDICA.md:93` propõe "**menor que** 12"
— exclusivo. São regras **diferentes** para uma criança de 12 anos, e a spec manda decidir isso
no `/speckit-clarify`.

O plano absorve as duas incógnitas — o número **e** o lado — num único inteiro:

> **A regra é sempre `idade < limiar`.** O lado é absorvido pelo número: "até 12 anos
> inclusive" se escreve como **limiar 13**; "menor que 12" se escreve como **limiar 12**.

Com isso, a resposta do clarify é **uma linha em cada lado**:

- Banco: `create or replace function public.limiar_crianca() ... select <N>` — testado, e a
  troca vale na hora para a constraint, sem recriar nada.
- Dart: `const childAgeThreshold = <N>` em `profile.dart`.

E um teste impede as duas de divergirem (T008): lê `select public.limiar_crianca()` e compara
com a constante Dart. Enquanto o clarify não vier, o valor fica **12** com um comentário
`PENDENTE` nos dois lugares, e os testes são escritos **em função do limiar**, nunca com idade
literal — então nenhum teste precisa de edição quando o número mudar.

## Riscos e decisões que precisam de olho

1. **Cadastro antigo de menor vira somente-leitura, e ninguém percebe até a 016.** Está medido
   acima: com a constraint `not valid`, a linha antiga sobrevive, mas **qualquer** `update`
   nela é recusado — inclusive um que não tenha nada a ver com o responsável. Hoje isso é
   inofensivo (não existe tela de editar perfil, `MAPA-DE-DADOS.md:117-122`). Na **feature 016**
   vira um erro de banco na cara do usuário. A saída não é desfazer nada aqui: é a 016 tratar,
   ou a decisão de produto sobre cadastros antigos ser tomada. Fica escrito em `DEFERRED`
   dentro da própria migration, e em T029.

2. **`excluir_minha_conta` não sabe das colunas novas.** É o único ponto onde a feature pode
   violar o Princípio II em silêncio: a conta da criança é excluída, o Perfil é anonimizado, e
   o nome e o telefone da mãe **continuam lá**. É dado de terceiro que não tem como pedir
   exclusão — nem conta no app ela tem. T005 é obrigatória e não é opcional para o MVP.

3. **`VALIDATE CONSTRAINT` é uma bomba de efeito retardado.** Um dia alguém vai achar
   `convalidated = f` no banco e querer "arrumar". Rodar `alter table public.perfis validate
   constraint autorizacao_responsavel_crianca` **falha** se houver cadastro antigo — e, se não
   falhar, terá silenciosamente mudado a política de produto que a spec deixou em aberto. O
   contrato traz o aviso escrito ao lado da linha.

4. **A segunda constraint (FR-008) é a que amarra a decisão sobre adolescentes.**
   `autorizacao_responsavel_so_para_crianca` exige campos vazios acima do limiar. Se um dia a
   regra passar a exigir responsável para 13-17 com Igreja de origem preenchida — que é o que
   `REVISAO-JURIDICA.md:102-105` sugere —, **é essa constraint que impede**, e ela precisará
   mudar junto. Registrado em research D-004 para não virar surpresa.

5. **Contagem de caixas de seleção nos testes de widget.**
   `test/widget/cadastro_perfil_page_test.dart:132` afirma `findsNWidgets(2)` para
   `CheckboxListTile`. Criança **com** Igreja de origem passa a ter **três**. O teste atual usa
   idade 30, então não quebra — mas todo teste novo precisa achar a caixa **pelo texto**, nunca
   por tipo ou índice, senão a suíte vira um jogo de contagem.

6. **A versão do texto legal vem de `LegalMetadata.version` (hoje `'1.1'`)**, o que faz
   `profile.dart` importar `lib/features/legal/legal_metadata.dart`. É acoplamento pequeno e
   deliberado — a spec já diz que a **feature 017** unifica isso depois. Se a 017 entrar antes,
   esta feature lê a fonte que a 017 criar, e a coluna
   `autorizacao_responsavel_versao` continua fazendo sentido do mesmo jeito.

7. **O texto da autorização é o entregável de menor esforço técnico e maior peso jurídico.**
   FR-003 e FR-006 são sobre uma frase. Ela precisa dizer quem autoriza, o que é autorizado, e
   que a identidade de quem marca **não é verificada** — e a Política precisa dizer a mesma
   coisa (FR-010), senão o app volta a prometer o que não faz, que é o problema que originou
   esta feature.

## Ordem entre as features abertas

**`015 (esta) → 016 → 017`**

| Feature | Relação com a 015 |
|---|---|
| **009** (mergeada) | `excluir_minha_conta()` **precisa ser alterada** por esta feature (risco 2). É a única função existente que esta feature toca |
| **016 — Meu perfil** | **Depende desta e herda o risco 1.** Editar um cadastro antigo de menor será recusado pelo banco. Além disso, a tela de "meu perfil" é o único lugar de onde os dados do responsável poderiam vazar por descuido — ela precisa **não** exibi-los, ou exibi-los só ao próprio titular |
| **017 — Versão do consentimento** | Esta grava `autorizacao_responsavel_versao` a partir de `LegalMetadata.version`, do jeito que der (a spec autoriza). A 017 depois unifica a forma de gravar versão para os três consentimentos |
| **014 — Arquivar Grupo** | Sem interação. Nenhum arquivo em comum |

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 7 decisões — por que check constraint e não
gatilho nem política, como o limiar vira uma linha, por que `not valid`, por que uma segunda
constraint para FR-008, por que o gatilho de proteção, quem pode ler, e o que acontece com os
cadastros antigos.

**Um `NEEDS CLARIFICATION` permanece**: o valor do limiar. É a única pendência, é decisão de
produto, e está isolada em dois pontos.

## Fase 1 — Design

Concluída:

- [data-model.md](./data-model.md) — as quatro colunas, as duas invariantes, a tabela de quem
  lê o quê, e o que explicitamente não muda.
- [contracts/schema.sql](./contracts/schema.sql) — a função de limiar, as duas constraints
  `not valid`, o gatilho, a alteração de `excluir_minha_conta`, com o motivo de cada escolha
  escrito no próprio arquivo.
- [quickstart.md](./quickstart.md) — validação, incluindo a query que conta cadastros antigos
  **antes** de aplicar a migration.

**Constitution Check pós-design**: reavaliado, sem mudança de veredito. O design **reforçou** o
Princípio II (a alteração de `excluir_minha_conta` virou tarefa obrigatória, e a leitura das
colunas novas ficou provada por teste em vez de suposta) e manteve o IV intacto — nenhuma das
cinco regras centrais é tocada. Os Princípios I e III seguem com a condição (dois termos em
`CONTEXT.md` primeiro, mais a colisão com Líder/Diretor) e a pendência (o limiar) já
registradas.
