# Implementation Plan: Meu Perfil — ver e corrigir os próprios dados

**Branch**: `016-meu-perfil` | **Date**: 2026-08-09 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/016-meu-perfil/spec.md`

## Summary

O app guarda nome, Apelido, Igreja de origem, telefone, gênero, idade e a data do
consentimento LGPD de cada Usuário, e não oferece nenhum lugar onde ele veja ou corrija isso
— a própria Política de Privacidade manda escrever um e-mail
(`lib/features/legal/presentation/privacy_policy_page.dart:170-179`). Esta feature entrega a
tela `/perfil`: mostra tudo que está gravado sobre a pessoa e deixa corrigir nome, Apelido,
Igreja de origem e telefone.

Abordagem técnica: **cliente puro, nenhuma migration**. A permissão de escrita já existe e
nunca foi consumida — `perfis_update_own`
(`supabase/migrations/20260723191202_perfis_igrejas.sql:76-79`), com `grant ... update on
public.perfis to authenticated` na linha 56 do mesmo arquivo. Confirmado que ela basta
(prova em [research.md](./research.md), D-001). A tela grava com **um único `UPDATE`**, o que
resolve FR-012 (nada pela metade) sem transação, sem RPC e sem orquestração no cliente. As
regras que o cadastro já aplica — moderação de nome, Apelido obrigatório para menor,
consentimento destacado de Igreja — não são reimplementadas: passam a viver num lugar só
(`Profile`, `NameModeration`, `profileErrorMessage`) e as duas telas consomem o mesmo lugar.

## Technical Context

**Language/Version**: Dart / Flutter, SDK `^3.12.2` (`pubspec.yaml`)

**Primary Dependencies**: `flutter_riverpod ^3.3.2` (estado), `go_router ^17.3.0` (navegação),
`supabase_flutter ^2.8.0` (PostgREST). `mocktail` e `postgres` em teste. **Nenhuma dependência
nova.**

**Storage**: `public.perfis` no Supabase — tabela que já existe, **sem alteração de schema**.
Leitura pela policy `perfis_select_own`, escrita pela policy `perfis_update_own`, ambas de
2026-07-23.

**Testing**: `flutter_test` + `mocktail` (unit/widget), `package:test` + `package:postgres`
contra Supabase local (integração). Gates de CI em `.github/workflows/ci.yml`: `flutter
analyze`, `flutter test test/unit test/widget`, `dart test test/integration`, `flutter build
web`. **Esta feature roda os quatro** — diferente da 010, ela toca regra de banco (RLS e
constraints em `UPDATE`), então `dart test test/integration` é obrigatório.

**Target Platform**: Flutter multiplataforma; o alvo em deploy hoje é **web**
(`deploy-web.yml`) e Android/iOS. Que o alvo seja web importa aqui: a rota `/perfil` é
digitável na barra de endereço, então o gate de "Visitante sem Perfil" (FR-005) tem de estar
no `redirect` do router, não só no botão que leva à tela.

**Project Type**: app Flutter organizado por feature em `lib/features/<nome>/` com subpastas
`domain/`, `data/`, `presentation/`.

**Performance Goals**: nenhuma meta específica. Um `select` e um `update` de uma linha só,
por chave primária.

**Constraints**:
- **Nenhuma migration** (`Assumptions` da spec). Se a permissão existente não bastasse, o
  plano inteiro mudaria — por isso D-001 do research é a primeira coisa verificada.
- **Nada pela metade** (FR-012 / SC-005): a escrita é uma instrução só.
- **Mesma regra e mesma mensagem do cadastro** (FR-008): duplicar a lista de palavras ou o
  texto de erro seria cumprir a letra e quebrar o requisito na primeira divergência.
- **Idade e gênero não são editáveis** (Assumptions da spec) — mas **são exibidos** (FR-002).

**Scale/Scope**: 1 tela nova, 1 rota nova, 1 provider novo, 2 métodos novos de repositório.
~9 arquivos de produção tocados, 3 de teste. Distrito de 15+ igrejas.

## Constitution Check

*GATE: avaliado antes da Fase 0 e reavaliado após a Fase 1. Constituição v1.1.0.*

| Princípio | Veredito | Evidência / como será cumprido |
|-----------|----------|-------------------------------|
| **I. Linguagem Ubíqua do Domínio** | ✅ PASS | Todo identificador novo em **inglês**, nomeado explicitamente nas tarefas: `MyProfilePage` (arquivo `my_profile_page.dart`), `myProfileProvider`, `ProfileRepository.fetchMyProfile` / `updateMyProfile`, `Profile.fromMap` / `toUpdateMap`, campos `lgpdConsentAcceptedAt` / `churchLgpdConsentAcceptedAt`, função `profileErrorMessage`, const `NameModeration.cached`. Em teste também: `MockProfileRepository`, `pumpMyProfilePage`, `saveButton`, `testChurch`, `asUser` — só o **nome do arquivo** de teste fica em português (`meu_perfil_page_test.dart`, `perfil_edicao_rls_test.dart`). Continuam em português: as chaves de banco (`map['nome']`, `'apelido'`, `'igreja_id'`, `'telefone'`, `'consentimento_lgpd_aceito_em'`, `'consentimento_lgpd_igreja_aceito_em'`), toda string de UI e todo comentário. Termos de UI só do glossário — **Perfil**, **Apelido**, **Igreja de origem**, **Usuário**; nada de "conta", "cadastro completo". Nenhum termo novo: `CONTEXT.md` não muda. Os arquivos tocados (`profile.dart`, `name_moderation.dart`, `profile_repository.dart`, `profile_signup_page.dart`, `app.dart`, `providers.dart`) já passaram pela tradução da feature 012 — não há passe de tradução pendente neles. |
| **II. Privacidade e LGPD por Padrão** | ✅ PASS | **Nenhum dado pessoal novo é coletado** — a feature só devolve ao titular o que já é dele (LGPD art. 18, II e III). A exposição **não aumenta**: a tela lê `perfis` direto, e `perfis_select_own` (`20260723191202:66-69`) restringe a linha ao `auth.uid()`; a projeção pública de terceiros (`perfil_publico`, que já esconde idade e telefone) não é tocada, e a regra de exibir menor por Apelido continua intacta. Campos opcionais continuam opcionais **na edição também** (FR-010) — sem exigência disfarçada. `consentimento_lgpd_aceito_em` **nunca é reescrito** pela tela (D-006): sobrescrevê-lo apagaria o registro da base legal. Revogar a Igreja de origem zera também `consentimento_lgpd_igreja_aceito_em` (D-005), para não deixar consentimento órfão de finalidade. **Dívida registrada, não introduzida aqui**: o `grant` da linha 56 é de tabela inteira, sem recorte de coluna — via chamada direta o Usuário consegue escrever colunas do **próprio** Perfil que a tela não oferece (`idade`, `genero`, `consentimento_lgpd_aceito_em`). Existe desde 2026-07-23, é anterior a esta feature, e corrigir exigiria migration — o que a spec exclui. Ver "Riscos", item 3. |
| **III. Desenvolvimento Guiado por Spec** | ⚠️ PASS com ressalva | `spec.md` escrita e validada (`checklists/requirements.md`, 21/21). **`/speckit-clarify` não foi executado.** A única ambiguidade real que a spec deixa aberta — "Idade e gênero: são editáveis?", nos Edge Cases — já vem **resolvida em Assumptions** ("Idade e gênero fora do escopo de edição"), então não há regra de negócio decidida ad-hoc aqui. As demais decisões desta fase são de implementação, e estão em `research.md` com a alternativa descartada. |
| **IV. Integridade das Regras de Domínio Testada** | ✅ PASS (nenhuma regra do Princípio IV é tocada) | A feature não encosta em fila de espera, apuração/desempate de Rodada, revogação de voto ou de Participar, descarte de candidatas nem composição de Dupla Missionária. **Ponto de contato a vigiar**: gênero valida a composição de Dupla Missionária, e é exatamente por isso que ele **não é editável** — se fosse, uma Dupla já formada poderia virar inválida sem nada recalcular. É a razão técnica por trás da Assumption da spec. Nome alterado propaga sozinho para listas de participantes e confirmados, porque todas leem via `perfil_publico` a cada chamada (`group_repository.dart:74`, `action_repository.dart:109`) — não há cópia a sincronizar. As regras que **esta** feature tem ganham teste executável antes de pronto: RLS de Perfil alheio, `nome_valido` no `UPDATE`, `apelido_obrigatorio_menor` no `UPDATE`, `consentimento_igreja_destacado` no `UPDATE` (integração), e a atomicidade em widget test. |
| **V. Simplicidade e Papéis Mínimos** | ✅ PASS | Nenhum papel novo, nenhuma permissão nova — a feature **consome** uma policy que já existe, não cria nenhuma. Nenhuma dependência nova, nenhuma migration, nenhuma RPC nova, nenhuma entidade nova. Um provider novo (`myProfileProvider`) e uma tela. A escrita é um `UPDATE` direto, não uma função de banco: RPC só se justifica quando há mais de uma tabela ou regra a orquestrar numa transação (o caso de `excluir_minha_conta`), e aqui há uma linha e uma tabela. Sem confirmação em duas etapas (Assumption da spec): corrigir o próprio nome não é destrutivo. |

**Complexity Tracking**: nenhuma violação a justificar — a tabela foi removida.

## Project Structure

### Documentation (this feature)

```text
specs/016-meu-perfil/
├── spec.md              # Fase anterior (/speckit-specify)
├── plan.md              # Este arquivo
├── research.md          # Fase 0 — 8 decisões, com a alternativa descartada
├── data-model.md        # Fase 1 — o contrato coluna-a-coluna da tela
├── quickstart.md        # Fase 1 — como provar que funciona
├── checklists/
│   └── requirements.md  # Fase anterior
└── tasks.md             # Fase 2 (/speckit-tasks)
```

**`contracts/` não é gerado**, e o motivo é o achado central da feature: **não há contrato
novo**. Nenhuma migration, nenhuma coluna, nenhuma constraint, nenhuma RPC, nenhum `grant`,
nenhuma policy. O contrato que esta tela consome já está escrito e vigente em
`specs/001-cadastro-usuario/contracts/schema.sql` e aplicado em
`supabase/migrations/20260723191202_perfis_igrejas.sql` (+ `20260724140000` e
`20260806140000`). Criar um `contracts/schema.sql` com o SQL copiado seria uma segunda fonte
de verdade para o mesmo objeto — o pior resultado possível para um arquivo chamado
"contrato".

**`data-model.md` é gerado**, apesar de a spec dizer "Nenhuma entidade nova" — e ela está
certa. O arquivo não descreve entidade: descreve o **recorte** que a tela faz sobre `perfis`,
coluna por coluna — o que é exibido, o que é editável, o que é exibido mas nunca escrito, e o
que a tela nunca toca. É onde moram as três armadilhas desta feature (não reescrever
`consentimento_lgpd_aceito_em`, não escrever `idade`/`genero`, o que fazer com
`consentimento_lgpd_igreja_aceito_em` ao trocar ou remover a Igreja), e sem ele elas ficariam
espalhadas em comentários.

### Source Code (repository root)

```text
lib/
├── app.dart                                         # ALTERADO: rota /perfil + redirect
│                                                    #   de Visitante sem Perfil (FR-005)
├── core/
│   └── providers.dart                               # ALTERADO: myProfileProvider
└── features/
    ├── profile/
    │   ├── domain/
    │   │   ├── profile.dart                         # ALTERADO: Profile.fromMap,
    │   │   │                                        #   toUpdateMap, lgpdConsentAcceptedAt,
    │   │   │                                        #   age/gender nullable (D-003)
    │   │   ├── name_moderation.dart                 # ALTERADO: NameModeration.cached —
    │   │   │                                        #   a lista sai de dentro da tela
    │   │   └── profile_error_message.dart           # NOVO: profileErrorMessage(), a
    │   │                                            #   mesma mensagem nas duas telas
    │   ├── data/
    │   │   └── profile_repository.dart              # ALTERADO: fetchMyProfile,
    │   │                                            #   updateMyProfile
    │   └── presentation/
    │       ├── my_profile_page.dart                 # NOVO: a tela inteira
    │       └── profile_signup_page.dart             # ALTERADO: consome a lista e a
    │                                                #   mensagem compartilhadas
    ├── home/presentation/home_page.dart             # ALTERADO: caminho para /perfil (FR-006)
    └── legal/presentation/privacy_policy_page.dart  # ALTERADO: as duas frases saem (FR-014)

