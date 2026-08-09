# Implementation Plan: Foto de capa de Grupo e de Ação

**Branch**: `013-foto-de-capa` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/013-foto-de-capa/spec.md`

## Summary

Uma imagem de capa opcional por Grupo e por Ação, enviada por quem administra, visível a
qualquer pessoa, com aviso preventivo antes do envio, remoção pelo Administrador do distrito e
denúncia aberta a Visitante.

O app nunca hospedou arquivo binário. Esta feature introduz essa capacidade inteira: um lugar
para guardar o arquivo, regras de quem pode escrever nele, e — a parte difícil — a garantia de
que o arquivo **some** quando deve. Banco de dados apaga linha em cascata; **não apaga
arquivo**. Toda a engenharia desta feature está nessa lacuna.

Três achados do levantamento reescrevem partes da spec antes mesmo do plano existir. Estão em
"Achados que mudam a spec", abaixo.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2`

**Primary Dependencies**: `supabase_flutter ^2.8.0` (já traz o cliente de Storage),
`flutter_riverpod`, `go_router`. **Uma dependência nova é inevitável**: um seletor de
arquivo/imagem — o Flutter não tem seletor nativo. Escolha em `research.md` D-002.

**Storage**: PostgreSQL via Supabase para a referência da imagem e para a denúncia; **Supabase
Storage** (novo neste projeto) para o arquivo. Nenhum dos dois é usado hoje para imagem.

**Testing**: `flutter_test` + `mocktail` (unit/widget), `dart test test/integration` contra
Supabase local. Gates de `.github/workflows/ci.yml`.

**Target Platform**: Flutter web (deploy atual) + Android/iOS. **O seletor de imagem se
comporta de forma diferente em web e mobile** — é a diferença de plataforma mais relevante
desta feature.

**Project Type**: app Flutter por feature, com regra de domínio no banco.

**Performance Goals**: a listagem não pode ficar mais lenta por causa das capas. Imagem carrega
de forma preguiçosa e o card reserva espaço, para a lista não pular enquanto carrega.

**Constraints**:
- Imagem removida não alcançável por nenhum endereço (FR-012) — **e é aqui que cache de CDN
  ameaça a promessa**. Ver risco 1.
- 0 arquivos órfãos (SC-005) — cascade de banco não resolve. Ver risco 2.
- Nenhum dado de Grupo, Ação, presença ou Perfil alterado por operação de imagem (FR-026,
  SC-009).
- Política de Privacidade e `MAPA-DE-DADOS.md` atualizados **na mesma entrega** (FR-027,
  FR-028).

**Scale/Scope**: distrito de 15+ igrejas. Dezenas de Grupos, centenas de Ações. Uma imagem
cada, no máximo. Volume pequeno; o custo é de governança, não de escala.

## Achados que mudam a spec

Três coisas que a spec assumiu e o código contradiz. Nenhuma invalida a feature; todas mudam o
que precisa ser feito.

### 1. **Não existe apagar Grupo no app** — FR-021 descreve um evento que não acontece

`lib/features/group/data/group_repository.dart` só tem `delete` de `participacoes_grupo`
(linhas 96 e 105): sair do Grupo e remover participante. **Não há apagar Grupo**, nem no
cliente nem por RPC.

**Consequência**: FR-021 ("quando um Grupo é apagado, sua capa deve deixar de existir") é
inalcançável hoje. **Decisão**: manter o requisito como regra de banco — a capa é apagada em
cascata *se e quando* um Grupo for apagado — mas **não** criar o fluxo de apagar Grupo, que
está fora do escopo. O requisito fica coberto por construção, não por comportamento de tela.
Registrado para não virar um teste impossível de escrever.

### 2. **Ação cancelada não é apagada** — é marcada

`ActionRepository.cancelAction` faz `update ... set cancelada_em`. A linha continua existindo.
FR-022 exige que a capa da Ação cancelada deixe de existir, então **a exclusão da imagem tem
de ser um ato explícito no cancelamento**, não um efeito de cascade.

### 3. **Candidata perdedora É apagada** — e aí o cascade apaga a linha, não o arquivo

