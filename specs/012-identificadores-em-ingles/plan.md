# Implementation Plan: Identificadores Dart em inglês

**Branch**: `012-identificadores-em-ingles` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/012-identificadores-em-ingles/spec.md`

## Summary

Traduzir todo identificador Dart de `lib/` para inglês, incluindo nomes de arquivo e de pasta,
mantendo intactos o banco, as chaves de leitura/gravação, as strings de UI e as rotas.

O eixo técnico é um só: **o compilador é o guarda-corpo**. Renomeia-se a *declaração*,
`flutter analyze` lista cada referência quebrada, corrige-se uma a uma. Busca-e-substitui
textual está proibido — as strings de UI e as chaves de mapa contêm exatamente as mesmas
palavras portuguesas que os identificadores (`nome`, `grupo`, `acao`, `igreja`), e nenhuma
delas quebra a compilação quando alterada por engano. O erro mais caro desta feature é
silencioso, e o único método que o torna impossível é o que nunca toca em literal.

Entrega em 5 etapas por módulo, da menor superfície para a maior.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: nenhuma nova. `flutter analyze` (já em CI) é a ferramenta principal.

**Storage**: PostgreSQL via Supabase — **não tocado**. Nenhuma migration criada ou alterada.

**Testing**: `flutter_test` + `mocktail` + `dart test test/integration`. Gates de
`.github/workflows/ci.yml`: `flutter analyze`, `flutter test test/unit test/widget`,
`dart test test/integration`, `flutter build web`. Nenhum teste novo é escrito — os
existentes **são** o teste desta feature.

**Target Platform**: Flutter web + Android/iOS. Nenhuma mudança.

**Project Type**: refatoração mecânica de app Flutter organizado por feature.

**Constraints**:
- Zero mudança de comportamento observável.
- Zero literal de string alterado (FR-012, FR-013).
- Cada etapa compila e passa nos gates sozinha (FR-010, SC-009).
- Nenhuma feature de comportamento aberta sobre o mesmo módulo ao mesmo tempo.

**Scale/Scope**: 57 arquivos em `lib/`, 37 com nome em português, 4 pastas de módulo,
~40 tipos, ~16 providers. Testes: alterados apenas onde a compilação exigir.

### Levantamento que muda o tamanho do trabalho

Quatro dos sete módulos **já estão em inglês** por dentro — foram escritos depois da emenda
da constituição:

| Módulo | Arquivos | Estado |
|---|---|---|
| `legal/` | 4 | Inteiramente em inglês. As palavras portuguesas que aparecem estão dentro de texto jurídico, que é string — não se toca |
| `leadership/` | 5 | Em inglês. Só referencia símbolos alheios (`grupoProvider`, `perfilPublicoProvider`) |
| `district_admin/` | 5 | Em inglês. Idem |
| `acao_sugerida/` | 4 | Arquivos e tipos em inglês (`SuggestedAction`, `suggested_action_providers.dart`). **Só a pasta está em português** |
| `grupo/` | 8 | Português |
| `perfil/` | 12 | Português |
| `acao/` | 13 | Português — o maior |
| `core/` | 4 | Misto (`agrupar_por_igreja.dart`, `hasPerfilProvider`, `perfilRepositoryProvider`) |

O trabalho real está em **grupo, acao, perfil e core**. Os outros quatro entram de carona
quando um símbolo que eles referenciam é renomeado.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência |
|---|---|---|
| **I. Linguagem Ubíqua** | ✅ PASS — é o objeto da feature | O mapa de tradução (research D-002) entra em `CONTEXT.md` antes de qualquer rename, cumprindo "um termo novo ou renomeado só entra em código depois de atualizado em `CONTEXT.md`". O banco e as strings de UI ficam em português, como a fronteira exige. Ao fim, a ressalva do Complexity Tracking da 011 deixa de existir |
| **II. Privacidade e LGPD** | ✅ PASS | Nenhuma consulta, permissão ou regra de exibição muda. A regra de exibir menor de idade por Apelido continua onde está, com outro nome de símbolo. Nenhum dado se move |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita e validada. `/speckit-clarify` pulado; as três decisões de escopo (pastas, testes, entrega por módulo) foram resolvidas com o usuário antes da escrita e estão em Assumptions |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS | Nenhuma regra muda. A prova é negativa e forte: as mesmas asserções, na mesma quantidade, continuam passando. Se um teste precisar de asserção nova ou diferente, a refatoração deixou de ser refatoração |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel, dependência, arquivo novo ou mudança estrutural. Só rename |

**Complexity Tracking**: nenhuma violação. A exceção de `test/` (nomes de arquivo mantidos em
português) é decisão registrada do usuário, dentro do escopo que a spec declarou — está em
Assumptions, não é desvio de princípio.

## Project Structure

### Documentation (this feature)

```text
specs/012-identificadores-em-ingles/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — método, mapa de tradução, ordem dos módulos
├── quickstart.md        # Fase 1 — como provar que nada mudou
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks — NÃO criado aqui)
```

**`data-model.md` e `contracts/` não são gerados**: não há entidade (a spec já declara que
nenhum dado se move) nem interface externa. O mapa de tradução, que seria o candidato natural
a `contracts/`, vive em `research.md` D-002 e daí vai para `CONTEXT.md` — duplicá-lo num
terceiro arquivo é criar uma cópia que vai divergir.

### Source Code — o antes e o depois

```text
lib/
├── core/
│   ├── agrupar_por_igreja.dart      → group_by_church.dart
│   ├── providers.dart               (nome mantido; hasPerfilProvider → hasProfileProvider etc.)
│   ├── supabase_client.dart         (inalterado)
│   └── theme/app_theme.dart         (inalterado)
├── app.dart                         (imports e tipos referenciados mudam; rotas NÃO)
└── features/
    ├── acao/                        → action/
    ├── grupo/                       → group/
    ├── perfil/                      → profile/
    ├── acao_sugerida/               → suggested_action/
    ├── leadership/                  (pasta inalterada)
    ├── district_admin/              (pasta inalterada)
    └── legal/                       (pasta inalterada)

