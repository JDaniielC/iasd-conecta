# Research: Versão do texto aceito no consentimento

**Feature**: 017-versao-do-consentimento | **Date**: 2026-08-09

---

## D-001 — A autoridade da versão passa a ser o banco; o Dart vira espelho de exibição

**Esta é a decisão que decide a feature.** As outras cinco são consequências dela.

### A tensão, escrita sem enfeite

- **FR-002** manda a versão vir da *fonte única que o app já tem*, que é
  `LegalMetadata.version` (`lib/features/legal/legal_metadata.dart:11`), uma constante Dart.
- **FR-004** manda a versão ser gravada *pelo banco ou pelo servidor*, nunca por valor que o
  cliente envia — "senão o registro vale o que o cliente disser".

Os dois não podem ser verdade ao mesmo tempo com o código de hoje: **o banco não conhece
`LegalMetadata.version`**. Ou o Dart manda o valor (e FR-004 cai), ou o banco tem a sua própria
noção de versão (e FR-002 cai, porque passam a existir dois lugares).

### Decisão

**A autoridade do registro é o banco. A autoridade da exibição é o Dart. As duas são amarradas
por um teste que falha se divergirem.**

Concretamente:

1. Nasce `public.versoes_texto_legal (versao, vigente_desde, created_at)` — uma linha por versão
   publicada, escrita **só por migration**. `anon` e `authenticated` têm `select`; ninguém tem
   `insert`, `update` ou `delete`. Publicar versão é evento de release, não ação de runtime.
2. `public.versao_texto_legal_vigente()` devolve a versão com maior `vigente_desde <= now()`.
3. Um gatilho `before insert or update` em `perfis` grava essa versão nas colunas de
   consentimento. **O cliente não manda versão nenhuma** — `Profile.toInsertMap` continua sem a
   chave, e se um cliente adulterado mandar mesmo assim, o gatilho sobrescreve.
4. `LegalMetadata.version` **continua existindo e continua sendo o que as páginas exibem**
   (`privacy_policy_page.dart:37`, `terms_of_use_page.dart:31`), porque o **texto** mora no
   binário do app e a versão é metadado desse texto.
5. `test/integration/versao_texto_legal_registro_test.dart` afirma
   `versao_texto_legal_vigente() == LegalMetadata.version`. Divergir quebra o CI.

### Por que não é trapaça chamar isso de "fonte única"

Porque a duplicação é **de escrita única e verificação mecânica**: quem publica um texto novo
faz duas edições no mesmo commit (a constante e a linha do registro), e o gate recusa o commit
que fez só uma. É exatamente o padrão que a feature 011 já usa para o limiar de 4 horas
(`defaultActionDuration` no Dart × `interval '4 hours'` no SQL,
`specs/011-acoes-titulo-e-encerramento/contracts/schema.sql:27-31`). Precedente na casa, com o
mesmo custo e o mesmo remédio.

O que ganhamos ao pagar esse preço: **o registro deixa de valer o que o cliente disser.**

### Alternativas descartadas

**(a) O Dart manda `LegalMetadata.version` no `insert`; o banco valida contra o registro
(chave estrangeira ou `check`).**
Descartada porque validar não é autorar. Um cliente adulterado — e no Flutter web o cliente é
literalmente JavaScript na máquina de quem quiser — pode mandar `'1.0'` enquanto a tela exibiu
o texto 1.1, e a validação aceitaria: `'1.0'` é uma versão registrada. O registro passaria a
valer o que o cliente disser, que é a frase exata que FR-004 proíbe. É a alternativa mais
barata e a única que FR-004 nomeia para rejeitar.

**(b) A versão vive só no banco; o Dart lê por consulta e exibe o que vier.**
Descartada por trocar um problema conhecido por uma mentira. O **texto** legal está compilado
no binário. Um aparelho com uma versão antiga do app instalada renderizaria o texto 1.1 com o
rótulo "Versão 1.2" no topo, porque o banco disse 1.2 — e carimbaria 1.2 num aceite dado sobre
o texto 1.1. Hoje o problema é *não saber*; nesse desenho, o problema seria *afirmar errado*.
Some-se: a página legal passaria a depender de rede para renderizar seu próprio cabeçalho, e
ficaria sem versão nenhuma offline.

