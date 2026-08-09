# Research: Foto de capa de Grupo e de Ação

**Feature**: 013-foto-de-capa | **Date**: 2026-08-09

---

## D-001 — O arquivo vive no armazenamento de objetos, e o banco guarda só a referência

**Decisão**: o binário vai para um bucket do Supabase Storage. O banco guarda uma linha com o
caminho do arquivo, a quem pertence (Grupo **ou** Ação), quem enviou e quando.

**Rationale**: a alternativa — guardar a imagem codificada em texto na própria tabela — foi
avaliada e é pior em tudo que importa aqui: infla cada linha da listagem em centenas de KB,
impede carga preguiçosa (a lista de Grupos passaria a baixar todas as imagens de uma vez), e
não dá endereço estável para o navegador cachear. O único ponto a favor seria "um subsistema a
menos", e ele não paga o resto.

**Caminho do arquivo**: cada envio gera um caminho **novo e único**, nunca reaproveitado.
Trocar a capa não sobrescreve o arquivo anterior — sobe um novo e apaga o antigo. Isso importa
por causa de D-004: caminho reaproveitado com cache de borda serve a imagem velha; caminho
novo nunca colide.

---

## D-002 — Seletor de imagem: dependência nova, escolhida pelo suporte a web

**Decisão**: adicionar uma dependência de seleção de imagem/arquivo, com a exigência dura de
**funcionar em Flutter web**, que é o alvo em produção hoje (`deploy-web.yml`).

**Rationale**: o Flutter não oferece seletor nativo. A escolha exata (entre os pacotes usuais
de seleção de imagem e de arquivo) fica para a implementação, mas o critério de aceite está
fixado aqui, porque é onde este tipo de escolha costuma dar errado:

1. Funciona em web, Android e iOS.
2. Entrega os **bytes** do arquivo de forma uniforme — não só um caminho de arquivo, que não
   existe em web.
3. Não puxa código de plataforma que quebre `flutter build web` (gate de CI).

**A armadilha de plataforma**: em mobile o seletor devolve um caminho; em web, bytes. Código
escrito só contra o caminho compila e quebra em produção — que é justamente onde o app está
hoje. A camada de envio (`lib/core/image_upload.dart`) trabalha **sempre com bytes**, e a
diferença de plataforma morre no seletor.

**Validação antes de enviar** (FR-009): tipo de arquivo, tamanho e legibilidade são conferidos
no cliente **antes** de qualquer escrita. Recusar depois de publicar seria publicar.

**Limites**: formatos de imagem comuns de celular e um teto de tamanho na casa de poucos MB. O
número exato é decisão de implementação; o que a spec exige é que ele seja **informado ao
Usuário antes do envio**, não descoberto no erro.

---

## D-003 — Quem apaga o arquivo: o mesmo caminho que apaga a linha, sempre

**Decisão**: **nenhuma exclusão de imagem depende do cliente lembrar de apagar o arquivo.**
Toda exclusão passa por um único ponto no banco, acionado por gatilho, para os quatro caminhos:

| Caminho | Como a linha some hoje | Quem apaga o arquivo |
|---|---|---|
| Remoção manual (dono ou Administrador) | delete explícito | o mesmo gatilho |
| Ação cancelada | **a linha da Ação NÃO some** (`cancelada_em`) | ato explícito no cancelamento |
| Candidata perdedora descartada | `delete from public.acoes` em `fechar_rodada_se_devido` | cascade dispara o gatilho |
| Exclusão de conta | `excluir_minha_conta` (a Ação **sobrevive**) | ato explícito dentro da função |

**Rationale**: este é o núcleo técnico da feature. O risco não é teórico — a rodada de votação
apaga candidatas perdedoras com um `delete` direto (`20260724084300_rodada_votacao.sql:178`),
sem passar por tela nenhuma. Se a exclusão do arquivo morar no cliente, **esse caminho nunca
vai apagar arquivo**, e ninguém vai perceber, porque órfão não aparece em lugar algum. O
mesmo vale para o cancelamento de Ação e para a exclusão de conta, que são operações de banco.

Colocar a exclusão do arquivo atrás de um gatilho na tabela de referência faz com que **todo**
caminho que apaga a linha apague o arquivo, inclusive os que ainda não existem — como o
"apagar Grupo" que hoje não existe (achado 1 do plano).

**A dificuldade real**: apagar linha em Postgres não apaga arquivo em armazenamento de
objetos. O gatilho precisa de um mecanismo para alcançar o armazenamento. Ver D-004.

**Conferência obrigatória**: `test/integration/foto_capa_orfao_test.dart` conta os arquivos do
bucket antes e depois de cada um dos quatro caminhos. É o único jeito de provar SC-005 — órfão
não tem sintoma.

---

