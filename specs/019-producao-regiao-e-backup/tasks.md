# Tasks: Produção — confirmar região e resolver backup

**Input**: Design documents from `/specs/019-producao-regiao-e-backup/`

**Prerequisites**: [plan.md](./plan.md), [spec.md](./spec.md), [research.md](./research.md),
[quickstart.md](./quickstart.md)

**Tests**: nenhum teste automatizado novo. A feature não cria comportamento — ver plan.md
§ Technical Context. O único "teste" exigido é T017, a restauração executada por humano (FR-008).

**`data-model.md` e `contracts/` não existem** e isso é decisão registrada — ver plan.md
§ Project Structure.

## Formato: `[ID] [P?] [Story] Descrição`

- **[P]**: pode rodar em paralelo (arquivos diferentes, sem dependência)
- **[Story]**: US1 (região) ou US2 (backup)
- **👤 [HUMANO]**: **só um humano com acesso ao painel/conta do fornecedor, ou o responsável pelo
  app, consegue executar.** Continua sendo tarefa: tem critério de pronto e bloqueia o que vem
  depois. Não delegável a agente nem a CI (research D-005)

---

## Fase 1: Fundação documental (não depende de ninguém, começa já)

**Objetivo**: existir o lugar onde as respostas vão ser escritas, antes de as respostas
existirem. Assim a tarefa humana é "cole aqui", e não "invente um formato".

- [X] T001 Criar `docs/INFRA-PRODUCAO.md` com o esqueleto e os campos vazios marcados
  `[PENDENTE]`: (a) **Região exigida para qualquer ambiente** — `sa-east-1` (São Paulo), com a
  frase de que é requisito de provisionamento e não default do fornecedor; (b) **Verificação da
  produção atual** — campos de região lida, data, quem verificou, plano do projeto; (c)
  **Decisão de backup** — mecanismo, RPO, prazo de expiração da cópia, região da cópia, custo;
  (d) **Runbook de restauração**; (e) **Resultado do drill**. Cabeçalho dizendo que este arquivo
  é o registro canônico e que os outros documentos apontam para cá. **(FR-002, FR-005)**

- [X] T002 [P] Em `README.md` § Arquitetura (linhas 48-51), acrescentar uma linha apontando
  para `docs/INFRA-PRODUCAO.md` como fonte da exigência de região. Uma linha, ponteiro — não
  copiar o conteúdo. **(FR-005)** — depende de T001

- [X] T003 [P] No cabeçalho de `.env.example`, acrescentar um comentário apontando para
  `docs/INFRA-PRODUCAO.md`: quem monta um ambiente novo passa por aqui e hoje não recebe nenhum
  aviso sobre região. **(FR-005)** — depende de T001

- [X] T004 [P] Em `MAPA-DE-DADOS.md` § Terceiros, corrigir a afirmação que já é falsa hoje —
  *"hoje só existe configuração para ambiente local"* e *"Nenhuma configuração de produção
  (região do projeto Supabase Cloud, ou self-host) existe no repositório"*. Produção existe:
  `.env.prod` e os secrets `SUPABASE_URL` / `SUPABASE_PUBLISHABLE_KEY` de
  `.github/workflows/deploy-web.yml:34-42`. Apontar para `docs/INFRA-PRODUCAO.md`. **(FR-002)** —
  depende de T001

**Checkpoint**: o registro existe, vazio e apontado de três lugares. Nada foi afirmado ainda.

---

## Fase 2: User Story 1 — a afirmação sobre transferência internacional passa a ser verificada (P1) 🎯

**Goal**: a região do projeto de produção deixa de ser suposição repetida em quatro documentos.

**Independent Test**: `docs/INFRA-PRODUCAO.md` responde "qual a região?" com texto colado do
fornecedor, data e nome — e a Política afirma o que essa resposta permite afirmar.

### Os fatos (só humano)

- [ ] T005 👤 [HUMANO] [US1] Obter a região do projeto Supabase de produção e **colar a saída
  literal**: `supabase login && supabase projects list` (linha do projeto de produção, inteira),
  **ou** Dashboard → Project Settings → General, transcrevendo a string exatamente como aparece.
  Print de tela não serve — o que vai para o repositório é texto.
  **Critério de pronto**: um bloco de texto colável, com a data de hoje.
  **(FR-001, SC-001)** — ver quickstart.md Parte 1

