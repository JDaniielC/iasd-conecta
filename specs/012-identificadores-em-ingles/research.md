# Research: Identificadores Dart em inglês

**Feature**: 012-identificadores-em-ingles | **Date**: 2026-08-09

---

## D-001 — O compilador é o guarda-corpo. Busca-e-substitui textual está proibido

**Decisão**: o ciclo de rename é sempre este, um símbolo por vez:

1. Renomear a **declaração** (a classe, o método, o campo, o provider, o arquivo).
2. Rodar `flutter analyze`.
3. Corrigir exatamente os erros que ele apontar.
4. Repetir até `flutter analyze` ficar limpo.
5. Rodar os testes e comparar a contagem com a de antes.

**Nunca** `sed`, `grep -rl | xargs`, nem substituição em massa por texto.

**Rationale**: é a única propriedade que torna FR-012 e FR-013 impossíveis de violar por
acidente. O raciocínio:

- Uma referência a símbolo quebrada **sempre** produz erro de compilação.
- Um literal de string alterado **nunca** produz erro de compilação.

Portanto, um método que só edita o que o compilador aponta jamais toca em literal. A garantia
é estrutural, não disciplinar — não depende de alguém lembrar.

**A armadilha concreta**: as mesmas palavras portuguesas aparecem em três papéis diferentes,
e nenhuma ferramenta textual os distingue:

| Papel | Exemplo | Traduz? |
|---|---|---|
| Identificador Dart | `final String nome;` | **Sim** → `name` |
| Chave de leitura/gravação | `map['nome'] as String` | **Não** — é o contrato com o banco |
| Conteúdo visível | `'Informe um nome'`, e a palavra "nome" dentro do texto da Política de Privacidade | **Não** — é português por decisão da constituição |

Um `sed s/nome/name/g` acerta o primeiro e destrói os outros dois. O terceiro é feio; o
segundo quebra o app em produção sem nenhum aviso.

**Alternativas descartadas**:
- *Refatoração de IDE (`Rename Symbol`)*: seria a ferramenta certa — ela é ciente da árvore
  sintática. Descartada porque não está disponível para quem vai executar isto de forma não
  interativa. O ciclo guiado pelo analisador dá a mesma garantia, mais devagar.
- *Adicionar um pacote de refatoração*: dependência nova numa feature cujo princípio é não
  mudar nada. Contradição direta com o Princípio V.

---

## D-002 — Mapa de tradução

**Decisão**: esta tabela é a fonte de verdade. Ela vai para `CONTEXT.md`, ao lado de cada
entrada do glossário, **antes** da primeira etapa de rename (FR-005). Uma tradução por
conceito, para sempre.

### Termos do glossário

| Termo (glossário) | Identificador Dart | Situação |
|---|---|---|
| Visitante | `Visitor` | novo |
| Usuário | `User` | novo |
| Perfil | `Profile` | **já em uso** |
| Conta | `Account` | **já em uso** (`UpgradeContaPage` → `UpgradeAccountPage`) |
| Apelido | `Nickname` | **já em uso** (`PublicProfile.nickname`) |
| Categoria de Grupo | `GroupCategory` | novo (`CategoriaGrupo`) |
| Ação sugerida | `SuggestedAction` | **já em uso** |
| Grupo | `Group` | novo (`Grupo`) — exemplo da própria constituição |
| Participar do Grupo | `GroupMembership` / `joinGroup` | novo (`participar`) |
| Dono do Grupo | `GroupOwner` / `isOwner` | novo (`souDono`) |
| Ação | `Action` | novo (`Acao`) — exemplo da própria constituição |
| Ação candidata | `CandidateAction` | novo (`candidata`) |
| Rodada de votação | `VotingRound` | novo (`Rodada`) — exemplo da própria constituição |
| Votar | `Vote` / `vote` | novo (`Voto`, `votar`) |
| Igreja | `Church` | **já em uso** |
| Administrador do distrito | `DistrictAdmin` | **já em uso** |
| Ministério | `Ministry` | novo |
| Líder/Diretor | `Leader` | **já em uso** (`LeadershipDeclaration`) |
| Dupla Missionária | `MissionaryPair` | **já em uso** |

