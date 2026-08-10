# Quickstart — provar que a tela de Novidades funciona

**Feature**: 022-novidades | **Data**: 2026-08-10

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
flutter pub get
```

**Sem `supabase start`.** Esta feature não fala com o banco, e essa ausência é uma verificação
em si: se o quickstart precisar do Postgres, o desenho quebrou.

## Parte 1 — Os gates (automatizado)

```bash
flutter analyze
flutter test test/unit test/widget
flutter build web
```

Anote os **números reais**. Linha de base ao começar: 0 issues, **204** unidade+widget.

`dart test test/integration` **não deve ganhar nenhum teste novo** — e deve continuar
passando, intocado.

## Parte 2 — O que os testes provam

| # | Caso | Esperado | Requisito |
|---|---|---|---|
| 1 | Lista com três itens de datas diferentes | Ordenada do mais recente para o mais antigo | FR-001 |
| 2 | Item com data anterior a 6/10/2026 | **Não** aparece | FR-006 |
| 3 | Lista vazia | Texto explicando o que é a tela e por que não há nada — nunca área em branco | FR-007 |
| 4 | Nenhum marcador guardado | Sem aviso, e o marcador é gravado na hora | FR-011, D-003 |
| 5 | Marcador anterior à Novidade mais recente | Com aviso | FR-008 |
| 6 | Abrir a tela | Marcador vira a data mais recente; aviso some | FR-009 |
| 7 | Reabrir sem Novidade nova | Sem aviso | FR-010 |
| 8 | Novidade mais recente publicada depois | Aviso volta | US2/AC4 |
| 9 | Texto de toda Novidade da lista real | Sem `.dart`, sem nome de tabela, sem `v1.` — varredura sobre a lista inteira | FR-003, SC-002 |

O caso 9 é o que impede a lista de degenerar: ele roda sobre o **conteúdo real**, não sobre um
exemplo, então ele quebra no dia em que alguém colar uma frase de commit.

## Parte 3 — Verificação manual

### 3.1 Nada sobre a leitura vai ao servidor (FR-012, SC-003)

O item mais importante desta lista, e o único que prova a decisão de privacidade.

```bash
flutter run -d chrome
```

Com o DevTools aberto na aba **Network**, filtrando por `supabase`:

- [ ] abrir a Home — nenhuma requisição nova por causa do aviso de novidade;
- [ ] abrir a tela de Novidades — **nenhuma requisição**;
- [ ] fechar e reabrir — **nenhuma requisição**.

Qualquer chamada aqui significa que a leitura virou dado no servidor, e o desenho precisa
voltar.

### 3.2 O marcador está mesmo no aparelho

Ainda no DevTools, aba **Application → Local Storage**:

- [ ] depois de abrir a tela, existe uma chave com a data;
- [ ] apagar essa chave e recarregar: o app se comporta como instalação nova — sem aviso, e a
      chave é recriada (FR-011).

### 3.3 A Política não precisou de frase nova (FR-014, SC-007)

- [ ] `git diff` não toca `privacy_policy_page.dart` nem `legal_metadata.dart`.

É a verificação mais barata da feature e a que mais diz: se a Política precisou mudar, algo
passou a ser coletado.

### 3.4 A tela é encontrável (FR-004, SC-006)

- [ ] a partir da Home, alguém acha "Novidades" em menos de 15 segundos, sem ajuda;
- [ ] o rótulo é **texto**, não só ícone.

### 3.5 Visitante vê o mesmo (FR-005)

- [ ] sem Perfil, a tela abre e mostra a mesma lista — nada de redirecionamento para cadastro.

### 3.6 O texto é para gente do distrito (SC-001)

Não é revisão de quem escreveu. **Três pessoas do distrito** leem a lista e dizem, com as
palavras delas, o que mudou.

- [ ] as três entendem cada item sem explicação;
- [ ] nenhuma pergunta "o que é isso?" sobre um termo.

Enquanto a lista estiver vazia, este item fica pendente — e é o primeiro a fazer quando o
primeiro item entrar.

### 3.7 Navegador com armazenamento bloqueado

Registrado em research como não verificado.

- [ ] em janela com cookies/armazenamento bloqueados, a tela **abre e lista normalmente**; só
      o aviso é que reaparece a cada visita. Não pode dar erro.

## Como saber que falhou

| Sintoma | Significa |
|---|---|
| Alguma requisição ao servidor ao abrir Novidades | A leitura virou dado. É o modo de falha que a feature existe para evitar |
| A Política precisou de frase nova | Idem — algo passou a ser coletado |
| Nasceu arquivo em `supabase/migrations/` | A feature vazou do escopo: ela é cliente puro |
| O aviso aparece na primeira instalação | O marcador não está sendo gravado na primeira abertura (D-003) |
| Tela vazia mostrando área em branco | FR-007 não foi cumprido — a tela precisa se explicar |
| Um item cita arquivo, tabela ou versão | O critério de escrita foi furado; ver `CRITERIO-DE-NOVIDADE.md` |

## Definição de pronto

- [ ] os quatro gates verdes, com números anotados;
- [ ] os 9 casos da Parte 2 cobertos por teste;
- [ ] 3.1, 3.2 e 3.3 conferidos à mão — são a prova da decisão de privacidade;
- [ ] `CONTEXT.md` com a entrada **Novidade**;
- [ ] `CRITERIO-DE-NOVIDADE.md` na raiz;
- [ ] **confirmado com o dono do app** se a lista nasce vazia ou se ele quer as 21 features
      retroativas — é a única pergunta em aberto, e ela muda o trabalho de escrita, não o
      código.
