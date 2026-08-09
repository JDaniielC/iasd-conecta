# Quickstart — validar Consentimento de responsável

**Feature**: 015-consentimento-responsavel | **Date**: 2026-08-09

Esta feature **acrescenta dado pessoal de terceiro** — nome e contato de alguém que não usa o
app. A validação é menos sobre "o passo novo aparece" e mais sobre provar duas coisas que só se
provam olhando: que **nenhum caminho** grava cadastro de criança sem autorização, e que esse
dado **não sai** para ninguém.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start
```

Se `supabase start` reclamar de nome de container em uso, `supabase stop --no-backup` e subir
de novo. Se reclamar de espaço, o Docker está cheio — foi o que derrubou o Postgres durante a
feature 011.

## Parte 0 — ANTES de aplicar a migration: contar o que já existe

A feature não corrige cadastros antigos de menor, e a constraint entra `not valid` justamente
por isso. Mas é preciso **saber quantos são**, porque cada um deles fica somente-leitura:

```bash
docker exec -i supabase_db_iasd psql -U postgres -d postgres <<'SQL'
select count(*) as perfis_total,
       count(*) filter (where idade is not null and idade < 12) as cadastros_de_crianca
from public.perfis;
SQL
```

**Linha de base no banco local em 2026-08-09**: `perfis_total = 1`, `cadastros_de_crianca = 0`.

Anotar o número real. Se for maior que zero, anotar os `id` também — são as linhas que ficarão
somente-leitura, e a decisão de produto sobre elas continua em aberto (spec, Assumptions).

## Parte 1 — Gates automatizados

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration          # exige supabase start
flutter build web
```

**Anotar o número real de cada suíte.** Nunca "os testes passaram".

**Linha de base em `main` ao começar** (2026-08-09): `flutter analyze` **0 issues**,
**152** testes unit/widget, **127** testes de integração.

### Os testes de integração que já existem e NÃO podem mudar

Esta feature não toca nenhuma das cinco regras do Princípio IV. Se qualquer asserção destes
precisar de edição, a feature vazou do escopo:

```
test/integration/apelido_obrigatorio_test.dart        # a régua dos 18 continua valendo,
                                                      # independente do limiar de criança
test/integration/perfis_constraints_test.dart
test/integration/perfil_publico_apelido_test.dart     # a projeção pública não mudou
test/integration/account_deletion_test.dart           # GANHA asserção nova, mas nenhuma
                                                      # asserção existente muda
test/integration/apuracao_vencedora_test.dart
test/integration/apuracao_empate_test.dart
test/integration/fila_de_espera_test.dart
```

`account_deletion_test.dart` é o único que **cresce**: as quatro colunas do responsável ficam
nulas depois da exclusão. As asserções que já existem lá continuam idênticas.

### O que cada teste novo prova

| Teste | Requisito |
|---|---|
| `test/unit/autorizacao_responsavel_test.dart` — `isChild` verdadeiro em `childAgeThreshold - 1`, falso em `childAgeThreshold` | limiar |
| — `readyToSubmit` falso sem a caixa marcada | FR-001, FR-004 |
| — `readyToSubmit` falso sem nome **ou** sem contato do responsável | FR-001, FR-004 |
| — `toInsertMap` grava as quatro chaves em português, com data e versão | FR-007 |
| — `toInsertMap` grava as quatro como `null` acima do limiar | FR-008 |
| `test/widget/autorizacao_responsavel_test.dart` — abaixo do limiar aparecem os dois campos e a caixa destacada | FR-001, FR-002 |
| — a caixa é recusável sozinha: marcar só a LGPD não habilita o botão | FR-002 |
| — o texto da caixa diz o que é autorizado e que a identidade não é verificada | FR-003, FR-006 |
| — subir a idade acima do limiar **descarta** o que foi digitado do responsável | FR-008 |
| `test/widget/cadastro_perfil_page_test.dart` — com idade 30, contagem de campos e de caixas **idêntica** à de hoje | FR-005, **SC-003** |
| **`test/integration/autorizacao_responsavel_test.dart`** — insert direto de criança sem autorização é recusado | **FR-009, SC-001** |
| — insert de criança com os quatro campos é aceito, e a leitura traz quem, contato, quando e versão | FR-007, **SC-002** |
| — insert de adulto com campos de responsável é recusado | FR-008 |
| — `update` tentando alterar a autorização gravada é recusado | US2 |
| — a constante Dart `childAgeThreshold` é igual a `select public.limiar_crianca()` | limiar |
| — linha antiga que viola sobrevive à migration, e continua somente-leitura | Assumptions |
| — exclusão de conta de uma criança zera as quatro colunas | Princípio II |
| `test/integration/autorizacao_responsavel_privacidade_test.dart` — outro Usuário lê **0 linhas** | **SC-004** |
| — `perfil_publico()` da criança devolve só `id, nome_exibido, igreja_id` | **SC-004** |
| — `anon` não tem `select` em `perfis` | **SC-004** |

**O teste que mais importa** é o de insert direto recusado. É a diferença entre FR-009 cumprido
e uma validação de tela com discurso de banco — e é o único que percebe se alguém um dia
"simplificar" a constraint para uma checagem no cliente.