- [ ] T006 👤 [HUMANO] [US1] No mesmo acesso, anotar **em que plano o projeto está** (Free /
  Pro / Team / Enterprise). É o que decide se backup automático existe (research D-002): Free não
  tem nenhum. Insumo obrigatório da US2 — sem ele, T014 não tem o que decidir.
  **Critério de pronto**: nome do plano, anotado.

- [ ] T007 [US1] Registrar em `docs/INFRA-PRODUCAO.md` a saída de T005 e o plano de T006, com
  **data** e **quem verificou**. Não parafrasear a saída do fornecedor: colar. Pode escrever o
  `project-ref` (já é público, vai no build web via `deploy-web.yml:34-42`); nunca escrever
  `SUPABASE_SERVICE_ROLE_KEY` nem senha de banco. **(FR-001, FR-002, SC-001)** — depende de
  T001, T005, T006

---

### 🚪 PORTÃO DE PRECEDÊNCIA (FR-004)

Depois de T007, ler o resultado e seguir **um** ramo. Os dois são mutuamente exclusivos.

- **Ramo A** — a região é `sa-east-1` / South America (São Paulo) → T008A, T009A.
- **Ramo B** — a região **não** é brasileira → **T008B primeiro, antes de qualquer outra tarefa
  deste ramo**, depois T009B, T010B, T011B.

**Por que a ordem do Ramo B é obrigatória**: enquanto a Política diz "o dado não sai do Brasil"
e ele sai, o app está afirmando algo falso a titulares. Consertar comentário de código,
documento de revisão jurídica ou planejar migração antes disso é deixar a afirmação falsa de pé
enquanto se arruma o resto.

---

### Ramo A — região confirmada como brasileira

- [ ] T008A [US1] Reescrever o comentário de `LegalMetadata.hostingRegion` em
  `lib/features/legal/legal_metadata.dart:22-27`: remover *"Ainda não provisionada"* e o
  ponteiro para o achado A-3; passar a registrar **a verificação com data** e apontar para
  `docs/INFRA-PRODUCAO.md`. O identificador `hostingRegion` **não é renomeado** (já está em
  inglês, Princípio I); o comentário continua em português. **(FR-003, FR-005, SC-002)**

- [ ] T009A [US1] Em `REVISAO-JURIDICA.md` item 4 (linhas 182-208): substituir o bloco ⚠️
  *"Isto é uma decisão, não um fato ainda em produção"* / *"o projeto Supabase Cloud de produção
  ainda não foi criado"* pela evidência de T007 (região verificada, data, quem). O item passa de
  "resolvido como decisão" para "resolvido como fato verificado" — a diferença é a evidência,
  não a palavra. **(FR-012, SC-002)** — depende de T007

---

### Ramo B — região fora do Brasil

- [ ] T008B 🔴 **PRIMEIRO** [US1] Corrigir `lib/features/legal/presentation/privacy_policy_page.dart:145-150`:
  remover *"O dado não sai do Brasil, então não há transferência internacional de dado a
  declarar aqui"* e **declarar a transferência internacional** — para qual país/região o dado
  vai, e sob qual hipótese do art. 33 da LGPD ela se apoia. Texto em português, na voz da
  Política (`REVISAO-JURIDICA.md:206-208` já indica o caminho se a região for UE/EEE: art. 33, I).
  Nenhuma outra tarefa do Ramo B começa antes desta. **(FR-004, SC-005)** — depende de T007

- [ ] T009B [US1] Atualizar `LegalMetadata.hostingRegion` para a região **real** e reescrever
  o comentário: registrar a verificação com data, que a região diverge da exigida, e apontar para
  `docs/INFRA-PRODUCAO.md`. Identificador intocado. **(FR-003, SC-002)** — depende de T008B

- [ ] T010B [US1] Em `REVISAO-JURIDICA.md` item 4: rebaixar de "RESOLVIDO" para **"NÃO
  CONFORME — corrigido na Política, execução divergente da decisão"**, com a evidência de T007 e
  o ponteiro para T008B. **(FR-012, SC-002)** — depende de T008B

- [ ] T011B [US1] Registrar a migração de região como **pendência com feature própria** — em
  `docs/INFRA-PRODUCAO.md` e no achado de devops. Escrever o que ela implica: a documentação
  oficial de regiões não descreve troca depois de criado o projeto, então na prática é projeto
  novo + mover banco em produção, com gente usando. **Não é escopo desta feature** (research
  D-006). — depende de T008B

