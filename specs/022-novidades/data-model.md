# Phase 1 — Data Model: Novidades

**Feature**: 022-novidades | **Data**: 2026-08-10

## Nenhuma tabela, nenhuma coluna, nenhuma migration

Esta é a afirmação central do documento, e ela é verificável: se a implementação criar um
arquivo em `supabase/migrations/`, o desenho quebrou.

Há duas coisas com forma nesta feature — uma **Novidade** e um **marcador de leitura** — e
nenhuma das duas mora no servidor.

## Novidade

Item da lista. Vive numa constante Dart compilada no app, ao lado do padrão que os textos
legais já usam.

| Campo | Tipo | Para que serve |
|---|---|---|
| `date` | data | Quando a mudança chegou às pessoas. É por ela que a lista ordena e o aviso decide |
| `text` | texto | O que mudou, do ponto de vista de quem usa |

**Dois campos, e é de propósito.** Cada campo a mais é uma decisão de produto que ninguém
pediu:

- **sem `id`** — o marcador é por data (research D-002), então identificador estável não é
  necessário. E identificador em conteúdo escrito à mão é justamente o que quebra quando
  alguém reescreve um item;
- **sem `title`** — obrigaria a resumir o resumo, e o resultado seria um título técnico com um
  texto humano embaixo;
- **sem `category`** — classificar novidade em "novo/corrigido/removido" é vocabulário de
  changelog, e FR-016 já exige que remoção seja descrita como qualquer outra coisa;
- **sem `version`** — colide com `LegalMetadata.version`, que é versão de texto legal, e
  FR-003 proíbe número de versão na tela;
- **sem autor, sem link** — ninguém pediu.

### Invariantes

1. Nenhum texto de Novidade contém nome de arquivo, tabela, função ou número de versão
   interna (FR-003). É a invariante que um teste pode checar e que impede a lista de virar
   changelog técnico.
2. A lista exibida está ordenada da data mais recente para a mais antiga (FR-001).
3. Nenhum item com data anterior ao **marco de lançamento** aparece (FR-006).

## Marco de lançamento

Uma data única, constante. **6 de outubro de 2026.**

É filtro de **exibição**, não regra de escrita (research D-004): uma Novidade pode ser escrita
com data anterior ao marco e simplesmente não aparece. Isso mantém o registro honesto e faz
"mudar de ideia sobre o marco" custar uma linha.

## Marcador de leitura

Uma data, guardada **no aparelho** — `localStorage` na web, preferências nativas no móvel.
Nunca no servidor (FR-012, FR-013).

| Estado guardado | Significado | Como o app reage |
|---|---|---|
| Ausente | Instalação nova, primeira abertura | Grava a data da Novidade mais recente **na hora** e não mostra aviso (FR-011) |
| Igual à data mais recente da lista | A pessoa está em dia | Sem aviso |
| Anterior à data mais recente | Há Novidade que ela não viu | Mostra aviso (FR-008) |

**Por que uma data e não uma contagem nem uma lista de itens vistos**: research D-002 mede as
três. Contagem quebra quando alguém insere uma Novidade antiga esquecida; lista de
identificadores cresce para sempre e exige identificador estável em texto reescrito à mão.

**O que a perda desse marcador significa**: trocar de aparelho, reinstalar ou limpar o
navegador zera o estado, e o aviso reaparece para itens já lidos. **É comportamento aceito, não
defeito** (FR-013) — o preço de não guardar no servidor, e é um preço bom.

## Ciclo de vida

Novidade não tem máquina de estados: ela é escrita, publicada junto com uma versão do app, e
fica. Não é editada, não é removida, não expira.

Se um item precisar de correção, corrige-se o texto e publica-se de novo — a data não muda,
então o aviso **não** volta para quem já tinha lido. É o comportamento certo: uma vírgula
corrigida não é novidade.
