# Research: Meu Perfil — ver e corrigir os próprios dados

**Feature**: 016-meu-perfil | **Date**: 2026-08-09

Oito decisões tomadas antes de escrever código. Cada uma registra o que foi escolhido, por
quê, e o que foi descartado — o motivo do descarte é a parte que interessa numa sessão futura.

A D-001 é a que sustenta o plano inteiro: se ela tivesse dado errado, a feature deixaria de
ser cliente puro.

---

## D-001 — Nenhuma migration. `perfis_update_own` basta, e a verificação

**Decisão**: a feature não cria migration nenhuma. A escrita usa a policy e o `grant` que já
existem desde 2026-07-23.

**Verificado no código, não na spec** (`supabase/migrations/20260723191202_perfis_igrejas.sql`):

```sql
-- linha 56
grant select, insert, update on public.perfis to authenticated;

-- linhas 66-69
create policy perfis_select_own
  on public.perfis for select
  to authenticated
  using (auth.uid() = id);

-- linhas 76-79
create policy perfis_update_own
  on public.perfis for update
  to authenticated
  using (auth.uid() = id);
```

São quatro coisas que precisavam ser verdadeiras ao mesmo tempo, e as quatro são:

1. **Privilégio de tabela**: `grant ... update ... to authenticated` existe (linha 56). Sem
   ele, RLS nem seria consultado — o Postgres recusa antes.
2. **A linha certa é alcançável**: um `UPDATE ... where id = $uid` precisa **enxergar** a
   linha, e quem permite isso é `perfis_select_own` (linha 66), que também já existe. Sem
   policy de `select`, o `UPDATE` acharia zero linhas e falharia em silêncio — o pior modo de
   falhar.