### Conceitos operacionais recorrentes

| Conceito | Identificador Dart | Hoje |
|---|---|---|
| Confirmar presença | `confirmAttendance` | `confirmarPresenca` |
| Desistir | `withdraw` | `desistir` |
| Fila de espera | `waitlist` | `fila` |
| Confirmado (status) | `confirmed` | `confirmado` |
| Criador | `creator` / `creatorId` | `criador`, `criadorId` |
| Cancelar / cancelada | `cancel` / `isCancelled`, `cancelledAt` | `cancelar`, `cancelada`, `canceladaEm` |
| Data e hora | `dateTime` | `dataHora` |
| Local | `location` | `local` |
| Detalhes | `details` | `detalhes` |
| Nome | `name` | `nome` |
| Limite de vagas | `capacity` | `limiteVagas` |
| Prazo | `deadline` | `prazo` |
| Sábado (adventista) | `sabbath` / `isOnSabbath` | `acaoNoSabado` |
| Período da Ação | `ActionPeriod` | `PeriodoAcao` |
| Ordenação | `sortOrder` | `_OrdenacaoAcao`, `_OrdenacaoGrupo` |
| Agrupar por Igreja | `groupByChurch` | `agruparPorIgreja` |
| Seção por Igreja | `ChurchSection` | `SecaoPorIgreja` |
| Participante | `member` | `participantes` |
| Transferir posse | `transferOwnership` | `transferirPosse` |
| Propor candidata | `proposeCandidate` | `proporCandidata` |
| Abrir Rodada | `openRound` | `abrirRodada` |
| Fechar se devido | `closeIfDue` | `fecharSeDevido` |

**Rationale das escolhas menos óbvias**:

- **`capacity` para "limite de vagas"**: `seatLimit` seria literal mas estranho; `capacity` é
  o termo usual e não colide com nada.
- **`location` para "local"**: `local` é palavra reservada de leitura em Dart em contextos de
  variável local e confunde na leitura.
- **`isCancelled` / `cancelledAt`**: grafia britânica com dois `l`, escolhida uma vez para não
  virar `canceled` em metade do código. É exatamente o tipo de divergência que o mapa existe
  para prevenir.
- **`User` para Usuário**: colide conceitualmente com o `User` do Supabase, que já aparece no
  código. Onde houver ambiguidade real, prefixar (`AppUser`) — e registrar aqui se acontecer.
- **`Action`**: colide com `Action` do Flutter (`package:flutter/widgets.dart`). Quando um
  arquivo importar os dois, usar prefixo de import no lado do Flutter, nunca renomear o
  conceito de domínio. É a exigência da constituição: uma tradução por conceito.

**A colisão de `Action` é o item mais provável de virar exceção não planejada.** Está aqui
para que, se acontecer, a saída já esteja decidida.

### O que NÃO entra no mapa

Chaves de banco e valores de coluna: `'nome'`, `'data_hora'`, `'local'`, `'detalhes'`,
`'limite_vagas'`, `'criador_id'`, `'cancelada_em'`, `'grupo_id'`, `'rodada_id'`,
`'confirmada'`, `'eh_dupla_missionaria'`, `'genero_visitado'`, `'masculino'`, `'feminino'`,
`'confirmado'`, `'fila'`, `'acao_id'`, `'usuario_id'`, `'igreja_id'`, `'status'`,
`'created_at'`. Continuam em português, exatamente como estão.

---

## D-003 — Ordem das etapas: da menor superfície para a maior

**Decisão**: cinco etapas, nesta ordem.

