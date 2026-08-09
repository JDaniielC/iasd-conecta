# Quickstart — validar encerramento, contagem e clareza do título

**Feature**: 011-acoes-titulo-e-encerramento | **Date**: 2026-08-09

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
```

Para a parte de banco:

```bash
supabase start            # sobe Postgres local com as migrations aplicadas
```

## Parte 0 — Verificar as premissas da migration ANTES de escrevê-la

`contracts/schema.sql` depende de duas premissas. Se qualquer uma cair, o plano A (política
de acesso) não serve e vale o plano B de `research.md` D-003.

```bash
supabase db diff --help > /dev/null   # sanity: CLI disponível
psql "$SUPABASE_DB_URL" -c "\
  select p.proname, p.prosecdef as security_definer \
  from pg_proc p join pg_namespace n on n.oid = p.pronamespace \
  where n.nspname='public' and p.proname='excluir_conta';"

psql "$SUPABASE_DB_URL" -c "\
  select relname, relrowsecurity, relforcerowsecurity \
  from pg_class where relname in ('confirmacoes_acao','acoes');"
```

**Esperado**: `excluir_conta` com `security_definer = t`; `confirmacoes_acao` com
`relrowsecurity = t` e `relforcerowsecurity = f`.

**Se `relforcerowsecurity = t`**: parar e ir para o plano B. Seguir mesmo assim cria um bug
de exclusão de conta (LGPD), não um bug de UX.

## Parte 1 — Gates automatizados

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration          # exige supabase start
flutter build web
```

**Resultado esperado**: 0 falhas. Anotar o número real de testes que passaram em cada suíte —
não "os testes passaram".

**Atenção especial**: os testes de integração que já existem e cobrem regras do Princípio IV
devem passar **sem edição**. Se algum precisar mudar, esta feature vazou do escopo:

```
test/integration/confirmar_idempotente_test.dart
test/integration/apuracao_empate_test.dart
test/integration/cancelar_acao_grupo_test.dart
test/integration/dupla_missionaria_promocao_pula_invalido_test.dart
test/integration/dupla_missionaria_composicao_valida_mesmo_genero_test.dart
```

### O que cada teste novo prova

| Teste | Requisito |
|---|---|
| `test/unit/acao_encerramento_test.dart` — fronteiras `-1s`, `+0s`, `+4h`, `+4h+1s` | FR-001, FR-002 |
| `test/unit/acao_nome_criador_test.dart` — igualdade após normalizar caixa, acento e espaço | FR-017 |
| `test/unit/acao_nome_criador_test.dart` — "Visita a José" é aceita | FR-019 |
| `test/widget/lista_acoes_page_test.dart` — Ação de 4h01 atrás não aparece, em nenhuma seção | FR-003, SC-001 |
| `test/widget/lista_acoes_page_test.dart` — mesma Ação com "Só Sábado" ligado também não aparece | FR-003, SC-001 |
| `test/widget/lista_acoes_page_test.dart` — Ação de 1h atrás aparece como acontecendo agora | FR-002 |
| `test/widget/lista_acoes_page_test.dart` — card com 3 confirmados mostra "3 confirmados"; com 0 mostra "Ninguém confirmou ainda"; com 1 mostra o singular | FR-009, FR-010, FR-011 |
| `test/widget/lista_acoes_page_test.dart` — com limite, mostra "4 de 10 vagas"; lotada com fila, mostra a fila separada | FR-012, FR-013 |
| `test/widget/detalhe_acao_page_test.dart` — Ação encerrada abre, mostra o rótulo, e não tem botão de confirmar/desistir/cancelar | FR-004, FR-005, SC-004 |
| `test/widget/detalhe_acao_page_test.dart` — confirmados numerados 1., 2., 3.; fila numerada recomeçando em 1. | FR-020, FR-021 |
| `test/widget/detalhe_acao_page_test.dart` — sem ninguém confirmado, mensagem de vazio, não lista numerada vazia | FR-023 |
| `test/widget/criar_acao_page_nome_test.dart` — nome igual ao do criador é recusado com a mensagem de FR-018 | FR-017, FR-018, SC-006 |
| `test/widget/criar_acao_page_nome_test.dart` — nome do criador indisponível (RPC falhando) **não** bloqueia a criação | research D-005 |
| `test/integration/acao_encerrada_nao_promove_fila_test.dart` — em Ação encerrada, o `delete` de `confirmacoes_acao` é recusado e ninguém sobe da fila | **FR-007, Princípio IV** |
| `test/integration/acao_encerrada_nao_promove_fila_test.dart` — em Ação **não** encerrada, desistir ainda promove o próximo da fila | FR-006, não-regressão |
| `test/integration/acao_encerrada_nao_promove_fila_test.dart` — `excluir_conta` continua apagando `confirmacoes_acao` de Ação encerrada | Risco 1 do plano — LGPD |

