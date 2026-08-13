## Why

`chat-de-grupo-e-acao` entrega moderação **humana e reativa**: a mensagem
ofensiva fica no ar até alguém denunciar e o dono do Grupo abrir o app. Naquela
change isso está registrado como risco aceito (`design.md` → Risks), com a
observação de que o caminho certo não é reusar `palavras_bloqueadas` como está.

Esta change fecha as duas portas que a moderação reativa deixa abertas:

1. **Nada barra a palavra na entrada.** `nome_valido()` existe, mas casa por
   substring (`like '%' || palavra || '%'`,
   `20260806090000_nome_valido_security_definer.sql:38-41`) sobre uma lista
   calibrada para nome de cadastro. Em texto corrido, substring produz falso
   positivo — a palavra proibida dentro de outra palavra legítima — e a lista
   de nomes não é a lista de conversa.
2. **Nada limita o ritmo.** Uma pessoa consegue encher o chat de um Grupo em
   segundos. Sem limite no banco, a única contenção é a boa vontade, e a
   remoção é uma a uma.

## What Changes

- **Lista de palavras própria da conversa**, separada da lista de nomes, com
  casamento por **palavra inteira** em vez de substring.
- Mensagem que casa é **recusada na escrita**, não escondida depois. Quem
  escreveu recebe de volta a palavra que ele mesmo digitou — a lista completa
  continua secreta.
- O mesmo filtro vale para o `motivo` de uma denúncia. Sem isso, o campo de
  denúncia vira o canal aberto que o chat deixou de ser.
- **Intervalo mínimo entre mensagens** do mesmo autor no mesmo chat, e **teto
  por janela**. Ambos verificados no banco, sob trava — no cliente é enfeite.
- A tela mostra o tempo restante quando o intervalo barra, em vez de devolver
  erro cru.

## Capabilities

### New Capabilities
- `filtro-de-palavra-em-mensagem`: que texto o sistema recusa escrever, como
  a pessoa fica sabendo, e por que a lista não é a mesma dos nomes.
- `intervalo-entre-mensagens`: quantas mensagens uma pessoa manda em quanto
  tempo, e o que ela vê quando passa do limite.

### Modified Capabilities
Nenhuma. As duas recusas novas são preocupações novas, não mudança da
requirement existente de `chat-de-grupo-e-acao` ("A mensagem tem autor
verificável e conteúdo limitado"), que continua verdadeira como está. Elas
entram como requirements próprias nas capabilities acima — e
`openspec/specs/chat-de-grupo-e-acao/spec.md` só passa a existir depois que
aquela change for arquivada, então um delta escrito agora diverge do texto que
ele diz modificar.

## Impact

**Depende de** `chat-de-grupo-e-acao` aplicada. Sem `mensagens` e
`denuncias_mensagem`, não há o que filtrar nem o que limitar.

**Banco** — tabela nova de palavras da conversa (com RLS fechada, como
`palavras_bloqueadas` ficou em `20260806090000`), função de casamento por
palavra inteira, e gatilho `before insert` em `mensagens` e em
`denuncias_mensagem`.

**Nenhum dado pessoal novo.** O intervalo se calcula do `created_at` que a
mensagem já tem. Não se grava contador, histórico de tentativa nem registro de
recusa — isso seria dado de comportamento, que o projeto já recusou uma vez
por escrito (`news_repository.dart:7-16`).

**Ledgers** — `PENDENCIAS.md` (a dívida de moderação reativa fecha
parcialmente), `REVISAO-JURIDICA.md` (recusar mensagem é decisão com efeito
sobre o titular). `MAPA-DE-DADOS.md` não muda: nenhuma coluna nova de pessoa.

**Legal** — os Termos de Uso passam a precisar dizer que existe filtro e que
existe limite de ritmo. Regra que recusa conteúdo sem estar escrita em lugar
nenhum é a pior versão disso.