| # | Etapa | Superfície (arquivos do módulo + importadores em `lib/` + testes) | Conteúdo |
|---|---|---|---|
| 0 | Mapa em `CONTEXT.md` | 1 | Nenhum código. Só o mapa de D-002 |
| 1 | `acao_sugerida/` → `suggested_action/` | 4 + 3 + 2 = 9 | Só rename de pasta e imports. O interior já está em inglês — é o ensaio do método com risco quase zero |
| 2 | `grupo/` → `group/` | 8 + 7 + 7 = 22 | `Grupo`, `NovoGrupo`, `CategoriaGrupo`, `GrupoRepository`, 4 páginas, providers |
| 3 | `acao/` → `action/` | 13 + 1 + 7 = 21 | `Acao`, `NovaAcao`, `AcaoComIgreja`, `Rodada`, `NovaRodada`, `Voto`, `PeriodoAcao`, `StatusConfirmacao`, 2 repositórios, 6 páginas. **Espera a 011 mergear** |
| 4 | `perfil/` → `profile/` | 12 + 12 + 12 = 36 | `PerfilRepository`, `PerfilGuard`, `ContaGuard`, `NomeModeration`, `PerfilAusenteBanner`, 4 páginas. Maior fan-in do app |
| 5 | `core/` | 4 + 32 = 36+ | `agrupar_por_igreja.dart`, `SecaoPorIgreja`, `hasPerfilProvider`, `perfilRepositoryProvider`. Toca quase todo arquivo do app |

**Rationale**: a etapa 1 tem risco quase nulo e valida o método antes de o diff ficar grande.
As etapas 4 e 5 têm o maior fan-in e ficam por último, quando o ciclo já está afiado. Cada
etapa fecha compilando e com os gates passando (FR-010) — dá para parar depois de qualquer
uma delas.

Módulos `legal/`, `leadership/` e `district_admin/` **não têm etapa própria**: já estão em
inglês por dentro. Eles são alterados de carona, dentro da etapa que renomeia o símbolo alheio
que eles referenciam (`grupoProvider`, `perfilPublicoProvider`, `categoriasGrupoProvider`).

**Alternativa descartada** — *da maior para a menor*: renomear `core/` e `perfil/` primeiro
faria o primeiro commit tocar quase todo o repositório, sem que o método tivesse sido validado
em nada. Se algo estiver errado no método, descobre-se no pior lugar possível.

---

## D-004 — Providers: renomear junto com o módulo que os define

**Decisão**: cada provider é renomeado na etapa do módulo onde é **declarado**, não onde é
usado. `hasPerfilProvider` e `perfilRepositoryProvider` estão declarados em
`lib/core/providers.dart` e, portanto, vão na **etapa 5**, mesmo falando de Perfil.

**Rationale**: a unidade de commit é o arquivo que declara. Renomear um provider a partir do
consumidor deixaria a declaração e o uso em commits diferentes — o repositório não compilaria
no meio, quebrando FR-010 e SC-009.

**Consequência**: durante as etapas 1 a 4, `hasPerfilProvider` continua com nome português
sendo usado por módulos já traduzidos. É feio e é temporário. A alternativa — mover a
declaração para o módulo de Perfil — seria mudança estrutural, que a spec proíbe (Assumptions:
"nenhum arquivo é dividido, unido ou movido de camada").

**Providers que já estão em inglês e não mudam**: `churchesProvider`,
`currentUserIdProvider`, `isAnonymousProvider`, `authStateChangesProvider`,
`supabaseClientProvider`, `goRouterProvider`, `authRepositoryProvider`,
`isDistrictAdminProvider`, `districtAdminRepositoryProvider`, `leadershipRepositoryProvider`,
`myDeclarationProvider`, `pendingDeclarationsProvider`, `currentLeadersProvider`,
`suggestedActionRepositoryProvider`, `suggestionsForCategoryProvider`,
`suggestionsForGroupProvider`, `allSuggestedActionsProvider`.
