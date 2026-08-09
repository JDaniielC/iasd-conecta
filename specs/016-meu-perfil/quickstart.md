# Quickstart — validar "Meu Perfil"

**Feature**: 016-meu-perfil | **Date**: 2026-08-09

Como provar que a feature funciona. Três partes: os gates que a máquina roda, o que cada teste
prova, e o que só gente resolve.

## Pré-requisitos

```bash
cd /Users/jdsc2/projects/iasd
cp .env.example .env      # só se .env ainda não existir
flutter pub get
supabase start            # necessário: esta feature roda testes de integração
```

## Parte 1 — Gates automatizados

Os mesmos quatro comandos de `.github/workflows/ci.yml`. **Todos os quatro** — diferente da
feature 010, esta toca regra de banco (RLS e constraints em `UPDATE`), então integração não é
opcional.

```bash
flutter analyze
flutter test test/unit test/widget
dart test test/integration
flutter build web
```

### Base em `main`, para comparar

| Gate | Base em `main` | Depois desta feature |
|---|---|---|
| `flutter analyze` | **0 issues** | 0 issues |
| `flutter test test/unit test/widget` | **152 passando** | 152 + os novos |
| `dart test test/integration` | **127 passando** | 127 + os novos |
| `flutter build web` | ✅ | ✅ |

**Anotar o número real** em cada um ao fechar a feature. "Os testes passaram" sem número não
é verificação — é uma frase.

### O que cada teste prova

**Unidade — `test/unit/profile_model_test.dart` (ampliado)**

| Teste | Requisito |
|---|---|
| `Profile.fromMap` lê nome, Apelido, Igreja, telefone, gênero, idade e a data do consentimento | FR-002, SC-001 |
| `Profile.fromMap` aceita `idade` e `genero` nulos (Perfil anonimizado) sem estourar | research D-003 |
| `toUpdateMap()` tem exatamente 5 chaves e **nenhuma** delas é `'idade'`, `'genero'`, `'consentimento_lgpd_aceito_em'` ou `'anonimizado_em'` | Assumptions da spec, research D-006 |
| `toUpdateMap()` converte Apelido e telefone vazios em `null`, nunca `''` | FR-009, FR-010 |
| Trocar de Igreja carimba `consentimento_lgpd_igreja_aceito_em`; manter a mesma não recarimba; remover zera | FR-011, research D-005 |

**Widget — `test/widget/meu_perfil_page_test.dart` (novo)**

| Teste | Requisito |
|---|---|
| Os sete campos aparecem, com os rótulos do glossário | FR-001, FR-002, SC-001 |
| Apelido/telefone/Igreja vazios aparecem como vazios explícitos, não como espaço ambíguo | FR-003 |
| A tela monta com override só de `myProfileProvider` e `churchesProvider` — não consulta nada de terceiro | FR-004 |
| Nome recusado pela moderação mostra **a mesma frase** do cadastro (`Esse nome não pode ser usado. Tente outro.`) | FR-008 |
| Perfil de menor: esvaziar o Apelido desabilita "Salvar" | FR-009 |
| Esvaziar o telefone mantém "Salvar" habilitado, e `updateMyProfile` recebe `null` | FR-010 |
| Escolher Igreja faz aparecer a caixa destacada e desabilita "Salvar" até marcá-la | FR-011 |
| Falha ao salvar: aviso aparece, `myProfileProvider` **não** é invalidado, os valores exibidos continuam os antigos | FR-012, SC-005 |
| Salvar com sucesso invalida `myProfileProvider` **e** `publicProfileProvider` | US2 cenário 1, risco 2 do plano |

**Integração — `test/integration/perfil_edicao_rls_test.dart` (novo)**

| Teste | Requisito |
|---|---|
| Usuário A tenta alterar o Perfil de B: 0 linhas afetadas, o Perfil de B continua intacto | FR-013, SC-004 |
| Usuário A tenta reatribuir o próprio Perfil para o `id` de B: recusado (o `using` de `perfis_update_own` vale também para a linha nova) | FR-013, SC-004 |
| `UPDATE` com nome contendo palavra bloqueada: recusado | FR-008 |
| `UPDATE` esvaziando o Apelido de menor: recusado | FR-009 |
| `UPDATE` pondo `igreja_id` sem `consentimento_lgpd_igreja_aceito_em`: recusado | FR-011 |
| Depois de cada recusa acima, a linha está **byte a byte** como antes | FR-012, SC-005 |
| `UPDATE` legítimo do próprio Perfil é aceito e altera as 5 colunas de uma vez | FR-007, FR-012 |

**Política de Privacidade — `test/widget/`**

| Teste | Requisito |
|---|---|
| As frases `ainda não existe uma tela própria` e `enquanto não existe tela de edição de perfil` **não** aparecem em lugar nenhum da página | FR-014, SC-006 |
| A página aponta para "Meu Perfil" dentro do app | FR-014 |

**Router**

| Teste | Requisito |
|---|---|
| Sem Perfil, `/perfil` redireciona para `/cadastro` | FR-005 |
| Com Perfil, `/perfil` constrói `MyProfilePage` | FR-001 |

## Parte 2 — Verificação manual

```bash
flutter run -d chrome        # web, o alvo em deploy hoje
```