---

### Fechamento da US1 (os dois ramos)

- [ ] T012 👤 [HUMANO] [US1] Fechar o achado A-3 em
  `/Users/jdsc2/projects/.achados/20260724-direito-digital-iasd.md:114` (**fora do
  repositório**): de *"Região de hospedagem decidida (sa-east-1), mas ainda não provisionada"*
  para o resultado real, com data e ponteiro para `iasd/docs/INFRA-PRODUCAO.md`. Ajustar também o
  resumo das linhas 13-15. **(SC-006)** — depende de T009A ou T010B

**Checkpoint US1**: `docs/INFRA-PRODUCAO.md` responde a região com evidência; nenhum documento
do repositório afirma que produção não existe; a Política diz sobre transferência internacional
o que é verdade.

---

## Fase 3: User Story 2 — existe uma resposta escrita para "e se o banco morrer?" (P2)

**Goal**: fechar D-3. Depende de T006 (o plano do projeto decide o que está disponível) e da
tabela de opções em research D-002.

**Independent Test**: alguém pergunta "quanto de dado a gente perde no pior caso?" e a resposta
está escrita, em unidade de tempo, sem ninguém precisar pesquisar.

### A decisão (só humano)

- [X] T013 👤 [HUMANO] [US2] Perguntar **por escrito ao suporte do fornecedor em que região
  as cópias de backup ficam**, e guardar a resposta. A documentação pública não diz — só "our
  storage servers" e "backups stored in S3" (research D-002, fonte consultada 2026-08-09).
  Enquanto não houver resposta, a opção de backup gerenciado **não pode** ser registrada como
  "zero transferência internacional". **(FR-010)**
  ✅ **NÃO SE APLICA** (2026-08-10) — a decisão foi a opção C, que não cria cópia. Sem
  cópia, não há região de cópia a verificar. FR-010 fica satisfeito por vacuidade, e
  `INFRA-PRODUCAO.md` § 3 registra a exigência para o dia em que existir cópia.


- [X] T014 👤 [HUMANO — RESPONSÁVEL PELO APP] [US2] **Escolher** entre as opções de research
  D-002, e declarar junto: **mecanismo**, **RPO** (quanto de dado se perde no pior caso, em
  unidade de tempo), **prazo de expiração automática da cópia**, **onde a cópia fica**, e
  **custo**. A opção D (dump em GitHub Actions) está rejeitada pelo plano — copia o banco inteiro
  para fora do Brasil.
  ⚠️ **Trava do plano**: qualquer opção que crie cópia só fecha com prazo de expiração escrito.
  Prazo de retenção do backup **é** prazo de retenção do dado de quem pediu exclusão (a feature
  009 anonimiza o banco vivo, não a cópia).
  **Critério de pronto**: as cinco respostas, com nome de quem decidiu e data. **(FR-006, SC-003)**
  — depende de T006, T013
  ✅ **FEITA** (2026-08-10) — **opção C, sem backup**. Mecanismo: nenhum. RPO: tudo, desde
  o início. Expiração: não se aplica. Região da cópia: não se aplica. Custo: US$ 0,00.
  Decidida pelo fundador, responsável pelo app.


### O registro

- [X] T015 [US2] Registrar a decisão de T014 em `docs/INFRA-PRODUCAO.md` § Decisão de backup:
  mecanismo, frequência, RPO em unidade de tempo, prazo de expiração da cópia, região da cópia
  (resposta de T013), custo, quem decidiu, quando. **(FR-006, FR-010, SC-003)** — depende de T014
  ✅ **FEITA** (2026-08-10) — registrada em `REVISAO-JURIDICA.md` item 4-B, **não** em
  `INFRA-PRODUCAO.md`. Desvio do plano, com motivo: `docs/` está no `.gitignore` e o
  repositório é público; a frase "perde-se tudo desde o início" não vai para lá. Ver a nota
  de desvio no fim deste arquivo.


- [X] T016 [US2] **Só se a decisão for não ter backup automático**: registrar em
  `docs/INFRA-PRODUCAO.md` como **risco aceito**, explícito — *"num incidente de perda do banco,
  perde-se tudo desde o início; não há recuperação"* — com **quem aceitou** e **quando**. Risco
  aceito sem nome e data é risco implícito, que é o que a spec proíbe. **(FR-007, SC-003)** —
  depende de T014
  ✅ **FEITA** (2026-08-10) — risco aceito escrito em `REVISAO-JURIDICA.md` item 4-B, com
  quem aceitou (o fundador) e quando (2026-08-10). Texto explícito: num incidente,
  perde-se tudo desde o início, não há recuperação.