3. **A linha alterada continua sendo a própria**: `perfis_update_own` declara `using` e **não**
   declara `with check`. Não é lacuna: em política de `UPDATE`, quando `WITH CHECK` é omitido,
   o Postgres usa a expressão de `USING` também como expressão de checagem da linha nova
   (`CREATE POLICY`, seção *Per-Command Policies*: *"if no `WITH CHECK` expression is defined,
   then the `USING` expression will be used both to determine which rows are visible (normal
   `USING` case) and which new rows will be allowed to be added (`WITH CHECK` case)"*). Ou
   seja: `auth.uid() = id` vale para a linha antiga **e** para a nova, e ninguém consegue
   reatribuir o próprio Perfil para outro `id`. É o que FR-013 e SC-004 exigem, garantido no
   banco.
4. **As constraints continuam valendo no `UPDATE`**: `check (nome_valido(nome))` (linha 29),
   `apelido_obrigatorio_menor` (linha 38) e `consentimento_igreja_destacado`
   (`20260724140000:9-11`) são `CHECK` de tabela, reavaliadas em qualquer `INSERT` **ou
   `UPDATE`** da linha. Não é preciso replicar nada: FR-008 e FR-009 chegam de graça no banco.

**O que faltaria se algum desses quatro não existisse** — registrado porque é o achado que
mudaria o plano: bastaria uma migration nova, sem tocar nada existente. Não é o caso.

**Alternativas descartadas**:
- *Criar uma RPC `atualizar_meu_perfil()` `security definer`*: existe precedente
  (`excluir_minha_conta`), mas o precedente traz o motivo junto — aquela função toca 6 tabelas
  e precisa de `BYPASSRLS`. Aqui é uma tabela e uma linha. RPC adicionaria um objeto de banco,
  uma migration, e retiraria a checagem de RLS do caminho, trocando uma garantia por uma
  função que precisa reimplementá-la. Fere o Princípio V.
- *Adicionar `with check (auth.uid() = id)` à policy por explicitude*: seria uma migration para
  não mudar comportamento nenhum. Se um dia a policy ganhar um `with check` diferente do
  `using`, aí sim. Fica só o teste de integração provando a garantia (T0..., ver `tasks.md`) —
  teste é mais barato que migration e prova mais.

---

## D-002 — Uma tela só, em `/perfil`, que vê e edita

**Decisão**: `MyProfilePage`, arquivo `lib/features/profile/presentation/my_profile_page.dart`,
rota `/perfil`. A mesma tela atende US1 (ver) e US2 (corrigir): os quatro campos editáveis são
campos de formulário, os três não editáveis são linhas de texto, e um botão "Salvar" no fim.

**Rationale**: separar em `/perfil` (ver) e `/perfil/editar` (corrigir) dobraria a tela, a rota
e o teste para atender um requisito que ninguém escreveu — a spec não pede confirmação nem
passo intermediário, e diz o contrário em Assumptions ("Sem confirmação por segunda etapa").
Princípio V. Além disso, "ver e não poder corrigir de onde se vê" é justamente a experiência
que a feature existe para acabar.

**A entrega continua incremental**: US1 entrega a tela com os sete campos em modo de leitura;
US2 troca quatro deles por campos de formulário e acrescenta o "Salvar". `tasks.md` está
cortado assim, e US1 é demonstrável sozinha.

**Rota em português** (`/perfil`, como `/cadastro`, `/privacidade`, `/termos`): rota é texto
visível na barra de endereço do navegador, não identificador Dart. As rotas do app são
mistas hoje (`/delete-account`, `/upgrade-conta`); `/perfil` acompanha as legíveis pelo
Usuário, que são a maioria e as que ele de fato vê.

**Alternativa descartada**: aba de navegação inferior com "Perfil". Introduz estrutura de
navegação nova no app inteiro — foi descartada pela mesma razão na feature 010 (D-001).

---

## D-003 — Um modelo `Profile` só, com `idade` e `gênero` nulos toleráveis

**Decisão**: não existe classe de leitura separada. `Profile` (`domain/profile.dart`) ganha:

- `factory Profile.fromMap(Map<String, dynamic> map)` — lê a linha de `perfis`;
- `Map<String, dynamic> toUpdateMap()` — só as colunas editáveis (ver `data-model.md`);
- `final DateTime? lgpdConsentAcceptedAt` e `final DateTime? churchLgpdConsentAcceptedAt` —
  nulos no rascunho de cadastro, preenchidos quando a linha vem do banco (FR-002 exige exibir
  a data do consentimento);
- `final int? age` e `final Gender? gender` — **passam a ser nulos permitidos**.

**Rationale de nulificar `age`/`gender`**: o schema já os nulificou. `20260806140000:45-46`
(feature 009) fez `alter column genero drop not null` e `alter column idade drop not null`,
porque anonimizar de verdade exige apagá-los. Um modelo que declara `int age` não-nulo está
descrevendo um schema que deixou de existir há três dias, e estoura em cast na única linha em
que a diferença aparece. O caminho para chegar lá é estreito mas real (risco 4 do `plan.md`:
`signOut()` falhando depois da RPC de exclusão). Preferir o `crash` "porque não deveria
acontecer" é a decisão que a feature 009 já tinha rejeitado ao derrubar a FK.

**Custo verificado, e é baixo**: `readyToSubmit` ganha `age != null` e `isMinor` vira
`age != null && age! < _ageOfMajority`. `profile_signup_page.dart` **não muda por causa disso**
— `_currentProfile` (linhas 49-62) já devolve `null` quando a idade não parseia, então o
caminho de cadastro nunca constrói um `Profile` de idade nula, e passar um `int` não-nulo para
um parâmetro `int?` compila. `test/unit/profile_model_test.dart` também não quebra pelo mesmo
motivo.

**O ganho é o que evita duplicação (FR-008, FR-009, FR-011)**: a tela de edição reusa
`needsNickname`, `needsChurchConsent` e `readyToSubmit` **exatamente como estão**. `readyToSubmit`
exige `lgpdConsentAccepted`, e `Profile.fromMap` o preenche com `true` — porque
`consentimento_lgpd_aceito_em` é `not null` na tabela, então uma linha que existe é uma linha
que consentiu. Nenhuma regra é reescrita para a edição.

**Alternativas descartadas**:
- *Classe `MyProfile` separada para leitura*: obrigaria a reimplementar `needsNickname`,
  `needsChurchConsent` e `readyToSubmit`, ou a converter entre as duas — é exatamente a
  duplicação de regra que FR-008 e FR-009 proíbem.
- *`Profile.fromMap` lançando `StateError` em Perfil anonimizado*: mais curto, mas transforma
  um estado previsto do schema em exceção não tratada. E o teste que provaria o
  comportamento seria um teste de que o app quebra.

---

## D-004 — A lista de palavras e a mensagem de erro saem da tela de cadastro

**Decisão**: dois movimentos, ambos sem mudar comportamento nenhum do cadastro.

1. A lista literal de `profile_signup_page.dart:31`
   (`const NameModeration(['idiota', 'burro', 'estupido', 'imbecil', 'babaca'])`) vira
   `static const NameModeration cached` dentro de `name_moderation.dart`. As duas telas passam
   a ler `NameModeration.cached`.
2. `_errorMessage(PostgrestException)` (`profile_signup_page.dart:102-113`), que traduz
   `nome_valido`, `apelido_obrigatorio_menor` e `consentimento_igreja_destadado` em frases,
   vira a função de topo `profileErrorMessage(PostgrestException e)` em
   `lib/features/profile/domain/profile_error_message.dart`. As duas telas passam a chamá-la.

**Rationale**: FR-008 diz "a **mesma** regra e a **mesma** mensagem do cadastro". Uma cópia da
lista e uma cópia da string cumprem isso no dia da entrega e param de cumprir na primeira vez
que alguém atualizar só uma das duas — sem erro de compilação e sem teste vermelho. Não é
zelo estético: é a única forma de o requisito continuar verdadeiro depois.

**A mensagem genérica de fallback difere entre as telas** e isso é intencional: o cadastro diz
"Não deu pra concluir o cadastro agora", a edição precisa dizer algo sobre salvar. Então
`profileErrorMessage` recebe a frase de fallback como parâmetro
(`String fallback`), e só as três traduções de constraint — que são as que FR-008 cobre —
ficam compartilhadas.

**Já existe duplicação hoje, dentro do próprio arquivo**: a frase "Esse nome não pode ser
usado. Tente outro." aparece duas vezes em `profile_signup_page.dart` (linha 68, pré-checagem
no cliente; linha 104, tradução da constraint do banco). O movimento resolve as duas.

