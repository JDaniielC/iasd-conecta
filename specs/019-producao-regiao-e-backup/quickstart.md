# Quickstart: Produção — confirmar região e resolver backup (019)

Esta feature não tem tela para abrir nem teste para rodar. O que ela tem é: **duas coisas que só
um humano com login consegue obter**, e **um conjunto de `grep` que prova que nenhuma afirmação
não verificada sobrou no repositório**.

## Pré-requisitos

Para as verificações por `grep` (agente ou qualquer pessoa): só o repositório.

Para as duas verificações de fato: acesso ao painel do Supabase Cloud do projeto de produção,
**ou** Supabase CLI autenticada (`supabase login`). Nada disso entra no CI — ver `research.md`
D-005.

⚠️ Nunca cole `SUPABASE_SERVICE_ROLE_KEY` (existe em `.env.prod`, propositalmente ausente do CI —
ver o aviso 🔴 em `.github/workflows/deploy-web.yml:9-14`) nem senha de banco em nenhum documento
desta feature. O `project-ref` **pode** ser escrito: ele já vai público dentro do build web
(`deploy-web.yml:34-42`).

---

## Parte 1 — Obter a região (humano, uma vez)

Dois caminhos, escolha um:

```bash
# Caminho CLI
supabase login              # guarda um personal access token localmente
supabase projects list      # copie a linha do projeto de produção, inteira
```

```text
# Caminho painel
Supabase Dashboard → o projeto de produção → Project Settings → General
Transcreva a string de região EXATAMENTE como aparece na tela.
```

**Critério de pronto**: o texto da saída está colado em `docs/INFRA-PRODUCAO.md`, acompanhado de
**data** e de **quem verificou**. Print de tela não conta — não se versiona nem se pesquisa por
`grep`.

No mesmo acesso, anote **em que plano o projeto está** (Free / Pro / Team). É o insumo que
decide se backup automático sequer existe (`research.md` D-002).

### O portão

| Resultado | O que acontece |
|---|---|
| Região **é** `sa-east-1` / South America (São Paulo) | Ramo A do `tasks.md`. A Política não muda por causa da região |
| Região **não** é brasileira | Ramo B. **Primeiro** corrigir `privacy_policy_page.dart:145-150` para declarar a transferência internacional. Só depois qualquer outra coisa. Migração é feature nova |

---

## Parte 2 — O drill de restauração (humano, uma vez, só se houver backup)

FR-008 e SC-004 não pedem um procedimento escrito. Pedem um procedimento **executado**. Backup
não testado é hipótese.

Roteiro mínimo:

1. Escolher a cópia mais recente disponível pelo mecanismo decidido.
2. Restaurar **para um destino que não seja produção** — projeto/instância descartável, ou o
   Supabase local (`supabase start`). Nunca restaurar por cima de produção para "testar".
3. Conferir três coisas no destino restaurado, e anotar os **números**:
   - contagem de linhas de `perfis`, `grupos`, `acoes`;
   - existe pelo menos um Perfil anonimizado (`anonimizado_em` não nulo) — mostra que a cópia
     preserva o estado de exclusão, e não o desfaz;
   - o app sobe contra o destino restaurado e a listagem de Grupos carrega.
4. Cronometrar do início ao fim. Esse número é o **RTO real** — quanto tempo a comunidade fica
   sem o app num incidente.

**Critério de pronto**: `docs/INFRA-PRODUCAO.md` tem data do drill, quem executou, os números do
passo 3 e o tempo do passo 4. Sem números, o drill não aconteceu.

---

## Parte 3 — As verificações por `grep` (repositório, repetíveis)

Rodar da raiz do repositório. Cada uma corresponde a um Success Criterion.

### SC-002 — 0 afirmações de que produção não existe

Duas redações, não uma. O `grep` literal de SC-002 pega só a primeira:

```bash
grep -rn "ainda não provisionada" --include="*.dart" --include="*.md" . | grep -v "^./specs/019"
grep -rn "ainda não foi criado\|não foi provisionad" --include="*.dart" --include="*.md" . | grep -v "^./specs/019"
```

**Esperado ao fim**: 0 linhas em ambas. Estado inicial (2026-08-09): `legal_metadata.dart:24` na
primeira, `REVISAO-JURIDICA.md:200-201` na segunda.

