# Quickstart — validar Arquivar Grupo

**Feature**: 014-arquivar-grupo | **Date**: 2026-08-09

Esta feature toca **quatro das cinco** regras centrais do Princípio IV. A validação é menos
sobre "o botão funciona" e mais sobre provar que **nada** foi apurado, apagado ou promovido.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start
```

Se `supabase start` reclamar de nome de container em uso, `supabase stop --no-backup` e
subir de novo. Se reclamar de espaço, o Docker está cheio — foi o que derrubou o Postgres
durante a feature 011.

## Parte 1 — Gates automatizados

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration          # exige supabase start
flutter build web
```

**Anotar o número real de cada suíte.** Nunca "os testes passaram".

**Linha de base ao começar** (main em 2026-08-09): `analyze` 0 issues, **152** unit/widget,
**127** integração.

### Os testes de integração que já existem e NÃO podem mudar

Se algum deles precisar de edição de asserção, a feature vazou do escopo — ela promete não
alterar apuração, empate nem fila:

```
test/integration/apuracao_vencedora_test.dart
test/integration/apuracao_empate_test.dart
test/integration/apuracao_presenca_test.dart
test/integration/apuracao_sem_candidata_test.dart
test/integration/confirmar_idempotente_test.dart
test/integration/dupla_missionaria_promocao_pula_invalido_test.dart
test/integration/acao_encerrada_nao_promove_fila_test.dart
```

### O que cada teste novo prova

| Teste | Requisito |
|---|---|
| `test/unit/group_archive_test.dart` — `isArchived` derivado de `archivedAt` | FR-010 |
| `test/widget/archive_group_sheet_test.dart` — a confirmação mostra os quatro números reais | FR-003, SC-001 |
| `…` — com tudo zerado, diz em palavras que nada será perdido, não quatro zeros | FR-004 |
| `…` — Ministério com Líder confirmado ganha o aviso extra | FR-005 |
| `…` — desistir da confirmação não dispara chamada nenhuma | FR-006, SC-002 |
| `…` — participante que não é Dono não vê a opção | FR-002 |
| `test/widget/lista_grupos_page_test.dart` — Grupo arquivado não aparece, sob nenhum filtro | FR-010, SC-003 |
| **`test/integration/arquivar_grupo_efeitos_test.dart`** | **Princípio IV, os quatro** |
| — Ações futuras ficam canceladas; Ação passada **intacta** | FR-014 |
| — **nenhuma presença apagada** (contagem antes = depois) | FR-015, SC-006 |
| — **ninguém promovido da fila** | fila de espera |
| — Rodada aberta fecha com `vencedora_id` **nulo** | FR-007, SC-005 |
| — **todas** as candidatas descartadas, nenhuma virou Ação confirmada | descarte |
| — Rodada já fechada e sua apuração **intactas** | FR-014, SC-009 |
| — `participacoes_grupo` **não perdeu nenhuma linha** | FR-017 |
| `test/integration/arquivar_grupo_permissao_test.dart` — participante comum é recusado | FR-002 |
| — Dono arquiva o próprio; Administrador arquiva qualquer um | FR-001 |
| — Grupo já arquivado é recusado | FR-009 |
| — desarquivar: só Administrador; Dono é recusado | FR-018 |
| — depois de desarquivar, participantes voltam sem ação deles | FR-021, SC-007 |
| — depois de desarquivar, as Ações canceladas **continuam canceladas** | FR-022 |
| — Grupo arquivado recusa participar, propor candidata, abrir Rodada e votar | FR-011, FR-012, SC-004 |

**O teste que mais importa** é o de `vencedora_id` nulo. É a prova de que o arquivamento não
chamou `fechar_rodada_se_devido` — se alguém "simplificar" a função um dia reusando ela, este
teste é o único que percebe.

## Parte 2 — Verificação manual

```bash
flutter run -d chrome
```