## D-004 — ⚠️ Verificar em fonte primária antes de implementar

Duas afirmações sobre o comportamento do fornecedor sustentam D-003 e FR-012, e **nenhuma das
duas deve ser assumida de memória**. Este repositório tem regra explícita sobre isso, e a
Política de Privacidade vai descrever ao usuário o que estas respostas determinarem.

**Pergunta 1 — apagar o registro do objeto apaga o arquivo?**
Se um gatilho de banco apaga a linha do objeto no schema de armazenamento, o binário é
efetivamente removido, ou fica no armazenamento subjacente como órfão invisível?

**Pergunta 2 — por quanto tempo uma imagem removida continua servível?**
Objeto público servido por CDN: depois de removida a origem, o conteúdo cacheado continua
disponível por qual janela? Existe invalidação, e ela é síncrona?

**Por que isto não é detalhe de implementação**: FR-012 e SC-004 prometem indisponibilidade em
**100%** das tentativas, por **qualquer** endereço. Se a resposta à pergunta 2 for "o cache
serve por até N minutos", então:

- a promessa correta é "removida da origem imediatamente; pode permanecer em cache por até N";
- **a Política de Privacidade tem de dizer isso**, e não a versão desejada;
- e é preciso decidir se N é aceitável para o caso que motivou a feature — foto de menor.

**Plano alternativo, se as respostas forem desfavoráveis**: servir a imagem por endereço
assinado de vida curta em vez de objeto público. Remover passa a ser instantâneo por
construção (o endereço deixa de ser emitido), ao custo de a imagem não ser mais cacheável por
endereço estável e de o Visitante precisar de uma emissão de endereço para ver a lista.
É mais caro e mais lento; **só se justifica se a janela de cache for inaceitável**.

**Ordem**: esta verificação vem **antes** de escrever a migration e **antes** de redigir o
texto da Política de Privacidade. É a primeira coisa técnica da feature.

---

## D-005 — O aviso é uma parada obrigatória, não um texto na tela

**Decisão**: o aviso de FR-004 é apresentado como um passo que o Usuário precisa reconhecer
antes de o seletor de arquivo abrir. Aparece **toda vez**, inclusive na troca (FR-005).

**Rationale**: aviso escrito ao lado do botão é lido por ninguém. A pergunta que a feature
precisa responder é "esta imagem tem gente nela?", e ela só funciona antes da escolha — depois
de escolher a foto da filha, o Usuário já decidiu.

**Texto** (FR-006, português direto, o motivo em uma frase):

> **Use uma imagem ilustrativa.** Logo do ministério, arte do evento, foto do local. **Não
> envie foto de pessoas, e nunca de crianças ou adolescentes** — qualquer pessoa na internet
> consegue ver esta imagem, mesmo sem cadastro no app.

O motivo dado é o que é verdade e o que convence: a imagem é pública para qualquer um. Não é
apelo jurídico.

**Repetir a cada envio não é atrito desnecessário**: o custo é um toque; o benefício é a única
barreira preventiva que a feature tem.

**Alternativa descartada** — *marcar "não mostrar de novo"*: transformaria a barreira em nada
depois do primeiro uso, e quem envia muitas imagens é exatamente quem mais precisa ver.

---

## D-006 — Denúncia aceita Visitante, e a identidade não vai para quem enviou

**Decisão**: a denúncia pode ser registrada **sem Perfil** (FR-015). Guarda o motivo em texto
curto, a imagem, e o autor **quando houver** — Visitante sem Perfil gera denúncia sem autor
identificável, e isso é aceito.

**Rationale**: o caso que motivou a feature é uma mãe sem cadastro vendo a foto da filha.
Exigir cadastro dela para pedir a remoção seria exigir que ela entregue os próprios dados para
retirar os da filha. É o oposto do que o Princípio II defende.

**Consequência aceita**: denúncia sem autor abre espaço para volume abusivo. A spec decidiu
não criar punição nem bloqueio automático — o Administrador do distrito julga. Para um distrito
de 15+ igrejas, o volume não justifica maquinaria antiabuso.

**Quem enviou nunca vê quem denunciou** (FR-020). O Administrador vê o que houver, para
conseguir julgar denúncia em massa.

**Denúncia duplicada** (FR-018): a lista de pendências é **por imagem**, não por denúncia.
Várias denúncias sobre a mesma imagem aparecem como um item, com a contagem. Resolver o item
resolve todas.

**Encerramento automático** (FR-019): se a imagem some por qualquer caminho — remoção pelo
dono, cancelamento da Ação, descarte da candidata, exclusão de conta — as denúncias pendentes
sobre ela são encerradas. Sem isso o Administrador acumula pendências sobre imagens que não
existem mais, e a lista perde credibilidade em poucas semanas.
