# Implementation Plan: Produção — confirmar região e resolver backup

**Branch**: `019-producao-regiao-e-backup` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/019-producao-regiao-e-backup/spec.md`

## Summary

Responder duas perguntas que o app já responde ao usuário sem ter verificado: **em que região o
banco de produção roda** (a Política afirma que o dado não sai do Brasil) e **o que acontece se
esse banco morrer** (não existe decisão de backup escrita).

O eixo técnico é um só, e é desconfortável: **o repositório não consegue responder nenhuma das
duas.** A região só existe no painel do fornecedor; o plano de backup custa dinheiro e é
escolha do responsável. Logo esta feature não se organiza por "código a escrever", e sim por
**quem consegue executar cada passo**: um bloco de tarefas humanas, curtas e bem definidas, que
produzem *fatos*; e um bloco de tarefas de agente que transformam esses fatos em registro
permanente, em Política verdadeira, e em documento que a próxima pessoa vai ler.

Duas regras de ordem, que o `tasks.md` obedece:

1. **FR-004 tem precedência.** Se a região não for brasileira, corrigir a Política vem antes de
   qualquer coisa — inclusive antes de consertar o comentário no código e antes de discutir
   migração. Afirmação falsa a titular é o dano que está acontecendo agora; migração é conserto,
   e conserto pode esperar. Migração não é escopo desta feature.
2. **Prazo de retenção do backup é prazo de retenção do dado apagado.** A feature 009 anonimiza
   o banco vivo; ela não alcança cópia nenhuma. Por isso o plano trava: qualquer mecanismo de
   backup escolhido precisa de **prazo de expiração automático e escrito**, e a Política precisa
   dizer esse prazo. Sem isso, "Apagamos seu nome" (`privacy_policy_page.dart:181-183`) deixa
   de ser verdade por tempo indeterminado.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2` — **nenhum código Dart novo**. Dois arquivos
Dart são tocados, e só em conteúdo português: o comentário de `LegalMetadata.hostingRegion`
(`lib/features/legal/legal_metadata.dart:22-27`) e o texto da Política
(`lib/features/legal/presentation/privacy_policy_page.dart`), que é string visível ao usuário.

**Primary Dependencies**: nenhuma nova no `pubspec.yaml`. Fora do repositório: acesso ao painel
do fornecedor (Supabase Cloud) e/ou Supabase CLI autenticada (`supabase login`) — que o agente
não tem e não deve ter.

**Storage**: PostgreSQL via Supabase Cloud — **nenhuma migration criada ou alterada**. Esta
feature não escreve uma linha em `supabase/`. Ela decide o que se faz com o conteúdo do banco,
não com o schema.

**Testing**: nenhum teste automatizado novo, e nenhum é possível — não se testa em CI a região
de um projeto de fornecedor sem guardar credencial de conta (research D-005). Os gates de
`.github/workflows/ci.yml` continuam valendo porque dois arquivos Dart mudam: `flutter analyze`,
`flutter test test/unit test/widget`, `flutter build web`. A verificação própria da feature está
em [quickstart.md](./quickstart.md) e é de duas naturezas: `grep` (afirmação falsa continua no
repositório? sim/não) e **um teste de restauração executado por humano, com resultado anotado**
(FR-008) — o único "teste" que esta feature de fato exige.

**Target Platform**: Flutter web em produção (`deploy-web.yml`), Supabase Cloud. Nenhuma mudança
de plataforma.

**Project Type**: infraestrutura e conformidade. Entrega documento e verificação, não
comportamento.

**Constraints**:

- Nada muda na tela. Se algo mudar visualmente além do texto legal, saiu do escopo.
- Nenhuma credencial de fornecedor entra no CI (research D-005).
- Nenhum backup pode ir parar fora do Brasil sem que a Política declare (edge case da spec).
- Toda cópia de dado pessoal precisa de prazo de expiração automático e escrito (research D-002).
- A escolha do mecanismo é do responsável pelo app; o plano garante que ela seja **feita e
  registrada**, não qual seja.

