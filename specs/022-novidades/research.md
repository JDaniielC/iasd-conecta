# Phase 0 — Research: tela de Novidades

**Feature**: 022-novidades | **Data**: 2026-08-10

Três das seis decisões abaixo foram resolvidas medindo o repositório, não deduzindo — e uma
delas mudou o desenho, porque a peça que eu ia adicionar já estava lá.

---

## D-001 — O "já vi" fica no aparelho, com `shared_preferences`, que já está no app

**Decision**: guardar o marcador de leitura em `shared_preferences`, promovendo-o de
dependência **transitiva** para **direta** em `pubspec.yaml`.

**Rationale**: o app não declara nenhum pacote de armazenamento local — `pubspec.yaml` tem
`supabase_flutter`, `flutter_riverpod`, `go_router`, `flutter_dotenv`, `intl` e
`cupertino_icons`, e nada mais. Mas `pubspec.lock` mostra:

```
  shared_preferences:
    dependency: transitive
```

`supabase_flutter` já o usa para persistir a sessão, então o código **já está no bundle que
todo mundo baixa**. Adicionar a linha em `pubspec.yaml` não aumenta o tamanho do app em um
byte; só torna explícito algo que já é verdade.

E declarar explicitamente **não é formalidade**: hoje o pacote está lá porque outra
dependência o arrasta. No dia em que `supabase_flutter` trocar de mecanismo de persistência,
o import desta feature quebra sem ninguém ter mexido nela. Dependência que a gente usa, a
gente declara.

Na web, `shared_preferences` grava em `localStorage` — mesmo aparelho, mesmo navegador,
nada sai para o servidor. É exatamente o que FR-012 e FR-013 pedem.

**Alternatives considered**:

- **Gravar no banco, numa coluna de `perfis`** — rejeitada, e é a rejeição que mais importa
  desta feature. Seria o caminho óbvio: sobrevive à troca de aparelho e "resolve" o edge case.
  Mas criaria um dado de comportamento novo — quando esta pessoa abriu o app, o que ela leu —
  que nenhuma entrada do glossário autoriza, e num app que acabou de passar três features
  (018, 021 e 015) fechando exposição. FR-014 é o teste dessa decisão: se a Política precisar
  de frase nova, o desenho errou.
- **Cookie ou `window.localStorage` direto** — rejeitada: só funcionaria na web, e o app é
  também móvel.
- **Não ter aviso nenhum, só a tela** — rejeitada porque US2 existe: lista que ninguém abre
  não comunica. Mas vale registrar que essa alternativa **não** é absurda, e é o plano B se o
  aviso se mostrar irritante.

---

## D-002 — O marcador é uma **data**, não uma contagem nem uma lista de identificadores

**Decision**: guardar a data da novidade mais recente que a pessoa já viu, como texto ISO.
Há novidade nova quando a data do item mais recente da lista é posterior à guardada.

**Rationale**: as três formas óbvias falham de jeitos diferentes, e a data é a única que
sobrevive ao que de fato acontece com uma lista escrita à mão:

| Forma | Como quebra |
|---|---|
| **Contagem** ("já vi 7") | Inserir uma novidade antiga no meio — porque alguém esqueceu de registrar na época — faz a contagem apontar para o item errado, e o aviso some sozinho |
| **Lista de identificadores vistos** | Cresce para sempre no aparelho e exige identificador estável em conteúdo que é escrito à mão; renomear um item ressuscita o aviso |
| **Data do item mais recente visto** | Inserir item antigo não dispara aviso (correto: a pessoa não perdeu nada novo); reordenar não afeta; nada cresce |

**Alternatives considered**: guardar "data da última vez que abri a tela" em vez da data do
item — quase equivalente, mas erra num caso real: se a pessoa abre a tela no mesmo minuto em
que uma novidade é publicada, o relógio dela pode ficar à frente do item e esconder um item que
ela não viu. Comparar item-com-item não tem esse problema.

---

## D-003 — Primeira instalação nasce "tudo visto", gravado na hora

**Decision**: ao abrir o app sem marcador guardado, gravar imediatamente a data da novidade
mais recente e **não** mostrar aviso.

