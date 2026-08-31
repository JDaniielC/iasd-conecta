## 1. Identidade própria por arquivo

- [x] 1.1 **Levantado hoje: 19 identificadores em 12 pares de arquivo — não
      16.** A varredura de 2026-08-16 estava certa para aquela data; a
      diferença é real, não erro de varredura: as 4 changes mescladas em
      2026-08-30 (`alcance-do-titular-sobre-texto-proprio`,
      `afirmar-sem-conferir`, `denuncia-como-registro`,
      `observador-de-retencao`) acrescentaram arquivos de teste novos, e um
      deles (`observador_de_retencao_test.dart`) nasceu colidindo com
      `chat_corte_de_idade_test.dart`. Excluído da contagem
      `00000000-0000-0000-0000-000000000000` — não é identidade de teste, é o
      `instance_id` boilerplate de `auth.users`, compartilhado por desenho em
      todo helper que cria usuário fake.
- [x] 1.2 Decidido por par: nos 12 pares, as ocorrências empataram em todos
      (cada uid usado uma vez por arquivo) — desempate por "mais novo"
      (`git log --diff-filter=A`, timestamp do primeiro commit) em todos os
      casos. `consentimentos_por_versao_test.dart` cobria dois pares ao mesmo
      tempo (colidia com dois arquivos diferentes em uids diferentes); um
      prefixo novo resolveu os dois juntos, então são 12 pares mas 11
      arquivos trocados.
- [x] 1.3 Prefixo novo conferido contra toda `test/integration/` (85
      prefixos hexadecimais de 8 dígitos já em uso, listados antes de
      escolher) — os 11 arquivos trocados usam `11000000` a `1b000000`,
      sequenciais e nenhum reaproveitado.
- [x] 1.4 `supabase db reset --local` depois da última troca — limpa tudo,
      inclusive linha órfã com uid antigo que nenhum `tearDownAll` mais
      alcança.
- [x] 1.5 Rodado `dart test test/integration` (575 testes) depois de CADA
      arquivo trocado — 11 rodadas, todas 575/575. 11 commits, um por arquivo
      (dois pares em `consentimentos_por_versao_test.dart` fecharam num commit
      só). `git add` por caminho em todos.

## 2. A verificação que impede a volta

- [x] 2.1 `test/integration/identidade_de_arquivo_test.dart` varre
      `test/integration/*.dart` (não `test/` inteiro — o risco é Postgres
      compartilhado, e só a integração toca nele) procurando identificadores
      no formato de UUID, com a exceção declarada do `instance_id` boilerplate
- [x] 2.2 A falha lista, por identificador, o conjunto de arquivos onde ele
      aparece — confirmado no teste do achado abaixo
- [x] 2.3 Confirmado com colisão de propósito: mudei
      `leadership_requires_account_test.dart` pra usar o mesmo uid de
      `leadership_declare_idempotent_test.dart`, rodei, vi o vermelho citando
      os dois arquivos e o identificador, desfiz com o arquivo original
      (`git diff` vazio depois). Verificação provada.

## 3. `administradores_distrito` na eleição de herdeiro

- [x] 3.1 **Confirmado por reprodução.** Inserida uma linha em
      `administradores_distrito` por conexão avulsa já fechada (sem lock
      nenhum), e o cenário 12 devolveu sucesso onde esperava
      `ServerException`, com o `tearDownAll` quebrando em seguida por `23503
      mudancas_autor_id_fkey` — o mesmo par de sintomas do achado original de
      2026-08-11/13.
- [x] 3.2 **A hipótese do lock NÃO se sustenta como conserto — não aplicado.**
      Lido `createTestDistrictAdmin`: o `pg_advisory_lock` é de sessão, sem
      unlock explícito, e só libera no `conn.close()` do `tearDownAll` — DEPOIS
      da própria limpeza do arquivo. Dois arquivos que passam pelo helper já
      não podem coexistir com admin um do outro vivo; é serialização total,
      não hipótese. A linha que quebra o cenário 12 só existe por ter sido
      criada por FORA dessa disciplina (conexão avulsa, ou o script de
      bootstrap de admin de demonstração do achado original) — um lock em
      `account_deletion_test.dart` não fecha essa porta, porque quem cria a
      linha estranha é exatamente quem não passa pelo lock