### O procedimento, e a prova de que ele funciona

- [X] T017 👤 [HUMANO] [US2] **Só se houver backup**: executar a restauração **uma vez**,
  para destino que não seja produção (projeto descartável ou `supabase start` local). Anotar os
  números do roteiro do quickstart Parte 2: contagem de `perfis`/`grupos`/`acoes`, existência de
  pelo menos um Perfil com `anonimizado_em` não nulo (a cópia preserva o estado de exclusão, não
  o desfaz), o app subindo contra o destino restaurado, e o **tempo total** (= RTO real).
  Sem números, o drill não aconteceu. **(FR-008, SC-004)** — depende de T014
  ✅ **NÃO SE APLICA** (2026-08-10) — condicional a existir backup. Não existe, logo não há
  restauração a executar. Um drill inventado seria pior que nenhum.


- [X] T018 [US2] Escrever o runbook de restauração em `docs/INFRA-PRODUCAO.md`: os passos
  exatos executados em T017, na ordem, com os comandos reais — não um resumo do que deveria
  funcionar. Anexar o resultado do drill (data, quem, números, tempo). **(FR-008, SC-004)** —
  depende de T017
  ✅ **NÃO SE APLICA** (2026-08-10) — mesmo motivo de T017. Escrever runbook aqui seria
  documentar uma capacidade que não existe.


### A Política e o mapa

- [X] T019 [US2] **Só se houver backup**: atualizar
  `lib/features/legal/presentation/privacy_policy_page.dart` — (a) § "Por quanto tempo guardamos"
  (linhas 158-167): a cópia de segurança existe e é guardada por N dias; (b) § "Com quem
  compartilhamos" (145-150): a cópia como destino, e onde ela fica; (c) o bullet de exclusão de
  conta (181-198): qualificar a promessa — some do app na hora, some da cópia de segurança em até
  N dias. Português, na voz da Política. **(FR-009, SC-005)** — depende de T014, T015
  ✅ **NÃO SE APLICA** (2026-08-10) — condicional a existir backup. Verificado que a Política
  não precisa de nenhuma mudança: `grep` em `privacy_policy_page.dart` dá **0 ocorrências**
  de "backup", "cópia" e de "segurança" no sentido de armazenamento. E a promessa da linha
  203 — *"Não há como desfazer nem recuperar"* — passa a ser literalmente verdadeira sem
  cópia: a anonimização da feature 009 alcança o único lugar onde o dado existe.


- [X] T020 [US2] **Só se o texto da Política mudou** (por T008B ou T019): subir
  `LegalMetadata.version` de `'1.1'` e atualizar `effectiveDate` em
  `lib/features/legal/legal_metadata.dart:11-12`. Registrar em `docs/INFRA-PRODUCAO.md` a
  limitação conhecida: `perfis.consentimento_lgpd_aceito_em` não grava a versão aceita
  (`legal_metadata.dart:1-9`), então quem aceitou antes fica com versão desconhecida — é a
  feature **017**, não esta. **(SC-005)** — depende de T008B, T019
  ✅ **NÃO SE APLICA** (2026-08-10) — condicional a o texto da Política mudar. Não mudou
  (T019). `LegalMetadata.version` continua em **`1.3`** — e não em `1.1`, como esta tarefa
  supunha: o número subiu nas features 021 e 015 depois que este `tasks.md` foi escrito.


- [X] T021 [US2] **Só se houver backup**: registrar o backup em `MAPA-DE-DADOS.md` como
  **destino de dado pessoal** — na seção § Terceiros, no formato já usado lá (destino, o que vai,
  onde fica, por quanto tempo), e um ponteiro em § Retenção e exclusão explicando que a
  anonimização da feature 009 não alcança a cópia e que o prazo dela é o prazo do dado apagado.
  **(FR-011)** — depende de T014, T015
  ✅ **NÃO SE APLICA** (2026-08-10) — FR-011 é condicional a existir cópia. `MAPA-DE-DADOS.md`
  não ganhou linha de backup em § Terceiros, e a ausência agora é verdadeira, não omissão.


