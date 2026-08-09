# Quickstart — provar que o voto parou de vazar

**Feature**: 021-visibilidade-do-voto | **Data**: 2026-08-09

Guia de validação. O que é automatizável está em `test/integration/`; o que exige olho
humano está na Parte 3.

## Pré-requisitos

```bash
docker ps --filter name=supabase_db --format "{{.Names}} {{.Status}}"   # precisa estar healthy
supabase start                                                          # se não estiver
supabase db reset                                                       # aplica a migration nova
```

Se `supabase start` falhar com `No space left on device`, o Docker está sem espaço — é um
problema conhecido deste ambiente, e limpar imagens é decisão sua, não do agente.

## Parte 1 — Os gates (automatizado)

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration
flutter build web
```

Anote os **números reais**. "Os testes passaram" sem contagem não é verificação.

Esperado: nenhum teste de unidade ou widget muda de resultado — a feature não toca
`lib/` além de uma string de texto legal.

## Parte 2 — O teste que é a feature (automatizado)

```bash
dart test test/integration/votos_visibilidade_test.dart
```

Ele precisa cobrir, no mínimo, estes seis casos. Os cinco primeiros são a feature; o sexto
é a bomba que a feature arma.

| # | Caso | Esperado | Requisito |
|---|---|---|---|
| 1 | Visitante (`anon`) consulta `votos` com votos gravados | 0 linhas, **sem erro** | FR-001 |
| 2 | Usuário cadastrado, fora do Grupo, consulta | 0 linhas | FR-002 |
| 3 | Participante do Grupo consulta os votos alheios | 0 linhas | FR-004 |
| 4 | A pessoa consulta o próprio voto | 1 linha, a candidata certa | FR-003 |
| 5 | A pessoa **troca de voto** com a política nova aplicada | a linha vira a segunda candidata; só a última conta | FR-008 |
| 6 | Rodada com maioria numa candidata fecha | a **majoritária** vence, mesmo quem fechou tendo votado noutra | FR-009 |

O caso 6 é o que impede o desastre silencioso. Ele precisa ser montado assim: **quem chama
`fechar_rodada_se_devido` votou na candidata perdedora**. Se a apuração deixar de rodar por
fora da RLS, ela conta só o voto de quem chamou, e a candidata desse chamador vence.
Um teste em que o vencedor coincide com quem fechou a Rodada **não detecta nada**.

O caso 1 precisa distinguir lista vazia de erro de permissão. Se a consulta levantar
exceção em vez de devolver 0 linhas, o tamanho da resposta vira canal lateral e a invariante
5 do `data-model.md` quebrou.

Padrão do repositório para trocar de identidade dentro do teste — o mesmo `_asUser` de
`acao_encerrada_nao_promove_fila_test.dart:24-36`:

```dart
await conn.execute('set role authenticated');
await conn.execute(
    "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'");
// ... e no finally: reset role; reset request.jwt.claims
```

**Idioma** (Princípio I): identificadores em **inglês** dentro do arquivo — `voter`,
`candidate`, `votingRoundId`, `closeRound`. Só o **nome do arquivo** fica em português,
seguindo a convenção que já existe em `test/integration/`.

## Parte 3 — Verificação manual

Cinco itens. Os dois primeiros só você pode fazer.

### 3.1 A API de verdade, sem cadastro (FR-005)

O teste de integração fala com o Postgres direto. Isto fala com o PostgREST, que é por onde
o vazamento acontece de verdade.

```bash
# ANON_KEY vem de `supabase status` — é chave pública, pode aparecer no terminal
curl -s "http://127.0.0.1:54321/rest/v1/votos?select=*" \
  -H "apikey: $ANON_KEY"
```

**Esperado**: `[]`.

**Antes da migration este mesmo comando devolve a tabela inteira.** Rode antes e depois —
o contraste é a prova da feature, e vale mais que qualquer descrição.

### 3.2 Depois de publicar (FR-005, produção)

O mesmo `curl` contra o ambiente publicado, com a chave anônima de produção. Precisa
devolver `[]`.

Enquanto a feature 019 não fechar o que se sabe sobre produção, este passo é o único jeito
de saber que a correção chegou lá.

### 3.3 A tela da Rodada não mudou (FR-010)

Abra uma Rodada com votos de mais de uma pessoa:

- [ ] A candidata em que **você** votou aparece marcada.
- [ ] Trocar de candidata funciona, e a marcação segue.
- [ ] Nenhuma contagem de votos aparece na tela — se aparecer, alguém adicionou junto e
      isso está fora do escopo desta feature.

### 3.4 A Política diz a verdade (FR-012)

Abra a Política de Privacidade no app e leia o item sobre voto
(`privacy_policy_page.dart:131-133`).

- [ ] Não diz mais "o voto não é anônimo **entre os participantes do Grupo**", porque agora
      nem os participantes leem.
- [ ] O que está escrito é exatamente o que o `curl` do 3.1 demonstra.

Este item é a feature tanto quanto a migration. Trocar um texto falso por outro texto falso
não resolve nada.

### 3.5 Os documentos (FR-013, FR-014)

- [ ] `MAPA-DE-DADOS.md:66` não lista mais `votos_select_public` como leitura irrestrita
      vigente — nome e regra atualizados.
- [ ] A decisão está registrada com o **motivo** (por que "só o próprio voto" e não "os
      participantes do Grupo"). Sem o motivo, `using (true)` volta na próxima feature que
      precisar ler a tabela — foi exatamente assim que ele sobreviveu até aqui.

## Como saber que falhou

| Sintoma | Significa |
|---|---|
| `curl` anônimo devolve linhas | A política não pegou. Confira se `drop policy` e `create policy` rodaram, e se não sobrou outra política de `select` na tabela — políticas se somam por `OR`. |
| Trocar de voto passou a dar erro | Só acontece se a política ficou mais apertada que o desenho. A linha em conflito é sempre a da própria pessoa. |
| Uma Rodada fechou elegendo a candidata de quem a fechou | A apuração parou de rodar fora da RLS. É o modo de falha do caso 6 — e as candidatas perdedoras já foram apagadas. |
| Consulta anônima devolve erro em vez de `[]` | Alguém revogou o `grant select` de `anon`. O erro vira canal lateral. |