**Scale/Scope**: 1 arquivo novo (`docs/INFRA-PRODUCAO.md`), 2 arquivos Dart tocados em texto
português, 4 documentos atualizados (`README.md`, `.env.example`, `MAPA-DE-DADOS.md`,
`REVISAO-JURIDICA.md`), 2 achados fechados **fora do repositório**
(`/Users/jdsc2/projects/.achados/`). ~6 tarefas dependem de um humano com acesso ao fornecedor.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência |
|---|---|---|
| **I. Linguagem Ubíqua do Domínio** | ✅ PASS — sem objeto | **Esta feature não cria código Dart.** Nenhuma classe, enum, método, variável, parâmetro, provider ou arquivo `.dart` nasce aqui, nem em `lib/` nem em `test/` — logo a regra de identificador em inglês não tem no que se aplicar. O que muda em `.dart` é conteúdo em português por obrigação: o comentário de `LegalMetadata.hostingRegion` e strings da Política, que o Princípio I manda manter em português. O identificador `hostingRegion` já está em inglês e **não é renomeado**. Nenhum termo novo entra em `CONTEXT.md` |
| **II. Privacidade e LGPD por Padrão** | ⚠️ PASS — e é o motivo da feature existir | Nenhum dado novo é coletado. Mas as duas perguntas são de dado pessoal: a região é a base para a Política afirmar que não há transferência internacional (`privacy_policy_page.dart:145-150`), e o backup é cópia integral do banco — nome, apelido de menor, telefone, igreja (dado provavelmente sensível, `MAPA-DE-DADOS.md` § Classificação), gênero e idade. A feature entra **em débito** com este princípio hoje: o app afirma o que não verificou. Sai dele quando o registro existir. A trava de expiração automática (research D-002) existe para que criar backup não crie um débito novo |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | Spec escrita, checklist de qualidade preenchido, `/speckit-clarify` **não** rodado. A ambiguidade que sobra não é de regra de negócio — é falta de um *fato* (a região) e de uma *decisão de custo* (o backup), e nenhuma das duas se resolve conversando com o repositório. Ambas estão declaradas em Assumptions e viram tarefa nomeada, com dono humano, no `tasks.md` |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS — sem objeto | Nenhuma regra de domínio é tocada: nada de fila de espera, empate, revogação de voto ou Dupla Missionária. Nenhuma migration, nenhum RPC. A suíte existente continua passando sem alteração; se algum teste precisar mudar, a feature saiu do escopo. O análogo de "prova executável" aqui é FR-008 — a restauração precisa ter sido **executada**, não descrita |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel, permissão ou hierarquia. Um arquivo novo de documentação e três ponteiros de uma linha (research D-003). A opção mais fácil de automatizar — dump agendado em GitHub Actions — foi **rejeitada** por reintroduzir transferência internacional, não adotada por ser simples de escrever |

**Complexity Tracking**: nenhuma violação a justificar. O item que mais se aproxima é o arquivo
novo `docs/INFRA-PRODUCAO.md`; a alternativa mais simples (escrever tudo em documento existente)
foi avaliada e rejeitada em research D-003, porque nenhum documento existente comporta um
runbook de restauração nem tem como leitor quem provisiona ambiente.

## Project Structure

### Documentation (this feature)

```text
specs/019-producao-regiao-e-backup/
├── spec.md
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 6 decisões: por que o repositório não sabe a região,
│                        #   as opções de backup com fonte primária, onde registrar,
│                        #   o que muda na Política, a fronteira agente/humano, o não-escopo
├── quickstart.md        # Fase 1 — como provar que ficou verdadeiro (greps + o drill humano)
├── checklists/
│   └── requirements.md
└── tasks.md             # Fase 2 (/speckit-tasks)
```

**`data-model.md` e `contracts/` não são gerados, e não é omissão.**

- **`data-model.md`** descreve entidade, campo, relação e transição de estado. Esta feature não
  cria, altera nem move campo nenhum: zero migration, zero coluna, zero RPC. O mapa das
  entidades que o backup copiaria já existe e é `MAPA-DE-DADOS.md` — que é o ROPA de fato do
  projeto (art. 37 da LGPD) e ganha o backup como **destino** (FR-011). Criar um segundo mapa
  dentro de `specs/019/` seria fabricar uma cópia que diverge do primeiro na semana seguinte.
- **`contracts/`** descreve interface entre partes — schema SQL, endpoint, formato de mensagem.
  Não há nenhuma: o app não ganha chamada nova, o banco não ganha função nova. O único artefato
  desta feature que se parece com contrato é o **runbook de restauração** (FR-008), e ele
  precisa morar onde quem restaura vai procurar — `docs/INFRA-PRODUCAO.md` — e não dentro de uma
  pasta de spec que ninguém abre no meio de um incidente.

### Arquivos afetados (repositório inteiro)

```text
docs/
└── INFRA-PRODUCAO.md            # NOVO — registro canônico: região exigida + evidência da
                                 #   verificação (data, quem) + decisão de backup + runbook
                                 #   de restauração + resultado do drill

lib/features/legal/
├── legal_metadata.dart          # comentário de hostingRegion (FR-003) + version/effectiveDate
│                                #   se o texto da Política mudar. Identificadores intocados
└── presentation/
    └── privacy_policy_page.dart # só se a região não for BR (FR-004) ou se houver backup (FR-009)

README.md                        # § Arquitetura (48-51): ponteiro para docs/INFRA-PRODUCAO.md
.env.example                     # cabeçalho: ponteiro para docs/INFRA-PRODUCAO.md
MAPA-DE-DADOS.md                 # § Terceiros: estado real de produção + backup como destino
REVISAO-JURIDICA.md              # item 4 (182-208): resolvido com evidência, ou reaberto

supabase/                        # INTOCADO
test/                            # INTOCADO
.github/workflows/               # INTOCADO (ver research D-002, opção D rejeitada)

/Users/jdsc2/projects/.achados/  # FORA DO REPOSITÓRIO — SC-006
├── 20260724-direito-digital-iasd.md   # A-3 (região) fechado
└── 20260724-devops-iasd.md            # D-3 (backup) fechado
```