- [X] T022 👤 [HUMANO] [US2] Fechar D-3 em `/Users/jdsc2/projects/.achados/20260724-devops-iasd.md`
  (**fora do repositório**) — a seção D-3 nas linhas **115-120** e a reabertura na emenda,
  linhas **148-151**. Registrar a decisão de T014, com data e ponteiro para
  `iasd/docs/INFRA-PRODUCAO.md`. Atualizar também A-4 (linhas 55-67), que dependia de D-3.
  Nota: a spec cita `:184-187` para D-3, mas o arquivo tem 156 linhas — as linhas corretas são as
  acima. **(SC-006)** — depende de T015
  ✅ **FEITA** (2026-08-10) — em `/Users/jdsc2/projects/.achados/20260724-devops-iasd.md`:
  D-3 fechada na seção original e na emenda de 2026-08-05, A-4 fechado, e uma emenda nova
  de 2026-08-10 no fim do arquivo com a decisão, o RPO e o que ela **não** fecha (a região,
  que continua pendente).


**Checkpoint US2**: existe decisão escrita sobre backup, com RPO, prazo e dono; se há cópia, ela
foi restaurada uma vez de verdade e a Política diz que ela existe.

---

## Fase 4: Verificação e fechamento

- [ ] T023 Rodar todas as verificações por `grep` do [quickstart.md](./quickstart.md) Parte 3:
  SC-002 (as **duas** redações — "ainda não provisionada" e "ainda não foi criado"), SC-001
  (evidência com data), SC-003 (RPO em unidade de tempo), SC-005 (checklist manual de
  contradição entre Política e decisão), SC-006 (achados), FR-005 (os três ponteiros existem).
  Anotar o resultado real de cada uma, com números. **(SC-001, SC-002, SC-003, SC-005, SC-006,
  FR-005)**

- [ ] T024 Rodar os gates de `.github/workflows/ci.yml`, porque dois arquivos Dart foram
  tocados: `flutter analyze`, `flutter test test/unit test/widget`, `flutter build web`.
  **Esperado**: analyze limpo, a **mesma contagem** de testes de antes (nenhum novo, nenhum
  alterado — não existe teste que leia o texto da Política, conferido), build web sucedendo. Se
  algum teste precisou mudar, a feature saiu do escopo.

- [ ] T025 Conferir que `docs/INFRA-PRODUCAO.md` responde, sem `[PENDENTE]` sobrando, as
  cinco perguntas que justificam a existência do arquivo: (1) qual região qualquer ambiente novo
  DEVE usar; (2) qual região a produção atual usa, verificada quando e por quem; (3) há backup, e
  qual; (4) quanto se perde no pior caso; (5) como se restaura, e quando isso foi testado pela
  última vez. **(FR-002, FR-005, FR-006, FR-008)**

---

## Dependências e ordem de execução

```text
T001 ──┬─ T002 [P]
       ├─ T003 [P]
       └─ T004 [P]

T005 (👤) ─┬─ T007 ─── 🚪 PORTÃO FR-004 ─┬─ Ramo A: T008A, T009A
T006 (👤) ─┘                              └─ Ramo B: T008B → T009B, T010B, T011B
                                                       ↓
                                                     T012 (👤)

T006 (👤) ─┬─ T014 (👤) ─┬─ T015 ─┬─ T019 ─ T020
T013 (👤) ─┘             │        ├─ T021
                         │        └─ T022 (👤)
                         ├─ T016 (se sem backup)
                         └─ T017 (👤) ─ T018

tudo ─── T023, T024, T025
```

**Ordem entre as histórias**: US1 (P1) antes de US2 (P2) — é a única das duas em que o app
**afirma** algo. Mas T006 (plano do projeto) é colhido dentro da US1 e é insumo da US2: quem for
abrir o painel deve fazer T005, T006 e T013 na mesma sessão, para não precisar de três acessos.

**Paralelismo**: T002/T003/T004 são independentes entre si. Dentro da US2, T019/T021/T022 tocam
arquivos diferentes e podem ir em paralelo depois de T015. Todo o resto é sequencial por
dependência de fato, não de arquivo.

---

## Tarefas que dependem de acesso humano ao painel ou de decisão do responsável

Seis, e nenhuma delas é omitida ou fingida como automatizável:

