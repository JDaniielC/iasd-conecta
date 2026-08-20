## Why

A cobertura nunca foi medida neste repo — não havia alvo de `coverage` no
Makefile nem `--coverage` no `ci.yml`. Medida pela primeira vez em 2026-08-20:

```
flutter test --coverage test/unit test/widget   → 469 testes, All tests passed
total                          2993/4824  = 62,0%
lib/features/*/data/ (repos)     13/693   =  1,9%
resto (UI, providers, domain)  2980/4131  = 72,1%
```

Os 1,9% de `data/` não são buraco: quem exercita repositório é
`dart test test/integration`, que não entra nesse lcov. O buraco real está na
camada de apresentação, e é concentrado — dez páginas somam **476 linhas com
1,5% cobertas (7 linhas)**, sendo que quatro delas (`voting_round_detail_page` 0/66,
`create_voting_round_page` 0/44, `declare_leadership_page` 0/40,
`voting_round_list_page` 0/24) são a Rodada de votação e a Declaração de
liderança, exatamente as regras que o Princípio IV da constituição chama de
inegociáveis (desempate por sorteio, revogabilidade de voto, descarte de
candidatas perdedoras).

O Princípio IV hoje diz "teste automatizado **antes de ser considerada
pronta**". Isso é teste-antes-de-fechar, não teste-primeiro — e o resultado
medido acima é o que essa redação permite: a regra tem teste em algum lugar da
suíte de integração, e a tela que a pessoa usa não tem nenhum.

## What Changes

- **Emenda ao Princípio IV da constituição** (`.specify/memory/constitution.md`,
  1.1.0 → 1.2.0, MINOR por expansão material): de "teste antes de pronto" para
  **teste-primeiro** — o teste que descreve o comportamento novo DEVE existir e
  DEVE falhar antes do código de produção que o satisfaz. Inclui o Sync Impact
  Report exigido pela seção Governance.
- **Seção operacional no `CLAUDE.md`**: o *quando* e o *como* do ciclo
  vermelho-verde neste repo — o que conta como teste que falha primeiro, o que
  fazer quando a mudança é em RLS (onde o vermelho vem de `affectedRows`, não de
  exceção), e as exceções declaradas.
- **Testes de widget para as dez páginas em ~0%**: `create_group_page`,
  `manage_suggested_actions_page`, `voting_round_detail_page`,
  `create_voting_round_page`, `declare_leadership_page`, `archived_groups_page`,
  `promote_admin_page`, `login_page`, `pending_declarations_page`,
  `voting_round_list_page`.
- **Alvo de cobertura no Makefile** (`make coverage`) que mede, imprime o número
  e **reprova se o piso cair**. O piso é travado no número medido quando esta
  change fechar; ele sobe, nunca desce.
- **`ci.yml` roda o gate** no job `fast`, junto de `flutter analyze`.
- **Denominador declarado**: `lib/features/*/data/**` sai da conta do gate, com
  o motivo escrito no alvo — quem prova essa camada é `test/integration`, e
  incluí-la faria o piso medir a ausência da integração, não a cobertura.
  `lib/main.dart` também sai (bootstrap, sem lógica testável).

Nenhuma mudança de comportamento do app. Nada de **BREAKING**.

## Capabilities

### New Capabilities

- `disciplina-de-teste`: quando um teste precisa existir em relação ao código
  que ele prova (teste-primeiro), o que a medição de cobertura conta e o que ela
  deliberadamente não conta, e o que o gate reprova.

### Modified Capabilities

<!-- Nenhuma. `suite-de-integracao` continua valendo sem alteração: ela fala do
     determinismo e do papel de banco da suíte de integração, não de quando o
     teste é escrito nem de piso de cobertura. -->

## Impact

- `.specify/memory/constitution.md` — Princípio IV reescrito, versão 1.2.0,
  Sync Impact Report atualizado. A seção Governance exige conferir
  `plan-template.md`, `spec-template.md` e `tasks-template.md` depois da emenda.
- `CLAUDE.md` — seção nova de fluxo TDD.
- `Makefile` — alvo `coverage` novo. `deploy-web` não muda (ele já depende da
  prova de CI verde, e o gate novo entra dentro dessa prova).
- `.github/workflows/ci.yml` — job `fast` passa a rodar `make coverage`.
- `test/widget/` — dez arquivos novos.
- Nenhum arquivo em `lib/` muda de comportamento. Se um teste novo revelar
  defeito numa dessas páginas, o conserto é change própria, e o achado vai para
  `PENDENCIAS.md`.