`fechar_rodada_se_devido` faz `delete from public.acoes where rodada_id = ... and confirmada =
false and id <> v_vencedora` (`20260724084300_rodada_votacao.sql:178`). Uma referência de
imagem com `on delete cascade` desaparece junto — e **o arquivo fica órfão para sempre**, sem
ninguém saber que ele existe.

**Este é o cenário que quebra SC-005 silenciosamente**, e é o motivo de a estratégia de
exclusão de arquivo (research D-003) ser a decisão central do plano.

### 4. Exclusão de conta: a Ação sobrevive, a capa não

`excluir_minha_conta` **não apaga as Ações** de quem sai — anonimiza o Perfil e deixa
`acoes.criador_id` apontando para ele, de propósito (histórico). FR-024 diz que a capa some.
Então a Ação continua existindo, sem capa, com criador "Membro removido". É o que a decisão do
usuário pede, e vale estar escrito: **não é bug, é a regra**.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|---|---|---|
| **I. Linguagem Ubíqua** | ⚠️ PASS condicionado | Dois termos **novos**: Foto de capa e Denúncia de imagem. A constituição exige que entrem em `CONTEXT.md` **antes** do código (FR-029) — é a primeira tarefa da feature, não a última. Identificadores Dart novos em inglês: `CoverPhoto`, `ImageReport`. Tabelas e colunas em português, como o resto do banco. **Herda o desvio da 011**: os arquivos tocados (`grupo/`, `acao/`) continuam com identificadores em português até a feature 012 |
| **II. Privacidade e LGPD** | ⚠️ **PASS com risco residual declarado** | É o princípio dominante desta feature. A declaração completa está na spec. O que o plano acrescenta: a imagem é **pública para qualquer pessoa**, o app **não analisa conteúdo**, e existe uma janela entre publicar e denunciar. FR-027/FR-028/FR-030 põem Política de Privacidade e `MAPA-DE-DADOS.md` dentro da entrega — sem isso, o app passa a coletar imagem enquanto o documento jura que não coleta, que é exatamente a divergência que a constituição chama de violação |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita e validada. `/speckit-clarify` pulado; as três decisões (proteção, retenção, escopo) foram tomadas com o usuário antes da escrita. **Ressalva adicional**: a spec foi escrita sobre uma premissa errada em FR-021 (apagar Grupo), corrigida aqui |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS | Nenhuma regra central muda. A única interação é o descarte de candidata perdedora levar a capa junto — e essa é justamente a que ganha teste de integração, porque é onde o arquivo órfão nasce |
| **V. Simplicidade e Papéis Mínimos** | ⚠️ PASS com custo declarado | Nenhum papel novo. Mas a feature adiciona: uma dependência (seletor de imagem), um subsistema de armazenamento de arquivo, duas tabelas e uma tela de moderação. É a feature mais cara do repositório até aqui, e o custo é intrínseco ao que foi pedido — não há versão mais simples de "hospedar imagem pública com moderação" |

### Complexity Tracking

| Violação | Por que é necessária | Alternativa mais simples rejeitada porque |
|---|---|---|
| **Dependência nova (seletor de imagem)** | Flutter não tem seletor de arquivo nativo; sem ele não há como o Usuário escolher uma imagem | Escrever o seletor à mão exige código de plataforma para Android, iOS e web — muito mais superfície do que a dependência |
| **Subsistema de armazenamento de arquivo** | Imagem não cabe em coluna de banco de forma sensata, e o app precisa servi-la por endereço público | Guardar a imagem codificada em texto na própria tabela foi considerado: infla toda consulta de listagem com centenas de KB por linha e impede carga preguiçosa. Pior em tudo, exceto em número de subsistemas |
| **Tela de moderação (denúncias pendentes)** | FR-016. O Administrador não pode agir sobre o que não vê | Receber denúncia por canal externo (WhatsApp) foi considerado e rejeitado: não deixa rastro, não fecha o ciclo, e depende de o Administrador ser achável |

## Project Structure

### Documentation (this feature)

