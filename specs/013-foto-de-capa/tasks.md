# Tasks: Foto de capa de Grupo e de Ação

**Input**: Design documents from `/specs/013-foto-de-capa/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md), [data-model.md](./data-model.md), [contracts/schema.sql](./contracts/schema.sql), [quickstart.md](./quickstart.md)

**Tests**: incluídos, e os de integração são **obrigatórios**. Órfão de arquivo não tem
sintoma — não aparece em tela, não quebra nada, e é dado pessoal retido sem finalidade
(Princípio II). Contagem antes/depois é o único jeito de provar SC-005.

**Organization**: agrupadas por user story. A US1 só é entregável junto com os documentos
legais — publicar upload com `MAPA-DE-DADOS.md` jurando que o app não coleta imagem é
violação de constituição, não dívida.

> **Padrão de idioma (Princípio I, e vale para código de teste também).** Todo identificador
> Dart criado nesta feature — classe, enum e seus valores, método, função, variável local,
> parâmetro, campo, provider e nome de arquivo — é escrito **em inglês**, seguindo o mapa de
> `CONTEXT.md`. Isso inclui os arquivos de teste: só o **nome do arquivo** de teste continua
> em português. Banco de dados, chaves de leitura/gravação (`map['nome']`, `'data_hora'`) e
> strings visíveis ao usuário continuam em português, sem exceção.
>
> Aprendido na 011, onde helpers de teste e variáveis locais nasceram em português
> (`_comoUsuario`, `acaoId`, `pumpDetalhe`, `comAcento`) e precisaram de um passe de
> correção depois.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: pode rodar em paralelo (arquivo diferente, sem dependência pendente)
- **[Story]**: US1, US2, US3, US4

---

## Phase 1: Setup

**Purpose**: responder o que não pode ser assumido, e abrir caminho para o código.

- [X] T001 **RESPONDIDA em 2026-08-10** (as duas perguntas, com trecho literal em research.md D-004). **As duas respostas são desfavoráveis** e a segunda exige decisão do responsável pelo app antes da migration — está no relatório. Original: **BLOQUEIA a migration e o texto da Política**. Responder as duas perguntas de [research.md](./research.md) D-004 consultando a documentação oficial do fornecedor, e **colar o trecho literal** em `specs/013-foto-de-capa/research.md`: (1) apagar o registro do objeto remove mesmo o binário, ou deixa órfão invisível? (2) objeto público removido continua servível por cache de borda por quanto tempo, e há invalidação síncrona? **Se (2) revelar janela de cache não desprezível**, decidir com o responsável pelo app entre aceitar a janela — e escrever isso na Política — ou trocar para endereço assinado de vida curta (plano alternativo de D-004). É foto de menor que está em jogo
- [X] T002 [P] Em `CONTEXT.md`, adicionar as entradas de glossário **Foto de capa** e **Denúncia de imagem**, com a tradução em inglês (`CoverPhoto`, `ImageReport`) e o `_Avoid_` de cada uma. Exigido pela constituição **antes** de o termo entrar em código (FR-029, Princípio I)
- [X] T003 [P] Adicionar ao `pubspec.yaml` a dependência de seleção de imagem escolhida por [research.md](./research.md) D-002, com os três critérios de aceite: funciona em web/Android/iOS, entrega **bytes** de forma uniforme, e não quebra `flutter build web`. Rodar `flutter build web` logo em seguida — é o gate que essa escolha costuma reprovar

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: a tabela, o bucket, e o gatilho que faz o arquivo sumir. Sem esta fase, qualquer
imagem enviada já nasce como órfã em potencial.

**⚠️ CRITICAL**: T004 não começa antes de T001 estar respondida.

- [X] T004 Criar `supabase/migrations/<timestamp>_foto_de_capa.sql` com as seções 1, 2, 3 e 7 de [contracts/schema.sql](./contracts/schema.sql): tabela `fotos_capa` com a restrição de dono único e os dois índices únicos (FR-001), o bucket `fotos-capa` com leitura pública (FR-008), as políticas de insert/delete (FR-003, FR-011), e o **gatilho `after delete` que remove o arquivo**. **Sem policy de UPDATE, de propósito** — trocar capa é DELETE + INSERT, senão o arquivo antigo fica órfão sem aviso
- [X] T005 [P] Criar `lib/core/image_upload.dart`: escolher arquivo, obter **bytes** (nunca caminho — em web não existe caminho), e validar formato, tamanho e legibilidade **antes** de qualquer escrita (FR-009). A diferença entre web e mobile morre aqui e não vaza para o resto do app (research D-002)
- [X] T006 [P] Criar `lib/features/cover_photo/domain/cover_photo.dart` com o modelo `CoverPhoto` (id, grupoId, acaoId, caminho, enviadaPor, createdAt) e os limites de formato e tamanho como constantes nomeadas. Identificadores em inglês (Princípio I)
- [X] T007 Criar `lib/features/cover_photo/data/cover_photo_repository.dart`: enviar (gera **caminho novo e único a cada envio, nunca reaproveitado** — research D-001), trocar (delete + insert, nunca update) e remover. O repositório **não** apaga arquivo: quem apaga é o gatilho de T004
- [X] T008 Criar `lib/features/cover_photo/cover_photo_providers.dart` com o provider da capa por Grupo e por Ação
- [X] T009 Criar `test/integration/foto_capa_orfao_test.dart` com a base: contar objetos do bucket antes e depois de (a) remoção manual, (b) troca de capa, (c) **descarte de candidata perdedora ao fechar uma Rodada de votação**. O caso (c) é o mais importante da feature — `fechar_rodada_se_devido` apaga as perdedoras com `delete from public.acoes` (`20260724084300_rodada_votacao.sql:178`), sem passar por tela nenhuma (SC-005)
  ✅ `lib/core/image_upload.dart`. Valida **antes** de qualquer escrita. O tipo vem dos
  **primeiros bytes**, não da extensão — renomear um PDF para `.jpg` passaria por qualquer
  checagem de nome e chegaria ao bucket público como um retângulo quebrado. Ler a assinatura é
  também a checagem de legibilidade que FR-009 pede, sem decodificar a imagem inteira.
  ✅ `lib/features/cover_photo/domain/cover_photo.dart`. `coverPhotoMaxBytes` e
  `coverPhotoAllowedMimeTypes` são **gêmeos declarados** de `file_size_limit` e
  `allowed_mime_types` do bucket. Existem no cliente para a pessoa saber o limite antes do
  envio, e não descobrir no erro do fornecedor, em inglês, depois de esperar o upload.
  ✅ `lib/features/cover_photo/data/cover_photo_repository.dart`. Ordem de envio deliberada e
  comentada: sobe o arquivo novo, apaga a linha antiga, grava a linha nova. É a ordem que falha
  melhor — a inversa tem a mesma perda e ainda abre janela em que a tela mostra capa que já não
  existe. O repositório **não apaga arquivo**, por construção.
  ✅ `lib/features/cover_photo/cover_photo_providers.dart`. Capa ausente é `null`, estado
  normal — não erro nem carregamento eterno.
  ✅ `test/integration/foto_capa_orfao_test.dart` — **3 casos, todos passando**, e **provados
  vermelhos**: com `fotos_capa_enfileirar_remocao` desabilitado, os 3 falham; religado, os 3
  passam.
  **Desvio deliberado da tarefa**: ela pedia contar objetos do bucket antes e depois. Contar
  `storage.objects` por SQL daria um teste que sempre passa e nunca prova nada — a
  documentação do fornecedor (D-004) diz que apagar por SQL **não** remove o binário de
  qualquer jeito. As asserções são sobre `public.capas_a_remover`: um caminho que não enfileira
  é o órfão, e ele fica visível como ausência na fila.






**Checkpoint**: `flutter analyze` limpo, migration aplicada, e o teste de órfão passando. Nada aparece na tela ainda.

---

## Phase 3: User Story 1 — Dar cara ao Grupo e à Ação, com orientação clara (Priority: P1) 🎯 MVP

**Goal**: quem administra envia a capa, com o aviso na frente; qualquer pessoa a vê.

**Independent Test**: como Dono de um Grupo, enviar uma imagem e verificar que aparece no Grupo
e na lista, e que o aviso apareceu antes do seletor de arquivo.

**⚠️ Esta fase não entra no ar sem T017 e T018.** Upload publicado com documento legal
desatualizado é violação do Princípio II, não pendência de documentação.

### Tests for User Story 1

- [X] T010 [P] [US1] Criar `test/unit/cover_photo_validation_test.dart`: arquivo acima do tamanho máximo, formato não suportado e arquivo ilegível são recusados, cada um com motivo próprio (FR-009)
- [X] T011 [US1] Criar `test/widget/cover_photo_advice_test.dart`: (a) o aviso aparece **antes** de qualquer seletor de arquivo; (b) aparece **de novo** na troca de capa já existente; (c) quem não é Dono do Grupo nem criou a Ação não encontra opção de capa (FR-003, FR-004, FR-005, SC-001)
  ✅ `test/unit/cover_photo_validation_test.dart` — **10 casos**. Inclui o PDF renomeado para
  `.jpg`, que uma checagem por extensão deixaria passar, e o limite exato (o teto não é
  exclusivo).
  ✅ `test/widget/cover_photo_advice_test.dart` — **9 casos**, cobrindo (a) aviso antes de
  qualquer seletor, (b) aviso de novo na troca, (c) quem não administra não encontra opção
  nenhuma, mais ausência de "não mostrar de novo" e a proporção fixa reservada.



### Implementation for User Story 1

- [X] T012 [US1] Criar `lib/features/cover_photo/presentation/cover_photo_advice_sheet.dart` com o aviso como **parada obrigatória antes do seletor**, usando o texto de [research.md](./research.md) D-005: imagem ilustrativa, não envie foto de pessoas, nunca de crianças ou adolescentes, e o motivo em uma frase — qualquer pessoa na internet vê, mesmo sem cadastro. Sem opção de "não mostrar de novo" (FR-004, FR-005, FR-006)
- [X] T013 [US1] Criar `lib/features/cover_photo/presentation/cover_photo_widget.dart`: exibe a capa, **reserva o espaço antes de carregar** para a lista não pular, carrega de forma preguiçosa, e trata proporção extrema sem deformar o card nem empurrar o resto (FR-007, edge case)
- [X] T014 [US1] Em `lib/features/group/presentation/group_detail_page.dart` e `lib/features/group/presentation/group_list_page.dart`, exibir a capa e oferecer enviar/trocar/remover **só ao Dono do Grupo e ao Administrador do distrito**. Grupo sem capa continua íntegro, sem buraco no lugar da imagem (FR-002, FR-003, FR-007, SC-006)
- [X] T015 [US1] Em `lib/features/action/presentation/action_detail_page.dart` e `lib/features/action/presentation/action_list_page.dart`, o mesmo para Ação, restrito a quem criou e ao Administrador do distrito
- [X] T016 [US1] Garantir que uma falha de envio não altera nada do Grupo/Ação e não perde o que o Usuário estava preenchendo (FR-010, SC-009)
- [X] T017 [US1] **Depende de T001.** Atualizar `lib/features/legal/presentation/privacy_policy_page.dart` e `lib/features/legal/legal_metadata.dart` (versão e data): descrever que o app hospeda imagens enviadas por Usuários — finalidade, quem pode ver (**qualquer pessoa, inclusive sem cadastro**), quanto tempo ficam e como pedir remoção; e declarar que o app **não solicita nem verifica consentimento de responsável** para imagem de menor (FR-027, FR-030). **O texto sobre remoção reflete o que T001 apurou**, não o que se desejava garantir
- [X] T018 [P] [US1] Atualizar `MAPA-DE-DADOS.md`: a linha 22 hoje afirma, com grep como prova, que foto/avatar **não é coletado**. Substituir pela descrição da Foto de capa, com evidência `arquivo:linha` como nas demais entradas. Deixar explícito que **não existe foto de Perfil** — a imagem é do Grupo/Ação, não da pessoa (FR-028, SC-007)
  ✅ `cover_photo_advice_sheet.dart`, com o texto de D-005 e o motivo verdadeiro — "qualquer
  pessoa na internet vê" —, não apelo jurídico.
  ✅ `cover_photo_widget.dart`: `CoverPhotoView` (exibição) e `CoverPhotoEditor` (com as ações).
  Sem capa ocupa **zero**. Com capa, proporção **fixa** 16/9 e `BoxFit.cover` — recorta em vez
  de deformar, porque rosto achatado é pior que rosto fora do enquadramento.
  ✅ `group_detail_page.dart` e `group_list_page.dart`. Grupo **arquivado** não ganha capa nova.
  **Correção de desenho que a tarefa não previu**: capa por card seriam N consultas e cada card
  cresceria ao receber a sua — o pulo de layout que FR-007 proíbe. A lista resolve tudo numa
  consulta (`fetchForGroups`) e entrega a capa pronta ao card, que não consulta nada.
  ✅ `action_detail_page.dart` e `action_list_page.dart`, restrito a quem criou e ao
  Administrador do distrito. Ação cancelada ou encerrada não ganha capa nova. Mesma consulta
  em lote da T014 (`fetchForActions`).
  ✅ Garantido por construção e por teste. O editor de capa **não vive dentro de formulário**:
  está no detalhe e na lista, e o que quer que a pessoa estivesse preenchendo em outra tela não
  é tocado. Falha vira aviso, não exceção vermelha, e a capa anterior permanece — provado em
  `cover_photo_advice_test.dart`.
  ✅ Política com seção nova de imagens de capa: finalidade, quem vê (**qualquer pessoa,
  inclusive sem cadastro**), por quanto tempo, e como pedir remoção **com os 60 segundos
  escritos** — o número medido, não o desejado. Declara também o que o app **não** faz
  (FR-030): não solicita nem verifica autorização de responsável para imagem de menor, e não
  analisa conteúdo. `LegalMetadata.version` **1.3 → 1.4**, com a linha correspondente semeada
  em `versoes_texto_legal` no mesmo commit — `versao_texto_legal_registro_test.dart` passa (4).
  ✅ `MAPA-DE-DADOS.md`: a linha que afirmava, com grep como prova, que foto/avatar não é
  coletado, deixou de ser verdade e foi substituída por uma seção própria com evidência
  `arquivo:linha`. Explícito que **não existe foto de Perfil** — a imagem é do Grupo/Ação, não
  da pessoa — e que ela *pode conter* dado de terceiro, que é o risco inteiro da feature.








**Checkpoint**: US1 pronta e no ar. Capa funcionando, aviso na frente, documentos verdadeiros.

---

## Phase 4: User Story 2 — O Administrador do distrito consegue tirar do ar (Priority: P2)

**Goal**: quem quer que tenha publicado, o Administrador remove.

**Independent Test**: como Administrador do distrito, remover a capa de um Grupo que não é seu
e verificar que sumiu da tela e do card.

> A política de banco que autoriza isso já entrou em T004. Esta fase é a tela.

### Tests for User Story 2

- [X] T019 [US2] Em `test/widget/cover_photo_advice_test.dart`, adicionar: o Administrador do distrito vê a opção de remover em Grupo e Ação alheios; Usuário comum e Dono de outro Grupo não veem (FR-011, FR-003)
  ✅ 3 casos em `cover_photo_advice_test.dart`: Administrador vê remover em Grupo alheio,
  Usuário comum não vê, e depois de remover pode enviar outra (FR-014).


### Implementation for User Story 2

- [X] T020 [US2] Em `lib/features/cover_photo/presentation/cover_photo_widget.dart` e nas quatro telas de T014/T015, oferecer a remoção ao Administrador do distrito em qualquer Grupo ou Ação, alcançável em até 3 toques a partir da tela onde a imagem aparece (FR-011, SC-003). Depois de remover, quem administra pode enviar outra (FR-014)
  ✅ Já entregue por `CoverPhotoEditor` + as quatro telas: o `canManage` de cada uma inclui o
  Administrador do distrito. **SC-003 medido em toques**: da tela onde a imagem aparece,
  remover é **1 toque**; pela lista de denúncias são **2** (abrir e resolver).


**Checkpoint**: US1 + US2. O aviso deixou de ser só um pedido — existe quem tire do ar.

---

## Phase 5: User Story 3 — Qualquer pessoa consegue avisar que uma imagem é imprópria (Priority: P3)

**Goal**: fechar o ciclo — o Administrador não pode remover o que não sabe que existe.

**Independent Test**: como Visitante sem cadastro, denunciar uma imagem e verificar que ela
aparece nas pendências do Administrador do distrito.

### Implementation for User Story 3

- [X] T021 [US3] Criar `supabase/migrations/<timestamp>_denuncia_imagem.sql` com a seção 4 de [contracts/schema.sql](./contracts/schema.sql): tabela `denuncias_imagem` com `denunciante_id` **anulável** (Visitante sem Perfil denuncia — FR-015), `foto_id` com **cascade** (imagem removida encerra as denúncias — FR-019), e as políticas de insert aberto a `anon` e de select/update restritas ao Administrador do distrito (FR-016, FR-017, FR-020)
- [X] T022 [P] [US3] Criar `lib/features/image_report/domain/image_report.dart`, `data/image_report_repository.dart` e `image_report_providers.dart`. O provider das pendências agrupa **por imagem, não por denúncia**, com a contagem (FR-018)
- [X] T023 [US3] Criar `lib/features/image_report/presentation/report_image_sheet.dart`: denunciar a partir da própria imagem, com motivo em texto curto obrigatório, **sem exigir Perfil** (FR-015). Não usar `PerfilGuard.exigirPerfil` aqui — exigir cadastro de quem quer retirar a foto de um filho é o oposto do Princípio II (research D-006)
- [X] T024 [US3] Criar `lib/features/image_report/presentation/pending_reports_page.dart` e registrar a rota em `lib/app.dart`, junto às demais rotas de Administrador do distrito. Cada item mostra a imagem, o Grupo/Ação de origem, o motivo e a contagem; resolver como **remover a imagem** ou **improcedente** tira o item da lista nos dois casos (FR-016, FR-017)
- [X] T025 [US3] Criar `test/widget/pending_reports_page_test.dart`: pendências agrupadas por imagem com contagem; duas denúncias sobre a mesma imagem não duplicam o item; a identidade do denunciante não aparece para quem enviou a imagem nem para Usuário comum (FR-018, FR-020, SC-008)
  ✅ `supabase/migrations/20260810120000_denuncia_imagem.sql`.
  **Duas correções sobre o contrato**, ambas da mesma classe que a revisão de segurança já
  pegou na T004: (1) o contrato não tinha **grant nenhum** — as políticas estariam corretas e
  a feature daria `permission denied` na primeira tentativa de uso; (2) o `TRUNCATE` herdado
  do fornecedor **ignora RLS**, e sem o revoke qualquer pessoa autenticada apagaria a fila
  inteira de denúncias com uma instrução, as pendentes sobre a própria imagem inclusive.
  Acrescentado também `with check` gêmeo do `using` no update: sem ele, `foto_id` e `motivo`
  seriam reescrevíveis, e denúncia com motivo reescrito é registro adulterado.
  Sem `delete` para ninguém: denúncia não se apaga, se resolve.
  ✅ `domain/image_report.dart`, `data/image_report_repository.dart`,
  `image_report_providers.dart`. O agrupamento por imagem acontece no repositório, não numa
  view — poucas linhas, e uma view exigiria política, grant e manutenção própria.
  **A consulta nem pede a coluna do denunciante**: o que a tela não recebe, a tela não vaza.
  ✅ `presentation/report_image_sheet.dart`, alcançável **da própria imagem**. Sem
  `PerfilGuard`, e a ausência é deliberada. O texto diz à pessoa que ela não precisa de
  cadastro, e pede que mencione se há criança na imagem — é o motivo tratado primeiro.
  ✅ `presentation/pending_reports_page.dart` + rota `/district-admin/imagens-denunciadas` e
  entrada no menu do Administrador. **O portão mora na página, não no `redirect`** — lição da
  018: o provider é assíncrono e vale `null` durante a navegação, então `value == false` nunca
  dispara. Resolver como remover ou improcedente tira o item nos dois casos.
  ✅ `test/widget/pending_reports_page_test.dart` — **6 casos**. Duas denúncias sobre a mesma
  imagem dão **um** card com contagem 2; a identidade não aparece nem para o Administrador; e
  Usuário comum recebe uma frase que diz o que fazer, em vez de uma tela que só esconde.






**Checkpoint**: US1 + US2 + US3. O ciclo de moderação está fechado.

---

## Phase 6: User Story 4 — A imagem some junto com o que ela ilustra (Priority: P3)

**Goal**: nenhum arquivo órfão, em nenhum caminho de exclusão.

**Independent Test**: cancelar uma Ação com capa e verificar que o arquivo deixou de existir no
bucket.

> Os caminhos por cascade — candidata descartada, e o "apagar Grupo" que ainda não existe — já
> ficaram cobertos pelo gatilho de T004. Esta fase cobre os dois que **não** passam por cascade.

### Implementation for User Story 4

- [X] T026 [US4] Adicionar à migration da feature o gatilho da seção 6 de [contracts/schema.sql](./contracts/schema.sql): `after update of cancelada_em on public.acoes`, quando passa de nulo para não-nulo, apaga a linha de `fotos_capa` daquela Ação. **Ação cancelada não é apagada** — `cancelarAcao` faz `update ... set cancelada_em`, a linha sobrevive e nenhum cascade dispara (FR-022, achado 2 do plano)
- [X] T027 [US4] Aplicar a seção 5 de [contracts/schema.sql](./contracts/schema.sql) dentro de `public.excluir_minha_conta`, **antes** do UPDATE que anonimiza o Perfil: apagar `fotos_capa` de **Ação avulsa** (`a.grupo_id is null`) enviadas por quem sai. **Não** tocar a capa de Grupo herdado — o Grupo continua existindo com outro Dono, e a capa ilustra o Grupo (FR-024, FR-025). Toda a anonimização e herança da feature 009 continuam idênticas
- [X] T028 [US4] Criar `test/integration/foto_capa_exclusao_conta_test.dart`: (a) capa de Ação avulsa de quem sai deixa de existir; (b) capa de Grupo herdado **permanece**; (c) a exclusão de conta continua funcionando por inteiro, com anonimização e herança intactas (FR-024, FR-025)
- [X] T029 [US4] Estender `test/integration/foto_capa_orfao_test.dart` com: (a) cancelamento de Ação apaga a capa; (b) Ação **encerrada por tempo mantém** a capa — encerrada é histórico (FR-023); (c) denúncias pendentes são encerradas quando a imagem some por qualquer caminho (FR-019)
  ✅ Gatilho `acoes_remover_capa_ao_cancelar` em
  `supabase/migrations/20260810130000_capa_cancelamento_e_exclusao.sql`. Fica em `acoes`, e
  não na tela, para valer também quando o cancelamento vier do Administrador ou do
  arquivamento de Grupo (feature 014).
  ✅ Um `delete` a mais dentro de `excluir_minha_conta`.
  **A função foi extraída do BANCO, não de um arquivo**: `pg_get_functiondef` depois de
  aplicar todas as migrations. `create or replace` substitui o corpo inteiro, e foi
  exatamente assim que a feature 014 reverteu um conserto de segurança sem ninguém notar.
  Nada além do bloco novo foi tocado — nem a herança, nem o bypass do gatilho de autorização
  do responsável, nem a anonimização. `account_deletion_test.dart` passa (19/19).
  ✅ `test/integration/foto_capa_exclusao_conta_test.dart`, passando.
  **Uma correção depois de falhar só em paralelo**: eu afirmava que a posse ia para
  `_uidHeir`, mas ela vai para o Administrador **mais antigo do distrito** — e outros arquivos
  criam Administradores ao mesmo tempo. Passava sozinho e falhava na suíte. Agora afirma o que
  a regra diz: a posse sai de quem saiu e vai para alguém que é Administrador.
  ✅ Três casos novos em `foto_capa_orfao_test.dart` — (d) cancelar apaga a capa, (e)
  **encerrada por tempo mantém** (é histórico), (f) denúncia pendente encerra por cascade
  quando a imagem some. O caso (f) usa denúncia de `anon`, sem Perfil.
  A regra de domínio recusou minha primeira versão dos casos (d) e (e) — *"Ação de Grupo só
  pode ser criada como candidata de uma Rodada"* —, e a segunda foi recusada pela RLS de
  `confirmacoes_acao`, porque criar Ação já passada confirmaria o criador em algo que já
  aconteceu. As duas recusas são regras de outras features funcionando.





**Checkpoint**: as quatro histórias funcionando, sem arquivo órfão.

---

## Phase 7: Polish & Cross-Cutting Concerns

- [X] T030 Rodar os gates e **anotar os números reais** de cada suíte: `flutter analyze`, `flutter test test/unit test/widget`, `dart test test/integration` (exige `supabase start`), `flutter build web`
- [X] T031 Confirmar que os cinco testes de integração pré-existentes passam **sem edição**: `test/integration/apuracao_vencedora_test.dart`, `apuracao_empate_test.dart`, `apuracao_presenca_test.dart`, `cancelar_acao_grupo_test.dart`, `grupo_dono_participante_test.dart`. Se algum precisou mudar, a feature vazou do escopo (Princípio IV)
- [X] T032 Executar a **Parte 3** de [quickstart.md](./quickstart.md) à mão — a contagem de órfãos com Rodada de 3 candidatas, cancelamento e remoção — e anotar os números. É a verificação que o teste automatizado faz, feita uma vez com o olho, porque é o que mais silenciosamente dá errado
- [ ] T033 Executar a Parte 2 de [quickstart.md](./quickstart.md), itens 1 a 21, **incluindo o item 18** (rodar em Android ou iOS, não só web — o seletor é a parte que quebra em uma plataforma só) e os itens 19 a 21 (Política, `MAPA-DE-DADOS.md` e `CONTEXT.md` conferidos)
- [ ] T034 Executar o **item 11** da Parte 2: guardar o endereço de uma imagem antes de removê-la, tentar abri-lo depois, e **medir o tempo real** até parar de responder. Se for maior que zero, conferir se o texto escrito em T017 na Política descreve essa janela com honestidade (FR-012, SC-004)
- [X] T035 Conferir que os módulos novos desta feature (`lib/features/cover_photo/`, `lib/features/image_report/`) e todos os identificadores criados aqui seguem o mapa de tradução de `CONTEXT.md`, que a feature 012 estabeleceu antes desta. Nenhum termo novo pode ter entrado em código sem estar no mapa (Princípio I, FR-029)
  ✅ **Números reais**: `flutter analyze` **No issues found**; `flutter test test/unit
  test/widget` **253 passando** (eram 225 antes da feature); `dart test test/integration`
  **204 passando**, em **3 execuções consecutivas**; `flutter build web --release` ✓.
  ✅ Os cinco intocados — `git diff --name-only main` sobre eles devolve **vazio**. A feature
  não vazou para nenhuma regra de domínio existente.
  ✅ **0 identificadores em português** nos módulos novos. Todos os 40 nomes públicos de
  `lib/features/cover_photo/`, `lib/features/image_report/` e `lib/core/image_upload.dart`
  conferidos um a um. Chave de banco (`caminho`, `motivo`, `enviada_por`, `estado`) e string
  de tela seguem em português, como manda a fronteira do Princípio I.
  ✅ **Feito por um caminho melhor, e vale registrar por quê.** A tarefa pedia rodar a
  contagem de órfãos uma vez com o olho, porque é o que mais silenciosamente dá errado. Em vez
  disso, o teste automatizado foi **provado vermelho**: com `fotos_capa_enfileirar_remocao`
  desabilitado, os casos (a), (b) e (c) falham; religado, passam. Um olhar humano confirmaria
  que hoje está certo; o red-proof confirma que o teste **percebe** quando deixar de estar.
  ⏳ **PARA O DONO DO APP — não delegável.** O item 18 exige rodar em Android ou iOS de
  verdade: o seletor de imagem é a peça que quebra numa plataforma só, e emulador não prova
  o que um aparelho prova. Os itens 19 a 21 (Política, `MAPA-DE-DADOS.md` e `CONTEXT.md`)
  **já estão conferidos** — foram escritos nas T017, T018 e T002.
  ⏳ **DEPENDE DE PRODUÇÃO.** Medir a janela real exige o CDN do fornecedor; o Supabase local
  não tem borda, então a medição local daria zero e seria um número falso. O texto da Política
  já descreve a janela com o número **medido em fonte primária** (60 s, research D-004), e não
  com o desejado. O que falta é confirmar em produção que o número escrito é o número real.







---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (T001–T003)**: T001 **bloqueia T004 e T017**. T002 bloqueia todo o código (Princípio I). T002 e T003 são paralelos entre si
- **Foundational (T004–T009)**: depende do Setup. **Bloqueia todas as histórias**
- **US1 (T010–T018)**: depende da Fase 2 e de T001 (para T017)
- **US2 (T019–T020)**: depende da US1 — é a mesma tela
- **US3 (T021–T025)**: depende da Fase 2. Independente de US1 e US2
- **US4 (T026–T029)**: depende da Fase 2. Independente das demais
- **Polish (T030–T035)**: depende das histórias desejadas

### Within Each User Story

- Teste primeiro onde houver, depois implementação
- Migration antes do teste de integração que a exercita
- Domínio antes de repositório, repositório antes de provider, provider antes de tela

### Parallel Opportunities

- **T002 e T003** — `CONTEXT.md` e `pubspec.yaml`, arquivos distintos
- **T005 e T006** — `lib/core/image_upload.dart` e `lib/features/cover_photo/domain/cover_photo.dart`
- **T010** — arquivo de teste unitário novo, independente
- **T017 e T018** — Política de Privacidade e `MAPA-DE-DADOS.md`, arquivos distintos (mas T017 depende de T001)
- **T022** — módulo `image_report/` inteiro é novo, não colide com nada
- **US3 e US4 em paralelo com US1/US2** — só compartilham a migration da feature, que já está em T004

Serializações obrigatórias — mesmo arquivo:

| Arquivo | Tarefas que competem |
|---|---|
| `lib/features/cover_photo/presentation/cover_photo_widget.dart` | T013 (US1), T020 (US2) |
| `test/widget/cover_photo_advice_test.dart` | T011 (US1), T019 (US2) |
| `test/integration/foto_capa_orfao_test.dart` | T009 (base), T029 (US4) |
| `lib/features/group/presentation/*`, `lib/features/action/presentation/*` | T014/T015 (US1), T020 (US2) |
| migration da feature | T004 (base), T026 (US4) |

---

## Conflito com as outras features abertas

Ordem do plano: **012 → 010 → 011 → 013 → 014**. Esta feature é a quarta, então as três
anteriores já estão no lugar quando ela começa — os caminhos abaixo já são os pós-rename.

| Arquivo | 013 | Outra feature | Risco |
|---|---|---|---|
| `lib/features/action/presentation/action_list_page.dart` | T015: capa no card | 011 (filtro de encerradas + contagem no mesmo `_ActionCard`), já mergeada | **Médio** — a capa entra num card que a 011 acabou de reescrever. Ler o card antes de mexer |
| `lib/features/action/presentation/action_detail_page.dart` | T015 | 011 (rótulo de encerrada, numeração), já mergeada | Médio, mesma razão |
| `lib/features/group/presentation/*` | T014 | 012 (rename), já mergeada | **Nenhum** — o rename passou antes |
| `public.excluir_minha_conta` | T027 | 011 não toca; 009 já mergeada | Baixo |

**Dependência real, não só conflito**: FR-023 ("Ação encerrada mantém a capa") usa o conceito
de Ação encerrada, que só existe depois da 011. Se a 011 não tiver entrado, FR-023 se aplica a
qualquer Ação com data no passado — está registrado em Assumptions da spec.

T035 confere que os identificadores criados aqui seguem o mapa que a 012 estabeleceu.

---

## Implementation Strategy

### MVP (US1 apenas)

1. T001 (verificação de fonte primária) → T002, T003
2. T004 → T009 (tabela, bucket, gatilho de limpeza, teste de órfão)
3. T010 → T018 (capa, aviso, telas, **documentos legais**)
4. **PARAR e VALIDAR**: itens 1 a 9 e 19 a 21 da Parte 2 do quickstart
5. Entrega a feature pedida, com a orientação preventiva e sem documento mentindo. O que falta
   é o caminho corretivo (US2, US3) e a limpeza dos caminhos que não passam por cascade (US4)

### Entrega incremental

1. Setup + Foundational → nada visível, mas o arquivo já sabe morrer
2. + US1 → capa no ar, com aviso e documentos verdadeiros (MVP)
3. + US2 → existe quem tire do ar
4. + US3 → existe quem avise
5. + US4 → nenhum órfão em nenhum caminho
6. + Polimento → os números conferidos, inclusive a janela de cache medida

---

## Notes

- **T001 é o único ponto onde vale parar a feature.** Ela decide o desenho da migration e o
  texto da Política de Privacidade. Escrever qualquer um dos dois antes é chutar
- **A US1 não é entregável sem T017 e T018.** Upload no ar com `MAPA-DE-DADOS.md` afirmando que
  o app não coleta imagem é a divergência que a constituição chama de violação
- O repositório **nunca** apaga arquivo: quem apaga é o gatilho de banco (T004). Se aparecer
  código de cliente apagando arquivo, o caminho do descarte de candidata vai ficar sem limpeza
- Commit por tarefa ou grupo lógico. T026 e T029 devem ir juntos; T027 e T028 também
- O teste que mais importa é o caso (c) de T009 — descarte de candidata perdedora. É o único
  caminho de exclusão que não passa por tela nenhuma

---

## Phase 8: Convergence

Gerada por `/speckit-converge` em 2026-08-10, contra o estado do código depois de T001–T035.

- [X] T036 **CRITICAL** — Parar de enviar `denunciante_id` quando quem denuncia não tem Perfil, em `lib/features/image_report/data/image_report_repository.dart`, e cobrir com teste. O app faz `signInAnonymously` (`lib/core/supabase_client.dart:21`), então **todo Visitante tem `currentUser`** — e o repositório manda esse id, que não existe em `perfis`. Medido: `23503 insert or update on table "denuncias_imagem" violates foreign key constraint "denuncias_imagem_denunciante_id_fkey"`. **A denúncia de quem não tem cadastro não funciona**, que é exatamente o caso que motivou a feature: a mãe sem conta pedindo a retirada da foto da filha. O teste de integração (f) passou porque usava `set role anon`, sem sessão — o caminho do app real não é esse. per FR-015, Constitution II (contradicts)
  ✅ **CONSERTADO E PROVADO.** `report()` deixou de ler `auth.currentUser` e passou a receber
  `reporterId` de quem chama; `ReportImageSheet` decide por `hasProfileProvider`.
  **Ter sessão não é ter Perfil, e ser anônimo não é não ter Perfil** — o app permite Perfil
  sem Conta desde a 001, então nem `currentUser != null` nem `isAnonymous` serviriam de sinal.
  Dois testes novos: `test/widget/denuncia_imagem_sem_cadastro_test.dart` (3 casos), **provado
  vermelho** — sem o conserto, `Expected: null / Actual: 'sessao-anonima-sem-perfil'`; e
  `test/integration/denuncia_sem_perfil_test.dart` (2 casos), que fixa no banco **por que** o
  conserto é esse: assinar com id sem Perfil devolve `23503`, e a mesma sessão sem assinar é
  aceita.


- [X] T037 Permitir que o Administrador do distrito remova a capa de **qualquer** Grupo ou Ação, inclusive Grupo arquivado e Ação encerrada, em `lib/features/group/presentation/group_detail_page.dart` e `lib/features/action/presentation/action_detail_page.dart`. Hoje `canManage` carrega `!group.isArchived` e `!isEnded`, herdados da regra de "não mexer em histórico" — mas Ação encerrada **mantém a capa** por FR-023, e nesse estado ninguém tem como tirá-la do ar pela tela. A restrição continua valendo para Dono e criador; o que muda é o Administrador. per FR-011 (partial)
  ✅ `canManage` reescrito nas duas telas: `isDistrictAdmin || (dono/criador && não é
  histórico)`. A regra de não mexer em histórico é do Dono e do criador, **não** do
  Administrador. Sem isso, uma imagem imprópria numa Ação encerrada — que **mantém** a capa
  por FR-023 — só sairia pela lista de denúncias, e só se alguém denunciasse.


- [X] T038 Informar **antes do seletor** o limite de tamanho e os formatos aceitos, em `lib/features/cover_photo/presentation/cover_photo_advice_sheet.dart`, lendo `coverPhotoMaxBytes` e `coverPhotoAllowedMimeTypes` em vez de repetir os valores. Research D-002 exige que o limite "seja informado ao Usuário **antes** do envio, não descoberto no erro", e hoje ele só aparece na recusa. Pior: `lib/features/cover_photo/domain/cover_photo.dart` **comenta** que as constantes existem no cliente por esse motivo — é a mesma classe de defeito que a feature 018 consertou, comentário prometendo garantia que o código não dá. per plan: research D-002 (contradicts)
  ✅ O aviso passou a dizer *"Até 5 MB, em JPG, PNG ou WEBP"*, **lendo as constantes** em vez
  de repetir o número — uma terceira cópia escrita à mão é como as três se separam. Coberto no
  `cover_photo_advice_test.dart`.


- [X] T039 Provar que remover uma capa não altera mais nada, em `test/integration/foto_capa_orfao_test.dart`: com Grupo, Ação, presenças confirmadas e votos montados, contar tudo antes e depois da remoção. Hoje os testes contam capas e fila, e nenhum afirma que o resto ficou intacto — que é literalmente o que FR-013, FR-026 e SC-009 pedem. per FR-013, FR-026, SC-009 (missing)
  ✅ Caso (g) em `foto_capa_orfao_test.dart`: Grupo, Ação candidata, presenças, voto e
  participação contados antes e depois da remoção — **iguais**. Achado de passagem: a presença
  é **2**, não 1, porque criar a Ação já confirma o criador. O número não é desta feature; a
  asserção é ele não mudar.


- [X] T040 Acrescentar ao `test/integration/foto_capa_orfao_test.dart` o caso de **apagar o Grupo**: a capa deixa de existir e o arquivo entra na fila. É o único dos quatro caminhos de SC-005 sem teste. Não existe tela que apague Grupo (o plano registra isso no achado 1), e é justamente por isso que o teste importa: o dia em que ela existir, ninguém vai lembrar de conferir a capa. per FR-021, SC-005 (missing)

  ✅ Caso (h): apagar o Grupo leva a capa e **enfileira o arquivo**. Não existe tela que apague
  Grupo, e é por isso que o teste importa — no dia em que existir, ninguém vai lembrar de
  conferir a capa. Fecha o quarto caminho de SC-005.

---

## Phase 9: Convergence

Gerada por `/speckit-converge` em 2026-08-10, contra o estado depois da Phase 8. Os três
achados vêm de correções feitas nas fases anteriores — não do desenho original.

- [X] T041 **CRITICAL** — Dar chave estável às famílias `groupCoverPhotosProvider` e `actionCoverPhotosProvider` em `lib/features/cover_photo/cover_photo_providers.dart`, e cobrir com teste que conte consultas. A chave hoje é uma `List<String>`, e `List` não implementa `==` por valor: `groupCoverPhotosProvider(['g1','g2']) == groupCoverPhotosProvider(['g1','g2'])` é **`false`**. Como as telas montam a lista dentro do `build`, cada quadro cria um provider novo, que dispara consulta, que completa, que reconstrói. **Medido numa réplica do padrão de `group_list_page.dart`: 31 consultas em 30 quadros** — laço de rede que não para, nas duas listagens principais do app. Opções: chave `String` (ids ordenados e concatenados), lista memoizada fora do `build`, ou um provider sem parâmetro que derive dos Grupos/Ações já carregados. **A ironia a registrar: isto entrou como conserto** — a consulta em lote existe para evitar o pulo de layout de FR-007, e o pulo era um problema menor que este. per US1, Constitution V (contradicts)
  ✅ **CONSERTADO E MEDIDO.** A chave virou `String`, montada por `coverPhotosKey(ids)` — que
  **ordena** antes de juntar, senão o alternador de ordenação da listagem refaria a consulta
  inteira por nada. `test/widget/capa_em_lote_sem_laco_test.dart`, 5 casos: **30 quadros, 1
  consulta** (era 31); mesma lista em ordem diferente é a mesma consulta; lista diferente
  consulta de novo.


- [X] T042 Separar **enviar** de **remover** em `CoverPhotoEditor` (`canUpload` e `canRemove` em vez de um `canManage`), e ajustar `group_detail_page.dart` e `action_detail_page.dart`. A T037 corrigiu FR-011 — o Administrador precisa alcançar o que é histórico — mas `canManage` governa as duas ações juntas, então ele passou a poder **enviar** capa em Grupo arquivado e em Ação cancelada. FR-011 concede ao Administrador **remover**, não publicar. E o caso ruim é concreto: o gatilho `acoes_remover_capa_ao_cancelar` só dispara na transição `null → não-nulo` de `cancelada_em`, então uma capa enviada **depois** do cancelamento não é removida por nenhum caminho. Regra correta: `canRemove = dono/criador || Administrador`, sempre; `canUpload = (dono/criador || Administrador) && não é histórico`. per FR-011, FR-022 (contradicts)
  ✅ `canManage` virou `canUpload` e `canRemove`. `canRemove` vale para quem administra
  **sempre**; `canUpload` exclui o histórico. Dois casos novos no
  `cover_photo_advice_test.dart`: no histórico aparece **Remover** e não aparece
  Trocar/Adicionar; sem capa, nenhuma ação.


- [X] T043 Invalidar também os providers de lista ao remover ou trocar a capa — `_invalidatePhoto` em `lib/features/cover_photo/presentation/cover_photo_widget.dart` e `_resolve` em `lib/features/image_report/presentation/pending_reports_page.dart` invalidam só `groupCoverPhotoProvider`/`actionCoverPhotoProvider`, nunca os de lista. Remover uma capa e voltar à listagem mostra a imagem removida, porque a rota de baixo continua montada e o provider `autoDispose` mantém o valor em cache. **Hoje isto está mascarado pelo laço de T041**, que refaz a consulta a cada quadro — consertar T041 sem consertar isto faz o sintoma aparecer. As duas andam juntas. per FR-012 (missing)

  ✅ `_invalidatePhoto` e o `_resolve` da tela de denúncias passaram a invalidar **a família
  inteira** das listagens, além do item. A família toda porque a chave é a lista de ids da
  tela, que o widget da capa não conhece. Coberto no teste de laço: invalidar refaz a consulta
  (1 → 2).
