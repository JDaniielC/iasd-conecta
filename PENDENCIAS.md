# Pendências

**Atualizado**: 2026-08-09 | **Base**: `main`, commit `da60de7`

O que falta, em quatro grupos: o que **implementar** (já tem spec, plan e tasks), o que
**especificar** (achado real, sem spec), o que **só gente mede** (verificação manual), e o
que **depende de decisão sua**.

O último grupo é o que trava mais coisa. Se você responder as cinco perguntas da seção
"Decisões que dependem de você", três features destravam.

---

## 1. Implementar — spec, plan e tasks prontos

Nada aqui precisa de trabalho de especificação. É só executar.

| Feature | Tarefas | O que entrega | Bloqueio |
|---|---|---|---|
| **015** consentimento-responsavel | 34 | Autorização do responsável para menor de 13 anos | **Destravada** — limiar decidido: abaixo de 13 |
| **014** arquivar-grupo | 31 | Arquivar Grupo (deletar é impossível hoje — FKs sem `on delete`) | — |
| **013** foto-de-capa | 35 | Foto de capa de Grupo e Ação, com aviso contra foto pessoal e de menor | — |
| **019** producao-regiao-e-backup | 27 | Registrar a região confirmada e o backup como risco aceito | **Destravada** — virou quase toda documento |
| **020** deploy-gcs-cdn | 32 (7 humanas) | Publicar em Cloud Storage + CDN, com invalidação de cache | 7 tarefas exigem conta GCP — só você |

**Sugestão de ordem**: 015 → 014 → 013, porque 015 é conformidade com prazo (menor de idade
sem autorização de responsável é exposição legal ativa) e as outras duas são produto. A 019 e
a 020 podem correr em paralelo assim que você abrir os acessos.

**A 015 tem uma armadilha já mapeada**, verificada contra o Postgres local durante o
planejamento: a check constraint precisa de `not valid`, e o preço é que a linha antiga vira
somente-leitura. É a mesma classe de armadilha que a 017 desarmou — vale reler
`specs/015-consentimento-responsavel/research.md` antes de começar.

---

## 2. Especificar — achado real, sem spec

Os três vieram de verificação durante a implementação, não de auditoria dedicada. Nenhum tem
spec, e nenhum deve virar código antes de ter.

### 2.1 `grant update` em `perfis` sem recorte de coluna

Registrado em `SECURITY-AUDIT.md`, achado 5. `perfis_update_own` protege a **linha**, não a
**coluna**: por chamada direta à API, a pessoa consegue escrever a própria `idade` e o próprio
`genero`.

**Não é vazamento** — só o próprio dado. É contorno de regra de domínio: mudar a `idade` foge
da exigência de Apelido de menor, mudar o `genero` forja composição de Dupla Missionária.

O conserto está escrito no achado (`revoke update` + `grant update (colunas)`). Exige migration
e conferir coluna a coluna quem mais escreve em `perfis`.

### 2.2 `anon` tem `TRUNCATE` em todas as tabelas

Descoberto ao verificar as premissas da 018. `anon` e `authenticated` têm `TRUNCATE`,
`REFERENCES` e `TRIGGER` nas 14 tabelas de `public` — herança do default do Supabase. **TRUNCATE
ignora RLS por completo.**

**Não é porta aberta hoje**: `anon` é `rolcanlogin = f`, só alcançável via PostgREST, que mapeia
verbos HTTP para SELECT/INSERT/UPDATE/DELETE e nunca emite TRUNCATE. É desvio de menor
privilégio, não vulnerabilidade viva — e é assim que deve ser descrito, sem dramatizar.

Vale spec porque o conserto (`revoke truncate, references, trigger`) toca todas as tabelas e
precisa de teste que prove que nada legítimo quebrou.

### 2.3 `deploy-web.yml` publica mesmo com teste vermelho

`.github/workflows/deploy-web.yml` dispara em `push: branches: [main]`, sem `needs:` e sem
`workflow_run:`. Não depende do `ci.yml` — um commit que quebra os testes vai para produção
assim mesmo.

É conserto de poucas linhas, mas muda quando o deploy acontece, então merece decisão escrita.
Está registrado como T031 dentro da 020; se a 020 demorar, vale spec própria antes.

---

## 3. Verificação manual — só gente mede

Nenhuma destas é "esqueci". Todas exigem rodar o app, olhar a tela, cronometrar alguém ou
esperar o tempo passar. Estão marcadas como abertas nos respectivos `tasks.md`.

### Exigem rodar o app e olhar

| Onde | O quê |
|---|---|
| 016 T039 | Quickstart, 16 itens. Três obrigatórios: `/perfil` sem Perfil, nome corrigido propagando na página do Grupo, e a data do consentimento não mudando ao corrigir o nome |
| 017 T021 | O corpo do `insert` no DevTools não pode ter chave de versão; e a tela de cadastro não ganhou campo nem passo |
| 018 T015 | Quatro telas: Líder visível a Visitante, estado da própria declaração, pendências do Administrador, e Usuário comum em `/leadership/pending` vendo lista vazia sem erro |
| 021 T025 | Item 3.3: a tela da Rodada continua marcando sua candidata e não mostra contagem de votos |
| 010 T019–T021 | Paisagem a ~375px, contraste dos pares texto/fundo, alvos de toque e leitor de tela |

### Exigem cronômetro ou tempo

