# Implementation Plan: Versão do texto aceito no consentimento

**Branch**: `017-versao-do-consentimento` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/017-versao-do-consentimento/spec.md`

## Summary

Hoje o aceite grava **quando**, nunca **o quê**. Esta feature faz o banco carimbar, junto do
instante do aceite, a versão do texto legal vigente naquele instante — e faz isso de um jeito
em que **nenhum valor mandado pelo cliente sobrevive**.

A frase que resume o desenho, e que resolve a tensão central do FR-004:

> **O cliente diz SE a pessoa aceitou. O banco diz QUANDO e SOB QUAL TEXTO.**

Quatro peças:

1. **Registro de versões no banco** — `public.versoes_texto_legal`, uma linha por versão
   publicada, alimentada só por migration. É daqui que sai a resposta de "qual texto está
   vigente agora", via `public.versao_texto_legal_vigente()`.
2. **Duas colunas em `public.perfis`** — `consentimento_lgpd_versao` e
   `consentimento_lgpd_igreja_versao`, **anuláveis**, cada uma ao lado do `_aceito_em` que já
   existe, com chave estrangeira para o registro de versões.
3. **Um gatilho `before insert or update`** que carimba as duas colunas (e o próprio
   `_aceito_em`) sempre que um aceite entra ou muda, e que **restaura o valor antigo** quando
   o aceite não mudou. É ele que cumpre FR-004 e, de quebra, torna impossível o preenchimento
   retroativo de FR-007 — nem um cliente autenticado, nem uma escrita direta na tabela
   consegue inventar uma versão.
4. **Uma função de consulta agregada** `public.consentimentos_por_versao()`, restrita ao
   Administrador do distrito, que responde em um passo quantas pessoas estão sob cada versão e
   quantas estão sob versão **desconhecida**.

Os aceites antigos **não são preenchidos**. Versão desconhecida é `null` — sem valor sentinela,
sem `not null`, sem palpite.

O lado Dart quase não muda: `Profile.toInsertMap` **continua não mandando versão nenhuma**, e
`LegalMetadata.version` continua sendo o número que as páginas legais exibem. A gêmea de
banco e a constante Dart são amarradas por um teste de integração que falha se divergirem.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: `flutter_riverpod ^3.3.2`, `go_router ^17.3.0`,
`supabase_flutter ^2.8.0`, `postgres` (só em `test/integration`). **Nenhuma dependência nova.**

**Storage**: PostgreSQL via Supabase. Tabelas envolvidas: `public.perfis` (2 colunas novas) e
`public.versoes_texto_legal` (**tabela nova**, de referência, não de dado pessoal). Uma função
de gatilho, uma função de leitura da versão vigente e uma função de consulta agregada.

**Testing**: `flutter_test` + `mocktail` (unit/widget) e `dart test test/integration` contra o
Supabase local. Gates de `.github/workflows/ci.yml`: `flutter analyze`,
`flutter test test/unit test/widget`, `dart test test/integration`, `flutter build web`.
Base em `main`: **0 issues**, **152** unit/widget, **127** integração.

**Target Platform**: Flutter web (deploy atual) + Android/iOS.

**Project Type**: app Flutter organizado por feature, com a regra de domínio morando no banco
(gatilhos, políticas, funções) e o cliente como espelho de feedback.

**Performance Goals**: irrelevante em volume — o gatilho roda uma vez por cadastro, e a
consulta agregada roda sob demanda para uma pessoa só. O que importa é que a consulta seja
**um passo** (SC-003), não uma varredura manual.

**Constraints**:

- FR-004 é uma restrição de **confiança**, não de desempenho: o valor não pode ser do cliente.
  Isso elimina de saída qualquer desenho em que o Dart mande a versão no `insert`.
- FR-007 proíbe `not null` e proíbe backfill. Também proíbe — e este é o achado menos óbvio
  desta feature — qualquer `check` do tipo "versão não pode ser nula", inclusive `not valid`:
  ver Riscos, item 1.
- Nenhum dado pessoal novo (Princípio II). A consulta da US2 devolve **contagem**, nunca
  identidade.
- A duplicação `LegalMetadata.version` (Dart) × `versoes_texto_legal` (banco) é declarada e
  testada, no mesmo padrão da duplicação do limiar de 4 horas da feature 011.

**Scale/Scope**: 1 migration, 2 colunas, 1 tabela de referência, 3 funções de banco, 1 gatilho;
no Dart, 1 modelo de leitura, 1 repositório, 1 provider e 1 página só de leitura para o
Administrador; 4 arquivos de teste de integração, 1 de unidade, 1 de widget. Nenhuma mudança
na tela de cadastro (SC-004).

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|-----------|----------|-------------------------------|
| **I. Linguagem Ubíqua** | ✅ PASS | Nenhum termo novo de domínio — `CONTEXT.md` não muda. A **fronteira de idioma** é o ponto de atenção desta feature, e está resolvida explicitamente: banco em **português** (`versoes_texto_legal`, `consentimento_lgpd_versao`, `consentimento_lgpd_igreja_versao`, `versao_texto_legal_vigente`, `perfis_carimbar_consentimento`, `consentimentos_por_versao`), identificadores Dart em **inglês** (`ConsentTally`, `ConsentKind`, `consentedVersion`, `isVersionUnknown`, `ConsentRepository`, `consentTallyProvider`, `ConsentVersionsPage`), chaves de `map[...]` em **português** (`map['versao']`, `map['tipo']`, `map['quantidade']`), strings de UI em **português**. Os dois lados de cada par estão escritos nome a nome em [data-model.md](./data-model.md) §5 e nomeados dentro de cada tarefa. **Vale igualmente para os testes**: helper, variável e parâmetro em inglês (`asUser`, `seedLegacyProfile`, `currentVersion`); só o **nome do arquivo** de teste continua em português. |
| **II. Privacidade e LGPD** | ✅ PASS — a feature existe para isto | Nenhum dado pessoal novo: a versão de um documento é dado sobre o **texto**, não sobre a pessoa. Nenhuma exposição muda — a coluna nunca é exibida a outro Usuário nem a Visitante, e `perfil_publico()` não é tocada. A consulta da US2 devolve **`(tipo, versao, quantidade)`**: nunca `id`, nunca `nome`. A feature **fortalece** a base legal do tratamento que já acontece, que é exatamente o que o Princípio II protege. Perfil anonimizado (feature 009) é excluído da contagem, e o gatilho **não** atravessa o caminho de `excluir_minha_conta` (Riscos, item 1). |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita, checklist de qualidade preenchido. `/speckit-clarify` **não foi executado**; as três decisões que ele teria resolvido — (a) onde vive a fonte da versão, (b) como representar "desconhecida", (c) quem pode consultar — foram tomadas na Fase 0 e estão registradas em [research.md](./research.md) com a alternativa descartada de cada uma. Nenhum `NEEDS CLARIFICATION` restou. |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS | A feature **não toca** nenhuma das regras listadas no Princípio IV (fila de espera, desempate por sorteio, revogação de voto/participação, descarte de candidatas, Dupla Missionária). O gatilho é `before insert or update` em `perfis`, tabela que nenhuma dessas regras escreve. Os **127** testes de integração existentes devem passar **sem edição** — se algum precisar mudar, esta feature vazou do escopo (a exceção prevista e tolerada é assertiva sobre o valor exato de `consentimento_lgpd_aceito_em`, ver Riscos item 3). A regra nova desta feature — "o banco carimba, o cliente não" — nasce com teste de integração, não com botão escondido. |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | **Nenhum papel novo**: a consulta da US2 é gated pelo `administradores_distrito`, que já existe desde a feature 005. Nenhuma tela de cadastro muda. A escolha de **colunas pareadas** em vez de uma tabela `consentimentos` normalizada é o caminho mais simples que atende a regra descrita — com o gatilho de reincidência declarado em [research.md](./research.md) D-005 (o 4º consentimento manda revisitar). Nenhuma generalização especulativa: não há versionamento do conteúdo do texto, não há reaceite forçado, não há notificação. |

### Complexity Tracking

**Nenhuma violação a justificar.**

Uma tensão foi resolvida em vez de justificada, e vale registrar: FR-002 ("a versão vem da
fonte única que o app já tem") e FR-004 ("a versão é gravada pelo banco, não pelo cliente")
apontam para lugares diferentes, porque a fonte de hoje é uma constante Dart que o banco não
conhece. A saída não foi escolher um e violar o outro: foi **mover a autoridade para o banco e
manter o Dart como espelho de exibição, amarrando os dois com um teste que falha se
divergirem**. O desenvolvimento disso está em [research.md](./research.md) D-001.

## Project Structure

### Documentation (this feature)

```text
specs/017-versao-do-consentimento/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 6 decisões, cada uma com a alternativa descartada
├── data-model.md        # Fase 1 — colunas, registro de versões, e o mapa pt↔en dos nomes
├── contracts/
│   └── schema.sql       # Fase 1 — delta de migration (contrato, não a migration)
├── quickstart.md        # Fase 1 — gates, o que cada teste prova, checagem manual
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
lib/
├── app.dart                                        # ALTERADO: + rota /district-admin/consentimentos
├── features/legal/
│   ├── legal_metadata.dart                         # ALTERADO: comentário de linhas 4-9 (FR-009);
│   │                                               #   version continua '1.1', agora com a gêmea
│   │                                               #   de banco apontada
│   ├── legal_providers.dart                        # NOVO: consentRepositoryProvider, consentTallyProvider
│   ├── domain/consent_tally.dart                   # NOVO: ConsentKind, ConsentTally
│   ├── data/consent_repository.dart                # NOVO: rpc('consentimentos_por_versao')
│   └── presentation/
│       └── consent_versions_page.dart              # NOVO: página só de leitura (US2)
├── features/profile/domain/profile.dart            # ALTERADO: só comentário — toInsertMap
│                                                   #   continua NÃO mandando versão (FR-004)
└── features/group/presentation/group_list_page.dart # ALTERADO: + ícone de entrada, dentro do
                                                     #   bloco `if (isDistrictAdmin)` que já existe