| Tarefa | O que trava se ela não acontecer |
|---|---|
| T005 👤 | A US1 inteira. A Política continua afirmando o que ninguém verificou |
| T006 👤 | A US2 inteira — sem saber o plano, não há opções a comparar |
| T013 👤 | FR-010. Backup gerenciado não pode ser declarado como "sem transferência internacional" |
| T014 👤 | A US2 inteira. É a decisão, e ela é do responsável pelo app |
| T016 / T017 👤 | FR-007 (risco aceito precisa de assinatura) ou FR-008 (backup não testado é hipótese) |
| T012 / T022 👤 | SC-006 — os achados vivem fora do repositório, em `/Users/jdsc2/projects/.achados/` |

---

## Cobertura — cada FR e cada SC em pelo menos uma tarefa

| Requisito | Tarefas |
|---|---|
| FR-001 | T005, T007 |
| FR-002 | T001, T004, T007, T025 |
| FR-003 | T008A (ramo A) / T009B (ramo B) |
| FR-004 | T008B — 🔴 primeira do ramo B, precedência declarada |
| FR-005 | T001, T002, T003, T008A, T023, T025 |
| FR-006 | T014, T015, T025 |
| FR-007 | T016 |
| FR-008 | T017, T018, T025 |
| FR-009 | T019 |
| FR-010 | T013, T015 |
| FR-011 | T021 |
| FR-012 | T009A (ramo A) / T010B (ramo B) |
| SC-001 | T005, T007, T023 |
| SC-002 | T008A / T009B, T009A / T010B, T023 |
| SC-003 | T014, T015, T016, T023 |
| SC-004 | T017, T018 |
| SC-005 | T008B, T019, T020, T023 |
| SC-006 | T012, T022, T023 |

**25 tarefas** (T001–T025, contando os dois ramos do portão como alternativas exclusivas).
Executadas de fato: 19 no ramo A sem backup, até 22 no ramo B com backup.

---

## Notas

- Nenhuma tarefa toca `supabase/`, `test/` ou `.github/workflows/`. Se alguma precisar, a feature
  saiu do escopo — ver plan.md § Riscos.
- Nenhuma tarefa cria identificador Dart. Os dois arquivos `.dart` tocados mudam só comentário e
  string em português (Princípio I — ver Constitution Check do plano).
- Nenhuma tarefa escreve valor de segredo em documento. `project-ref` pode; chave de service role
  e senha de banco, nunca.
- Migração de região **não** é tarefa desta feature. Se o ramo B acontecer, T011B a registra como
  feature futura e para por aí.

---

## Desvio do plano registrado durante a execução (2026-08-10)

**`docs/INFRA-PRODUCAO.md` não podia existir.** `docs/` está na linha 11 do
`.gitignore`, junto com `REVISAO-JURIDICA.md` e `.tickets/`, como artefato de
processo que fica no disco de quem trabalha. O plano (research D-003) escolheu
esse caminho sem verificar, e o primeiro commit da feature criou o arquivo no
disco **sem versioná-lo** — FR-002 exige "registrado no repositório", e um
arquivo ignorado não está no repositório.

Descoberto ao rodar as verificações de T023: o `grep` recursivo não encontrava
`REVISAO-JURIDICA.md`, porque o `grep` deste ambiente respeita `.gitignore`.

**Correção, decidida pelo responsável**: o registro foi **dividido em dois**,
por sensibilidade e não por assunto.

| Onde | O quê | Por quê |
|---|---|---|
| `INFRA-PRODUCAO.md` (raiz, versionado, **público**) | A exigência de região e a verificação da produção | FR-005 só se cumpre se quem clona o repositório para provisionar um ambiente receber a exigência. E a região já é pública: está no `README.md` e em `legal_metadata.dart` |
| `REVISAO-JURIDICA.md` item 4-B (**não versionado**) | A decisão de backup e o risco aceito | O repositório é público (`JDaniielC/iasd-conecta`). Publicar "não há backup, perde-se tudo" sobe o valor de um ataque destrutivo sem beneficiar quem precisa da informação — que tem acesso ao arquivo |

`INFRA-PRODUCAO.md` § 3 diz que a decisão existe, está fechada e onde ela mora —
sem revelar qual foi. Os três ponteiros de T002/T003/T004 apontam para a raiz.

**Uma segunda correção, menor**: os `grep` de SC-002 no `quickstart.md` são
case-sensitive e filtram por `^./specs/019`. Ambos falham neste ambiente — a
ocorrência real em `legal_metadata.dart:48` é *"Ainda não provisionada"*, com A
maiúsculo, e o `grep` imprime os caminhos sem `./`. Use `grep -rni` e
`grep -v "specs/019"`.