| Onde | O quê |
|---|---|
| 016 T043 | Cronometrar 3 pessoas corrigindo o nome, do abrir o app até salvar. Meta: menos de 1 minuto |
| 016 T044 | Conferir `jdaniielc@gmail.com` 30 dias depois do lançamento: chegou pedido de acesso ou correção que a tela já cobre? |
| 011 T026a | Dar 5 Ações a alguém e cronometrar se identifica a mais confirmada em menos de 10s |
| 001 T039 | Tempos de cadastro (<2min) e reabertura (<5s) — bloqueado desde o começo por falta de ambiente |

### Exige produção no ar

| Onde | O quê |
|---|---|
| 021 quickstart 3.2 | `curl` anônimo contra o ambiente publicado, provando que `votos` devolve `[]` lá também |
| 018 | Mesma coisa para `liderancas` |

---

## 4. Decisões — respondidas em 2026-08-09 pelo dono do app

### 4.1 Limiar de idade — **abaixo de 13** ✅ (destrava a 015)

Autorização do responsável passa a ser exigida para **menor de 13 anos**, alinhado ao art. 14
da LGPD (criança até 12; adolescente de 13 a 17 não exige consentimento de um dos pais).
A 015 já previu o número numa função (`public.limiar_crianca()`), então é uma linha.

### 4.2 Região do Supabase — **a documentação está correta** ✅ (destrava parte da 019)

O dono do app confirma `sa-east-1 (São Paulo, Brasil)`.

**Registrar com honestidade sobre a natureza da evidência**: isto é **afirmação do
controlador**, não leitura do painel colada no repositório. É base suficiente para a
Política parar de ser tratada como possivelmente falsa, e a 019 deve gravar assim — quem ler
daqui a um ano precisa saber que a fonte é a palavra do controlador, com data, e não um
`select` nem uma captura de tela. Se um dia for preciso provar a terceiro, aí sim vale
anexar a evidência do painel.

O comentário `Ainda não provisionada` em `legal_metadata.dart` sai — ele está errado desde
que produção passou a existir.

### 4.3 Backup — **só os usuários; o resto é descartável** ✅ (destrava a 019)

Decisão: **não** contratar backup automático. O que precisa sobreviver é o **cadastro das
pessoas** (`auth.users` + `public.perfis`); Grupos, Ações, Rodadas, votos, confirmações e
declarações de liderança são passíveis de deleção e podem ser recriados pela comunidade.

A 019 documenta isso como **risco aceito**, com quem aceitou e quando — não como ausência de
decisão. E precisa dizer o que "perder o resto" significa na prática para quem usa o app.

**Consequência que a 019 tem de tratar, não contornar**: se existe qualquer cópia do cadastro,
ela contém dado pessoal, e a Política precisa dizer que ela existe, por quanto tempo é
guardada, e o que acontece com ela quando alguém pede exclusão de conta (art. 18, VI). Um
backup de `perfis` esquecido é justamente o caso em que o app promete apagar e não apaga.

### 4.4 Alcance da visibilidade do voto — **de acordo** ✅

Fica "só a própria pessoa lê o próprio voto", como implementado na feature 021. Nada a mudar.

### 4.5 Ordem das features de produto

Respondida na prática: **014 primeiro** (arquivar Grupo), por escolha do dono do app.

## 5. Conferido e fechado — não reinvestigar

Registrado para ninguém gastar tempo de novo.

- **`README.md`**: conferido, só uma linha desatualizada (a lista de rotas em `README.md:140`
  não cita `/perfil`, `/home` nem as telas de Administrador). Não é dívida grande.
- **Tickets fora do Spec Kit**: `IASD-01` e `IASD-02` estão **feitos**, `IASD-03` foi
  **descartado**, e `IASD-CI-GCS-UPLOAD` virou a feature 020. Nenhum ticket órfão.
- **As nove policies que ainda são `using (true)`** (`acoes`, `grupos`,
  `participacoes_grupo`, `confirmacoes_acao`, `rodadas_votacao`, `acoes_sugeridas`,
  `categorias_grupo`, `administradores_distrito`, `versoes_texto_legal`) foram conferidas uma a
  uma: **todas correspondem a algo que a Política de Privacidade declara público**. As duas que
  não correspondiam eram `votos` e `liderancas`, e as duas foram fechadas (features 021 e 018).
- **Identificadores em português**: 0 em `lib/` e 0 em `test/`. O verificador considera
  identificador que *começa* com a palavra portuguesa (`acaoId`, `grupoAsync`), que era o furo
  do scan da feature 012.
- **`CONTEXT.md`**: nenhum termo novo de domínio entrou nas features 016–021.

---

## 6. Estado das features

| Feature | Situação |
|---|---|
| 001–009 | Entregues |
| 010 pagina-home | Entregue; 3 verificações de acessibilidade abertas |
| 011 acoes-titulo-e-encerramento | Entregue; 1 medição com gente aberta |
| 012 identificadores-em-ingles | Entregue |
| 013 foto-de-capa | **Especificada, não implementada** (35 tarefas) |
| 014 arquivar-grupo | **Especificada, não implementada** (31 tarefas) |
| 015 consentimento-responsavel | **Especificada, não implementada** (34 tarefas) — destravada |
| 016 meu-perfil | Entregue; 3 verificações manuais abertas |
| 017 versao-do-consentimento | Entregue; 1 verificação manual aberta |
| 018 visibilidade-de-liderancas | Entregue; 1 verificação manual aberta |
| 019 producao-regiao-e-backup | **Especificada, não implementada** (27) — destravada; vira trabalho de documento |
| 020 deploy-gcs-cdn | **Especificada, não implementada** (32) — precisa de acesso GCP |
| 021 visibilidade-do-voto | Entregue; 1 verificação manual aberta |
