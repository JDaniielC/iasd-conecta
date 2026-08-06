# Implementation Plan: Exclusão de conta

**Branch**: `009-exclusao-de-conta` | **Date**: 2026-08-06 | **Spec**: [spec.md](./spec.md)

**Input**: Feature specification from `/specs/009-exclusao-de-conta/spec.md`

## Summary

Uma função `excluir_minha_conta()` `SECURITY DEFINER`, chamada por `rpc()`
a partir de uma tela nova em `lib/features/perfil/`, faz tudo em uma
transação: elege o herdeiro, transfere o que precisa de dono, apaga os
vínculos vivos, anonimiza a linha de `perfis` e apaga o `auth.users`.

Nenhuma tabela nova. As mudanças de schema são três colunas/constraints:
`perfis.anonimizado_em` (nova), `perfis.genero` e `perfis.idade` perdem o
`not null`, e a FK `perfis_id_fkey -> auth.users` é derrubada — sem isso a
linha anonimizada morre junto com o login e a feature inteira não existe.

A ordem das operações dentro da função é a parte não-óbvia, porque três
triggers já existentes reagem a ela: `grupos_dono_deve_participar` (BEFORE
UPDATE) recusa a transferência se o herdeiro ainda não participa;
`confirmacoes_acao_promover_fila` (AFTER DELETE) promove a fila de espera
sozinho, então FR-013 não precisa de código; e
`confirmacoes_acao_decidir_status` (BEFORE INSERT) é o que decide quem entra
como confirmado e quem entra na fila — nenhuma linha desta feature deve
duplicar essa lógica.

O escopo não-código (FR-016: Política de Privacidade e Termos) entra no
mesmo lote, porque hoje eles prometem uma ressalva que deixa de existir.

## Technical Context

**Language/Version**: Dart 3.x (Flutter 3.x stable) — mesmo projeto das
features 001-008

**Primary Dependencies**: as mesmas já usadas; nenhuma dependência nova

**Storage**: Supabase Postgres com RLS — nenhuma tabela nova; uma coluna
nova em `perfis`, dois `not null` relaxados, uma FK derrubada, uma função
`SECURITY DEFINER` nova

**Testing**: mesmo padrão das features anteriores — contrato direto no
Postgres local via `docker exec psql`, depois integração
(`package:postgres`, rodando como role `authenticated`), unit e widget com
`flutter_test`/`mocktail`

**Target Platform**: iOS 13+ / Android 8+ (inalterado)

**Project Type**: mobile-app (mesmo projeto Flutter único)

**Performance Goals**: a exclusão é síncrona e conclui em <5s na percepção
do Usuário (SC-005 pede <1min para o fluxo inteiro, incluindo ler a tela de
confirmação)

**Constraints**:

- `perfis.id` referencia `auth.users(id)` com `on delete cascade`. Enquanto
  essa FK existir, apagar o login apaga o Perfil — o oposto do que a feature
  quer. Derrubar a FK é obrigatório, e a consequência é que `perfis` deixa
  de ter garantia referencial contra `auth.users`. É aceitável porque a
  única escrita em `perfis.id` continua sendo o cadastro, que usa
  `auth.uid()`.
- `grupos_dono_deve_participar` é `BEFORE UPDATE`, e
  `grupos_dono_vira_participante` é `AFTER INSERT` **apenas**. Transferir
  posse por `update` não cria a participação automaticamente: a função tem
  que inserir a participação do herdeiro **antes** de trocar `dono_id`.
- A operação é tudo-ou-nada (FR-015). Uma função PL/pgSQL roda numa
  transação só, então isso sai de graça — desde que nada seja feito em duas
  chamadas separadas a partir do Dart.
- `SECURITY DEFINER` exige `search_path` fixo, seguindo o precedente de
  `20260806090000_nome_valido_security_definer.sql`.
- `perfis` só tem policy de select para o próprio dono
  (`perfis_select_own`); a exibição pública passa por `perfil_publico()`,
  que devolve `coalesce(apelido, nome)` e por isso já mostra
  `'Membro removido'` sem alteração nenhuma.
- `votos` não tem policy de `delete`. Retirar voto (FR-018) só é possível
  de dentro da função `SECURITY DEFINER` — o que é desejável: ninguém apaga
  voto pela API.
- O JWT continua válido até expirar mesmo depois do `auth.users` sumir.
  O cliente Dart precisa chamar `signOut()` logo após a `rpc()`, senão a
  sessão parece viva até a expiração.

**Scale/Scope**: eventos raros (unidades por ano numa comunidade de um
distrito); nenhuma preocupação de volume ou concorrência

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