## Parte 2 — Verificação manual

```bash
flutter run -d chrome
```

| # | Checagem | Requisito | Esperado |
|---|---|---|---|
| 1 | Cadastro com idade **abaixo** do limiar | FR-001 | Aparecem nome do responsável, contato do responsável e uma caixa destacada, **antes** de concluir |
| 2 | Tentar concluir sem marcar a caixa | FR-004 | Recusa, com o motivo em **uma frase** |
| 3 | Tentar concluir sem o nome, e depois sem o contato | FR-004 | Recusa nos dois casos |
| 4 | Marcar a caixa LGPD comum e **não** a de autorização | FR-002 | Botão continua desabilitado — as duas são independentes |
| 5 | Ler o texto da caixa em voz alta | FR-003, FR-006 | Dá para entender sem advogado, e diz que a identidade do responsável **não é verificada** |
| 6 | Cadastro com idade **acima** do limiar | FR-005, **SC-003** | Nada novo aparece. Mesmo número de campos e de caixas de hoje |
| 7 | Digitar idade de criança, preencher o responsável, e **subir** a idade acima do limiar | FR-008 | O passo some e o que foi digitado é **descartado** — não vai para o banco |
| 8 | Concluir um cadastro de criança e conferir a linha no Studio | FR-007, **SC-002** | Nome, contato, data/hora **e versão** do texto gravados |
| 9 | Conferir a mesma linha de um cadastro de adulto | FR-008 | As quatro colunas **vazias** |
| 10 | Como outro Usuário, abrir a página pública da criança | **SC-004** | Só o Apelido. Nenhum sinal de que existe responsável |
| 11 | Como Visitante (sem cadastro), procurar qualquer rastro do responsável | **SC-004** | Nada. `anon` nem `select` em `perfis` tem |
| 12 | Ler a Política de Privacidade, seção de crianças | FR-010, **SC-005** | Descreve o mecanismo que **existe**, e diz que a identidade não é verificada |
| 13 | Ler `MAPA-DE-DADOS.md` | FR-011, **SC-005** | As quatro colunas na tabela, com finalidade, quem vê e prazo |
| 14 | Ler `REVISAO-JURIDICA.md:88-112` | FR-012, **SC-005** | Não diz mais "não implementada" |
| 15 | Excluir a conta de uma criança e conferir a linha anonimizada | Princípio II | As quatro colunas **nulas**. O nome da mãe não sobrevive |

**O item 12 é o que fecha o ciclo desta feature.** Ela nasceu de a Política afirmar algo que o
código não fazia; se o texto continuar desalinhado depois da entrega, a feature não terminou.

## Parte 3 — À mão, no banco: os quatro caminhos que FR-009 fecha

O que o teste automatizado faz, feito uma vez com o olho, porque FR-009 é sobre caminhos que a
tela não conhece:

```bash
docker exec -i supabase_db_iasd psql -U postgres -d postgres
```

1. **Como `postgres` (superusuário)**: `insert` em `perfis` com idade abaixo do limiar e sem
   responsável → deve ser **recusado**. Superusuário não pula `CHECK`.
2. **Como `authenticated`** (`set local role authenticated` + `request.jwt.claims`): o mesmo
   `insert` → **recusado**.
3. **Como `service_role`**: o mesmo `insert` → **recusado**. É o papel que a política de RLS
   deixaria passar; a constraint não.
4. **`update`** subindo um adulto já cadastrado para idade de criança, sem preencher o
   responsável → **recusado**. É o caminho que a feature 016 vai abrir.

E, na mesma sessão, o experimento que prova que a proteção do registro funciona:

5. Com o JWT da própria criança, `update public.perfis set responsavel_nome = 'Fulano'` na
   própria linha → **recusado** pelo gatilho. Antes desta feature, isso passava: medido,
   `'Maria Mae'` virou `'Fulano Inventado'` com `UPDATE 1`.

Qualquer um dos cinco que passar significa que a regra está só na tela — que é exatamente a
situação que esta feature existe para acabar.

## Definição de pronto

- [ ] `/speckit-clarify` respondeu o **limiar**, e o número está nos dois lugares (banco e
      Dart), com os comentários `PENDENTE` removidos
- [ ] `CONTEXT.md` com **Responsável** e **Criança**, e o `_Avoid_` de Líder/Diretor ajustado,
      commitado **antes** do código (FR-013)
- [ ] Parte 0 feita **antes** da migration, com o número anotado
- [ ] Parte 1 verde, com o número real de cada suíte
- [ ] Os testes de integração pré-existentes passando **sem edição de asserção**
- [ ] Parte 2, itens 1 a 15 — com o item 12 conferido lendo o texto inteiro
- [ ] Parte 3, os cinco caminhos, todos recusados
- [ ] SC-006 medido com gente: uma mãe conclui o cadastro da filha em **até 3 minutos**
- [ ] Nenhum identificador Dart novo em português, inclusive em teste (Princípio I)
- [ ] Nenhuma consulta em `lib/` lê `responsavel_nome` ou `responsavel_contato` (SC-004)
