## 1. Schema, policies e grants (nada observável na tela)

- [x] 1.1 Escrever `test/integration/presenca_registro_test.dart` com os cenários de
  "Quem criou a Ação afirma quem esteve nela": criador marca, participante tenta,
  dono do Grupo tenta, marca sobre quem não confirmou, marca antes do horário,
  marca em Ação cancelada. Rodar e **colar no commit a mensagem de falha de cada
  um** — o vermelho tem que dizer valor/contagem errada, não "coluna não existe"
  em todos.
- [x] 1.2 Migration: `confirmacoes_acao.compareceu_em timestamptz`,
  `marcado_por uuid references perfis(id)`, `contestada_em timestamptz`;
  `acoes.presenca_fechada_em timestamptz`, `acoes.presentes_no_fechamento integer`.
- [x] 1.3 `revoke update on confirmacoes_acao from authenticated` e
  `grant update (compareceu_em, marcado_por)`. **Sem** grant de `contestada_em` —
  só gatilho escreve (D-006).
- [x] 1.4 Policy de `update` de presença: só o criador da Ação, só depois de
  `data_hora`, só em Ação não cancelada, só sobre linha de confirmação existente.
- [x] 1.5 Rodar 1.1 verde. Registrar a contagem de testes que passaram.

## 2. Fechamento e a distinção entre não registrado e ausente

- [x] 2.1 Escrever `test/integration/presenca_fechamento_test.dart`: Ação passada
  sem marca nenhuma não produz ausente; marca parcial sem fechamento não produz
  ausente; fechamento converte o que sobrou; fechar antes do horário é recusado;
  marcar depois do fechamento é recusado; fechar sem ser o criador é recusado;
  Ação antiga nunca fechada segue fora das contagens. Ler as falhas antes de
  seguir.
- [x] 2.2 Policy e gatilho de fechamento; `presentes_no_fechamento` gravado **no
  fechamento**, não calculado depois (D-002).
- [x] 2.3 View `public.presencas_computaveis` (D-009) — o único lugar que define
  "esta linha conta". `security_invoker`, sem agregação, sem juízo.
- [x] 2.4 Provar que Ação não fechada fica fora de numerador **e** denominador —
  o teste tem que afirmar as duas ausências separadamente, senão passa por
  metade do motivo.
- [x] 2.5 Rodar 2.1 verde. Contagem no commit.

## 3. Contestação, e a marca que nada limpa

- [x] 3.1 Escrever `test/integration/presenca_contestacao_test.dart`: titular
  contesta; contestar marca alheia é recusado; criador desfaz; criador mantém;
  decidir sem ser o criador é recusado; apagar contestação é recusado; reescrever
  contestação é recusado. **Asserção de recusa é `affectedRows == 0`, nunca
  `throwsA`** — recusa de RLS é ausência, não erro.
- [x] 3.2 Migration de `public.contestacoes_presenca` (append-only, no padrão de
  `denuncia-como-registro`) e gatilho que preenche `confirmacoes_acao.contestada_em`.
- [x] 3.3 Teste explícito de que **nenhuma decisão limpa `contestada_em`** — nem
  `mantida`, nem `desfeita`. É a regra que a change existe para tornar
  estrutural (D-003).
- [x] 3.4 Rodar 3.1 verde. Contagem no commit.

## 4. Alcance do titular depois da saída

- [x] 4.1 Escrever `test/integration/presenca_alcance_titular_test.dart`:
  contesta depois de sair do Grupo; vê a própria marca depois de desistir da
  Ação; contesta com Grupo arquivado. E o contraprova: **não** vê confirmação de
  terceiro em Ação restrita de Grupo do qual saiu.
- [x] 4.2 Acrescentar o disjunto `auth.uid() = usuario_id` a
  `confirmacoes_acao_select_conforme_acao` (D-005), com comentário citando
  `PENDENCIAS.md` 2.28 e o motivo — `update` não alcança o que `select` não vê.
- [x] 4.3 Rodar 4.1 verde. Contagem no commit.

## 5. Trava de consentimento na coleta

- [x] 5.1 Escrever `test/integration/presenca_trava_consentimento_test.dart`:
  marca sobre aceite defasado é recusada; sobre aceite de versão `NULL` é
  recusada; depois do reaceite é aceita; a função recusa quem não é o criador
  daquela Ação; recusa consulta sobre quem não tem confirmação nela.
- [x] 5.2 Função `security definer` devolvendo **apenas booleano**, com os dois
  braços de autoridade (D-004). Comentário na migration registrando o vazamento
  residual aceito.
- [x] 5.3 Ligar a trava à policy de `update` de presença.
- [x] 5.4 Rodar 5.1 verde. Contagem no commit.

## 6. Retenção com rastro