| # | Checagem | Requisito | Como fazer | Esperado |
|---|---|---|---|---|
| 1 | A tela existe e mostra tudo | FR-001, FR-002, SC-001 | Com Perfil, chegar a "Meu Perfil" pela Home | Nome, Apelido, Igreja de origem, telefone, gênero, idade e data do consentimento, todos visíveis |
| 2 | Conferir contra o banco | SC-001 | `select * from public.perfis where id = '<uid>'` no Supabase local | Cada coluna pessoal da linha tem correspondente na tela. Nenhuma sobra |
| 3 | Campo opcional vazio | FR-003 | Perfil sem Apelido, sem telefone e sem Igreja | Cada um aparece explicitamente vazio, não como espaço em branco ambíguo |
| 4 | **Digitar a URL sem Perfil** | FR-005 | Apagar o armazenamento local do navegador e ir direto para `/perfil` | Cai em `/cadastro`. **Se abrir a tela, o gate está só no botão** — é o risco 1 do plano |
| 5 | Caminho pela navegação | FR-006 | Abrir o app com Perfil | "Meu Perfil" alcançável a partir da Home, rotulado em texto |
| 6 | **Corrigir o nome e ver propagar** | US2 cenário 1, risco 2 do plano | Abrir um Grupo de que participa e olhar seu nome na lista → voltar → corrigir o nome em "Meu Perfil" → salvar → voltar ao **mesmo** Grupo | O nome novo aparece. Se aparecer o antigo, faltou invalidar `publicProfileProvider` |
| 7 | Limpar o telefone | FR-010 | Apagar o telefone e salvar; conferir no banco | `telefone` é `null`, não `''` |
| 8 | Menor de idade | FR-009 | Com um Perfil de idade < 18, apagar o Apelido | "Salvar" desabilita, com a mensagem do cadastro |
| 9 | Igreja pela primeira vez | FR-011 | Escolher uma Igreja de origem | A caixa destacada aparece desmarcada e "Salvar" fica desabilitado até marcá-la |
| 10 | Trocar de Igreja | FR-011, research D-005 | Trocar para outra Igreja | A caixa **volta a aparecer desmarcada** — o consentimento anterior não vale para a igreja nova |
| 11 | Manter a Igreja | research D-005 | Corrigir só o telefone, sem mexer na Igreja; conferir no banco antes e depois | `consentimento_lgpd_igreja_aceito_em` **não muda** |
| 12 | Remover a Igreja | research D-005 | Tirar a Igreja de origem e salvar; conferir no banco | `igreja_id` e `consentimento_lgpd_igreja_aceito_em` **ambos** `null` |
| 13 | **Nada pela metade** | FR-012, SC-005 | Anotar a linha do banco → DevTools → Network → Offline → mudar nome, Apelido e telefone → Salvar | Aviso visível, sem tela quebrada; a linha no banco **idêntica** à anotada. Reconectar e salvar de novo funciona |
| 14 | Data do consentimento intacta | FR-002, Princípio II | Anotar `consentimento_lgpd_aceito_em` → corrigir o nome → salvar → conferir | **Não mudou.** Se mudou, `toUpdateMap()` virou `toInsertMap()` |
| 15 | Política de Privacidade | FR-014, SC-006 | Ler a seção "Seus direitos e como usar cada um" | Nenhuma frase dizendo que a tela não existe; ela indica "Meu Perfil" |
| 16 | Nenhum dado de terceiro | FR-004 | Olhar a tela inteira | Só os próprios dados. Nenhum nome, contagem ou lista de outra pessoa |

### Verificação de RLS por fora do app (SC-004)

Vale fazer uma vez à mão, porque é o único requisito que fala explicitamente de "chamada
direta que não passe pela tela":

```sql
-- No Postgres local (porta 54322), fingindo ser o Usuário A:
set role authenticated;
set request.jwt.claims to '{"sub":"<uid-de-A>","role":"authenticated"}';
update public.perfis set nome = 'Invadido' where id = '<uid-de-B>';   -- 0 linhas
update public.perfis set id   = '<uid-de-B>' where id = '<uid-de-A>'; -- recusado
reset role; reset request.jwt.claims;
```

## Parte 3 — O que nenhum comando verifica

Registrado, não escondido. Os dois viram tarefa aberta em `tasks.md`, não desaparecem.

| Critério | Por que não dá para automatizar | Como medir de verdade |
|---|---|---|
| **SC-002** — corrigir o próprio nome em menos de 1 minuto | É tempo de pessoa usando o app, não de código rodando. Cronometrar o `pumpAndSettle` mediria a máquina | Cronometrar 3 pessoas que nunca viram a tela, do abrir o app até o nome corrigido. Se passar de 1 minuto, o caminho até `/perfil` é o suspeito |
| **SC-003** — 0 pedidos de acesso/correção por e-mail para o que a tela cobre | Depende da caixa de entrada de `jdaniielc@gmail.com`, fora do repositório | Conferir a caixa 30 dias depois do lançamento. Pedido que chegar sobre nome, Apelido, Igreja ou telefone é sinal de que a tela não foi encontrada — problema de FR-006, não de FR-007 |

## Definição de pronto

- [ ] Parte 1 verde, com os quatro números reais anotados e comparados com a base (0 / 152 / 127 / ✅)
- [ ] Parte 2, itens 1 a 16, conferidos
- [ ] Item 4 conferido especificamente — é o gate que passa despercebido em app web
- [ ] Item 6 conferido especificamente — é o bug silencioso do cache de `publicProfileProvider`
- [ ] Item 14 conferido especificamente — é o dado de base legal
- [ ] `git status` em `supabase/migrations/` **limpo**: se nasceu migration, a premissa da feature caiu e o plano precisa voltar
- [ ] `CONTEXT.md` **não** precisou de alteração (nenhum termo novo de domínio)
- [ ] SC-002 e SC-003 registrados como abertos, com quem vai medir