**Structure Decision**: a estrutura de `lib/` não muda. O registro canônico vai para `docs/`,
que já existe (`docs/plans/`), pelo raciocínio de research D-003: é o único lugar que comporta
runbook e cujo leitor é quem provisiona ambiente. Os três ponteiros (README, `.env.example`,
comentário em `legal_metadata.dart`) são de uma linha e apontam — nunca copiam o conteúdo, para
não criarem uma segunda verdade que envelhece.

## O que é tarefa de agente e o que é tarefa humana

Esta é a seção que decide o formato do `tasks.md`. **Tarefa humana continua sendo tarefa** — ela
entra numerada, com critério de pronto, e bloqueia o que depende dela.

| # | O que | Quem | Por quê |
|---|---|---|---|
| 1 | Ler a região do projeto de produção (painel, ou `supabase projects list`) | **Humano com login** | Não existe no repositório. `SUPABASE_URL` é `<ref>.supabase.co` e o *ref* não codifica região (research D-001) |
| 2 | Ler em que plano o projeto está (Free/Pro) | **Humano com login** | Decide se backup automático sequer existe (research D-002) |
| 3 | Perguntar ao fornecedor onde as cópias ficam (FR-010) | **Humano** | A documentação pública não diz — só "our storage servers" / S3 |
| 4 | Escolher o mecanismo, ou aceitar o risco de não ter (FR-006, FR-007) | **Humano responsável** | Custa dinheiro e é escolha, não cálculo. Precisa de nome e data |
| 5 | Executar a restauração uma vez (FR-008) | **Humano com login** | Backup não testado é hipótese, não garantia (edge case da spec) |
| 6 | Assinar o risco aceito, se for o caso (FR-007) | **Humano responsável** | Não existe "risco aceito" sem alguém que aceitou |
| — | Todo o resto: registro, comentário, Política, `MAPA-DE-DADOS`, `REVISAO-JURIDICA`, achados, greps de verificação | Agente | É documento, e documento o repositório escreve |

**O que deliberadamente não se automatiza**: a verificação de região no CI. Exigiria guardar um
personal access token do fornecedor como secret do repositório — credencial de conta inteira,
muito mais poderosa que as duas chaves de projeto que `deploy-web.yml:34-42` usa hoje, e contra
o aviso 🔴 de `deploy-web.yml:9-14`. Risco permanente de credencial em troca de uma verificação
que se faz uma vez é troca ruim. O que vira permanente é o **registro** dela.

## Precedência de FR-004: o portão que bifurca a feature

O `tasks.md` tem um portão explícito depois da verificação de região. O que sai dele são dois
ramos mutuamente exclusivos:

- **Ramo A — região é `sa-east-1`.** Os quatro documentos que afirmam isso deixam de ser
  suposição e passam a ser fato verificado. A Política **não muda** por causa da região.
- **Ramo B — região não é brasileira.** A primeira tarefa executada, antes de qualquer outra
  deste ramo, é corrigir `privacy_policy_page.dart:145-150` para declarar a transferência
  internacional. Só depois se conserta o comentário do código, o item 4 da revisão jurídica e os
  achados. **Migração é feature nova**, registrada como pendência — não entra aqui, e não
  atrasa a correção da Política.

O motivo da ordem: no ramo B o app está, agora, afirmando algo falso a titulares de dado. Isso é
o dano em curso. A região errada é um problema de conformidade que se conserta com um projeto
novo e uma janela de manutenção; a afirmação falsa se conserta com um parágrafo, hoje. Inverter
a ordem é deixar a mentira de pé enquanto se planeja a mudança.

## Backup e exclusão de conta: a interação que o plano trata como requisito, não como nota

`privacy_policy_page.dart:181-183` promete que a exclusão apaga nome, apelido, telefone, igreja,
gênero e idade. `privacy_policy_page.dart:196-198` acrescenta "Não há como desfazer nem
recuperar". A feature 009 entrega isso **no banco vivo** — `excluir_minha_conta()` anonimiza a
linha de `perfis` numa transação (`MAPA-DE-DADOS.md` § Retenção e exclusão). Um backup tirado
antes do pedido continua com o nome, e nenhuma função do banco alcança essa cópia.