**(c) Uma Edge Function do Supabase faz o insert do Perfil e carimba a versão lá.**
Descartada por custo desproporcional e por não resolver melhor. FR-004 aceita "banco **ou**
servidor"; o gatilho é servidor tanto quanto a função, roda dentro da mesma transação do
`insert`, não introduz um segundo runtime para manter e implantar, e não pode ser contornado
por quem escrever direto na tabela (o que a Edge Function não impede). O projeto não tem
nenhuma Edge Function hoje; introduzir a primeira para isto violaria o Princípio V.

---

## D-002 — Gatilho, não `default` de coluna

**Decisão**: o carimbo é feito por `public.perfis_carimbar_consentimento()`, um
`before insert or update ... for each row`. **Não** por
`default public.versao_texto_legal_vigente()` na definição da coluna.

**Rationale**: `default` só entra em ação quando a coluna **não é mencionada** no `insert`. Um
cliente que mencione a coluna sobrescreve o default sem nenhuma resistência — ou seja, `default`
cumpre FR-004 apenas contra um cliente educado. Gatilho `before` é incondicional: ele reescreve
`new.consentimento_lgpd_versao` independentemente do que veio.

**O `else` do gatilho é tão importante quanto o `if`**: quando o `_aceito_em` **não** mudou, o
gatilho **restaura os valores antigos** das duas colunas. É isso que impede um cliente
autenticado de rodar `update public.perfis set consentimento_lgpd_versao = '1.1'` na própria
linha antiga e fabricar um backfill — SC-002 vira execução, não promessa.

**Alternativa descartada**: `revoke insert (consentimento_lgpd_versao) on public.perfis from
authenticated`, isolando a coluna por privilégio. Funciona, mas transforma um cliente
desatualizado num cadastro que **falha** em vez de um cadastro que é **corrigido em silêncio**.
Corrigir é o comportamento certo aqui: o Usuário não tem culpa nem remédio para um cliente que
manda campo a mais. Descartada também por redundância — com o gatilho, o privilégio não
acrescenta garantia, só um segundo lugar para procurar quando algo der errado.

---

## D-003 — Versão desconhecida é `null`. Sem valor sentinela, sem `not null`, sem `check`

**Decisão**: as duas colunas são `text` **anuláveis**, sem `not null` e **sem nenhuma
constraint**. `null` significa uma coisa só: *este aceite é anterior à feature 017 e não há como
saber sob qual texto foi dado*.

**Por que não um valor sentinela** (`'desconhecida'`, `'0'`, `'?'`): um sentinela é um valor, e
valor se parece com fato. Ele apareceria ordenado entre versões reais, entraria em `group by` ao
lado delas, casaria com a chave estrangeira só se fosse registrado como se fosse uma versão de
verdade, e obrigaria toda consulta futura a lembrar de excluí-lo à mão. `null` já é a palavra
que o Postgres tem para "não sei", e `count(*) group by` separa nulo sem esforço, que é
exatamente o que FR-006 pede.

**Por que a coluna não pode ser `not null`**: seria impossível adicioná-la sem backfill, e
backfill é o que FR-007 proíbe.

**Por que nem mesmo um `check ... not valid` — o achado menos óbvio desta feature**: a
construção abaixo parece resolver tudo (linhas antigas intocadas, linhas novas obrigadas):

```sql
alter table public.perfis
  add constraint consentimento_lgpd_versao_obrigatoria
  check (consentimento_lgpd_versao is not null) not valid;   -- NÃO FAZER
```

`not valid` dispensa a verificação das linhas **existentes no momento em que a constraint é
criada** — mas passa a verificar toda linha tocada por `INSERT` **ou `UPDATE`** dali em diante,
inclusive `update` que não menciona a coluna. Um Perfil antigo, de versão nula, deixaria de
poder ser atualizado. E `public.excluir_minha_conta` (feature 009,
`20260806140000_exclusao_de_conta.sql`) termina com um
`update public.perfis set nome = 'Membro removido', ...` — quem se cadastrou antes desta
feature **perderia o direito de apagar a conta** (LGPD art. 18, VI). A feature 016 (Meu Perfil),
que existe para permitir `UPDATE` em `perfis`, encostaria no mesmo muro.