```text
specs/013-foto-de-capa/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 6 decisões, incluindo a de exclusão de arquivo
├── data-model.md        # Fase 1 — 2 entidades novas e o que muda em grupos/acoes
├── contracts/
│   └── schema.sql       # Fase 1 — tabelas, políticas, bucket, gatilhos de limpeza
├── quickstart.md        # Fase 1 — validação, com foco em "a imagem sumiu mesmo?"
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks — NÃO criado aqui)
```

### Source Code (repository root)

```text
lib/
├── core/
│   └── image_upload.dart                        # NOVO: escolher, validar e enviar arquivo
└── features/
    ├── cover_photo/                             # NOVO — o subsistema em si
    │   ├── domain/cover_photo.dart              #   CoverPhoto, validação, limites
    │   ├── data/cover_photo_repository.dart     #   enviar, trocar, remover
    │   ├── cover_photo_providers.dart
    │   └── presentation/
    │       ├── cover_photo_widget.dart          #   exibição, com espaço reservado
    │       └── cover_photo_advice_sheet.dart    #   o aviso de FR-004
    ├── image_report/                            # NOVO — denúncia
    │   ├── domain/image_report.dart
    │   ├── data/image_report_repository.dart
    │   ├── image_report_providers.dart
    │   └── presentation/
    │       ├── report_image_sheet.dart          #   denunciar (aberto a Visitante)
    │       └── pending_reports_page.dart        #   pendências do Administrador
    ├── group/presentation/                      # ALTERADO: capa no detalhe e no card
    │   ├── group_detail_page.dart
    │   └── group_list_page.dart
    └── action/presentation/                     # ALTERADO: idem
        ├── action_detail_page.dart
        ├── action_list_page.dart
        └── create_action_page.dart

supabase/migrations/
└── <timestamp>_foto_de_capa.sql                 # NOVO: tabelas, bucket, políticas, gatilhos

lib/app.dart                                     # ALTERADO: rota das denúncias pendentes

CONTEXT.md                                       # ALTERADO: 2 termos novos (FR-029) — PRIMEIRO
MAPA-DE-DADOS.md                                 # ALTERADO: deixa de negar que coleta imagem
lib/features/legal/presentation/privacy_policy_page.dart   # ALTERADO: FR-027, FR-030
lib/features/legal/legal_metadata.dart           # ALTERADO: versão e data da Política

test/
├── unit/cover_photo_validation_test.dart        # NOVO
├── widget/cover_photo_advice_test.dart          # NOVO
├── widget/pending_reports_page_test.dart        # NOVO
└── integration/
    ├── foto_capa_orfao_test.dart                # NOVO — o teste que importa
    └── foto_capa_exclusao_conta_test.dart       # NOVO
```

**Structure Decision**: Foto de capa e Denúncia de imagem ganham **módulos próprios**, não
entram em `grupo/` nem em `acao/`. Motivo: os dois conceitos servem às duas entidades
igualmente, e enfiá-los em um dos módulos obrigaria o outro a importar de lá — acoplamento sem
razão. `grupo/` e `acao/` só ganham o widget de exibição e o ponto de entrada.

## Riscos e decisões que precisam de olho

1. **Cache de borda pode manter viva uma imagem removida.** FR-012 e SC-004 prometem que a
   imagem removida não é alcançável por **nenhum** endereço, em **100%** das tentativas.
   Arquivo público servido por CDN costuma ser cacheado, e apagar a origem não invalida o cache
   instantaneamente. **É a promessa mais frágil da feature**, e ela é sobre foto de menor —
   o pior lugar possível para uma promessa frágil. Tratamento em `research.md` D-004; exige
   **verificação em fonte primária** antes de implementar, e a redação de FR-012 na Política de
   Privacidade deve refletir o que o sistema realmente garante, não o que se desejava garantir.
2. **Cascade de banco não apaga arquivo.** A candidata perdedora é apagada por
   `fechar_rodada_se_devido`; a linha da capa some junto por cascade e o arquivo fica órfão,
   invisível, para sempre. Vale para todo caminho de exclusão. `research.md` D-003 escolhe o
   mecanismo; `test/integration/foto_capa_orfao_test.dart` é o que prova.