Portanto, decidido neste plano:

1. Todo mecanismo de backup escolhido tem **prazo de expiração automático e escrito**. Sem prazo,
   FR-009 não é satisfazível com honestidade e a decisão não fecha.
2. Esse prazo é declarado na Política, na seção "Por quanto tempo guardamos"
   (`privacy_policy_page.dart:158-167`), no formato: *some do app na hora; some da cópia de
   segurança em até N dias*.
3. Se a escolha for o dump manual (research D-002, opção B), a expiração depende de um humano
   lembrar. Isso não elimina a opção — obriga a Política a declarar o prazo que o humano se
   comprometeu a cumprir, e obriga o registro a dizer que a garantia é de processo, não de
   máquina.
4. Se a escolha for **não ter backup** (opção C), a Política **não muda** por causa disso: não
   há destino novo, não há cópia, e nada do que ela diz hoje fica falso. É a única opção com
   custo zero de conformidade — e com risco de perda total.

## Riscos e decisões que precisam de olho

1. **O risco maior é a feature parar no meio.** As tarefas humanas são curtas (minutos), mas
   bloqueiam quase tudo. Se ninguém abrir o painel, o `tasks.md` fica com dois checkboxes
   abertos e a Política continua afirmando o que não se verificou. Mitigação: as tarefas
   humanas são as **primeiras** de cada fase e produzem um artefato colável, não uma impressão.
2. **Fechar o item errado.** `REVISAO-JURIDICA.md:182` já diz "RESOLVIDO: sa-east-1" — resolvido
   como *decisão*, com um ⚠️ logo abaixo dizendo que não é fato. Marcar FR-012 como resolvido
   sem colar a evidência do painel repete exatamente o erro que esta feature existe para
   consertar.
3. **A afirmação falsa tem mais de uma redação.** SC-002 pede 0 ocorrências de "ainda não
   provisionada" (`legal_metadata.dart:24`), mas `REVISAO-JURIDICA.md:200-201` diz a mesma coisa
   com outras palavras: "o projeto Supabase Cloud de produção ainda não foi criado". O
   `quickstart.md` procura as duas redações.
4. **Backup fácil é backup ilegal.** Dump agendado em GitHub Actions custa US$0 e leva vinte
   linhas de YAML — e copia o banco inteiro para fora do Brasil. Está registrado como rejeitado
   em research D-002 justamente porque é a solução que alguém vai propor de novo daqui a seis
   meses.
5. **Subir a versão da Política aumenta a dívida da 017.** Não existe coluna com a versão aceita
   (`legal_metadata.dart:1-9`); subir de `1.1` para `1.2` amplia o conjunto de pessoas cujo
   consentimento é de versão desconhecida. Subir continua sendo o certo — não subir seria texto
   novo sob versão velha — mas o cruzamento fica registrado, e é argumento a favor da 017.
6. **`MAPA-DE-DADOS.md` § Terceiros está desatualizado agora**, antes desta feature: afirma que
   "nenhuma configuração de produção existe no repositório", o que deixou de ser verdade com
   `.env.prod` e os secrets de `deploy-web.yml`. Vira tarefa.
7. **Dois achados vivem fora do repositório**, em `/Users/jdsc2/projects/.achados/`. SC-006 só
   fecha escrevendo lá. Quem executar precisa saber que sai da árvore do projeto.

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 6 decisões — por que o repositório não sabe a
região e o que conta como evidência (D-001); as opções de backup com fonte primária de
2026-08-09 e a trava de expiração automática (D-002); onde a decisão fica escrita e por quê
(D-003); o que muda na Política e a versão do texto legal (D-004); a fronteira agente/humano
(D-005); e o não-escopo (D-006).

Nenhum `NEEDS CLARIFICATION` de regra de negócio restante. Restam duas **incógnitas de fato**,
que são tarefas com dono humano e não ambiguidade de spec: a região real, e a escolha de backup.

## Fase 1 — Design

Concluída. Ver [quickstart.md](./quickstart.md): as verificações por `grep` que provam que
nenhuma afirmação não verificada sobrou, o formato exigido da evidência, e o roteiro do drill de
restauração (FR-008) — o único procedimento desta feature que precisa ser **executado** e não só
escrito.

`data-model.md` e `contracts/` não se aplicam (justificado em Project Structure).

**Constitution Check pós-design**: reavaliado, sem mudança. Os cinco princípios seguem PASS, com
as mesmas duas ressalvas (II, por ser o débito que a feature paga; III, por `clarify` não
rodado). O design não introduziu papel, dependência, migration, entidade nem identificador Dart.

## Complexity Tracking

Nenhuma violação de constituição a justificar. Tabela intencionalmente vazia.