**A garantia vem de onde deve vir**: o gatilho, que carimba toda linha nova. E ela é provada por
teste de integração, não por constraint — com um caso dedicado a `excluir_minha_conta` sobre um
Perfil de versão desconhecida, no espírito do risco 1 da feature 011.

---

## D-004 — A consulta é agregada, é uma função, e é do Administrador do distrito

**Decisão**: `public.consentimentos_por_versao()` — `security definer`, `stable`, devolve
`(tipo text, versao text, quantidade bigint)`, e levanta exceção se quem chama não estiver em
`public.administradores_distrito`.

**Por que uma função e não um `select` direto**: `perfis` tem `perfis_select_own`
(`20260723191202_perfis_igrejas.sql:66-69`) — um `select` direto devolve exatamente uma linha,
a de quem perguntou. Sem `security definer`, a pergunta da US2 é irrespondível de dentro do app.

**Por que agregada, e não uma lista nominal**: FR-005 pede distinguir *quem aceitou qual versão*;
US2 e SC-003 esclarecem o uso real — *quantas pessoas estão sob cada versão*. Devolver a lista
nominal ao Administrador entregaria identidade que ninguém pediu, contra o Princípio II
(minimização). A distinção por pessoa **existe no dado** — é uma coluna por linha de `perfis` —
e permanece alcançável pelo controlador via `service_role`/painel do Supabase, que é o acesso
apropriado para responder a um pedido individual de titular ou a uma auditoria. Está declarado
assim, e não escondido: o app responde a pergunta agregada; a pergunta nominal é operação de
controlador, fora do app.

**Por que Administrador do distrito e não um papel novo**: Princípio V. O papel existe desde a
feature 005, tem tabela, tem trigger de promoção e tem UI. Contagem de conformidade cabe no
mesmo lugar onde já se gere Igreja e se promove Administrador.

**Perfil anonimizado sai da contagem** (`anonimizado_em is not null`): a pergunta é "quantas
**pessoas** estão sob cada versão", e uma linha anonimizada não é mais uma pessoa rastreada —
contá-la inflaria o número. O consentimento continua gravado na linha, porém, como prova da base
legal do histórico que a feature 009 preserva de propósito.

**Alternativa descartada**: uma `view` `consentimentos_por_versao`. View em Postgres roda com os
privilégios do dono por padrão (`security_invoker = false`), o que a torna um `security definer`
disfarçado — mesma potência, menos visível, e sem lugar natural para a checagem de
Administrador. Função explícita diz o que faz.

---

## D-005 — Colunas pareadas, não tabela normalizada — com gatilho de reincidência

**Quantos consentimentos existem hoje**: **dois**.

| Consentimento | Coluna de data | Origem |
|---|---|---|
| LGPD do cadastro | `consentimento_lgpd_aceito_em` (`not null`) | `20260723191202_perfis_igrejas.sql:36` |
| Igreja de origem (destacado, art. 11 I) | `consentimento_lgpd_igreja_aceito_em` (anulável) | `20260724140000_consentimento_igreja_destacado.sql:6-7` |

**Um terceiro está a caminho**: a feature 015 (autorização de responsável) declara em FR-007 que
precisa registrar "data/hora da autorização e a versão do texto legal vigente no momento". A
feature 016 não acrescenta consentimento novo, mas acrescenta um **momento novo** para o
consentimento de Igreja (dado depois do cadastro), que o gatilho já cobre pelo ramo de `UPDATE`.

**Decisão**: uma coluna de versão **ao lado de cada** coluna de data — `consentimento_lgpd_versao`
e `consentimento_lgpd_igreja_versao` agora, `autorizacao_responsavel_versao` quando a 015 chegar.
Não criar `consentimentos (usuario_id, tipo, aceito_em, versao)`.

**Rationale**: o formato pareado é o que a tabela **já tem** — cada consentimento já é uma coluna
de data em `perfis`. Acrescentar a versão ao lado mantém um só formato, mantém intacta a
constraint `consentimento_igreja_destacado` (que é um `check` de coluna e viraria gatilho
entre tabelas num modelo normalizado), não mexe em RLS, não mexe em
`excluir_minha_conta`, e não migra dado existente. Princípio V: o caminho mais simples que
atende a regra descrita, sem generalizar para necessidade não especificada. Custo de um 3º
consentimento: uma coluna e ~8 linhas no gatilho.

