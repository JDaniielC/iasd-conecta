# Para você finalizar

**Gerado em**: 2026-08-10 | **Base**: `main`

São **18 tarefas** nas features já entregues. Nenhuma é de código — todas dependem de algo
que eu não tenho: uma tela para olhar, uma pessoa para cronometrar, um acesso à nuvem, ou
tempo passando.

Agrupei por **sessão**, não por feature, para você fazer em bloco. Cada item diz o que fazer e
o que significa "passou".

> **Não confundir com trabalho pendente.** As features **013** (foto de capa), **019**
> (produção: região e backup) e **020** (deploy GCS+CDN) somam 94 tarefas e **não estão
> implementadas** — elas não entram aqui. Isso é construção, e a maior parte é minha. Ver
> `PENDENCIAS.md`.

---

## Sessão 1 — Uma volta pelo app no navegador (~40 min)

Roda tudo de uma vez:

```bash
cd /Users/jdsc2/projects/iasd
supabase start          # se ainda não estiver de pé
flutter run -d chrome
```

Deixe o **DevTools aberto na aba Network** — dois itens dependem dele.

| # | O que conferir | Passou quando |
|---|---|---|
| 1 | **016 T039** — digite `/perfil` na barra de endereço **sem ter Perfil** | Cai no cadastro, não numa tela quebrada |
| 2 | **016 T039** — corrija seu nome em Meu Perfil e abra um Grupo de que participa | O nome novo aparece na lista de participantes. Se aparecer o antigo, o cache não foi invalidado |
| 3 | **016 T039** — corrija só o telefone e confira a data do consentimento | A data **não** mudou. Se mudou, a base legal virou "última vez que mexi no cadastro" |
| 4 | **017 T021** — no cadastro, abra o DevTools e olhe o corpo do `insert` de Perfil | **Nenhuma chave de versão** vai no corpo. Quem grava a versão é o banco |
| 5 | **017 T021** — a tela de cadastro | Nenhum campo ou passo a mais para quem é maior de idade |
| 6 | **018 T015** — página de um Ministério com Líder confirmado, como Visitante | O Líder aparece |
| 7 | **018 T015** — declare-se Líder de um Ministério e veja a própria declaração | Você vê o estado dela (pendente) |
| 8 | **018 T015** — como Administrador, abra as declarações pendentes | Lista o que precisa decidir |
| 9 | **018 T015** — como Usuário **comum**, digite `/leadership/pending` | Vê "Nenhuma declaração pendente." — **sem erro e sem tela vermelha** |
| 10 | **021 T025** — abra uma Rodada de votação em que você votou | Sua candidata aparece marcada, e **nenhuma contagem de votos** na tela |
| 11 | **014 T029** — como Visitante, procure o Líder de um Ministério **arquivado** | Ele **não** aparece. ⚠️ **Este é o único item que falha em silêncio** — nada no banco impede, o filtro é no cliente |
| 12 | **015 T030** — leia a seção "Crianças e adolescentes" da Política em voz alta, ao lado da caixa de autorização do cadastro | As duas dizem a mesma coisa |
| 13 | **010 T019** — vire a janela para paisagem com altura ~375px, fonte padrão | "A Deus seja a glória" visível sem rolar |
| 14 | **010 T020** — confira alvos de toque na Home | Nada menor que 44×44 |
| 15 | **010 T021** — ligue o leitor de tela na Home | A ordem de leitura acompanha a visual, e a doxologia é lida como texto |

---

## Sessão 2 — Contagem no banco, antes e depois (~20 min)

Duas verificações que exigem contar linhas com o app aberto ao lado. O modo de falha das duas
é **estado parcial** — metade feita, metade não —, e contagem é o único jeito de vê-lo.

**16. 014 T028 — arquivar um Grupo.** Monte um Grupo com pelo menos 2 Ações futuras, algumas
presenças confirmadas e 1 Rodada aberta. Conte antes e depois:

```sql
select count(*) from public.confirmacoes_acao c
  join public.acoes a on a.id = c.acao_id
 where a.grupo_id = '<id>' and a.confirmada = true;
select count(*) from public.participacoes_grupo where grupo_id = '<id>';
select id, fechada_em, vencedora_id from public.rodadas_votacao where grupo_id = '<id>';
```

