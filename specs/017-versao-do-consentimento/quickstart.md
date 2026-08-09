# Quickstart — validar a versão do texto aceito no consentimento

**Feature**: 017-versao-do-consentimento | **Date**: 2026-08-09

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start            # sobe Postgres local com as migrations aplicadas
```

## Parte 0 — Duas verificações ANTES de escrever a migration

### 0.a — Quais testes existentes comparam o valor de `consentimento_lgpd_aceito_em`?

O gatilho passa a sobrescrever esse timestamp com o `now()` do banco (risco 3 do plano). Antes
de escrever a migration, varrer o que pode quebrar e **anotar o resultado real**:

```bash
grep -rn "consentimento_lgpd_aceito_em\|consentimento_lgpd_igreja_aceito_em" test/ lib/
```

**Esperado**, pelo levantamento de 2026-08-09 — nenhum destes compara valor, só presença:

```
lib/features/profile/domain/profile.dart:70,71        # grava o sinal de aceite
test/unit/profile_model_test.dart:85,90,94,96          # só isNotNull / isNull
test/integration/db_test_helper.dart:65,113            # semeia com now()
test/integration/perfis_constraints_test.dart:39,80,93 # presença/ausência
```

**Se aparecer alguma assertiva sobre o valor exato**: ela precisa mudar junto, e a mudança é
esperada — não é regressão. Anotar quais.

### 0.b — O estado de partida do banco local

```bash
docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select count(*) from public.perfis;"

docker exec supabase_db_iasd psql -U postgres -d postgres -tAc \
  "select column_name, is_nullable from information_schema.columns \
   where table_name='perfis' and column_name like 'consentimento%';"
```

Serve para provar, depois da migration, que **nenhuma linha existente ganhou versão**
(SC-002): o `count` de `consentimento_lgpd_versao is not null` entre as linhas que já existiam
tem de continuar **0**.

## Parte 1 — Gates automatizados

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration          # exige supabase start
flutter build web
```

**Base em `main`**: 0 issues, **152** unit/widget, **127** integração.
**Resultado esperado**: 0 falhas, e o número de testes **sobe** nas duas suítes. Anotar os
números reais — não "os testes passaram".

**Atenção especial**: os **127** testes de integração existentes devem passar **sem edição**.
Esta feature não toca nenhuma regra do Princípio IV. Se algum precisar mudar, ou vazou do
escopo, ou é uma assertiva de timestamp identificada na Parte 0.a — e nesse caso a Parte 0.a
tinha de ter previsto.

### O que cada teste novo prova

| Teste | Requisito |
|---|---|
| `test/unit/consentimento_versao_test.dart` — `ConsentTally.fromMap` lê `map['tipo']`, `map['versao']`, `map['quantidade']` | fronteira de idioma (chave pt, campo en) |
| `test/unit/consentimento_versao_test.dart` — `consentedVersion == null` ⇒ `isVersionUnknown` verdadeiro; `'1.1'` ⇒ falso | FR-006, FR-007 |
| `test/integration/versao_texto_legal_registro_test.dart` — `versao_texto_legal_vigente()` é igual a `LegalMetadata.version` | **FR-002**, risco 2 do plano |
| `test/integration/versao_texto_legal_registro_test.dart` — `authenticated` não consegue `insert`/`update`/`delete` em `versoes_texto_legal` | FR-004 |
| `test/integration/versao_texto_legal_registro_test.dart` — gravar em `perfis` uma versão inexistente é recusado pela FK | FR-002 |
| `test/integration/consentimento_versao_carimbada_test.dart` — insert de Perfil grava a versão vigente e a data do banco | **FR-001**, SC-001 |
| `test/integration/consentimento_versao_carimbada_test.dart` — insert mandando `consentimento_lgpd_versao = '1.1'` numa base cuja vigente é outra: **o valor do cliente é descartado** | **FR-004** — o teste central da feature |
| `test/integration/consentimento_versao_carimbada_test.dart` — insert mandando `consentimento_lgpd_aceito_em` de três dias atrás: gravado é o `now()` do banco | FR-004, US1 cenário 3 |
| `test/integration/consentimento_versao_carimbada_test.dart` — consentimento de Igreja dado no cadastro grava a versão | **FR-003** |
| `test/integration/consentimento_versao_carimbada_test.dart` — consentimento de Igreja dado depois por `update` grava a versão **daquele instante**; retirá-lo zera data e versão juntas | FR-003, edge case da 016 |
| `test/integration/consentimento_versao_carimbada_test.dart` — publicar uma versão nova no catálogo e cadastrar de novo grava a nova, **sem uma linha de código mudar** | **SC-005** |
| `test/integration/consentimento_versao_desconhecida_test.dart` — Perfil pré-feature continua com versão `null` depois da migration | **FR-007**, SC-002 |
| `test/integration/consentimento_versao_desconhecida_test.dart` — `authenticated` tentando `update` da própria versão numa linha antiga: valor antigo é restaurado, continua `null` | **SC-002** — backfill é impossível, não só desaconselhado |
| `test/integration/consentimento_versao_desconhecida_test.dart` — mudar o `nome` de um Perfil de versão desconhecida funciona e mantém a versão `null` | risco 1 do plano (feature 016) |
| `test/integration/consentimento_versao_desconhecida_test.dart` — `excluir_minha_conta()` funciona sobre Perfil de versão desconhecida, e a linha anonimizada conserva data e versão | **risco 1 do plano — LGPD art. 18, VI** |
| `test/integration/consentimentos_por_versao_test.dart` — quem não é Administrador do distrito recebe exceção | Princípio II / D-004 |
| `test/integration/consentimentos_por_versao_test.dart` — Administrador recebe uma linha por versão, com os `null` contados à parte | **FR-005, FR-006, SC-003** |
| `test/integration/consentimentos_por_versao_test.dart` — nenhuma coluna de identidade é devolvida (`tipo`, `versao`, `quantidade` e mais nada) | **Princípio II** |
| `test/integration/consentimentos_por_versao_test.dart` — Perfil anonimizado não entra na contagem | data-model §4 |
| `test/widget/consentimentos_por_versao_page_test.dart` — a página mostra a contagem por versão e rotula o `null` como "Versão desconhecida", nunca como "0" ou vazio | FR-006, SC-003 |
| `test/widget/consentimentos_por_versao_page_test.dart` — sem nenhum aceite desconhecido, a linha de desconhecida não aparece inventada | FR-006 |

