# Quickstart: Cadastro de Perfil e Upgrade para Conta

## Pré-requisitos

- Flutter 3.x instalado (`flutter --version`)
- Projeto Supabase (local via `supabase start`, ou um projeto na nuvem) com a
  CLI do Supabase instalada
- `.env` do app com `SUPABASE_URL` e `SUPABASE_ANON_KEY`

## Setup

```bash
supabase start                      # sobe Postgres+Auth+API local
supabase db reset                   # aplica supabase/migrations/*.sql + seed.sql
flutter pub get
```

## Rodar o app

```bash
flutter run
```

## Roteiro de validação (mapeado às Acceptance Scenarios da spec)

1. **Criar Perfil sem e-mail/senha** (US1, cenário 1): abrir o app pela
   primeira vez, preencher nome/gênero/idade (≥18), aceitar consentimento
   LGPD, deixar Igreja e telefone em branco → confirma tela inicial do app.
2. **Bloqueio sem consentimento** (US1, cenário 2): repetir sem marcar o
   consentimento LGPD → botão de concluir permanece bloqueado.
3. **Nome com palavrão** (US1, cenário 3): digitar um nome da lista de
   `palavras_bloqueadas` do seed → erro de validação antes de prosseguir.
4. **Persistência entre sessões** (US1, cenário 5 / SC-004): fechar o app
   totalmente e reabrir → volta direto pro app, sem tela de cadastro, em
   menos de 5s.
5. **Apelido obrigatório para menor** (US2): repetir o cadastro com idade <18
   → tela de Apelido aparece como etapa obrigatória antes de concluir.
6. **Apelido substitui nome em exibição pública** (US2, cenário 2): validar
   via `select * from perfil_publico('<id-do-menor>')` no SQL editor local —
   `nome_exibido` deve ser o Apelido, e a função não deve expor `idade`.
7. **Upgrade pra Conta preserva o id** (US3): no app, usar a opção de virar
   Conta, vincular e-mail+senha. Conferir no banco:
   `select id, is_anonymous from auth.users` — mesmo `id` de antes,
   `is_anonymous` agora `false`.
8. **Login em outro aparelho recupera o Perfil** (US3, cenário 2): em um
   segundo emulador/dispositivo, logar com a credencial vinculada → mesmo
   nome/Apelido/dados aparecem.
9. **Credencial errada não vaza detalhe** (US3, cenário 3): tentar login com
   senha errada → mensagem genérica, sem indicar se o e-mail existia.

## Verificação de privacidade (SC-003)

```sql
-- Como um papel autenticado que NÃO é o dono, isto deve retornar 0 linhas:
select * from public.perfis where id <> auth.uid();

-- Isto nunca deve incluir "idade" no resultado:
select * from public.perfil_publico('<qualquer-id>');
```

## Resultados da validação (2026-07-23)

Cenários 1-9 automatizados e verdes (27/27 testes, `flutter test`, contra
Postgres+Auth local via `supabase start`):

- US1 (cenários 1-5): `test/integration/perfis_constraints_test.dart`,
  `test/integration/nome_valido_test.dart`, `test/unit/perfil_model_test.dart`,
  `test/widget/cadastro_perfil_page_test.dart`
- US2 (cenários 1-3): `test/integration/apelido_obrigatorio_test.dart`,
  `test/integration/perfil_publico_apelido_test.dart` (inclui a query de
  privacidade acima, executada contra o banco de verdade — 0 linhas vazadas)
- US3 (cenários 1-3): `test/integration/upgrade_conta_test.dart`,
  `test/integration/login_erro_generico_test.dart`,
  `test/widget/upgrade_conta_page_test.dart`

`flutter build macos --debug` confirma que o app compila e empacota de
ponta a ponta (não só passa no analyzer).

**Lacuna conhecida — SC-001 e SC-004 (tempo de cadastro <2min, reabertura
<5s)**: não foram medidos com cronômetro em dispositivo real nesta sessão —
o ambiente de execução não tem display disponível pra rodar o app
interativamente (`flutter run`/screenshot falharam por falta de sessão
gráfica). Os testes automatizados confirmam a *funcionalidade* (bloqueio de
consentimento, moderação de nome, persistência via sessão anônima, Apelido
obrigatório, upgrade preservando `auth.uid()`), mas a métrica de tempo em
uso real por uma pessoa fica pendente de QA manual num dispositivo/simulador
com tela.
