# Para você finalizar

**Atualizado**: 2026-08-10 | **Base**: `main`

Sobraram **14 itens**, e **nenhum é código**. Dois são dois minutos seus clicando num botão que
a automação não alcança, sete dependem de **outras pessoas**, dois da **foto de capa** (um deles
exige um celular de verdade), um só se responde daqui a 30 dias, e dois esperam o **deploy**.

O que eu já verifiquei saiu daqui: está em `PENDENCIAS.md` § 5, para ninguém refazer.

---

## 1. Dois minutos seus (itens 2 e 4)

Os dois exigem **concluir um formulário**, e o botão de enviar não responde a clique sintético
no canvas do Flutter — tentei por coordenada, por nó de acessibilidade e por teclado. **Não é
defeito do app**: digitar funciona (a idade 9 faz o passo do responsável aparecer, e 30 o faz
sumir). É limite da automação.

```bash
supabase start && flutter run -d chrome
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
`CRITERIO-DE-NOVIDADE.md`, e o teste do critério é justamente esse. **Três eu já suspeito** —
pergunte especificamente sobre eles:

- o da **liderança recusada** usa "Administrador do distrito", termo do glossário mas talvez não
  do vocabulário de quem lê;
- o do **voto** tem três orações, quando a regra pede uma ideia por item;
- o da **foto de capa** é o mais longo de todos e diz quatro coisas de uma vez (que existe capa,
  quem escolhe, quem enxerga, e o que não enviar). Pela regra deveria ser mais curto; deixei
  junto porque separar o aviso sobre foto de criança do resto me pareceu pior. Se as três
  pessoas travarem nele, eu quebro em dois.

---

## 3. Foto de capa — dois itens da 013

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

## 4. Daqui a 30 dias

**Item 24 (016 T044)** — conferir `jdaniielc@gmail.com` 30 dias depois do lançamento: chegou
pedido de acesso ou correção sobre **nome, Apelido, Igreja de origem ou telefone**?

**Passou quando**: zero. Qualquer um é sinal de que a tela Meu Perfil não foi **encontrada** —
problema de caminho, não de formulário.

---

## 5. Depende do deploy (feature 020)

**Item 26** — o `curl` anônimo contra **produção**, provando que `votos` e `liderancas` devolvem
vazio lá também. Local já está provado; falta o ambiente publicado.

**Item 27 (014 T029)** — os outros 16 itens da Parte 2 do quickstart de arquivar Grupo. O item
8, que era o único a falhar em silêncio, já passou.