| Princípio | Situação | Como esta feature atende |
|---|---|---|
| I. Linguagem Ubíqua (NON-NEGOTIABLE) | PASSA | Banco e strings de UI em português (`excluir_minha_conta`, `anonimizado_em`, `'Membro removido'`). Todo artefato Dart **novo** desta feature é em inglês, incluindo nome de arquivo, conforme a Fronteira de idioma da v1.1.0 — a cláusula de tradução gradual vale para arquivo já existente e não isenta arquivo novo. Tradução usada: Perfil→Profile, exclusão de conta→account deletion. `perfil.dart` é tocado por esta feature, então sua tradução é obrigatória; ela sai em commit separado (T006) para não afogar o diff da feature em 211 renomeações. |
| II. Privacidade e LGPD (NON-NEGOTIABLE) | PASSA | É a feature que torna o art. 18, VI exercível. Nenhum dado novo é coletado. `anonimizado_em` é metadado de processo, não dado pessoal. A seção "Dados pessoais tratados" da spec cumpre a exigência de declaração. |
| III. Desenvolvimento Guiado por Spec | PASSA | Spec 009 escrita e validada antes deste plano; a única ambiguidade real (voto em Rodada aberta) foi resolvida como FR-018 antes do plano, não durante a implementação. |
| IV. Integridade das Regras de Domínio Testada (NON-NEGOTIABLE) | PASSA, com atenção | A feature toca quatro das regras listadas no princípio: promoção da fila de espera, revogação de presença, revogação de voto e composição de Dupla Missionária. Todas exigem teste de integração próprio — ver `quickstart.md`. Nenhuma delas é reimplementada: a feature `delete`ia e deixa os triggers existentes agirem. |
| V. Simplicidade e Papéis Mínimos | PASSA | Nenhum papel novo. O herdeiro é o Administrador do distrito que já existe no glossário. Nenhuma generalização especulativa (sem exclusão agendada, sem período de arrependimento, sem exclusão por terceiros). |

**Violações a justificar**: nenhuma. A seção Complexity Tracking fica de
fora.

### Re-check pós-design (Fase 1)

Refeito depois de `data-model.md` e `contracts/schema.sql`. Nenhum princípio
passou a ser violado pelo desenho. Dois pontos ganharam nuance e ficam
registrados:

- **Princípio IV**: o desenho não reimplementa nenhuma das quatro regras que
  toca — fila de espera, revogação de presença, revogação de voto e
  composição de Dupla Missionária. Todas continuam nos triggers existentes; a
  função apenas `delete`ia e deixa o banco reagir. `quickstart.md` cobre as
  quatro com cenário próprio, incluindo o caso 6, que falha alto se a ordem
  das operações regredir.
- **Princípio II**: a queda da FK `perfis_id_fkey` é a única concessão
  estrutural, e ela existe *a serviço* da privacidade, não contra ela — sem
  ela o dado pessoal do titular não pode ser apagado sem destruir histórico
  de terceiros. Consequência e alternativas em `research.md` § 2.

O contrato foi aplicado no Postgres local dentro de uma transação com
`rollback`, e passa: `ALTER TABLE` ×3, `CREATE FUNCTION`, `REVOKE`, `GRANT`.

## Project Structure

### Documentation (this feature)

```text
specs/009-exclusao-de-conta/
├── plan.md              # Este arquivo
├── spec.md              # O quê e por quê
├── research.md          # Fase 0 — decisões técnicas e alternativas
├── data-model.md        # Fase 1 — mudanças de schema e estados
├── quickstart.md        # Fase 1 — como validar de ponta a ponta
├── contracts/
│   └── schema.sql       # Fase 1 — fonte de verdade do schema
├── checklists/
│   └── requirements.md  # Validação da spec
└── tasks.md             # Fase 2 (/speckit-tasks — não criado aqui)
```

### Source Code (repository root)

```text
supabase/migrations/
└── 2026MMDDHHMMSS_exclusao_de_conta.sql   # nova: coluna, not null, FK, função

lib/features/perfil/
├── data/
│   └── perfil_repository.dart              # + deleteMyAccount()
├── domain/
│   └── profile.dart                        # renomeado em T005b; gender/age anuláveis
└── presentation/
    └── delete_account_page.dart            # nova: confirmação explícita

lib/features/legal/presentation/
├── privacy_policy_page.dart                # FR-016: reescrever a ressalva
└── terms_of_use_page.dart                  # FR-016: reescrever a ressalva

lib/app.dart                                 # + rota /delete-account

test/
├── integration/
│   └── account_deletion_test.dart           # nova: regras no banco
├── unit/
│   └── profile_model_test.dart              # ajuste: gender/age anuláveis
└── widget/
    └── delete_account_page_test.dart        # nova: confirmação e recusa
```

**Structure Decision**: a feature mora em `lib/features/perfil/`, que é
onde a conta do próprio Usuário já vive (features 001 e 003). Não se cria
`lib/features/exclusao/` — seria um módulo de um arquivo, e a tela é
naturalmente parte do Perfil. A regra de negócio inteira fica no banco,
como todas as outras deste projeto: o Dart só chama `rpc()` e traduz o erro.
