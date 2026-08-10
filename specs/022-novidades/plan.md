# Implementation Plan: Novidades — o que mudou no app

**Branch**: `022-novidades` | **Date**: 2026-08-10 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/022-novidades/spec.md`

## Summary

Uma tela que lista, em português voltado a quem usa o app, o que mudou desde o lançamento ao
distrito em 6 de outubro de 2026 — mais um aviso na Home quando há item que a pessoa ainda não
viu.

A lista é **conteúdo compilado**, no mesmo padrão dos textos legais. O marcador de "já vi" fica
**no aparelho**, com `shared_preferences` — que a medição mostrou já estar no bundle, arrastado
por `supabase_flutter`.

**Nenhuma migration, nenhuma coluna, nenhuma chamada nova ao servidor.** A feature é cliente
puro, e essa é a propriedade que a torna defensável: ler novidades não pode criar um registro
sobre quem leu.

**A tela nasce vazia.** O marco é futuro — hoje é 10 de agosto de 2026 —, então no dia em que
esta feature entrar não haverá nenhum item. Isso não é defeito: é o estado inicial, e a tela
tem de explicá-lo. Ver [research.md](./research.md) D-004 e a primeira Assumption da spec.

## Technical Context

**Language/Version**: Dart 3 / Flutter (canal estável do projeto)

**Primary Dependencies**: `flutter_riverpod`, `go_router`, `intl` (formatação de data) e
**`shared_preferences` promovido de transitivo para direto** — ver research D-001. Nenhuma
dependência nova de verdade entra no bundle.

**Storage**: **nenhum banco.** O único estado persistido é uma string de data no armazenamento
local do aparelho (`localStorage` na web, preferências nativas no móvel).

**Testing**: `flutter test test/unit test/widget`. **Sem teste de integração**, e é uma
afirmação, não um esquecimento: não há nada no Postgres para testar. Se esta feature vier a
precisar de `dart test test/integration`, ela passou a falar com o servidor e o desenho
quebrou.

**Target Platform**: Flutter Web (alvo publicado) e móvel.

**Project Type**: App móvel/web com backend gerenciado. Esta feature não toca o backend.

**Performance Goals**: nenhuma meta nova. A lista é uma constante em memória, com dezenas de
itens no horizonte previsível.

**Constraints**: nada sobre a leitura pode ir ao servidor (FR-012); a Política não pode ganhar
frase nova (FR-014).

**Scale/Scope**: 1 tela, 1 lista de conteúdo, 1 marcador local, ~4 arquivos de produção.

## Constitution Check

*GATE: avaliado antes da Phase 0 e reavaliado após a Phase 1.*

### I. Linguagem Ubíqua do Domínio (NON-NEGOTIABLE) — ⚠️ passa, com uma entrada a criar

**Novidade** é termo novo de domínio e **precisa entrar em `CONTEXT.md` antes do código** —
com `_EN_` (`NewsItem` / `news`) e `_Avoid_` dizendo que não é changelog, não é release note e
não é aviso do sistema. É a primeira tarefa da fase de setup.

**Fronteira de idioma**: todo identificador Dart em **inglês**, inclusive dentro de arquivos de
teste; só o **nome do arquivo** de teste fica em português. Nenhuma chave de banco aparece aqui
— não há banco. As traduções fixadas: Novidade→`NewsItem`, marcador de leitura→`lastSeenNewsDate`,
marco de lançamento→`launchDate`.

**Colisão a evitar**: o app já tem `LegalMetadata.version`, que é versão de **texto legal**.
Novidade não tem versão e não deve ganhar uma — ver Complexity Tracking.

### II. Privacidade e LGPD por Padrão (NON-NEGOTIABLE) — ✅ passa, e é o eixo do desenho

Declaração exigida pela seção "Requisitos de Domínio e Compliance":

| Pergunta | Resposta |
|---|---|
| Qual dado pessoal | **Nenhum.** A feature não lê nem escreve `perfis`, não chama RPC, não faz `select` |
| Finalidade | — |
| Quem pode ver | A lista é igual para todo mundo, inclusive Visitante sem cadastro |
| Consentimento adicional | Nenhum, e **FR-014 é o teste disso**: se a Política precisar de frase nova, a feature passou a coletar algo |

O único estado guardado é "até que data esta instalação já viu", **no aparelho**. A alternativa
óbvia — uma coluna em `perfis` — criaria dado de comportamento sem finalidade autorizada, e
está rejeitada com o porquê em research D-001.

### III. Desenvolvimento Guiado por Spec — ⚠️ passa, com ressalva registrada

`/speckit-specify` → este `/speckit-plan`. `/speckit-clarify` **não** foi rodado, e há uma
ambiguidade real que ele resolveria: a data `06/10/26` foi lida como **6 de outubro de 2026**
(dia/mês/ano), o que a torna futura e faz a lista nascer vazia.

A spec registra isso como primeira Assumption, com a consequência escrita. Não bloqueia o
plano — o marco é uma constante e o desenho já trata lista vazia como caso de primeira classe
(FR-007). Mas **é a única coisa nesta feature que vale confirmar antes de implementar**: se a
intenção era listar retroativamente as 21 features já entregues, o trabalho de escrita muda de
tamanho, ainda que o código não mude.

### IV. Integridade das Regras de Domínio Testada (NON-NEGOTIABLE) — ✅ passa, sem contato

A feature não encosta em **nenhuma** das cinco regras: fila de espera, desempate por sorteio,
revogabilidade de voto e de Participar, descarte de candidatas, composição de Dupla
Missionária. Não lê nem escreve `acoes`, `grupos`, `rodadas_votacao`, `votos`,
`confirmacoes_acao` nem `participacoes_grupo`.

Declarado como o Princípio manda, e verificável: se a implementação tocar qualquer uma dessas
tabelas, ela vazou do escopo.

### V. Simplicidade e Papéis Mínimos — ✅ passa

Nenhum papel novo; a tela é idêntica para Visitante, Usuário, Dono do Grupo, Líder/Diretor e
Administrador do distrito. Sem tabela, sem RPC, sem tela de administração, sem "marcar item
como lido", sem notificação. Cada uma dessas foi considerada e rejeitada por não ter sido
pedida — ver research D-001 e D-005.

**Resultado do gate**: aprovado, com uma entrada de glossário a criar (Princípio I) e uma
confirmação recomendada sobre a data (Princípio III).

### Reavaliação pós-Phase 1

Sem mudança. O desenho final ficou **menor** que o gate inicial previa: a descoberta de que
`shared_preferences` já está no bundle eliminou a única dependência nova que eu esperava
justificar. Nenhuma violação nova. ✅

## Project Structure

### Documentation (this feature)

```text
specs/022-novidades/
├── plan.md              # Este arquivo
├── research.md          # Phase 0 — 6 decisões, 3 medidas no repositório
├── data-model.md        # Phase 1 — a entidade e o marcador; nenhuma tabela
├── quickstart.md        # Phase 1 — como provar que funcionou
├── contracts/
│   └── news_content.md  # Phase 1 — o contrato de ESCRITA das novidades
├── checklists/
│   └── requirements.md  # do /speckit-specify
└── tasks.md             # do /speckit-tasks — NÃO criado aqui
```

### Source Code (repository root)

```text
lib/features/news/
├── domain/
│   └── news_item.dart          # NOVO — NewsItem, a lista const, e o marco
├── data/
│   └── news_repository.dart    # NOVO — lê e grava o marcador local
├── news_providers.dart         # NOVO — lista visível e "há algo novo?"
└── presentation/
    └── news_page.dart          # NOVO — a tela