- [x] 6.1 Escrever `test/integration/presenca_retencao_test.dart`: linha de Ação
  com mais de dois anos tem as colunas de presença zeradas; execução fica
  registrada em `execucoes_de_faxina`; execução sem nada a apagar **também** fica
  registrada, com quantidade zero; `presentes_no_fechamento` sobrevive.
  Escopar tudo por UUID próprio — a suíte roda em paralelo contra o mesmo Postgres.
- [x] 6.2 Faxina de `pg_cron` que zera `compareceu_em`, `marcado_por` e
  `contestada_em`, **sem apagar a linha de confirmação** (D-007).
- [x] 6.3 Teste de que `excluir_minha_conta` alcança as colunas novas: o
  comparecimento deixa de ser atribuível, e as marcas que a pessoa fez sobre
  outras deixam de identificá-la. **Provar, não presumir a herança** de
  `perfis(id)`.
- [x] 6.4 Rodar 6.1 e 6.3 verdes. Contagem no commit.

## 7. Aviso de versão defasada e reaceite (antes da versão nova existir)

- [x] 7.1 Escrever `test/widget/` para a spec `versao-aceita-e-vigente`: aceite
  defasado mostra o que mudou; aceite em dia não mostra nada; versão desconhecida
  mostra aviso dizendo que é desconhecida e **não** chuta qual era; sem Perfil não
  mostra nada; fechar sem aceitar mantém o uso e mantém a versão anterior.
  **Cada teste afirma texto ou estado na tela** — `pumpWidget` sozinho sobe
  cobertura e não prova nada.
- [x] 7.2 Acrescentar `consentimento_lgpd_aceito_em` ao `grant update` de `perfis`
  (hoje ele não está lá, ver design § Context). Teste de integração de que o
  gatilho carimba `now()` e a versão vigente no reaceite, e de que valor de versão
  mandado pelo cliente é descartado.
- [x] 7.3 Teste do caminho de falha: reaceite que falha deixa o aceite anterior
  intacto e a tela não afirma que atualizou. Conferir linhas afetadas antes de
  afirmar.
- [x] 7.4 Tela de aviso e reaceite. Não bloqueia o uso do app.
- [x] 7.5 Rodar a suíte de widget. Contagem no commit.

## 8. Versão nova de texto legal

- [x] 8.1 Escrever Política, Termos e o texto de autorização do responsável
  descrevendo comparecimento: o que é coletado, quem afirma, o que "não
  registrado" significa, o direito de contestar, o prazo de dois anos, e a
  finalidade de acompanhamento de envolvimento. O texto de responsável cita
  presença explicitamente.
- [x] 8.2 Migration da entrada nova em `versoes_texto_legal`, com
  `vigente_desde`. **Só depois de 7 estar em produção** — inverter recusa o
  check-in para o distrito inteiro (design § Migration Plan).
- [x] 8.3 Atualizar `legal_metadata.dart` e conferir que o app aponta para a
  versão nova.

## 9. Telas de presença

- [x] 9.1 Teste de widget: quem criou a Ação vê o botão de marcar; participante
  não vê; lista fechada não oferece marcar; recusa da trava de consentimento
  mostra mensagem que diz o que fazer, sem expor dado do Perfil alheio.
- [x] 9.2 Tela de marcar presença e fechar lista, em `lib/features/action/`.
  Identificador Dart em inglês, string de tela em português — consultar o
  glossário de `CONTEXT.md`, não traduzir por conta própria.
- [x] 9.3 Teste de widget do histórico próprio e da contestação, em
  `lib/features/profile/`: a pessoa vê a marca com instante e quem marcou, e
  consegue contestar.
- [x] 9.4 Repositórios conferem `.select()` e linhas afetadas antes de a tela
  afirmar sucesso — em marcar, fechar, contestar e decidir. Quatro caminhos,
  quatro conferências.
- [x] 9.5 Rodar a suíte de widget. Contagem no commit.

## 10. Ledger e gate

- [x] 10.1 `MAPA-DE-DADOS.md`: seção de comparecimento com `arquivo:linha` —
  colunas novas, quem vê o quê pela RLS, prazo de dois anos, o vazamento residual
  de D-004, e a classificação de sensibilidade em aberto.
- [x] 10.2 `PENDENCIAS.md`: fechar 2.29 apontando para esta change, e abrir a
  pendência jurídica nova (presença em evento religioso como provável art. 5º, II;
  se o consentimento por versão basta como destacado do art. 11, I). Registrar
  também o limite de D-008: o app guarda um aceite por pessoa, sem histórico.
- [x] 10.3 `flutter analyze` — registrar o número de issues, não a palavra "limpo".
- [x] 10.4 `make coverage` — registrar o percentual e o `COVERAGE_FLOOR` vigente.
  Se reprovar, escrever o teste que falta; **não** baixar o piso.
- [x] 10.5 `dart test test/integration` com o Supabase local de pé — registrar a
  contagem. Conferir que os arquivos novos não colidem com estado global de outros.
