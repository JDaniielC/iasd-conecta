# Data Model: Foto de capa de Grupo e de Ação

**Feature**: 013-foto-de-capa | **Date**: 2026-08-09

Duas entidades novas. Nenhuma coluna nova em `grupos` nem em `acoes` — a referência mora do
lado da imagem, não do lado do dono. Um bucket de armazenamento novo.

---

## 1. Foto de capa (`fotos_capa`)

Imagem única e opcional de um Grupo **ou** de uma Ação.

| Campo | Tipo | Regra |
|---|---|---|
| `id` | uuid | chave |
| `grupo_id` | uuid, nulo | referência a `grupos`, **cascade** |
| `acao_id` | uuid, nulo | referência a `acoes`, **cascade** |
| `caminho` | texto | caminho único do arquivo no bucket. **Nunca reaproveitado** (research D-001) |
| `enviada_por` | uuid | referência a `perfis` — quem enviou, para prestação de contas |
| `created_at` | timestamptz | quando |

**Invariantes**:

- **Exatamente um dono**: ou `grupo_id` ou `acao_id`, nunca os dois, nunca nenhum. Garantido
  por restrição, não por disciplina de código.
- **No máximo uma por dono** (FR-001): índice único sobre `grupo_id` e sobre `acao_id`. Trocar
  a capa é apagar a linha e inserir outra, não atualizar o caminho — assim o gatilho de
  exclusão dispara e o arquivo antigo some.
- **`caminho` único**: dois registros nunca apontam para o mesmo arquivo, então apagar um
  registro nunca deixa outro apontando para o vazio.

**Ciclo de vida**:

| Evento | O que acontece com a linha | O que acontece com o arquivo |
|---|---|---|
| Dono ou Administrador remove | delete explícito | gatilho apaga |
| Troca de capa | delete + insert | gatilho apaga o antigo |
| Grupo apagado | cascade (**hoje não existe apagar Grupo** — plano, achado 1) | gatilho apaga |
| Ação cancelada | **a Ação NÃO é apagada** (`cancelada_em`) — a linha da capa é apagada explicitamente | gatilho apaga |
| Candidata perdedora descartada | cascade, via `delete from public.acoes` em `fechar_rodada_se_devido` | gatilho apaga |
| Exclusão de conta | delete explícito dentro de `excluir_minha_conta`, só para capas de **Ação avulsa** de quem sai (FR-024) | gatilho apaga |
| **Grupo herdado** na exclusão de conta | **nada** — a capa fica (FR-025) | fica |
| Ação encerrada por tempo | **nada** — histórico (FR-023) | fica |

> A coluna que mais engana: **`enviada_por` não decide nada sobre permissão.** Quem controla a
> capa é quem administra o Grupo/Ação **hoje** (FR-003), não quem enviou. `enviada_por` existe
> para prestação de contas e para a regra de exclusão de conta.

---

## 2. Denúncia de imagem (`denuncias_imagem`)

Registro de que alguém considerou uma Foto de capa imprópria.

| Campo | Tipo | Regra |
|---|---|---|
| `id` | uuid | chave |
| `foto_id` | uuid | referência a `fotos_capa`, **cascade** — imagem removida encerra as denúncias (FR-019) |
| `motivo` | texto | texto curto, obrigatório, não vazio |
| `denunciante_id` | uuid, **nulo** | nulo quando Visitante sem Perfil denuncia (FR-015, research D-006) |
| `estado` | texto | `pendente`, `imagem_removida`, `improcedente` |
| `created_at` | timestamptz | quando |
| `resolvida_em` | timestamptz, nulo | quando saiu de pendente |

**Transições de estado**:

```
pendente ──(Administrador remove a imagem)──→ imagem_removida
pendente ──(Administrador julga improcedente)──→ improcedente
pendente ──(imagem some por qualquer outro caminho)──→ desaparece por cascade
```

Só o Administrador do distrito muda estado. Não há volta de resolvida para pendente.

**Agrupamento na tela** (FR-018): a lista de pendências é **por imagem**, não por denúncia.
Cinco denúncias sobre a mesma capa são um item com contagem 5. Resolver o item resolve as
cinco.

**Privacidade** (FR-020): `denunciante_id` **nunca** é exposto a quem enviou a imagem nem a
qualquer Usuário comum. Só o Administrador do distrito o vê, e só para julgar abuso de volume.

---

## 3. Bucket de armazenamento

| Aspecto | Decisão |
|---|---|
| Conteúdo | só imagem de capa. Nada mais entra |
| Leitura | pública (FR-008) — Visitante vê a capa, como já vê o Grupo e a Ação |
| Escrita | só quem administra o Grupo/Ação, mais o Administrador do distrito (FR-003) |
| Exclusão | pelo gatilho da tabela, não pelo cliente (research D-003) |
| Caminho | único por envio, nunca reaproveitado (research D-001, D-004) |

**Pendente de verificação em fonte primária** (research D-004): se apagar o registro do objeto
remove o binário de fato, e por quanto tempo um objeto público removido continua servível por
cache de borda. **A redação de FR-012 na Política de Privacidade depende dessas respostas** —
o documento descreve o que o sistema garante, não o que se pretendia garantir.

---

## 4. Quem pode o quê

| Ação | Visitante | Usuário | Dono do Grupo | Criador da Ação | Administrador do distrito |
|---|---|---|---|---|---|
| Ver a capa | ✅ | ✅ | ✅ | ✅ | ✅ |
| Enviar/trocar capa do Grupo | ❌ | ❌ | ✅ | ❌ | ✅ |
| Enviar/trocar capa da Ação | ❌ | ❌ | ❌ | ✅ | ✅ |
| Remover qualquer capa | ❌ | ❌ | só a sua | só a sua | ✅ (FR-011) |
| Denunciar imagem | ✅ | ✅ | ✅ | ✅ | ✅ |
| Ver denúncias pendentes | ❌ | ❌ | ❌ | ❌ | ✅ |
| Resolver denúncia | ❌ | ❌ | ❌ | ❌ | ✅ |

Nenhum papel novo (Princípio V). A linha "Denunciar imagem" aberta a Visitante é deliberada:
quem precisa pedir a retirada da foto de um filho não deve ter que se cadastrar para isso.

---

## 5. O que explicitamente NÃO muda

- `grupos` e `acoes`: nenhuma coluna nova, nenhum gatilho alterado.
- `confirmacoes_acao`, `votos`, `rodadas_votacao`, `participacoes_grupo`: intocados.
- Fila de espera, desempate por sorteio, revogação de voto e de Participar, composição de
  Dupla Missionária: inalterados.
- `perfis`: nenhuma coluna nova. A imagem **não** é foto de perfil — não existe avatar de
  Usuário nesta feature, e essa distinção precisa continuar clara em `MAPA-DE-DADOS.md`.
- `excluir_minha_conta` ganha **uma** instrução a mais (apagar capas de Ação avulsa de quem
  sai). Toda a lógica de anonimização e herança da feature 009 continua idêntica.