**Rationale**: FR-011. Para quem chega agora, o app inteiro é novo — apontar uma parte dele
como "novidade" não quer dizer nada, e o aviso vira ruído no primeiro contato.

O detalhe que importa: a gravação precisa acontecer **sem a pessoa abrir a tela**. Se o
marcador só fosse gravado ao abrir Novidades, quem instalasse e nunca abrisse carregaria o
aviso para sempre — e o aviso estaria mentindo, porque não há nada novo *para ela*.

**Alternatives considered**: mostrar o aviso na primeira vez, tratando o app como novidade
integral. Rejeitada: contradiz FR-011, e a primeira coisa que alguém vê ao instalar não deve
ser um alerta.

---

## D-004 — O marco de 6/10/2026 é filtro de **exibição**, não regra de escrita

**Decision**: as novidades são escritas com a data real em que a mudança chegou às pessoas, e
a lista exibida descarta o que for anterior ao marco. O marco é uma constante única.

**Rationale**: escrever só a partir do marco parece equivalente e não é — apaga a
possibilidade de registrar, no futuro, uma mudança anterior ao lançamento que alguém precise
consultar. Filtrar na exibição mantém o registro honesto e deixa o marco ser uma decisão
reversível: mudar de ideia sobre a data é trocar uma linha, e a lista inteira reaparece.

Também é o que torna FR-006 testável de verdade: dá para escrever um item datado antes do
marco e provar que ele **não** aparece.

**Alternatives considered**: não ter marco e listar tudo desde 23/07/2026 — é o que o dono do
app pode querer, e a spec registra isso como a linha que `/speckit-clarify` muda. Com o marco
como filtro, essa mudança fica trivial.

---

## D-005 — Conteúdo compilado, no mesmo padrão dos textos legais

**Decision**: a lista vive numa constante Dart, ao lado do que já existe em
`lib/features/legal/`.

**Rationale**: o app já tem precedente exato — Política de Privacidade e Termos de Uso são
texto compilado, com `LegalMetadata.version` marcando a versão. Publicar novidade é, por
definição, publicar versão; o conteúdo não muda entre um deploy e outro.

Guardar no banco exigiria tabela, política de escrita, tela de administração e moderação —
quatro peças que ninguém pediu, contra o Princípio V.

**Alternatives considered**:

- **Tabela `novidades` com tela de administração** — rejeitada por Princípio V. Se um dia for
  preciso publicar novidade **sem** lançar versão, aí a decisão muda, e aí a tabela se paga.
- **Gerar do histórico do git** — rejeitada, e a spec já explica: transformaria "fecha a
  leitura pública de votos" em item de tela. Verdadeiro, inútil e assustador.

---

## D-006 — O critério do que vira novidade fica escrito, ou a lista degenera

**Decision**: um arquivo curto no repositório com a regra de admissão, e o teste de idioma
como rede.

**Rationale**: FR-017 existe porque este é o modo de falha real desta feature. Quem escreve a
novidade é quem acabou de fazer a mudança, com o commit fresco na cabeça — e "corrigido bug na
RLS de votos" sai naturalmente. Seis meses assim e a tela é um changelog técnico que ninguém
lê.

A regra proposta, curta o bastante para ser seguida:

> Vira novidade o que **a pessoa percebe**: algo que ela passou a poder fazer, algo que parou
> de funcionar como antes, ou algo sobre os dados dela que mudou. Não vira novidade o que só
> quem constrói percebe.
>
> Escreva na segunda pessoa e no que muda **para ela**. Se a frase não faz sentido lida em voz
> alta para alguém do distrito, ela não está pronta.

**Alternatives considered**: confiar na revisão de código. Rejeitada pelo mesmo motivo de
sempre neste repositório — `using (true)` sobreviveu meses de revisão.

---

## O que ficou sem verificação

- **Se o aviso incomoda.** Não há como saber antes de gente usar. O plano B está registrado em
  D-001: tirar o aviso e deixar só a tela.
- **Comportamento em navegador com armazenamento bloqueado.** `shared_preferences` na web
  depende de `localStorage`; num navegador que o bloqueie, o marcador não persiste e o aviso
  reaparece a cada visita. Não testado — está no quickstart como verificação manual.