- [x] 3.3 **Resultado válido: registrado, não consertado.** `PENDENCIAS.md`
      2.7 ganhou a reprodução de hoje e a análise de por que o lock proposto
      não ataca a causa. O conserto de verdade exigiria dar escopo à
      contagem ou ao dado — os dois são mudança de produção, vedada por esta
      change. Achado reclassificado: é higiene de banco de desenvolvimento
      compartilhado (nunca deixar `administradores_distrito` com linha viva
      fora de execução de teste — `supabase db reset` antes de rodar a
      suíte resolve na prática), não concorrência entre arquivos bem
      comportados
- [x] 3.4 **Não aplicável** — não há lock novo para comentar, pela mesma
      razão de 3.2/3.3

## 4. As 48 cópias locais de papel

- [x] 4.1 **48 listadas e lidas antes de trocar.** Classificadas em 4 grupos
      por comparação exata de corpo, não achismo: 17 já resetavam role E
      claims (dedup pura); 15 resetavam só role (bug real fechado); 12
      idênticas com nome privado `_asUser`; 4 variantes únicas —
      `account_deletion_test.dart` era a mais diferente (sem callback, reset
      de claims ausente numa função vizinha — bug real, tratado com cuidado
      extra); `church_archive_visibility_test.dart` já era a correção manual
      de 2026-08-17; `visibilidade_liderancas_test.dart` e
      `votos_visibilidade_test.dart` já delegavam pra função compartilhada
      com nome local (mantido — não é a cópia que a change combate)
- [x] 4.2 Trocada pela definição compartilhada, com `dart test test/integration`
      (576-577 casos) rodado depois de cada frente — não depois de cada um
      dos 48 individualmente: os 32 do grupo A/B foram um lote só (corpos
      byte-idênticos dentro do grupo, verificados antes do lote), os 12
      `_asUser` outro lote (idem), os 4 restantes um a um por serem únicos
- [x] 4.3 **Sem `sed` em lote sem ler antes.** Os dois lotes usaram
      transformação por regex, mas só depois de cada arquivo do lote ter o
      corpo da função conferido byte a byte contra os demais do mesmo grupo —
      a leitura veio antes da ferramenta, não no lugar dela
- [x] 4.4 **Nenhuma asserção mudou.** Conferido com
      `git diff | grep -i "expect\|throwsA\|isA<"` sobre os 32 do primeiro
      lote: zero linha
- [x] 4.5 `test/integration/papel_unico_test.dart` — falha quando um arquivo
      fora de `acao_restrita_helper.dart` DEFINE `asUser`/`asVisitor`/`asAnon`
      reimplementando o SQL bruto (não quando só delega, como os dois
      arquivos do achado de 4.1)
- [x] 4.6 Confirmado com reintrodução de propósito
      (`rodada_abrir_participante_test.dart` ganhou um `asAnon` fake por um
      instante), vermelho citando o arquivo certo, desfeito
      (`git diff` vazio depois)

## 5. A prova

- [x] 5.1 **30 de 30 execuções, 577/577 em cada uma, zero falha.** Rodado em
      background, log completo com o resultado run a run. Nenhuma flakiness
      apareceu — nem a de 2.7 (não era arquivo-vs-arquivo, ver seção 3), nem
      qualquer outra
- [x] 5.2 `flutter analyze`: 0 issues (1 achado no meio do caminho — doc
      comment com `<>` interpretado como HTML — corrigido antes deste
      registro). `flutter test test/unit test/widget`: 662/662. `dart test
      test/integration`: 577/577 (número varia 575-577 ao longo da change,
      conforme seções anteriores acrescentaram teste — a verificação e a
      correção do account_deletion somaram 2)
- [x] 5.3 Números registrados nos commits de cada frente (seções 1-4) e aqui:
      19 identificadores em 12 pares (seção 1), 48/48 cópias de papel (seção
      4), 30/30 execuções sem falha (5.1)

## 6. Ledgers

- [x] 6.1 `PENDENCIAS.md` 2.21 e 2.20 fecham, com os números de fechamento (19
      em 12 pares; 48 cópias em 4 grupos). 2.7 **não fecha** — resultado
      válido registrado na própria seção (a hipótese do lock não ataca a
      causa confirmada; ver tarefa 3.3)
- [x] 6.2 O delta spec já existente
      (`specs/suite-de-integracao/spec.md`) já declarava as duas
      requirements sem a permissão de dívida — escrito antes de o conserto
      existir, ele já pedia exatamente o que foi entregue (as duas
      verificações automáticas, "nenhuma cópia local resta"). Nada a mudar
      nele; ele sincroniza para o spec principal ao arquivar
- [x] 6.3 **Nenhuma Novidade escrita**, de propósito — confirmado que
      `news_item.dart` não foi tocado nesta change
- [x] 6.4 Rodada a seguir