**Alternativa descartada**: extrair um widget `ProfileFormFields` compartilhado entre cadastro
e edição. Parece a economia óbvia e não é: os dois formulários **não são o mesmo formulário** —
o cadastro tem idade, gênero e o consentimento LGPD geral, que a edição não tem (D-006); o
cadastro é criação, a edição parte de valores existentes. O widget compartilhado nasceria com
um `bool isEditing` ramificando quase tudo, e passaria a ser mais difícil de ler que as duas
telas separadas. O que precisa ser único é a **regra**, não o layout — e é isso que os dois
movimentos acima garantem.

---

## D-005 — Consentimento de Igreja na edição: quando carimbar, quando limpar

**Decisão**: três casos, e o meio é o que erra fácil.

| O Usuário… | `igreja_id` | `consentimento_lgpd_igreja_aceito_em` | Caixa destacada |
|---|---|---|---|
| escolhe Igreja onde não havia, **ou troca de Igreja** | id novo | `now()` | **exigida**, desmarcada |
| mantém a mesma Igreja | inalterado | **inalterado** | não aparece |
| remove a Igreja | `null` | **`null`** | não aparece |

**Rationale de cada linha**:
- **Escolher ou trocar** é consentimento novo, com finalidade nova (destacar Grupos e Ações
  daquela igreja). FR-011 exige a caixa destacada, e o cadastro já faz exatamente isso —
  `profile_signup_page.dart:176-181` zera `_churchConsent` sempre que o seletor muda, com o
  comentário certo ("Trocar ou remover a igreja invalida o consentimento anterior — força
  reafirmar"). A edição replica esse comportamento, não o reinventa.
- **Manter** não pode recarimbar a data. Reescrever `now()` num consentimento que não foi dado
  de novo é falsificar o registro da base legal — e o Usuário que só corrigiu o telefone
  passaria a constar como tendo reconsentido hoje.
- **Remover** zera a data. A constraint `consentimento_igreja_destacado`
  (`igreja_id is null or consentimento_lgpd_igreja_aceito_em is not null`) **aceita** deixar a
  data preenchida com a igreja nula — ou seja, o banco não decide isso por nós. Deixar seria
  guardar um consentimento sem a finalidade que ele autorizava. Zerar é a leitura do art. 8º,
  §5º da LGPD (revogação) e é o que mantém o par coerente.

**Dependência com a 017, registrada**: escolher a Igreja pela tela de edição é um aceite novo,
e a 017 (FR-001, FR-003) exige que todo aceite registre a versão do texto vigente — a própria
spec da 017 prevê este caso nos Edge Cases. Ver a tabela de ordem no `plan.md`. O ponto de
atenção é o FR-004 da 017: a versão tem de ser gravada **pelo banco**, não enviada pelo
cliente, então `toUpdateMap()` provavelmente **não** ganhará a coluna de versão — o `default`
do banco a preenche.

---

## D-006 — Idade e gênero: exibidos, nunca escritos

**Decisão**: a tela **exibe** idade e gênero (FR-002 os lista) e **não oferece campo de
edição** para nenhum dos dois. `Profile.toUpdateMap()` não inclui `'idade'` nem `'genero'`.
Idem para `'consentimento_lgpd_aceito_em'` e `'anonimizado_em'`.

**Rationale — o que exatamente cada um carrega**:
- **Gênero** valida a composição de Dupla Missionária (glossário; `20260724110000`). Alterá-lo
  depois de a pessoa já ter confirmado presença numa Dupla poderia transformar uma composição
  válida em inválida, e nada recalcularia — é um caso de borda do Princípio IV, e a feature
  não quer carregá-lo.
- **Idade** decide a exigência de Apelido (`apelido_obrigatorio_menor`) e, se a feature 015
  entrar, decide a exigência de autorização do responsável. Baixá-la para faixa de criança
  seria um caminho de menor esforço para uma regra de proteção de menor.
- **`consentimento_lgpd_aceito_em`** é registro de base legal, não dado editável. É exibido
  (FR-002 pede) e nunca reescrito.

**Isso é decisão da spec, não desta fase**: está em Assumptions ("Idade e gênero fora do
escopo de edição … Continuam sendo corrigidos por e-mail. Se isso incomodar, vira feature
própria"). O que esta decisão acrescenta é o **motivo técnico** e a consequência de
implementação: a exclusão vive em `toUpdateMap()`, num lugar só, e é testável por unidade.

**Limite honesto**: `toUpdateMap()` é o cliente. O banco **não** impede o próprio Usuário de
escrever `idade`/`genero` por chamada direta, porque o `grant` da linha 56 é de tabela inteira,
sem recorte de coluna. Isso é anterior a esta feature e está registrado como dívida no risco 3
do `plan.md`, com o conserto identificado. Nenhum FR desta spec o exige — SC-004 fala de Perfil
**alheio**, que está coberto por RLS.

---

## D-007 — FR-005 e FR-006: como se chega, e como não se chega

**Chegar (FR-006)**: a Home ganha um caminho para `/perfil`, visível só quando
`hasProfileProvider` resolve em `true` — rótulo em texto ("Meu Perfil"), no mesmo padrão dos
demais botões da Home. É a navegação principal do app, não um link decorado, que é o que
FR-006 pede. A Política de Privacidade também passa a apontar para lá (FR-014, e ela já aponta
para `/delete-account` em `privacy_policy_page.dart:263` — mesmo padrão).

**Não chegar (FR-005)**: o gate vai no `redirect` de `lib/app.dart`, junto dos dois que já
existem (linhas 58 e 62):

```dart
if (hasProfile == false && state.matchedLocation == '/perfil') return '/cadastro';
```

**Rationale**: o app está em deploy web (`deploy-web.yml`), então `/perfil` é digitável na
barra de endereço. `ProfileGuard.requireProfile` (`domain/profile_guard.dart`) só protege o
botão — quem não passa pelo botão não é protegido. O redirect é a garantia; o guard no botão
continua sendo usado, como conforto e por consistência com o resto do app.

**Detalhe do redirect que não pode ser esquecido**: a primeira linha do `redirect` atual
(`app.dart:49`) devolve `null` enquanto `hasProfile == null` (ainda carregando). A comparação
tem de ser `hasProfile == false`, não `!hasProfile`, para não empurrar ao cadastro quem só
está esperando a rede.

---

## D-008 — Estratégia de teste: os três níveis, e por que a integração é obrigatória aqui

**Diferente da 010**: aquela feature não tocava banco e pulou `dart test test/integration`.
Esta toca — RLS e constraints em `UPDATE`, um caminho que **nenhum teste do repositório
exercita hoje**, porque nenhuma linha de código jamais fez `update` em `perfis`.

**Integração** (`test/integration/perfil_edicao_rls_test.dart`, conexão direta ao Postgres via
`db_test_helper.dart`, no padrão de `security_acoes_protege_campos_test.dart`):

| O que prova | Requisito |
|---|---|
| Usuário A não consegue alterar o Perfil de B (o `UPDATE` afeta 0 linhas) | FR-013, SC-004 |
| Usuário A não consegue reatribuir o próprio Perfil para o `id` de B (`with check` implícito) | FR-013, SC-004 |
| `UPDATE` que põe nome com palavra bloqueada é recusado | FR-008 |
| `UPDATE` que apaga o Apelido de menor é recusado | FR-009 |
| `UPDATE` que põe `igreja_id` sem `consentimento_lgpd_igreja_aceito_em` é recusado | FR-011 |
| Depois de cada recusa acima, a linha continua **idêntica** ao que era | FR-012, SC-005 |

O helper de sessão é reescrito em inglês (`asUser`), **não** copiado de `_comoUsuario` de
`security_acoes_protege_campos_test.dart:8` — identificador novo em teste é inglês
(Princípio I).

**Widget** (`test/widget/meu_perfil_page_test.dart`, `mocktail` sobre `ProfileRepository`, no
padrão de `cadastro_perfil_page_test.dart`): os sete campos aparecem; opcional vazio aparece
como vazio explícito; a tela não consulta repositório de terceiro; moderação recusa com a
mensagem do cadastro; Apelido de menor não pode esvaziar; telefone pode esvaziar; escolher
Igreja faz aparecer a caixa destacada e desabilita "Salvar" até marcá-la; falha ao salvar
mostra aviso e **não invalida** `myProfileProvider` (os valores exibidos continuam os antigos).

**Unidade** (`test/unit/profile_model_test.dart`, ampliado): `Profile.fromMap` lê a linha
inteira, inclusive `idade`/`genero` nulos; `toUpdateMap()` contém **exatamente** cinco chaves
e nenhuma delas é `'idade'`, `'genero'`, `'consentimento_lgpd_aceito_em'` ou `'anonimizado_em'`
— é o teste que trava D-006 contra um "só mais um campinho" futuro.

**Não coberto por teste automatizado**, e declarado como tal no `quickstart.md`: SC-002 (menos
de 1 minuto para corrigir o nome) e SC-003 (zero pedidos por e-mail para o que a tela cobre).
São medidas de gente usando o app; virar teste seria fingir que medem.