supabase/migrations/
└── <timestamp>_versao_do_consentimento.sql         # NOVO

test/
├── unit/
│   └── consentimento_versao_test.dart              # NOVO: ConsentTally.fromMap e isVersionUnknown
├── widget/
│   └── consentimentos_por_versao_page_test.dart    # NOVO: contagens e "Versão desconhecida"
└── integration/
    ├── versao_texto_legal_registro_test.dart       # NOVO: gêmea Dart×banco, e registro append-only
    ├── consentimento_versao_carimbada_test.dart    # NOVO: FR-001, FR-003, FR-004, SC-001, SC-005
    ├── consentimento_versao_desconhecida_test.dart # NOVO: FR-007, SC-002, e a armadilha de LGPD
    └── consentimentos_por_versao_test.dart         # NOVO: FR-005, FR-006, SC-003 e autorização

MAPA-DE-DADOS.md                                     # ALTERADO: FR-008
```

**Structure Decision**: mantida a organização por feature. A consulta de conformidade mora em
`lib/features/legal/` — não em `district_admin/` — porque o assunto é o consentimento, e
`district_admin/` é sobre gerir Igrejas e promover Administradores. O **ponto de entrada** da
tela, esse sim, entra no bloco de ícones de administrador que já existe em
`group_list_page.dart:57-78`, junto de "Igrejas do Distrito" e "Promover Administrador".

## Riscos e decisões que precisam de olho

1. **A armadilha desta feature: qualquer `check` de "versão não pode ser nula" quebra a
   exclusão de conta.** A tentação é forte e o desenho parece elegante:

   ```sql
   alter table public.perfis
     add constraint consentimento_lgpd_versao_obrigatoria
     check (consentimento_lgpd_versao is not null) not valid;   -- NÃO FAZER
   ```

   `not valid` deixa as linhas antigas em paz (FR-007 satisfeito) e obriga toda linha nova a
   ter versão (SC-001 satisfeito). Parece perfeito. **Não é**: no Postgres, uma constraint
   `not valid` **é verificada em todo `UPDATE` da linha**, mesmo que a coluna da constraint não
   apareça no `update`. Consequência: um Perfil antigo (versão nula) deixaria de poder ser
   atualizado — e `excluir_minha_conta` (feature 009) é justamente um `update public.perfis`
   de anonimização. Quem se cadastrou antes desta feature **ficaria sem conseguir apagar a
   conta**. Seria uma feature de conformidade criando um bug de LGPD, exatamente a classe de
   erro que a feature 011 evitou por pouco.

   **Decisão**: nenhuma constraint. A garantia de "linha nova sempre tem versão" fica no
   gatilho, e a de "linha antiga continua nula" fica em não escrever backfill nenhum. As duas
   metades têm teste de integração, e um dos casos é exatamente
   `excluir_minha_conta` sobre um Perfil de versão desconhecida.

2. **A duplicação `LegalMetadata.version` × `versoes_texto_legal` é real.** O texto legal mora
   no binário (`privacy_policy_page.dart`, `terms_of_use_page.dart`); o número da versão
   vigente mora no banco. Se alguém publicar texto novo sem inserir a linha no registro, o
   banco carimbará a versão anterior num aceite dado sobre um texto novo — um registro errado,
   silencioso, e pior do que não ter registro. Mitigação: comentário cruzado nos dois lados e
   **teste de integração que falha quando `versao_texto_legal_vigente()` ≠
   `LegalMetadata.version`**. Mesmo padrão do limiar de 4 horas da feature 011.

3. **O gatilho passa a sobrescrever `consentimento_lgpd_aceito_em` com `now()` do banco.** Hoje
   quem carimba é o cliente (`profile.dart:70`, `DateTime.now()`), o que é tão frágil quanto
   mandar a versão. A mudança é deliberada — a data e a versão precisam sair do **mesmo**
   relógio, senão o registro é internamente inconsistente (US1, cenário 3). Efeito colateral a
   conferir: qualquer teste que compare o valor exato de `consentimento_lgpd_aceito_em` com o
   que foi enviado passa a falhar. Uma varredura em `test/` deve ser feita **antes** de
   escrever a migration, e o resultado anotado.

4. **`versoes_texto_legal` vazia derruba o cadastro.** `versao_texto_legal_vigente()` levanta
   exceção quando não há versão vigente, em vez de devolver `null`. É intencional: se
   devolvesse `null`, uma linha nova nasceria com versão nula e ficaria indistinguível de um
   aceite antigo — o `null` perderia o único significado que FR-007 lhe dá. Preferimos recusar
   o cadastro a gravar um registro ambíguo. O custo é que a migration **tem de** semear a
   linha da versão vigente na mesma transação em que cria as colunas.

5. **Versão de Igreja de origem nula quando a Igreja é removida.** O gatilho zera
   `consentimento_lgpd_igreja_versao` quando `consentimento_lgpd_igreja_aceito_em` volta a ser
   nulo — versão sem aceite correspondente seria lixo. Atenção ao caminho de `excluir_minha_conta`,
   que zera `igreja_id` mas **não** zera o `_aceito_em`: os dois consentimentos ficam preservados
   na linha anonimizada de propósito, como prova da base legal do histórico que permanece.

6. **A feature 015 tem um terceiro consentimento.** O desenho aqui é de **colunas pareadas**,
   não de tabela normalizada — a 015 acrescenta `autorizacao_responsavel_versao` ao lado do seu
   `_aceito_em` e mais um bloco no gatilho. Isso é aceitável para 3 consentimentos e está
   justificado em [research.md](./research.md) D-005, **com o gatilho de reincidência escrito
   lá**: no 4º consentimento, ou na primeira vez que alguém precisar do **histórico** de
   aceites (e não só do último), a coluna pareada deixa de servir e a tabela
   `consentimentos (usuario_id, tipo, aceito_em, versao)` passa a ser o desenho certo.

## Ordem entre as features abertas

**`017 → 015 → 016`.**

- A **015** (consentimento de responsável) já declara, nas suas Assumptions, que *"depende da
  feature 017 para gravar a versão do texto aceito"*. Com a 017 antes, a 015 acrescenta uma
  coluna e um bloco de gatilho, e nasce certa — em vez de gravar "do jeito que der" e ser
  unificada depois.
- A **016** (Meu Perfil) introduz o `UPDATE` em `perfis` vindo do cliente, e é o caminho que
  faria a armadilha do Risco 1 explodir. Vindo depois, encontra o gatilho já escrito para o
  caso "aceite de Igreja dado depois do cadastro" e o `else` que preserva o que não mudou.
- Nada nesta feature depende da 015 nem da 016. Ela pode ser entregue sozinha e imediatamente.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões — onde vive a fonte da versão (D-001,
a decisão central), gatilho em vez de `default` (D-002), `null` em vez de valor sentinela
(D-003), consulta agregada restrita ao Administrador (D-004), colunas pareadas em vez de tabela
normalizada (D-005), e por que não há backfill nem mesmo o "inteligente" (D-006). Cada uma com
a alternativa descartada.

Nenhum `NEEDS CLARIFICATION` restante.

## Fase 1 — Design

Concluída:

- [data-model.md](./data-model.md) — as duas colunas, a tabela de referência, as transições do
  carimbo, o significado exato de `null`, e o mapa nome-a-nome português (banco) ↔ inglês
  (Dart).
- [contracts/schema.sql](./contracts/schema.sql) — delta de migration completo, com o porquê de
  cada escolha escrito no próprio arquivo e a constraint proibida registrada como aviso.
- [quickstart.md](./quickstart.md) — gates com números reais, o que cada teste prova, e a
  checagem manual.

**Constitution Check pós-design**: reavaliado. Princípios II, IV e V seguem PASS, e o design
reforçou o II (a consulta agregada não devolve identidade, e o Perfil anonimizado sai da
contagem) e o V (nenhum papel novo — a autorização reusa `administradores_distrito`). O
Princípio I ganhou um mapa explícito de nomes nos dois idiomas, escrito em `data-model.md` §5 e
repetido dentro de cada tarefa. O Princípio III segue com a ressalva de `/speckit-clarify`
registrada acima. Nenhum desvio novo apareceu no design.
