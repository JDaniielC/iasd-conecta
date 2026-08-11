# Para você finalizar

**Atualizado**: 2026-08-10 | **Base**: `main`

Sobraram **11 itens**. Eram 18; fiz 13 no navegador e no banco, e o que verifiquei está no fim
para você não repetir. Os **dois novos** vieram da 013, que fechou hoje.

Nada aqui é código. Sete dependem de **pessoas**, dois de **dois minutos seus** clicando num
botão que a automação não consegue clicar, e dois da **foto de capa** — um deles exige um
celular de verdade, que eu não tenho.

> **Duas features ficaram sem nenhuma pendência sua**: a **018** (visibilidade de lideranças) e
> a **021** (visibilidade do voto). As duas fecharam hoje.

---

## 1. Dois minutos seus (itens 2 e 4)

Os dois exigem **concluir um formulário**, e o botão de enviar não responde a clique sintético
no canvas do Flutter — tentei por coordenada, por nó de acessibilidade e por teclado. **Não é
defeito do app**: digitar funciona (a idade 9 faz o passo do responsável aparecer, e 30 o faz
sumir). É limite da automação.

```bash
cd /Users/jdsc2/projects/iasd && supabase start && flutter run -d chrome
```

**Item 2 (016 T039)** — crie um Perfil, entre num Grupo, corrija seu nome em **Meu Perfil** e
volte ao Grupo.
**Passou quando**: o nome novo aparece na lista de participantes. Se aparecer o antigo, o cache
de `publicProfileProvider` não foi invalidado.

**Item 4 (017 T021)** — no cadastro, com o **DevTools na aba Network**, olhe o corpo do `insert`
em `/rest/v1/perfis`.
**Passou quando**: **nenhuma chave de versão** vai no corpo — quem grava a versão é o banco.
*Já garantido sem isso*: `toInsertMap` não tem chave de versão (código e teste de unidade), e o
teste de integração prova que uma versão mandada pelo cliente seria descartada.

---

## 2. Com gente — sete medições

São as únicas que medem o que o app **é para quem usa**. Eu sei onde os botões estão, então
cronometrar a mim mesmo mediria zero.

| # | Quem | O que fazer | Meta |
|---|---|---|---|
| 18 | **3 pessoas do distrito** | **022 T027** — mostre a tela de Novidades e peça que digam, com as palavras delas, o que mudou | As três entendem os doze itens **sem explicação** |
| 19 | 1 pessoa que nunca viu o app | **022 T028** — cronometre até achar Novidades a partir da Home | < 15 s |
| 20 | 3 pessoas | **016 T043** — cronometre corrigir o próprio nome, do abrir o app ao salvar | < 1 min. Se passar, o suspeito é o **caminho** até a tela, não o formulário |
| 21 | 1 mãe | **015 T031** — cronometre cadastrar uma filha menor de 13, com o passo do responsável | < 3 min. Se passar, anote **onde** ela travou |
| 22 | 1 pessoa | **011 T026a** — dê 5 Ações e peça a que tem mais confirmados, **sem abrir nenhuma** | < 10 s |
| 23 | 1 pessoa | **014 T028a** — cronometre um Dono arquivando o próprio Grupo | < 1 min |
| 25 | junte com o 20 | **001 T039** — tempos de cadastro (< 2 min) e de reabertura (< 5 s) | Bloqueado desde julho por falta de ambiente; agora dá |

**Sobre o item 18**, o mais valioso: escrevi os doze textos das Novidades seguindo
`CRITERIO-DE-NOVIDADE.md`, e o teste do critério é justamente esse. **Dois eu já suspeito** —
pergunte especificamente sobre eles:

- o da **liderança recusada** usa "Administrador do distrito", termo do glossário mas talvez não
  do vocabulário de quem lê;
- o do **voto** tem três orações, quando a regra pede uma ideia por item;
- o da **foto de capa**, escrito hoje, é o mais longo de todos e diz quatro coisas de uma vez
  (que existe capa, quem escolhe, quem enxerga, e o que não enviar). Pela regra deveria ser
  mais curto; deixei junto porque separar o aviso sobre foto de criança do resto me pareceu
  pior. Se as três pessoas travarem nele, eu quebro em dois.

---

## 2b. Foto de capa — dois itens da 013

**Item 28 (013 T033)** — a Parte 2 do quickstart de `specs/013-foto-de-capa/`, 21 itens. O
**item 18 é o que importa de verdade**: rodar em **Android ou iOS**, não só no navegador.

Não é zelo. O seletor de imagem é o único pedaço desta feature que se comporta de forma
diferente entre web e celular, e **o celular nunca foi exercitado** — nem por mim, nem pelos
testes, que rodam em web. Se algo desta feature vai quebrar na mão de alguém, é aí.

