## Why

O app organiza Grupo e Ação, mas não tem onde combinar nada. Quem confirmou
presença numa Ação não consegue perguntar "quem leva o som?" dentro do app — a
conversa acontece fora, num grupo de WhatsApp que o app não conhece, e o app
vira um cadastro que ninguém reabre entre um encontro e outro.

Esta é a segunda metade da exploração que gerou
`log-de-mudancas-em-grupo-e-acao`. As duas foram separadas porque só esta traz
texto livre — o único dado do app cujo conteúdo não dá para declarar de
antemão no `MAPA-DE-DADOS.md`, e por isso o único que precisa de moderação,
de corte por idade e de prazo de descarte.

**Território novo.** `chat`, `mensagem` e `conversa` não aparecem nenhuma vez
nos dez ledgers do projeto. Toda tabela existente guarda dado estruturado,
validado por constraint. Esta é a primeira que guarda o que uma pessoa
escreveu para outra.

## What Changes

- **Chat de Grupo**, para quem participa do Grupo. Permanente.
- **Chat de Ação**, para quem tem confirmação (confirmado ou em fila) mais o
  criador da Ação e o dono do Grupo dela. Expira 30 dias depois de
  `acoes.data_hora`.
- **Corte por idade: só maior de 18 anos.** Quem tem menos de 18 não escreve,
  não lê e não vê a aba. Visitante (login anônimo, sem Perfil) idem. O app já
  sabe a idade (`perfis.idade`, obrigatória desde
  `20260723191202_perfis_igrejas.sql:35`).
- **Tempo real.** Mensagem nova chega sem recarregar, via Supabase Realtime
  (`supabase/config.toml:88` já tem `enabled = true`).
- **Denúncia e remoção.** Qualquer participante denuncia uma mensagem, no
  formato de `denuncias_imagem`. Remove quem manda no espaço: o dono do Grupo
  (ou o criador, na Ação avulsa) e o Administrador do distrito.
- **BREAKING (comportamento, não API):** excluir a conta deixa de conservar
  tudo do titular. O texto das mensagens dele é apagado, restando o rastro de
  que existiu mensagem ali. A anonimização de Perfil, sozinha, não anonimiza
  um nome escrito dentro de um texto.

## Capabilities

### New Capabilities
- `chat-de-grupo-e-acao`: quem escreve, quem lê, o que chega em tempo real,
  quanto tempo a mensagem dura, e o que acontece com ela quando a conta do
  autor é excluída.
- `moderacao-de-mensagem`: denúncia, remoção, quem tem autoridade sobre qual
  espaço, e o que sobra visível depois de uma remoção.

### Modified Capabilities
Nenhuma. `perfil-proprio` e `privilegios-de-banco` são specs de segurança
pontuais (uma requirement cada) e não mudam de requisito. A mudança em
`excluir_conta` é comportamento **do chat** diante da exclusão, e vive na
capability nova.

## Impact

**Superfície de risco.** É a maior que o projeto já abriu de uma vez:

| Frente | Por quê |
|---|---|
| Texto livre | Conteúdo não declarável no `MAPA-DE-DADOS.md` antes de existir |
| Dado de terceiro | Gente escreve sobre gente que não consentiu com aquilo |
| Menor de idade | Mitigado pelo corte em 18; o corte precisa valer no banco, não na tela |
| Realtime | RLS no canal falha calada — assina e não recebe, ou pior, recebe demais |
| Exclusão de conta | `20260806140000` anonimiza o Perfil; não alcança texto |
| Retenção | `pg_cron` sozinho não cumpre prazo no plano gratuito (`20260810170000:9-14`) |

**Banco** — duas tabelas (`mensagens`, `denuncias_mensagem`), RLS em ambas,
função de corte por idade no padrão `SECURITY DEFINER` com `search_path` fixo
(`20260806090000`), publicação Realtime, função de expurgo com agendamento
`pg_cron` **e** segundo gatilho no app, e alteração de `excluir_conta`.

**Ledgers** — `MAPA-DE-DADOS.md` (as duas tabelas, e a declaração de que o
conteúdo é indeterminado), `REVISAO-JURIDICA.md` (corte etário, prazo de
retenção, dado de terceiro), `PENDENCIAS.md` (o que ficar aberto),
`INFRA-PRODUCAO.md` (o `pg_cron` a agendar à mão em produção).

**Legal** — Política de Privacidade e Termos de Uso (`lib/features/legal/`)
passam a descrever uma categoria de dado que hoje não existe no texto. Sem essa
atualização a política mente, e o projeto trata isso como bloqueio
(Constituição, Princípio II).

**Código** — feature nova em `lib/features/chat/`; abas em
`group_detail_page.dart` e `action_detail_page.dart`.

**Dependência de ordem** — esta change assume
`log-de-mudancas-em-grupo-e-acao` já aplicada: as duas telas ganham seção e
aba, e mexer nas mesmas duas telas em paralelo conflita. Nada mais é
compartilhado.