- [x] 10.6 `openspec validate presenca-em-acao` (sem `--strict` — o repo escreve
  spec em português e o `--strict` reprova por RFC 2119).

## Convergence 1

- [x] C-1 **CRITICAL** — a trava de coleta DEVE consultar `autorizacao_responsavel_versao`
  para quem está abaixo de `limiar_crianca()`, não só `consentimento_lgpd_versao`
  — per "A idade não restringe o registro de comparecimento", cenário "Criança
  com autorização de versão anterior" (`contradicts`).
  **Medido em 2026-09-09**: criança de 10 anos com `autorizacao_responsavel_versao
  = '1.10'` e aceite 1.10 reaceita sozinha pelo aviso da Home; depois do
  `update`, `consentimento_lgpd_versao = '1.11'` e `autorizacao_responsavel_versao
  = '1.10'`. `pode_registrar_presenca` passa a devolver `true`, e a coleta é
  destravada por um toque da própria criança enquanto o responsável autorizou um
  texto que não menciona comparecimento.
  **E a autorização não tem como ser atualizada**: `perfis_protege_autorizacao_
  responsavel` (`20260810000000:160-176`) levanta exceção em qualquer mudança
  nas quatro colunas do responsável. Não é atraso — é impossibilidade. Sem
  decisão de produto sobre autorização retroativa (que a feature 015 recusou de
  propósito), a única saída correta é a trava RECUSAR menor de 13 cuja
  autorização não seja da versão vigente.
  Viola o Princípio II da constituição (privacidade e LGPD, inegociável) e a
  LGPD art. 14, §1º. Precisa de teste de integração com os dois cenários.

- [x] C-2 **HIGH** — `AttendanceRepository.fetchMyAttendance` quebra quando a Ação
  deixou de ser legível — per "O alcance do titular sobrevive à saída"
  (`partial`).
  **Medido em 2026-09-09**, para quem saiu do Grupo de uma Ação restrita:
  `confirmacoes visiveis: 1`, `acoes visiveis: 0`. O `select` embute
  `acoes(nome, data_hora)`, o PostgREST devolve `acoes: null`, e
  `row['acoes'] as Map<String, dynamic>` lança. A tela que quebra é "Meu Perfil"
  — exatamente a de quem a change alargou a policy para proteger. A correção não
  é alargar a leitura da Ação (o teste de contraprova exige que ela continue
  invisível): é a linha sobreviver sem o nome da Ação, dizendo o que sabe.

- [x] C-3 MEDIUM — escrever o teste de integração de "A idade não restringe o
  registro de comparecimento" (`missing`). Os dois cenários do requisito não têm
  nenhuma cobertura; nenhum arquivo desta change cita `limiar_crianca`. É o teste
  que teria pego C-1.

- [x] C-4 MEDIUM — quem está com o aceite EM DIA não tem onde ver qual versão
  aceitou e quando — per `versao-aceita-e-vigente`, cenário "A própria pessoa
  consulta a versão dela" (`missing`). `OutdatedConsentBanner` só renderiza
  quando há divergência. O lugar coerente é "Meu Perfil", ao lado das outras
  coisas que o app guarda sobre a pessoa.

- [x] C-5 LOW — fixar em teste que ler a versão aceita por outra pessoa devolve
  zero linhas — per `versao-aceita-e-vigente`, cenário "Consulta da versão
  alheia" (`missing`). A garantia vem de `perfis_select_own`, que é anterior a
  esta change e não foi tocada; o teste existe para que uma policy futura não a
  desfaça em silêncio.

## Convergence 1 — como cada achado foi resolvido (2026-09-09)

- C-1 — `pode_registrar_presenca` passou a exigir também
  `autorizacao_responsavel_versao` na versão vigente, abaixo de
  `limiar_crianca()` (`20260909170000_presenca_trava_do_responsavel.sql`).
  Coberto por `presenca_menor_de_idade_test.dart`, 5/5, incluindo o teste que
  prova que o reaceite da própria criança NÃO destrava a coleta, e o que prova
  que a autorização do responsável é imutável — o que faz a recusa ser
  permanente, e deliberada.
- C-2 — `fetchMyAttendance` trata `acoes` nulo; `MyAttendanceRecord.actionDate`
  virou anulável. A linha sobrevive sem o nome da Ação e continua contestável.
  Coberto em `minha_presenca_test.dart`.
- C-3 — `presenca_menor_de_idade_test.dart` cobre os dois cenários do
  requisito de idade, mais os três que C-1 exigiu.
- C-4 — `AcceptedVersionLine` em "Meu Perfil" diz sob qual versão a pessoa
  está, e diz "desconhecida" quando é.
- C-5 — dois testes em `presenca_trava_consentimento_test.dart`: a versão
  alheia devolve zero linhas, a própria devolve uma.
