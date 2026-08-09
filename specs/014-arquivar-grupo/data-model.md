# Data Model: Arquivar Grupo

**Feature**: 014-arquivar-grupo | **Date**: 2026-08-09

Nenhuma entidade nova. **Grupo** ganha um estado, e a tela ganha um objeto de leitura que não
existe no banco.

---

## 1. Grupo — duas colunas novas

| Campo | Tipo | Regra |
|---|---|---|
| `arquivado_em` | timestamptz, nulo | Nulo = ativo. Não-nulo = arquivado, e quando |
| `arquivado_por` | uuid, nulo, → `perfis(id)` | Quem arquivou. Visível **só ao Administrador do distrito** (FR-019) |

Identificadores Dart: `archivedAt`, `archivedBy`, e o derivado `bool get isArchived`.

**Espelha o padrão que o app já usa** para "saiu de circulação sem deixar de ter existido":
`acoes.cancelada_em` e `perfis.anonimizado_em`. Um terceiro jeito de dizer a mesma coisa só
confundiria.

**Transições**:

```
ativo ──(Dono ou Administrador arquiva)──→ arquivado
arquivado ──(só o Administrador desarquiva)──→ ativo
```

Desarquivar zera as duas colunas. Não há histórico de arquivamentos — o Grupo voltou, e
guardar o rastro não foi pedido.

---

## 2. Prévia do arquivamento — objeto de leitura, não existe no banco

Os quatro números que a confirmação exibe **antes** de qualquer efeito (FR-003). Montado no
cliente a partir de consultas normais (research D-004): as quatro tabelas já têm leitura
pública, e criar uma RPC só para contar seria superfície de banco a mais sem ganho.

| Campo | O que conta | Consulta |
|---|---|---|
| `futureActions` | Ações de Grupo que serão canceladas | `acoes` com `grupo_id = X`, `data_hora > now()`, `cancelada_em is null`, `confirmada = true` |
| `confirmedAttendances` | Presenças já confirmadas nessas Ações | `confirmacoes_acao` das Ações acima, `status = 'confirmado'` |
| `openVotingRounds` | Rodadas abertas que serão encerradas | `rodadas_votacao` com `grupo_id = X`, `fechada_em is null` |
| `members` | Quem participa do Grupo | `participacoes_grupo` com `grupo_id = X` |

**Regra de exibição** (FR-004): quando os quatro forem zero, a confirmação diz em palavras que
nada será perdido — quatro zeros na tela não informam nada a quem está decidindo.

**Aviso extra** (FR-005): quando o Grupo é Ministério com Líder/Diretor confirmado no ano
vigente, a confirmação avisa **explicitamente** que a identificação pública do Líder sai do ar.

**A prévia não altera nada.** É só leitura, e é isso que torna FR-006 e SC-002 verdadeiros por
construção: desistir da confirmação não tem o que desfazer.

---

## 3. O que `arquivar_grupo` faz, numa transação

Ordem importa, e o "ou tudo, ou nada" é o motivo de ser função e não quatro chamadas:

1. **Valida** que quem chama é o Dono do Grupo ou Administrador do distrito. Senão, recusa.
2. **Recusa** se o Grupo já está arquivado (FR-009).
3. `grupos`: `arquivado_em = now()`, `arquivado_por = auth.uid()`.
4. `acoes`: `cancelada_em = now()` nas Ações de Grupo **futuras** e ainda não canceladas.
   Ação passada **não é tocada** — histórico é histórico (FR-014).
5. `rodadas_votacao` abertas: `fechada_em = now()`, `vencedora_id` **nulo**.
6. `acoes`: `delete` de **todas** as candidatas dessas Rodadas (`confirmada = false`).

**O passo 5 e 6 não usam `fechar_rodada_se_devido`**, e isso é deliberado — ela apura, e apurar
aqui criaria uma Ação confirmada num Grupo que acabou de sair do ar. Ver research D-003.

**O que NÃO acontece**:

| | Por quê |
|---|---|
| Nenhuma presença é apagada | FR-015. A Ação fica cancelada, com quem havia confirmado |
| Ninguém é promovido da fila | FR-007 do Princípio IV. Não há vaga a preencher em Ação que não vai acontecer |
| Nenhum desempate por sorteio | A Rodada fecha sem apurar |
| `participacoes_grupo` não é tocada | FR-017, para o desarquivamento devolvê-las (research D-005) |
| `liderancas` não é tocada | Histórico de quem foi responsável perante a igreja. O que muda é a **exibição** (FR-016) |

---

## 4. Quem pode o quê

| Ação | Visitante | Usuário | Participante | Dono do Grupo | Administrador do distrito |
|---|---|---|---|---|---|
| Ver Grupo ativo | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ver Grupo arquivado por link | ✅ | ✅ | ✅ | ✅ | ✅ |
| Arquivar | ❌ | ❌ | ❌ | ✅ (o seu) | ✅ (qualquer) |
| Desarquivar | ❌ | ❌ | ❌ | ❌ | ✅ |
| Ver lista de arquivados, com quem arquivou e quando | ❌ | ❌ | ❌ | ❌ | ✅ |
| Participar / propor candidata / abrir Rodada / votar em Grupo arquivado | ❌ | ❌ | ❌ | ❌ | ❌ |

Nenhum papel novo (Princípio V). O Dono arquivar Ministério com Líder confirmado é decisão
registrada do usuário — o aviso de FR-005 é a única salvaguarda.

---

## 5. Onde o Grupo arquivado some, e onde não pode sumir

Está em research D-006, e vale repetir a linha que mais importa: **a exibição do Líder/Diretor
precisa filtrar Grupo arquivado**. `liderancas` não é tocada de propósito, então nada no banco
impede que um Ministério arquivado continue mostrando publicamente quem é o responsável.
Falha silenciosa, invisível a teste de unidade, e o dado exposto é justamente o que FR-016 diz
que sai do ar.

---

## 6. O que explicitamente NÃO muda

- Nenhuma tabela nova, nenhuma tabela removida.
- `confirmacoes_acao`, `votos`, `participacoes_grupo`, `liderancas`: estrutura intacta.
- `fechar_rodada_se_devido`, `confirmacoes_acao_promover_fila`,
  `confirmacoes_acao_decidir_status`: **inalteradas**. Os testes de integração que cobrem
  apuração, empate e fila devem passar **sem edição** — se algum precisar mudar, esta feature
  vazou do escopo.
- `acao_encerrada` e as políticas da feature 011: intactas.
- **Apagar Grupo de verdade continua não existindo.** O FR-021 da feature 013 — "quando um
  Grupo é apagado, sua capa deixa de existir" — segue descrevendo um evento que não acontece.
- **Grupo arquivado mantém a Foto de capa** (feature 013), porque o Grupo continua existindo.
