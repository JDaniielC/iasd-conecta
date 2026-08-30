## Why

A capability `mensagem-fixada` diz, em letra: *"O sistema DEVE permitir que o
autor desfixe mensagem que ele escreveu, mesmo sem ter autoridade no espaço."*
**Ela não é cumprida.** Medido em 2026-08-17 (`PENDENCIAS.md` 2.28), contra o
Postgres local, como `authenticated`:

| Sessão | `pode_moderar_mensagem` | `update ... set fixada_em = null` |
|---|---|---|
| autor participante do Grupo | `t` | **1 linha** |
| autor que saiu do Grupo | `t` | **0 linhas** |
| autor que desistiu da Ação | `t` | **0 linhas** |
| autor com idade corrigida para 17 | `t` | **0 linhas** |

A causa não é a policy de `update`, que acerta: no Postgres um `UPDATE` só
alcança linha que a policy de `SELECT` deixa a sessão ler, e
`pode_ver_chat_grupo`/`pode_ver_chat_acao` passaram a devolver `false`. Some-se
que o único caminho de desfixe em todo o `lib/` é
`ChatRepository.unpinMessage`, chamado só de dentro de `chat_page.dart`, e
`ChatGatePage` fecha a tela antes.

**Por que agora, e por que não é detalhe.** Fixar tira a mensagem do prazo de
30 dias, e o braço do autor é o contrapeso que sustentou a subida do texto
legal para 1.7 (`REVISAO-JURIDICA.md` § 4-E). Sem ele, o prazo do que uma
pessoa escreveu passa a depender de outra indefinidamente, e o único caminho
que resta — medido — é **excluir a conta inteira**. Exigir a exclusão da conta
para eliminar um dado é o oposto do art. 18 da LGPD.

A Política 1.7 hoje **declara** o limite em vez de prometer o que o app não
faz. Isso é honesto e é fraco: a promessa que a titular precisa é o caminho,
não o aviso de que ele não existe.

## What Changes

- Uma função no banco que alcança a linha que a policy de leitura esconde,
  restrita ao **autor** da mensagem e **só** às colunas de fixação.
- Um lugar, fora da conversa, de onde a pessoa vê as próprias mensagens
  fixadas e desfixa cada uma — inclusive nos chats que ela já não alcança.
- A Política de Privacidade deixa de mandar escrever para o e-mail de contato
  e passa a apontar o caminho dentro do app.

**NÃO muda quem lê o quê.** A pessoa passa a alcançar o próprio texto para
tirá-lo do topo; ela não passa a ler conversa de que não participa.

## Capabilities

### New Capabilities
Nenhuma. O comportamento já está declarado em `mensagem-fixada`; o que falta é
cumpri-lo, e a spec precisa dizer que ele vale **de fora do espaço**, que é
onde ele falha.

### Modified Capabilities
- `mensagem-fixada`: a requirement "O autor sempre desfixa a própria mensagem"
  ganha os cenários que hoje falham — sair do Grupo, desistir da Ação, perder o
  corte de idade — e a exigência de que o caminho exista fora da conversa.

## Impact

**Depende de** `mensagem-fixada` arquivada. Não conflita com
`denuncia-como-registro`, que toca `denuncias_mensagem`.

**Banco** — uma função `security definer` nova, com `grant execute` a
`authenticated`. É superfície nova de escrita na REST, e por isso o predicado
dela precisa ser estreito e provado por teste com sessão de verdade.

**Código** — `lib/features/chat/` (repositório) e uma entrada em `Meu Perfil`.

**Legal** — Política de Privacidade: o parágrafo que hoje diz "escreva para a
gente" passa a apontar o caminho no app. Muda o texto exibido, então muda a
versão (`LegalMetadata` e `versoes_texto_legal`), pelo mesmo critério da 1.7.

**Nenhum dado pessoal novo.**

**Ledgers** — `PENDENCIAS.md` 2.28 fecha; 2.25 **não** fecha e o motivo fica
escrito. `REVISAO-JURIDICA.md` § 4-E.

**FORA DE ESCOPO, declarado:** o caminho da pessoa **citada por outro**
(`PENDENCIAS.md` 2.25). Ela não é autora, e dar a ela um botão de desfixe seria
dar a um terceiro poder sobre o texto de quem escreveu — decisão de produto que
ninguém tomou. Continua saindo por denúncia. Esta change não a fecha e não a
piora.