| # | Checagem | Requisito | Esperado |
|---|---|---|---|
| 1 | Como Dono, abrir um Grupo com 2 Ações futuras, 5 presenças e 1 Rodada aberta, e acionar arquivar | FR-003 | A confirmação mostra os **quatro números certos** antes de qualquer coisa acontecer |
| 2 | Desistir da confirmação | FR-006 | Nada mudou: Grupo, Ações, Rodada e presenças no mesmo estado |
| 3 | Confirmar | FR-007 | Grupo sai da lista; Ações futuras aparecem canceladas; Rodada encerrada |
| 4 | Abrir o Grupo pelo link direto | FR-013 | Abre, marcado como arquivado — não dá erro |
| 5 | Abrir uma Rodada **já fechada** dele por link | FR-014 | A apuração continua lá, intacta |
| 6 | Como outro Usuário, tentar participar do Grupo arquivado | FR-011 | Não consegue |
| 7 | Como participante, tentar propor candidata, abrir Rodada e votar | FR-012 | Nenhum dos três |
| 8 | Como Visitante, procurar quem é o Líder/Diretor de um **Ministério arquivado** | **FR-016** | **Não encontra.** Se ainda aparecer, é o risco 4 do plano: a consulta do Líder não filtrou |
| 9 | Arquivar Grupo sem nada a perder | FR-004 | A confirmação diz em palavras, não mostra quatro zeros |
| 10 | Arquivar Ministério com Líder confirmado | FR-005 | O aviso sobre a identificação pública aparece |
| 11 | Como Administrador, ver a lista de arquivados | FR-019 | Mostra quem arquivou e quando |
| 12 | Desarquivar | FR-020, FR-021 | Grupo volta à lista, participantes voltam sem fazer nada |
| 13 | Antes de confirmar o desarquivamento | FR-022 | A tela avisa que Ações canceladas e Rodadas encerradas **não** voltam |
| 14 | Depois de desarquivar, olhar as Ações | FR-022 | Continuam canceladas — o aviso era verdade |
| 15 | Como Dono, tentar desarquivar | FR-018 | Não encontra a opção |
| 16 | Lista de Ações, filtro por Igreja | research D-006 | Ações **passadas** do Grupo arquivado continuam agrupadas na Igreja certa |
| 17 | Grupo arquivado com Foto de capa (feature 013) | interação | A capa continua lá — o Grupo não foi apagado |

**O item 8 é o único que falha em silêncio.** Todos os outros gritam quando quebram.

## Parte 3 — Contagem, à mão

O que o teste automatizado faz, feito uma vez com o olho, porque estado parcial é o modo de
falha desta feature:

1. Anotar, para um Grupo com atividade: nº de Ações futuras, de presenças confirmadas nelas,
   de Rodadas abertas, de participantes, e o nº de Rodadas **já fechadas**.
2. Arquivar.
3. Conferir:
   - Ações futuras: todas com `cancelada_em` preenchido.
   - Presenças: **contagem idêntica** à do passo 1. Nenhuma sumiu.
   - Rodadas antes abertas: `fechada_em` preenchido, `vencedora_id` **nulo**.
   - Candidatas daquelas Rodadas: **zero** linhas restantes.
   - Rodadas já fechadas: `vencedora_id` **inalterado**.
   - `participacoes_grupo`: **contagem idêntica**.

Qualquer divergência aqui é estado parcial — e estado parcial numa operação que deveria ser
atômica significa que a transação da função não está fazendo o trabalho.

## Definição de pronto

- [ ] `CONTEXT.md` com os dois termos novos, commitado **antes** do código (FR-023)
- [ ] Parte 1 verde, com o número real de cada suíte
- [ ] Os 7 testes de integração pré-existentes passando **sem edição**
- [ ] Parte 2, itens 1 a 17 — **com o item 8 conferido especificamente**
- [ ] Parte 3 conferida à mão, com os números anotados
- [ ] Nenhum identificador Dart novo em português, inclusive em teste (Princípio I)