### SC-001 — a região está registrada com evidência e data

```bash
grep -n "Verificado em\|Região verificada" docs/INFRA-PRODUCAO.md
```

**Esperado**: pelo menos uma linha, com data no formato `AAAA-MM-DD` e nome de quem verificou.
Se o arquivo só disser a região sem dizer quando e por quem foi lida, é a mesma suposição de
antes com endereço novo.

### SC-003 — "quanto se perde no pior caso" tem resposta em unidade de tempo

```bash
grep -n "RPO\|pior caso" docs/INFRA-PRODUCAO.md
```

**Esperado**: uma resposta em unidade de tempo (`24 horas`, `7 dias`, `2 minutos`) — ou, se a
decisão for não ter backup, a frase explícita de que se perde **tudo desde o início**, com o
risco aceito assinado e datado.

### SC-005 — 0 contradições entre a Política e o que foi decidido

```bash
grep -n "não sai do Brasil\|transferência" lib/features/legal/presentation/privacy_policy_page.dart
grep -n "Por quanto tempo guardamos" -A 12 lib/features/legal/presentation/privacy_policy_page.dart
grep -n "hostingRegion" lib/features/legal/legal_metadata.dart
```

Conferir à mão, contra `docs/INFRA-PRODUCAO.md`:

- [ ] A região que a Política mostra (`LegalMetadata.hostingRegion`) é a região verificada.
- [ ] Se a região não é brasileira, a Política declara a transferência internacional e **não**
      diz "o dado não sai do Brasil".
- [ ] Se existe backup, a seção "Por quanto tempo guardamos" diz que a cópia existe e por quanto
      tempo.
- [ ] Se existe backup, a promessa de exclusão (linhas 181-198) foi qualificada com o prazo da
      cópia — some do app na hora, some da cópia em até N dias.
- [ ] Se **não** existe backup, nenhuma dessas frases mudou, e isso está certo.
- [ ] O texto da Política mudou ⇒ `LegalMetadata.version` e `effectiveDate` subiram.

### SC-006 — 0 itens de região e backup em aberto nos achados

Estes arquivos ficam **fora do repositório**:

```bash
grep -n "A-3\|em aberto\|volta à mesa" /Users/jdsc2/projects/.achados/20260724-direito-digital-iasd.md
grep -n "D-3\|em aberto\|volta à mesa" /Users/jdsc2/projects/.achados/20260724-devops-iasd.md
```

**Esperado**: A-3 e D-3 marcados como fechados, cada um apontando para
`iasd/docs/INFRA-PRODUCAO.md` e para a data da verificação. Estado inicial: A-3 aberto
(`20260724-direito-digital-iasd.md:114`), D-3 "volta à mesa"
(`20260724-devops-iasd.md:115-120` e `148-151`).

### FR-005 — os três ponteiros existem

```bash
grep -rn "INFRA-PRODUCAO" README.md .env.example lib/features/legal/legal_metadata.dart
```

**Esperado**: 3 linhas, uma em cada arquivo.

---

## Parte 4 — Gates de sempre

Dois arquivos Dart são tocados (comentário e strings). Os gates de
`.github/workflows/ci.yml` continuam valendo:

```bash
flutter analyze
flutter test test/unit test/widget
flutter build web
```

**Esperado**: analyze limpo; a mesma quantidade de testes de antes, todos passando (nenhum teste
novo, nenhum alterado — não existe teste que leia o texto da Política hoje, conferido); build
web sucedendo.

Se algum teste precisar de asserção nova, a feature saiu do escopo — ela é documento e texto,
não comportamento.

---

## O que este quickstart **não** consegue provar

- Que a região está **certa**. Ele prova que ela está **verificada e declarada**. Se estiver
  errada, o conserto é uma migração, que é outra feature (`research.md` D-006).
- Que o backup fica no Brasil (FR-010). A documentação pública do fornecedor não diz onde as
  cópias moram; só a resposta escrita do suporte fecha isso, e ela é anexo de
  `docs/INFRA-PRODUCAO.md`, não resultado de comando.
- Que o dado de quem excluiu a conta sumiu de toda cópia. Prova-se o **prazo** (a cópia expira em
  N dias), não a ausência. É por isso que o prazo precisa existir e ser declarado.