O teste mais importante é o de `excluir_minha_conta` sobre Perfil de versão desconhecida. É ele
que impede esta feature de conformidade de criar um bug de LGPD — a mesma classe de erro que a
feature 011 documentou como risco 1.

**Como semear um Perfil "pré-feature" no teste** (o gatilho impede fazê-lo pelo caminho normal,
que é justamente o ponto): desligar o gatilho como superusuário, gravar a linha com versão
nula, religar. O helper em inglês, o arquivo em português:

```
alter table public.perfis disable trigger perfis_carimbar_consentimento_trigger;
-- update ... set consentimento_lgpd_versao = null ...
alter table public.perfis enable  trigger perfis_carimbar_consentimento_trigger;
```

## Parte 2 — Verificação manual

```bash
flutter run -d chrome
```

| # | Checagem | Requisito | Esperado |
|---|---|---|---|
| 1 | Fazer um cadastro novo, sem escolher Igreja | FR-001, SC-004 | Cadastro conclui igual a hoje; **nenhum campo ou passo novo** na tela |
| 2 | No banco, olhar a linha criada | FR-001 | `consentimento_lgpd_versao` = `1.1`, `consentimento_lgpd_igreja_versao` = `null` |
| 3 | Fazer um cadastro novo escolhendo Igreja e marcando o consentimento destacado | FR-003 | As duas versões preenchidas com `1.1` |
| 4 | Olhar as duas datas gravadas | US1 cenário 3 | Data e versão presentes juntas nas duas colunas |
| 5 | Contar as linhas anteriores à migration | FR-007, SC-002 | Todas com versão `null` — **nenhuma** preenchida |
| 6 | Inspecionar o tráfego do cadastro (DevTools → Network) | FR-004 | O corpo do `insert` **não** contém nenhuma chave de versão. Se contiver, parar: o Dart voltou a mandar valor |
| 7 | Entrar como Administrador do distrito e abrir a lista de Grupos | US2 | O ícone novo aparece ao lado de "Igrejas do Distrito" e "Promover Administrador" |
| 8 | Abrir a tela de versões de consentimento | FR-005, FR-006, SC-003 | Uma linha por versão, e "Versão desconhecida" com a sua contagem, numa tela só |
| 9 | Entrar como Usuário comum e tentar a rota `/district-admin/consentimentos` direto | D-004 | Sem ícone; a rota não entrega dado — a função recusa |
| 10 | Semear `('1.2', now())` no catálogo e cadastrar de novo | SC-005 | O novo cadastro grava `1.2` **sem nenhuma alteração de código**. Desfazer a semeadura depois — senão o gate de `versao_texto_legal_registro_test.dart` passa a falhar, e é isso que ele existe para fazer |
| 11 | Excluir a conta de um Perfil de versão desconhecida | risco 1 | Exclusão conclui normalmente; a linha anonimizada mantém data e versão |
| 12 | Abrir `/privacidade` e `/termos` | FR-009 | Cabeçalho continua "Versão 1.1 — vigente desde 6 de agosto de 2026" |

## Definição de pronto

- [ ] Parte 0.a rodada **antes** da migration, com a lista real de ocorrências anotada
- [ ] Parte 0.b anotada antes e depois — contagem de versões preenchidas em linhas antigas: **0**
- [ ] Parte 1 verde, com o número real de testes de cada suíte (base: 152 e 127)
- [ ] Os **127** testes de integração pré-existentes passando, e as exceções (se houver) sendo
      exatamente as previstas na Parte 0.a
- [ ] O teste de `excluir_minha_conta` sobre versão desconhecida passando
- [ ] Item 6 conferido no tráfego real — é o único jeito de provar que o cliente não manda versão
- [ ] Parte 2, itens 1 a 12, conferidos
- [ ] `MAPA-DE-DADOS.md` atualizado com as duas colunas e com o período dos aceites sem versão
- [ ] O comentário de `lib/features/legal/legal_metadata.dart:4-9` descreve o que passou a
      existir, e não a dívida que deixou de existir
- [ ] `CONTEXT.md` não precisou de alteração (nenhum termo novo de domínio)