O último é o teste mais importante desta feature. Ele é o que impede o bloqueio de FR-007 de
virar um bug de exclusão de conta.

**Como controlar o tempo nos testes de widget**: sobrescrever `clockProvider` com uma função
que devolve um instante fixo, e construir as Ações relativas a esse instante. Nenhum teste
pode depender de `DateTime.now()` real.

## Parte 2 — Verificação manual

```bash
flutter run -d chrome
```

| # | Checagem | Requisito | Esperado |
|---|---|---|---|
| 1 | A Ação de 08/08/2026 19:15 do reporte | FR-003 | Sumiu da listagem |
| 2 | Abrir essa Ação pelo link direto | FR-004 | Abre, marcada como encerrada, com quem participou |
| 3 | Nessa tela, procurar botões | FR-005 | Sem "Confirmar presença", sem "Desistir", sem cancelar |
| 4 | Criar Ação para daqui a 1 hora, e outra para 5 horas atrás | FR-001, FR-002 | A primeira na lista; a segunda não |
| 5 | Criar Ação para 2 horas atrás | FR-002 | Aparece como acontecendo agora, e ainda aceita confirmar |
| 6 | Olhar os cards da lista | FR-009 a FR-013 | Contagem correta em todos, inclusive nos de zero |
| 7 | Abrir a lista **sem cadastro** (Visitante) | FR-014 | As mesmas contagens aparecem |
| 8 | Inspecionar o tráfego da listagem (DevTools → Network) | Princípio II | A resposta de `confirmacoes_acao` traz **só** `acao_id` e `status`. Se aparecer `usuario_id`, parar: é vazamento de identidade |
| 9 | Criar Ação digitando o próprio nome no campo de nome | FR-017, FR-018 | Recusa, com a mensagem explicando e dando exemplo |
| 10 | O mesmo com outra capitalização, sem acento, com espaços sobrando | FR-017, SC-006 | Recusa igual |
| 11 | Criar Ação chamada "Visita a José" | FR-019 | Aceita |
| 12 | Propor Ação candidata numa Rodada com o próprio nome | FR-016, FR-017 | Mesma recusa, mesmo texto de apoio |
| 13 | Abrir Ação com 3 confirmados e 2 na fila | FR-020, FR-021 | Confirmados 1., 2., 3.; fila numerada recomeçando em 1. |
| 14 | Um dos confirmados desiste; recarregar | FR-022 | Numeração contígua, sem buraco |
| 15 | Ação cancelada **e** com data passada | FR-008 | Rótulo mostrado é "Cancelada" |
| 16 | Rodada de votação com candidata de data passada | edge case da spec | Candidata continua visível dentro da Rodada |
| 17 | Leitor de tela na lista de Confirmados | FR-024 | A posição é anunciada junto do nome |
| 18 | Deixar a tela aberta atravessando o instante do encerramento | edge case da spec | A Ação **não** some sozinha; só sai na próxima carga |

## Definição de pronto

- [ ] Parte 0 conferida **antes** de escrever a migration, com a saída real das duas consultas
- [ ] Parte 1 verde, com o número real de testes de cada suíte anotado
- [ ] Os 5 testes de integração pré-existentes passando **sem edição**
- [ ] O teste de `excluir_conta` em Ação encerrada passando
- [ ] Item 8 conferido no tráfego real — é o único jeito de provar a invariante de privacidade
- [ ] Parte 2, itens 1 a 18, conferidos
- [ ] `CONTEXT.md` não precisou de alteração (nenhum termo novo de domínio)
