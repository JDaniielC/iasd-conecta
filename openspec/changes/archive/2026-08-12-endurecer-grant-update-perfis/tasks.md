## 1. Levantamento

- [x] 1.1 Listar todas as colunas de `public.perfis` e classificar cada uma:
      gravável pela titular, ou não. Consultar `MAPA-DE-DADOS.md` — a
      classificação já existe lá para fins de LGPD e tem de bater
      — 17 colunas no total (`create table` em `20260723191202_perfis_igrejas.sql:28-39`
      + colunas somadas por `20260724140000`, `20260806140000`, `20260809220000`,
      `20260810000000`). Graváveis pela titular (5): `nome`, `apelido`, `igreja_id`,
      `telefone`, `consentimento_lgpd_igreja_aceito_em` — bate com `MAPA-DE-DADOS.md`
      e com o SQL já proposto em `SECURITY-AUDIT.md` achado 5. Não graváveis (12):
      `id` (PK), `genero`, `idade` (regra de domínio), `consentimento_lgpd_aceito_em`,
      `consentimento_lgpd_versao`, `consentimento_lgpd_igreja_versao` (carimbadas só
      pelo gatilho), `created_at`, `anonimizado_em` (gerenciadas pelo sistema),
      `responsavel_nome`, `responsavel_contato`, `autorizacao_responsavel_em`,
      `autorizacao_responsavel_versao` (dado de terceiro, só-na-criação, protegidas
      também pelo gatilho `perfis_protege_autorizacao_responsavel_trigger`)
- [x] 1.2 Procurar em `lib/` todo ponto que escreve em `perfis` (`.update(`,
      `.upsert(`, `.insert(`) e conferir contra a lista. Um ponto de escrita fora
      da lista é decisão a tomar antes da migration, não bug a descobrir depois
      — único `.update()` como `authenticated` é `profile_repository.dart:50`
      (`toUpdateMap()`, as 5 colunas acima). Único `.insert()` é `profile_repository.dart:60`
      (`toInsertMap()`, cadastro — grant de `insert`, não de `update`, fora do escopo
      desta change). Nenhum `.upsert()` em `perfis`. `excluir_minha_conta`
      (`20260810130000_capa_cancelamento_e_exclusao.sql:17-149`, versão vigente da
      função) é `security definer` — grava `genero`/`idade`/etc ao anonimizar, mas
      roda como dono da função e não é afetada pelo `revoke`/`grant` de `authenticated`.
      Nenhum RPC ou tela de admin escreve `idade`/`genero` de outra pessoa. Nenhum
      ponto de escrita fora da lista encontrado — sem ambiguidade a reportar.

## 2. Migration

- [x] 2.1 `revoke update on public.perfis from authenticated`, seguido de
      `grant update (<colunas graváveis>) on public.perfis to authenticated`
      — `supabase/migrations/20260811160000_grant_update_perfis_por_coluna.sql`
- [x] 2.2 Comentário na migration explicando por que a lista é explícita, e que
      coluna nova nasce sem escrita — é a instrução para quem vier depois
      — mesmo arquivo, cabeçalho completo com a justificativa e a instrução

## 3. Prova

- [x] 3.1 Teste de integração como `authenticated`, com a sessão de uma pessoa
      comum: corrigir `nome` e `telefone` passa
      — reusa o caso (f), já existente em `test/integration/perfil_edicao_rls_test.dart`,
      que grava as 5 colunas juntas (`nome`, `apelido`, `igreja_id`, `telefone`,
      `consentimento_lgpd_igreja_aceito_em`) contra o banco local já com a
      migration aplicada
- [x] 3.2 Mesmo teste: escrever `idade` e escrever `genero` recusam com
      `permission denied`, e o valor anterior permanece
      — casos novos (g)/(h) no mesmo arquivo, cada um asserta
      `ServerException` com `code == '42501'` (permission denied) e que a
      linha lida depois é idêntica à de antes. `dart test
      test/integration/perfil_edicao_rls_test.dart`: **8/8 passaram** (a–h),
      2026-08-11
- [x] 3.3 Rodar o fluxo de edição de Perfil do app contra o banco com a migration
      aplicada — nenhuma tela pode quebrar
      — `dart test test/integration` (banco local, migration aplicada):
      **212/212 passaram**, 0 falhas, 2026-08-11. Achado no caminho: o caso (b)
      de `consentimento_versao_desconhecida_test.dart` (feature 017, não desta
      change) escrevia `consentimento_lgpd_versao` direto e contava com o
      gatilho pra reverter o valor; com o `grant` novo o Postgres recusa a
      cláusula `SET` antes do gatilho rodar (`42501`) — proteção mais forte
      pro mesmo SC-002, teste ajustado para esperar `permission denied` em vez
      de reversão silenciosa. `flutter test test/widget/meu_perfil_page_test.dart
      test/widget/cadastro_perfil_page_test.dart`: **17/17 passaram**, 0 falhas
      (telas de edição e cadastro de Perfil), 2026-08-11

## 4. Registro

- [x] 4.1 Fechar o achado 5 de `SECURITY-AUDIT.md` e o § 2.1 de `PENDENCIAS.md`,
      com a data e o número dos testes que provaram
      — ambos marcados **FECHADO em 2026-08-11** pela change
      `endurecer-grant-update-perfis`, com os números reais: 212/212 testes
      de integração, 17/17 testes de widget das telas de Perfil