**O gatilho de reincidência, escrito aqui para não depender de memória** — trocar para a tabela
normalizada assim que **qualquer** um destes acontecer:

1. Surgir o **4º** consentimento distinto.
2. Alguém precisar do **histórico** de aceites, e não só do último. A coluna pareada guarda um
   estado, não uma série: reaceitar sobrescreve. Hoje ninguém pede série (a spec diz
   explicitamente que ninguém é forçado a reaceitar); no dia em que pedir, a coluna acabou.
3. Um consentimento passar a existir para algo que **não é o Perfil** (um Grupo, uma Ação),
   porque aí não há coluna em `perfis` onde parear.

**Alternativa descartada**: criar a tabela normalizada agora, já com os dois consentimentos
migrados. Descartada pelo tamanho: obrigaria a reescrever a constraint `consentimento_igreja_destacado`
como gatilho entre tabelas, criar RLS nova, alterar `excluir_minha_conta`, migrar dado existente
e reescrever as premissas das features 015 e 016 antes de elas serem planejadas — tudo isso para
um ganho que só aparece no 4º consentimento. A spec desta feature diz, em Key Entities: *"É um
campo, não um conceito"*.

---

## D-006 — Não há backfill, nem mesmo o backfill "inteligente"

**Decisão**: nenhuma linha existente é tocada. Nem por `update`, nem por default retroativo, nem
por inferência.

**A tentação concreta, que é melhor do que um chute e ainda assim foi recusada**: o dado para
inferir *existe*. `consentimento_lgpd_aceito_em` está gravado em toda linha, e
`LegalMetadata.effectiveDate` diz que 1.1 vigora desde 6 de agosto de 2026. Bastaria:

```sql
update public.perfis
set consentimento_lgpd_versao = case
  when consentimento_lgpd_aceito_em >= '2026-08-06' then '1.1' else '1.0' end;   -- NÃO FAZER
```

**Por que não**, em três razões que se somam:

1. O timestamp foi carimbado **pelo cliente** (`profile.dart:70`, `DateTime.now()` do aparelho),
   com o fuso e o relógio de quem se cadastrou. É a exata fragilidade que FR-004 existe para
   corrigir daqui em diante — usá-la como base de prova retroativa seria construir sobre o que
   acabamos de declarar frágil.
2. `effectiveDate` é `'6 de agosto de 2026'` — sem hora, sem fuso. E, mais grave, a data em que o
   **texto** passou a ser servido a cada pessoa é a data em que o binário chegou ao aparelho
   dela, não a data escrita na constante. Quem estava com o app aberto ou com uma build antiga em
   cache leu 1.0 depois do dia 6.
3. O resultado seria gravado numa coluna que, para todo consumidor futuro, se parece com fato
   apurado. A inferência viraria fato por mudança de suporte — que é precisamente o que a spec
   chama de *"um chute apresentado como fato"* (US3).

**O que fazemos com a inferência**: ela fica registrada em `MAPA-DE-DADOS.md` como **estimativa
possível sob demanda**, com as três ressalvas acima ao lado, e nunca é gravada na coluna. Se um
dia for preciso responder a uma autoridade, a resposta é "não sabemos, e aqui está a estimativa
com suas premissas" — que é uma resposta honesta e defensável. "1.0" numa coluna não é.

**Qual é, então, o período dos aceites desconhecidos** (FR-008): de **2026-07-23** (data da
migration que criou `perfis`, `20260723191202_perfis_igrejas.sql`) até a data de aplicação da
migration desta feature. É o que vai escrito em `MAPA-DE-DADOS.md`, com a observação de que
1.0 vigorou até 2026-08-05 e 1.1 desde 2026-08-06 — informação sobre o **documento**, que é
conhecida, e não sobre **quem aceitou o quê**, que não é.

**Sobre semear a versão 1.0 no registro `versoes_texto_legal`**: **não semeamos**. Não há, no
repositório, nenhuma data de vigência documentada para a 1.0 — inventá-la seria a mesma espécie
de mentira, num arquivo que a partir de agora é a fonte de verdade das versões. O registro nasce
com a linha de 1.1 e cresce por migration a cada publicação.