test/                                # nomes de arquivo INALTERADOS (decisão do usuário)
                                     # só os símbolos referenciados mudam
supabase/migrations/                 # INTOCADO
```

**Structure Decision**: a organização por feature não muda — nenhum arquivo é dividido, unido
ou movido de camada. Só renomeado. `lib/core/providers.dart` e `lib/core/supabase_client.dart`
mantêm o nome, porque já estão em inglês; o que muda dentro deles são os providers com nome
português.

## Ordem entre as features abertas

**Esta feature vem primeiro**: `012 → 010 → 011 → 013 → 014`.

Decisão revisada em 2026-08-09, a pedido do usuário. A ordem anterior era
`010 → 011 → 013 → 012`, e o argumento que a derrubou é melhor do que o que a sustentava.

| Ordem | Por quê |
|---|---|
| **1º — 012 (esta)** | Define o vocabulário que todas as outras vão usar, e faz o rename no momento mais barato que ele vai ter |
| 2º — 010 Página Home | Menor de todas. O módulo novo dela (`home/`) já nasce em inglês |
| 3º — 011 Ação: encerramento e contagem | Corrige informação errada em produção |
| 4º — 013 Foto de capa | Módulos novos (`cover_photo/`, `image_report/`) já nascem em inglês |
| 5º — 014 Arquivar Grupo | Idem |

**Por que primeiro**:

1. **O mapa de tradução é um padrão, não um detalhe.** Sem ele, cada feature inventa a própria
   tradução — a 011 já inventou `ActionTimeStatus` e `clockProvider`, a 013 inventou
   `CoverPhoto` e `ImageReport`, a 014 vai inventar os termos de arquivamento. O Princípio I
   proíbe exatamente isso: duas traduções para o mesmo conceito. O mapa (US1) custa três
   tarefas em um arquivo e bloqueia zero código.
2. **Agora é o momento mais barato do rename.** Nenhum código em voo, nada mergeado, nenhum
   branch. Cada feature que entra antes aumenta a superfície: a 013 sozinha acrescenta dois
   módulos e mexe em quatro telas de `grupo/` e `acao/`.
3. **Tudo depois nasce em inglês.** Zero trabalho dobrado.

**Custo pago, e como foi pago**: os `tasks.md` da 010, 011 e 013 citavam caminhos e símbolos em
português — 10, 48 e 15 linhas respectivamente. Foram atualizados para os nomes pós-rename na
mesma sessão em que esta ordem foi decidida. **T027 confere que eles batem com os nomes reais**
depois do rename — se alguma tradução sair diferente do mapa, é lá que aparece.

**O custo que sobra**: a 011 corrige um bug visível (a listagem anuncia evento que já passou) e
agora espera as cinco etapas do rename. Aceito conscientemente: o bug é irritante, não
perigoso.

**Não há mais portão de espera.** Nenhuma feature está em voo, então as cinco etapas de rename
podem ser executadas em sequência sem esperar nada.

## Riscos e decisões que precisam de olho

1. **O risco que mata: alterar um literal**. `map['nome']`, `'data_hora'`, `'criador_id'`,
   `'limite_vagas'`, `'cancelada_em'`, `'genero_visitado'`, `'masculino'`, `'feminino'`,
   `'confirmado'`, `'fila'` — e toda string de UI. Nenhum deles quebra a compilação se for
   trocado, e o app quebra em produção na hora de ler o dado. Mitigação: método guiado pelo
   compilador (research D-001), nunca busca-e-substitui textual, mais a verificação de
   literais do `quickstart.md`.
2. **Palavra portuguesa que é identificador em um lugar e conteúdo em outro**. `grep -r nome`
   encontra o campo `nome`, a chave `'nome'` e a palavra "nome" dentro do texto da Política de
   Privacidade. Nenhuma ferramenta textual distingue os três. Só o analisador distingue.
3. **`Voto` vs `votar` vs `'voto'`**: o tipo, o método e a tabela do banco. Dois viram inglês,
   um não.
4. **Renomear pasta muda todo import relativo do módulo**. É mecânico e o compilador pega
   tudo, mas o diff cresce e revisar exige separar "renomeou o arquivo" de "mudou o conteúdo".
   Mitigação: a etapa faz o `git mv` em um commit e os ajustes de conteúdo em outro, para o
   `git log --follow` continuar funcionando.
5. **Duas traduções para o mesmo conceito** é a falha silenciosa mais provável em trabalho
   longo. Mitigação: o mapa entra em `CONTEXT.md` **antes** da primeira etapa de rename, não
   depois (FR-005).
6. **`test/` fica em português por decisão do usuário**, então ao fim desta feature o
   repositório está deliberadamente meio-a-meio: `lib/` em inglês, nomes de arquivo de teste em
   português. Isso é escolha, não pendência — mas quem chegar depois vai achar que é bug se
   não estiver escrito. Está escrito.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 4 decisões — o método guiado pelo compilador,
o mapa de tradução completo, a ordem dos módulos por superfície, e o que fazer com os
providers.

Nenhum `NEEDS CLARIFICATION` restante.

## Fase 1 — Design

Concluída. Ver [quickstart.md](./quickstart.md): os gates por etapa e, principalmente, as três
verificações que provam que **nada mudou** — conjunto de literais idêntico, contagem de testes
idêntica, `supabase/` e rotas intocados.

`data-model.md` e `contracts/` não se aplicam (justificado em Project Structure).

**Constitution Check pós-design**: reavaliado, sem mudança. Os cinco princípios seguem PASS,
com a mesma ressalva no III. O design não introduziu papel, dependência, arquivo novo nem
qualquer alteração de dado.