test/
├── unit/profile_model_test.dart                     # ALTERADO: fromMap/toUpdateMap
├── widget/meu_perfil_page_test.dart                 # NOVO
└── integration/perfil_edicao_rls_test.dart          # NOVO: RLS e constraints no UPDATE
```

**Structure Decision**: mantida a organização por feature. A tela entra em
`lib/features/profile/presentation/`, junto de `profile_signup_page.dart`,
`delete_account_page.dart` e `upgrade_account_page.dart` — é a mesma feature de domínio
(Perfil), não uma nova. Nenhuma pasta nova é criada. `profile_error_message.dart` vai para
`domain/` e não para `presentation/`: a tradução de violação de constraint em frase para o
Usuário é conhecimento sobre a regra, e precisa ser alcançável pelas duas telas sem que uma
importe a outra.

## Interação com as features abertas em paralelo

### 017 — versão do consentimento (dependência real, registrada)

`specs/017-versao-do-consentimento/spec.md` já registra a interação, nas Assumptions e nos
Edge Cases: *"dar o consentimento de Igreja pela tela de perfil registra a versão daquele
momento, que pode diferir da do cadastro. São dois aceites distintos, e é correto que tenham
versões distintas."*

Consequência concreta para esta feature: quando o Usuário escolhe uma Igreja de origem pela
primeira vez **na tela de edição**, ele está dando um consentimento destacado novo (FR-011) —
e todo consentimento novo precisa carregar a versão do texto aceito (017, FR-001/FR-003).

| Ordem | O que acontece |
|---|---|
| **016 antes de 017** (ordem esperada, a 016 é a menor) | A 016 grava `consentimento_lgpd_igreja_aceito_em` sem versão, exatamente como o cadastro faz hoje. Não piora nada: é o mesmo comportamento do único caminho existente. A 017 entra depois e passa **os dois** caminhos a gravar a versão. |
| **017 antes de 016** | A 016 nasce já gravando a versão, pelo mecanismo que a 017 tiver criado. Atenção ao FR-004 da 017: a versão tem de ser gravada **pelo banco ou pelo servidor**, não por valor que o cliente envia — então provavelmente será um `default`/trigger, e `Profile.toUpdateMap()` **não** deve enviar a coluna de versão. |

**Ponto de conflito de arquivo**: a 017 mexe no mesmo caminho de escrita — `profile.dart`
(`toInsertMap`, e agora `toUpdateMap`) e `profile_repository.dart`. Conflito provável, e
resolvível: se a versão vier de `default` no banco, `toUpdateMap()` continua exatamente como
esta feature o deixa. **Registrar como tarefa da 017, não desta**: verificar que o `UPDATE` da
tela de perfil também carimba a versão.

### 015 — consentimento do responsável: não há interação nesta versão

A spec já fecha o assunto: a interação existiria se a idade fosse editável (baixar a idade
para faixa de criança exigiria a autorização do responsável), e **idade não é editável aqui**.
Se um dia virar feature própria, essa é a primeira regra a reabrir.

### 018 e as demais

`018-visibilidade-de-liderancas` não toca `perfis` nem a Política de Privacidade. Sem conflito
previsto.

## Riscos e decisões que precisam de olho

1. **A tela é alcançável por URL** (o app está em deploy web). Um gate só no botão que leva a
   `/perfil` não cumpre FR-005 — quem digitar `/perfil` sem Perfil chegaria a uma tela que
   tenta ler uma linha inexistente. Por isso o redirect entra em `lib/app.dart`, junto dos
   dois que já existem (linhas 58 e 62). O `ProfileGuard.requireProfile` continua sendo usado
   no botão, mas é conforto, não garantia.
2. **`publicProfileProvider` é `autoDispose.family` e fica em cache** enquanto uma tela o
   observa (`group_detail_page.dart:159`, `create_action_page.dart:245`,
   `create_candidate_page.dart:229`). Trocar o nome e voltar para uma dessas telas sem
   invalidar o provider mostra o nome antigo — que é literalmente o cenário 1 da US2 falhando,
   sem erro nenhum, sem teste vermelho. Salvar precisa invalidar `publicProfileProvider` e
   `myProfileProvider`. Os repositórios de Grupo e Ação chamam `perfil_publico` a cada
   carregamento e não guardam cópia, então esses não precisam de nada.
3. **O `grant` de `perfis` é de tabela inteira** (`20260723191202:56`), sem recorte de coluna.
   `perfis_update_own` protege a linha (Perfil alheio — FR-013 e SC-004 estão cobertos), mas
   **não** protege coluna: por chamada direta, o Usuário consegue escrever `idade`, `genero` e
   `consentimento_lgpd_aceito_em` do **próprio** Perfil. É anterior a esta feature e nenhum FR
   pede o conserto; consertar exigiria migration, o que a spec exclui. **Fica registrado aqui
   como dívida de segurança conhecida**, com o conserto identificado (revogar o `update` amplo
   e reemitir `grant update (nome, apelido, igreja_id, telefone,
   consentimento_lgpd_igreja_aceito_em)`), para virar feature própria — não some por
   conveniência.
4. **`idade` e `genero` são nulos em Perfil anonimizado** desde `20260806140000:45-46`. A tela
   não deveria alcançar essa linha (sem `auth.users`, sem sessão), mas há um caminho estreito:
   `deleteMyAccount()` chama a RPC e **depois** `signOut()`; se o `signOut()` falhar, o JWT
   emitido continua válido até expirar e a sessão ainda aponta para a linha anonimizada. Por
   isso o modelo lê `idade`/`genero` como nulos toleráveis em vez de estourar (D-003).
5. **A moderação de nome tem duas metades** e as duas precisam continuar valendo na edição: a
   lista cacheada no cliente, hoje literal dentro de `profile_signup_page.dart:31`, e a
   constraint `check (nome_valido(nome))` no banco, que o Postgres reavalia em `UPDATE`
   também. Copiar a lista para a tela nova é a forma mais fácil de quebrar FR-008 seis meses
   depois, quando uma das duas cópias for atualizada. Por isso ela sai da tela e vira
   `NameModeration.cached` (D-004).

## Fase 0 — Pesquisa

Concluída. Ver [research.md](./research.md): 8 decisões, cada uma com a alternativa descartada.
A que sustenta o plano inteiro é a **D-001** — a verificação de que `perfis_update_own` basta
e nenhuma migration é necessária, com a citação do comportamento do Postgres para política de
`UPDATE` sem `with check`.

Nenhum `NEEDS CLARIFICATION` restante no Technical Context.

## Fase 1 — Design

Concluída. Ver [data-model.md](./data-model.md) (o recorte coluna-a-coluna que a tela faz
sobre `perfis`) e [quickstart.md](./quickstart.md) (gates com os números da base em `main`, o
que cada teste prova, e as checagens que só gente resolve).

`contracts/` não se aplica (justificado em Project Structure).

**Constitution Check pós-design**: reavaliado, sem mudança. Os cinco princípios continuam
PASS, com a mesma ressalva no Princípio III. O design não introduziu papel, permissão,
dependência, entidade nem dado pessoal novo — e, o mais importante para o Princípio V, não
introduziu migration: confirmou-se que não era preciso.