**Item 29 (013 T034)** — o **item 11** da mesma Parte 2, com cronômetro:

1. abra uma capa e copie o endereço da imagem;
2. remova a capa;
3. tente abrir o endereço copiado, repetidamente, e **anote quantos segundos** até parar de
   responder.

**Passou quando**: parar de responder em **até 60 segundos**. A Política de Privacidade promete
esse número com essas palavras. Se der mais, quem está errada é a Política — me diga o número
medido e eu reescrevo o texto, não o contrário.

---

## 3. Daqui a 30 dias

**Item 24 (016 T044)** — conferir `jdaniielc@gmail.com` 30 dias depois do lançamento: chegou
pedido de acesso ou correção sobre **nome, Apelido, Igreja de origem ou telefone**?

**Passou quando**: zero. Qualquer um é sinal de que a tela Meu Perfil não foi **encontrada** —
problema de caminho, não de formulário.

---

## 4. Depende do deploy (feature 020)

**Item 26** — o `curl` anônimo contra **produção**, provando que `votos` e `liderancas` devolvem
vazio lá também. Local já está provado; falta o ambiente publicado.

**Item 27 (014 T029)** — os outros 16 itens da Parte 2 do quickstart de arquivar Grupo. O item
8, que era o único a falhar em silêncio, já passou.

---

## Verificado por mim — não repita

### Consertado hoje, depois de reprovar

**Alvos de toque (010 T020).** Os botões da Home tinham 32 a 36 px de altura; SC-004 exige 44. A
causa que só a medição no navegador mostrou foi o `visualDensity` adaptativo, que em desktop
subtrai 8 px — um mínimo de 48 virava 40 reais. Corrigido; remedido: **48 px** nos seis alvos.

**Tela de pendências (018).** Um Usuário comum que digitasse `/leadership/pending` via a
**própria** declaração pendente, com botões Confirmar e Rejeitar. Não era falha de segurança —
cliquei e o banco recusou —, mas a tela não dava retorno nenhum. Agora diz que só o
Administrador decide e aponta a página do Grupo. Verificado nos dois papéis.

Nos dois casos, **o primeiro conserto passou no `analyze` e continuou errado na tela.** Foi a
medição no navegador que mostrou.

### Uma reprovação que era erro meu

**A doxologia em paisagem (010 T019).** Reprovei o item e estava errado: SC-002 foi reescrita
quando a doxologia foi para o rodapé, e hoje pede "alcançável **rolando** até o fim", em 375 px
de **largura** — não de altura. A tarefa T019 ficou velha e eu copiei o texto dela para a sua
lista. Verificado contra o critério certo: **passou**.

### Passou na tela

`/perfil` sem Perfil cai no cadastro · cadastro de adulto sem passo a mais, e o passo de criança
aparecendo com idade 9 e sumindo com 30 · Líder confirmado visível · estado da própria
declaração · Administrador vendo as pendentes · Rodada com "Seu voto" e **nenhuma contagem** ·
ordem de leitura terminando em "A Deus seja a glória" · e o **Ministério arquivado**, que mostra
o aviso e faz o Líder sumir da tela com a linha ainda no banco — o único que falharia em
silêncio.

### Passou fora da tela

**Arquivar Grupo (014 T028)**: presenças 5→5, participações 2→2, Rodadas abertas 1→0, duas Ações
futuras canceladas, a **passada intacta**, e a Rodada fechando com `vencedora_id` **nulo**.

**Corrigir telefone (016)**: `consentimento_lgpd_aceito_em` e a versão idênticos antes e depois.

**Líder de Ministério arquivado, no banco**: sem o filtro do cliente, 1 linha; com o filtro, 0 —
confirma que a barreira funciona **e** que ela é só do cliente.

**Caixa de autorização × Política (015 T030)**: sem contradição. Uma assimetria — a caixa nomeia
o escopo do que se autoriza, a Política não. Fecha com uma oração.

### Já provado antes

- **021**: `curl` anônimo local devolve `[]` com HTTP 200.
- **015**: os cinco caminhos de recusa, incluindo `service_role` e a criança tentando reescrever
  o nome do responsável.
- **022**: zero requisições ao servidor ao abrir Novidades, com o tráfego de inicialização
  separado; e a tela abre normalmente com `localStorage` bloqueado.
- **Gates**: `analyze` sem apontamentos, 225 unidade+widget, 197 integração, `build web` ok, **0
  identificadores em português**.

### Um aviso sobre o método

Minha medição por `getBoundingClientRect` **mentiu duas vezes** hoje — um `top: 0` e um `33 px`
de nó ainda não posicionado. A captura de tela desmentiu as duas. Se você repetir alguma medição
por script, confira contra a tela.