lib/app.dart                    # EDITADO — a rota /novidades
lib/features/home/presentation/home_page.dart   # EDITADO — entrada + aviso
pubspec.yaml                    # EDITADO — shared_preferences explícito
CONTEXT.md                      # EDITADO — a entrada Novidade
CRITERIO-DE-NOVIDADE.md         # NOVO — a regra de admissão (FR-017)

test/unit/novidades_test.dart           # NOVO
test/widget/novidades_page_test.dart    # NOVO
```

**Structure Decision**: pasta própria `lib/features/news/`, seguindo
`lib/features/<nome>/{domain,data,presentation}` como todas as outras. Não vai em
`features/legal/` — o assunto é o app, não conformidade — nem em `features/home/`, porque a
Home é só o ponto de entrada.

**O que esta feature deliberadamente NÃO toca**: nenhum arquivo em `supabase/`, nenhum
repositório existente, nenhum provider que fale com o servidor. `pubspec.yaml` muda **só** para
declarar o que já é transitivo — a versão do app (`1.0.0+1`) fica como está, porque número de
versão é para quem constrói e FR-003 o proíbe na tela.

## Complexity Tracking

> Preenchido porque o gate do Princípio I saiu com pendência e o do III com ressalva.

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|--------------------------------------|
| Termo novo de domínio (**Novidade**) antes de haver código que o use | O Princípio I exige que o termo entre em `CONTEXT.md` antes de virar código, e "Novidade" tem três vizinhos com que se confundir: changelog (técnico), release note (de versão) e aviso do sistema (que o app não tem). Sem a entrada, o próximo a mexer usa os três como sinônimos | Não há alternativa: é exigência da constituição, e o custo é uma entrada de glossário |
| A feature entra com a lista **vazia** | O marco de lançamento é 6/10/2026 e hoje é 10/08/2026. Entregar só depois do marco deixaria a tela pronta e não usada por dois meses, e o custo de tê-la vazia é uma frase explicando | **Alternativa 1 — esperar outubro**: rejeitada, adia trabalho pronto sem ganho. **Alternativa 2 — listar retroativamente as 21 features**: é a leitura alternativa da data, e muda o tamanho da escrita, não o código; registrada como a linha que `/speckit-clarify` move. **Alternativa 3 — antecipar o marco para 23/07/2026**: rejeitada por contrariar o que foi pedido |
| Promover `shared_preferences` a dependência direta | O app precisa persistir uma string por instalação, e não declara nenhum pacote de armazenamento. Custo de bundle: **zero** — já entra por `supabase_flutter` | **Alternativa — usar o pacote sem declarar**, já que funciona hoje: rejeitada. Dependência transitiva some quando quem a arrasta muda de ideia, e a quebra apareceria numa feature que ninguém tocou |