3. **O aviso não impede nada.** Entre publicar e denunciar, uma foto de menor fica pública
   para qualquer pessoa, inclusive Visitante. Está declarado na spec e aceito pelo usuário. O
   plano não finge resolver — só encurta a janela deixando a denúncia a um toque de distância
   da imagem.
4. **Diferença de plataforma no seletor**: web entrega bytes, mobile costuma entregar caminho
   de arquivo. Código que só foi testado em um dos dois quebra no outro, e o alvo em produção
   hoje é web.
5. **Documento legal desatualizado é violação, não pendência.** Se o upload entrar no ar antes
   de FR-027/FR-028, o app coleta imagem enquanto `MAPA-DE-DADOS.md:22` jura que não coleta.
   A ordem das tarefas precisa impedir isso.
6. **`CONTEXT.md` antes do código** (FR-029): dois termos novos. É a primeira tarefa.

## Ordem entre as features abertas

**`012 → 010 → 011 → 013 → 014`** (ver `specs/012-identificadores-em-ingles/plan.md`).

Ordem revisada em 2026-08-09, a pedido do usuário. A anterior era `010 → 011 → 013 → 012`, e
a 012 passou para a frente por dois motivos: o mapa de tradução é um padrão que todas as
outras precisam antes de inventar identificador, e o rename é mais barato agora, com nada em
voo, do que depois de esta feature acrescentar dois módulos e mexer em quatro telas.

Consequências para esta feature:

| Posição | Feature | Relação com a 013 |
|---|---|---|
| 1º | 012 Identificadores em inglês | Os caminhos citados neste plano já são os pós-rename (`lib/features/group/`, `lib/features/action/`). Os módulos novos daqui (`cover_photo/`, `image_report/`) nascem em inglês de qualquer forma |
| 2º | 010 Página Home | Não encosta nesta feature |
| 3º | 011 Ação: encerramento e contagem | **Dependência real**: FR-023 usa o conceito de "Ação encerrada", que é definido lá |
| **4º** | **013 (esta)** | Entra depois das três |
| 5º | 014 Arquivar Grupo | Vem depois. Um Grupo arquivado mantém a capa, porque o Grupo não é apagado |

**O que esta feature paga por não vir antes**: nada de trabalho dobrado — ela nasce já
escrevendo em módulos com nome em inglês. O que paga é tempo de espera.

**O que herda de conflito**: a 011 entra logo antes e mexe no mesmo `_ActionCard` e no
`action_detail_page.dart` que esta feature altera para exibir a capa. Está na tabela de
conflitos do `tasks.md`.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões — onde o arquivo mora, qual seletor,
como garantir que o arquivo some, o que fazer com cache de borda, como o aviso é apresentado, e
como a denúncia aceita Visitante sem Perfil.

**Uma decisão fica marcada como "verificar em fonte primária antes de implementar"** (D-004),
com plano alternativo escrito. Não é ambiguidade de requisito — é afirmação sobre
comportamento de fornecedor, e este repositório tem regra explícita de não afirmar isso de
memória.

## Fase 1 — Design

Concluída:

- [data-model.md](./data-model.md) — `CoverPhoto` e `ImageReport`, o que muda em `grupos` e
  `acoes`, e a tabela de quem-pode-o-quê.
- [contracts/schema.sql](./contracts/schema.sql) — tabelas, políticas de acesso, configuração
  do bucket e os gatilhos de limpeza, com as premissas escritas no próprio arquivo.
- [quickstart.md](./quickstart.md) — validação, com uma seção inteira dedicada a provar que a
  imagem sumiu de verdade, e a checagem de que os documentos legais não ficaram mentindo.

**Constitution Check pós-design**: reavaliado. Os vereditos não mudaram. O design **reforçou**
o Princípio IV (o descarte de candidata ganhou teste de integração próprio) e deixou o
Princípio II ainda mais dependente de D-004 — a promessa de FR-012 vale exatamente o que a
verificação de fonte primária confirmar, e a Política de Privacidade deve ser escrita depois
dessa confirmação, não antes.
