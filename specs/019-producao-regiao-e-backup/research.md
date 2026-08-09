# Fase 0 — Pesquisa: Produção — confirmar região e resolver backup

**Feature**: `019-producao-regiao-e-backup` | **Data**: 2026-08-09

Seis decisões. As três primeiras existem porque o repositório **não consegue** responder as
perguntas da spec sozinho; elas definem o que conta como resposta e quem pode dá-la.

---

## D-001 — O repositório não sabe em que região o projeto de produção roda. Verificado, não suposto.

**Decisão**: parar de procurar no repositório. A região só sai do fornecedor.

**O que foi conferido** (2026-08-09, este agente, sem tocar credencial):

| Onde | O que tem | Responde a região? |
|---|---|---|
| `.env.prod` | chaves `SUPABASE_URL`, `SUPABASE_PUBLISHABLE_KEY`, `SUPABASE_SERVICE_ROLE_KEY`, `ADMIN_*` | Não |
| `.env` (local) | mesmas chaves menos a service role | Não |
| `.github/workflows/deploy-web.yml:34-42` | injeta só `SUPABASE_URL` e `SUPABASE_PUBLISHABLE_KEY` como secrets de repositório | Não |
| `supabase/config.toml` | `tenant_region`/`user_pool_region`/`s3_region` — todos comentados ou de storage local (linhas 351, 357, 398-401) | Não. Nada aqui descreve o projeto Cloud |
| `lib/features/legal/legal_metadata.dart:22-27` | `hostingRegion = 'sa-east-1 (São Paulo, Brasil)'` | **Não.** É a *intenção*, e o próprio comentário diz "Ainda não provisionada" |
| `REVISAO-JURIDICA.md:182-208` | item 4, "RESOLVIDO: sa-east-1", com ⚠️ explícito de que "isto é uma decisão, não um fato ainda em produção" | Não |
| `README.md:48-51` | "decidido: Supabase Cloud gerenciado (região `sa-east-1`)" | Não. Também é decisão |

`SUPABASE_URL` de um projeto Supabase Cloud tem a forma `https://<project-ref>.supabase.co`.
O *ref* é um identificador opaco: **não codifica a região**. Não existe, em lugar nenhum do
repositório, um campo que diga onde o projeto roda.

**Conclusão que importa**: quatro documentos afirmam `sa-east-1`, e os quatro citam uns aos
outros. É uma única afirmação repetida quatro vezes, e a origem dela é uma decisão de
2026-07-24 — não uma leitura do painel. **Nenhuma evidência no repositório responde a pergunta
da spec.**

**O que conta como evidência (FR-001)** — só duas coisas, ambas exigindo login:

1. `supabase login` + `supabase projects list`, colando a linha do projeto de produção.
   A CLI exige um personal access token guardado por `supabase login`
   (docs oficiais de `supabase projects list`, consultado 2026-08-09).
2. O painel: *Project Settings → General*, transcrevendo a string de região exatamente
   como aparece.

Em qualquer dos dois, o registro precisa de **data e de quem verificou**. Print de tela não
serve — não se versiona nem se pesquisa por `grep`; o que vai para o repositório é o texto.

O `project-ref` **pode** ser escrito no registro sem problema de segredo: ele já é público, vai
dentro do `.env` que `deploy-web.yml:34-42` empacota no build web. O que nunca entra é a
`SUPABASE_SERVICE_ROLE_KEY`, que só existe em `.env.prod` e propositalmente **não** está no CI
(ver o aviso 🔴 em `deploy-web.yml:9-14`).

**Alternativas rejeitadas**: inferir a região por latência de rede (mede caminho de CDN, não
onde o Postgres mora); usar a Management API a partir do CI (exigiria guardar um personal
access token do fornecedor como secret de repositório — credencial de conta inteira, muito mais
poderosa que as duas chaves de projeto que o CI usa hoje, para responder uma pergunta que se
responde uma vez).

---

## D-002 — Opções de backup, com fonte primária, e a trava que o plano impõe a qualquer escolha

**Fonte primária**: `supabase.com/docs/guides/platform/backups`, consultada em **2026-08-09**.
Literal:

> "We automatically back up all Pro, Team, and Enterprise Plan projects on a daily basis."

> Free tier: "We recommend that free tier plan projects regularly export their data using the
> Supabase CLI `db dump` command."

> Pro: "last 7 days of daily backups". Team: 14 dias. Enterprise: até 30 dias.