**Passou quando**: as duas primeiras contagens são **idênticas** antes e depois; a Rodada
fechou com `vencedora_id` **nulo**; e as Ações **futuras** ficaram canceladas enquanto a
**passada** continua intacta.

**17. 015 T031 — cadastrar uma criança.** Já verifiquei os cinco caminhos de recusa por SQL.
O que falta é a experiência: cronometrar de verdade — ver a Sessão 3.

---

## Sessão 3 — Com gente (não dá para eu fazer)

Estas quatro são as únicas que medem o que o app **é para quem usa**. Eu sei onde os botões
estão, então cronometrar a mim mesmo mediria zero.

| # | Quem | O que fazer | Meta |
|---|---|---|---|
| 18 | **3 pessoas do distrito** | **022 T027** — mostre a tela de Novidades e peça que digam, com as palavras delas, o que mudou | As três entendem cada um dos nove itens **sem explicação**. Se alguém perguntar "o que é isso?", o texto falhou |
| 19 | 1 pessoa que nunca viu o app | **022 T028** — cronometre até achar Novidades a partir da Home | Menos de 15 s |
| 20 | 3 pessoas | **016 T043** — cronometre corrigir o próprio nome, do abrir o app ao salvar | Menos de 1 min. Se passar, o suspeito é o **caminho** até a tela, não o formulário |
| 21 | 1 mãe | **015 T031** — cronometre cadastrar uma filha menor de 13, com o passo do responsável | Menos de 3 min. Se passar, anote **onde** ela travou |
| 22 | 1 pessoa | **011 T026a** — dê 5 Ações e peça a que tem mais confirmados, **sem abrir nenhuma** | Menos de 10 s |
| 23 | 1 pessoa | **014 T028a** — cronometre um Dono arquivando o próprio Grupo | Menos de 1 min |

Sobre o **item 18**: eu escrevi os nove textos seguindo `CRITERIO-DE-NOVIDADE.md`, mas o teste
do critério é justamente esse. Dois eu já marcaria como suspeitos, e vale perguntar
especificamente sobre eles:

- o da **liderança recusada** usa "Administrador do distrito" — termo do glossário, mas talvez
  não do vocabulário de quem lê;
- o do **voto** tem três orações, quando a regra pede uma ideia por item.

---

## Sessão 4 — Daqui a 30 dias

**24. 016 T044** — conferir a caixa de `jdaniielc@gmail.com` 30 dias depois do lançamento:
chegou algum pedido de acesso ou correção sobre **nome, Apelido, Igreja de origem ou
telefone**?

**Passou quando**: zero. Qualquer um é sinal de que a tela Meu Perfil não foi **encontrada** —
problema de caminho, não de formulário.

---

## Bloqueada por outra coisa

**25. 001 T039** — os tempos de cadastro (<2 min) e reabertura (<5 s) estão bloqueados desde o
começo por falta de ambiente. Agora **dá** para medir: junte com o item 20 da Sessão 3.

**26. 021 quickstart 3.2 e 018** — o `curl` anônimo contra **produção**, provando que `votos` e
`liderancas` devolvem vazio lá também. Depende do deploy, que é a feature 020.

---

## O que eu já verifiquei, para você não repetir

- **021** — `curl` anônimo local: `votos` devolve `[]` com HTTP 200. Antes do conserto,
  devolvia a lista nominal e dava para chegar ao nome pela RPC pública.
- **015** — os cinco caminhos que a regra fecha, recusados: `insert` de criança sem autorização
  como `postgres`, `service_role` e `authenticated`; `update` subindo adulto para idade de
  criança; e a criança reescrevendo o nome do responsável.
- **022** — abrir a tela de Novidades: **zero** requisições ao Supabase, medido com o tráfego
  de inicialização separado. E com `localStorage` lançando `SecurityError`, a tela abre e lista
  normalmente.
- **022** — o ciclo do aviso inteiro: primeira abertura não avisa e grava o marcador; marcador
  recuado faz o ponto aparecer; abrir a tela faz sumir sem recarregar.
- **Gates**, em todas as features entregues: `flutter analyze` sem apontamentos, 225
  unidade+widget, 197 integração, `flutter build web` ok, **0 identificadores em português** em
  `lib/` e `test/`.