> PITR: add-on de Pro para cima, "up to seconds of granularity"; "in the worst case scenario,
> PITR achieves a Recovery Point Objective (RPO) of two minutes"; exige "at least a Small
> compute add-on".

> Restauração: "You can access daily backups in the Database > Backups section of the Dashboard
> and restore a project to any of the backups."

> Sobre onde as cópias ficam: a página **não diz a região**. Só "our storage servers" e, ao
> apagar um projeto, "we permanently remove all associated data, including any backups stored
> in S3".

Isso confirma e atualiza o que `.achados/20260724-devops-iasd.md:148-151` (D-3) já registrava:
*"Supabase Cloud free tier não tem backup automático nem PITR"*. Continua verdade em 2026-08-09.

### As opções, honestas quanto ao que cada uma custa

| | Mecanismo | RPO (quanto se perde) | Custo | Expira sozinho? | Nova transferência internacional? |
|---|---|---|---|---|---|
| **A** | Plano Pro — backup diário automático, 7 dias | até 24h | US$25/mês | Sim, 7 dias | **Não sei** — depende da resposta de FR-010 |
| **B** | `supabase db dump` periódico, para lugar que o responsável controla no Brasil | o intervalo escolhido | US$0 + trabalho | Só se alguém apagar. Regra humana | Não, se o destino for no Brasil |
| **C** | Sem backup, risco aceito por escrito | tudo | US$0 | N/A | Não |
| **D** | Dump agendado em GitHub Actions, guardado como artefato | o intervalo | US$0 | Retenção do GitHub — [NÃO VERIFICADO] | **Sim** |

**A opção D é desaconselhada pelo plano, não é uma escolha em aberto.** Ela copia o banco
inteiro — nome, apelido de menor, telefone, igreja, gênero, idade — para a infraestrutura do
GitHub, que não fica no Brasil. Reintroduz exatamente a transferência internacional que a
decisão de região existe para zerar (`REVISAO-JURIDICA.md:190-196`), e por uma porta que
ninguém vai reler. Custa US$0 e é a mais fácil de automatizar — por isso está escrita aqui
como rejeitada, e não omitida.

### A trava: **toda cópia precisa de prazo de morte automático**

Qualquer opção que crie uma cópia (A, B ou D) só é aceitável se a cópia **expirar sozinha, num
prazo escrito**. O motivo não é higiene, é a promessa da Política:

- `privacy_policy_page.dart:181-191` promete "Apagamos seu nome, Apelido, telefone, Igreja de
  origem, gênero e idade" quando a pessoa exclui a conta.
- `privacy_policy_page.dart:196-198` vai além: "Não há como desfazer nem recuperar".
- A feature 009 cumpre isso **no banco vivo** (`excluir_minha_conta()` anonimiza a linha de
  `perfis` — ver `MAPA-DE-DADOS.md` § Retenção e exclusão). Ela não alcança nenhuma cópia.

Logo: **prazo de retenção do backup = prazo de retenção do dado apagado**. Um backup que dura
7 dias transforma a promessa em "some do app na hora, e da cópia de segurança em até 7 dias" —
declarável e defensável. Um backup sem prazo transforma a mesma frase em falsa e indefinida, e
o Fluxo de Desenvolvimento da constituição chama isso pelo nome: divergência entre o que a spec
promete e o que o código faz é violação de constituição, não detalhe.

Consequência prática: **a opção B só fecha se vier com uma regra de expiração escrita** ("dumps
com mais de N dias são apagados"), e a regra depende de um humano lembrar — que é justamente o
modo de falha que FR-009 proíbe. Isso não a elimina; obriga a que a Política declare o prazo
que o humano se compromete a cumprir, não um prazo idealizado.

**Nenhuma opção é escolhida aqui.** A spec (Assumptions) diz que a escolha é do responsável
pelo app. Esta pesquisa entrega o que ele precisa para escolher: RPO, custo, e o que cada uma
obriga a Política a dizer.

### FR-010 é uma pergunta que só o fornecedor fecha

A documentação pública não diz em que região as cópias ficam. Se a escolha for A, FR-010 vira
uma pergunta por escrito ao suporte do fornecedor, com a resposta guardada. **Enquanto ela não
for respondida, a opção A não pode ser registrada como "zero transferência internacional"** —
seria repetir o erro que esta feature existe para consertar: afirmar sem verificar.

---

## D-003 — Onde a decisão fica escrita: `docs/INFRA-PRODUCAO.md`, com três ponteiros

**Decisão**: um arquivo novo, `docs/INFRA-PRODUCAO.md`, como registro canônico — região exigida,
evidência da verificação com data, decisão de backup, e o runbook de restauração. Mais três
ponteiros de uma linha, dos lugares por onde as pessoas entram.

**O critério**: a pergunta de FR-002/FR-005 não é "onde isso é verdade", é *"o que a pessoa que
vai criar o próximo ambiente vai ter aberto na tela quando criar"*.

| Candidato | Por que não é o canônico |
|---|---|
| `REVISAO-JURIDICA.md` item 4 | É onde a decisão nasceu, e continua sendo atualizado (FR-012). Mas quem provisiona infra não abre um documento de revisão jurídica. E ele não comporta runbook |
| `lib/features/legal/legal_metadata.dart` | Comentário de código Dart. Quem cria projeto no painel do fornecedor não está lendo `lib/features/legal/`. Um comentário também não comporta procedimento de restauração |
| Novo `.md` na raiz | A raiz já tem quatro (`CONTEXT`, `MAPA-DE-DADOS`, `REVISAO-JURIDICA`, `SECURITY-AUDIT`) e todos são temáticos ou auditoria datada. Um quinto dilui |
| `SECURITY-AUDIT.md` | Auditoria datada de 2026-07-24, fechada. Registro vivo não entra em documento fechado |
| `.tickets/` | Efêmero por desenho — `IASD-03.md` já foi descartado |
| `.achados/` (fora do repo) | Vive em `/Users/jdsc2/projects/.achados/`, é do portfólio inteiro, e é log de achado, não documento de requisito. Continua sendo atualizado (SC-006), mas não é onde se procura "como provisiono isto" |

**Por que `docs/`**: já existe (`docs/plans/`), é o único lugar que comporta um runbook — e
FR-008 exige um procedimento de restauração escrito, que não cabe em comentário nem em item de
revisão jurídica. Segue também o padrão do portfólio já citado pelos próprios achados
(`infra/docs/adr/`), adaptado a um repositório que não tem `infra/`.

**Os três ponteiros** (uma linha cada, apontando para o arquivo — não cópias, que divergem):

1. `README.md` § Arquitetura, linhas 48-51, onde a região já é mencionada como decisão.
2. `lib/features/legal/legal_metadata.dart`, no comentário de `hostingRegion` — que FR-003 já
   obriga a reescrever.
3. Cabeçalho de `.env.example` — lido por todo mundo que monta um ambiente, e hoje não diz nada
   sobre região.

---

## D-004 — O que muda na Política, e a versão do texto legal

**A Política hoje não tem seção de segurança.** Conferido: as nove seções são "Quem é
responsável", "O que pedimos no cadastro", "O que fica público", "Com quem compartilhamos",
"Por quanto tempo guardamos", "Seus direitos", "Crianças e adolescentes", "Alterações" e "Fale
com a gente" (`privacy_policy_page.dart`, linhas 51, 61, 113, 145, 158, 169, 215, 241, 250).
SC-005 fala em "o que a Política diz sobre retenção e segurança" — sobre segurança ela **não
diz nada**. Silêncio não contradiz, mas também não cobre backup: se houver cópia, ela é destino
de dado pessoal e entra em "Com quem compartilhamos" / "Por quanto tempo guardamos", que
existem.

Os três pontos que podem mudar:

| Gatilho | Onde | O que passa a dizer |
|---|---|---|
| Região ≠ Brasil (FR-004) | `privacy_policy_page.dart:145-150` | Declara a transferência internacional: para qual país/região, e sob qual hipótese do art. 33 da LGPD. Some "O dado não sai do Brasil" |
| Backup existe (FR-009) | `privacy_policy_page.dart:158-167` (retenção) e 145-150 (destinos) | Que a cópia existe, por quanto tempo é guardada, e que quem exclui a conta some do app na hora e da cópia em até N dias |
| Backup existe (FR-009) | `privacy_policy_page.dart:181-198` | O "Não há como desfazer nem recuperar" precisa conviver com a cópia; ou se qualifica, ou continua verdade por outro motivo (a restauração seletiva de uma pessoa não é oferecida) |

**Versão do texto legal**: qualquer um dos três é mudança material — destino novo de dado, ou
declaração de transferência internacional. `LegalMetadata.version` (hoje `'1.1'`) e
`effectiveDate` sobem junto.

**Limitação conhecida, que esta feature não resolve**: `perfis.consentimento_lgpd_aceito_em`
grava a data do aceite, não a versão aceita — o próprio comentário de `legal_metadata.dart:1-9`
diz isso, e é o objeto da feature **017**. Subir a versão aqui aumenta o número de pessoas cujo
consentimento é de versão desconhecida. Não é motivo para não subir (não subir seria pior:
texto novo sob versão velha). É motivo para registrar o cruzamento, e é argumento a favor da
017.

---

## D-005 — A fronteira agente/humano, e por que ela não é preguiça

**Decisão**: separar as tarefas por *quem consegue executá-las*, não por dificuldade.

O que **só** um humano com acesso ao painel/conta do fornecedor faz:

- ler a região do projeto (D-001);
- ler qual plano o projeto está (Free vs. Pro decide se backup automático existe);
- perguntar ao fornecedor onde as cópias ficam (FR-010);
- mudar de plano ou ligar PITR — gasta dinheiro;
- **escolher** o mecanismo, ou aceitar o risco de não ter nenhum (FR-006, FR-007): é decisão do
  responsável, com nome e data, não um cálculo;
- executar a restauração de teste (FR-008) contra um projeto real.

O que agente ou CI faz sozinho: tudo que é documento — o registro, o comentário de
`legal_metadata.dart`, o texto da Política, `MAPA-DE-DADOS.md`, `REVISAO-JURIDICA.md`, os
achados, e as verificações por `grep` do `quickstart.md`.

**Por que não automatizar a verificação de região no CI**: seria preciso guardar um personal
access token do fornecedor como secret do repositório. Esse token dá acesso à conta inteira,
não a um projeto — é ordens de grandeza mais poderoso que as duas chaves públicas que
`deploy-web.yml` usa hoje, e o próprio workflow tem um aviso 🔴 na linha 9 contra ampliar o que
entra ali. Trocar risco permanente de credencial por uma verificação que se faz uma vez é troca
ruim. A verificação continua manual, e o **registro** dela é o que vira permanente.

---

## D-006 — O que esta feature não faz

- **Migrar de região.** Se a verificação der uma região não brasileira, FR-004 corrige a
  Política e a migração vira feature separada. A documentação oficial de regiões não descreve
  troca de região depois de criado o projeto — na prática é criar projeto novo e mover o banco,
  com o app em produção e gente usando. Isso é maior que esta feature inteira.
- **Retenção de log de acesso** (Marco Civil art. 15) — `REVISAO-JURIDICA.md:210-220`, depende
  de parecer, fora do escopo pela própria spec.
- **Versionamento do consentimento** — feature 017 (D-004).
- **Camada de front** (GCS + CDN) — feature 020, que declara a mesma fronteira
  (`specs/020-deploy-gcs-cdn/spec.md:21-23`).
- **Nenhum código Dart novo.** Ver o Constitution Check do plano.

---

## Correções de referência encontradas na leitura

Duas citações da spec apontam para lugar que não existe mais. Não invalidam nada — o conteúdo
está no arquivo, em outra linha:

- A spec cita `.achados/20260724-devops-iasd.md:184-187` para D-3. O arquivo tem **156 linhas**.
  D-3 está em **115-120** ("continua em aberto, mas moot por ora") e a reabertura em
  **148-151** ("D-3 volta à mesa — Supabase Cloud free tier não tem backup automático nem
  PITR"), dentro da emenda de 2026-08-05 que reverteu D-1 para Supabase Cloud.
- `MAPA-DE-DADOS.md` § Terceiros ainda afirma: *"hoje só existe configuração para ambiente
  local"* e *"Nenhuma configuração de produção (região do projeto Supabase Cloud, ou self-host)
  existe no repositório"*. Isso ficou falso quando `.env.prod` e os secrets de
  `deploy-web.yml:34-42` passaram a existir. Vira tarefa.

E uma variante de SC-002 que o grep literal não pega: além de "ainda não provisionada"
(`legal_metadata.dart:24`), `REVISAO-JURIDICA.md:200-201` diz *"O projeto Supabase Cloud de
produção **ainda não foi criado**"*. É a mesma afirmação falsa com outras palavras. O
`quickstart.md` procura as duas.
