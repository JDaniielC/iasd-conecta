## Why

**O app não sabe quem foi.** `confirmacoes_acao` guarda intenção — `status` em
`confirmado`/`fila` e `created_at`, e nada mais
(`20260723230639_acoes.sql:16-22`). Não existe coluna de comparecimento em
lugar nenhum do schema. Quem confirmou e não apareceu é, hoje, a mesma linha de
quem confirmou e apareceu.

Isso importa agora porque a liderança do distrito quer usar o app para
acompanhar envolvimento de membro, e **toda métrica construída sobre o dado
atual mede quem parou de clicar, não quem parou de vir.** A liderança vai ler
esse número como presença e agir sobre ele — visita pastoral a partir de um
sinal que o sistema nunca prometeu dar.

E há prazo, o que é raro num débito. A métrica que vai consumir esta coleta —
queda do envolvimento de uma pessoa contra o histórico dela mesma — precisa de
meses de histórico. `public.perfis` nasceu em **2026-07-23**
(`20260723191202_perfis_igrejas.sql`); em 2026-09-09 são **48 dias**. Cada
semana sem registro de presença é uma semana que a métrica futura nunca terá,
porque presença não se reconstrói retroativamente.

Junto vem a dívida `PENDENCIAS.md` 2.29, e não por conveniência: ela **bloqueia**
esta change. Medir comparecimento é finalidade nova, e a Política vigente promete
que *"o aceite dado numa versão não cobre finalidade nova que só a versão
seguinte passe a ter"* (`privacy_policy_page.dart:607`). Publicar a versão nova
sem caminho de reaceite deixaria todo Perfil com versão defasada e o check-in
recusado para o distrito inteiro. A 2.29 já declara que o mecanismo —
comparar `perfis.consentimento_lgpd_versao` com `versao_texto_legal_vigente()` e
mostrar o que mudou a quem está atrasado — *"é comportamento novo, e nasce em
spec"*. Nasce nesta.

## What Changes

- **Registro de comparecimento.** O criador da Ação marca quem esteve lá,
  depois de a Ação acontecer.
- **Três estados, e este é o coração da change.** Não marcado significa **não
  registrado**, nunca ausente. Só um fechamento explícito da lista, feito por
  quem criou a Ação, converte o que sobrou em ausência. Ação não fechada fica
  fora de numerador **e** de denominador de qualquer métrica futura. Segue a
  doutrina que o repo já aplica a `consentimento_lgpd_versao`, onde `NULL`
  significa desconhecida e *"nunca um palpite"* (`MAPA-DE-DADOS.md`,
  § Consentimento).
- **Contestação pelo titular.** A pessoa vê toda marca de presença sobre si e
  pode contestá-la; quem criou a Ação decide. Nem a contestação nem a decisão
  são apagadas — registro não se reescreve, como a change
  `denuncia-como-registro` estabeleceu. Mas **linha contestada sai da métrica
  para sempre**, decida o criador o que decidir: o titular tem efeito real sem
  precisar vencer a disputa.
- **Alcance do titular que sobrevive à saída.** A pessoa alcança a marca sobre
  si mesmo depois de sair do Grupo ou desistir da Ação. O defeito oposto já foi
  medido neste repo (`PENDENCIAS.md` 2.28) e corrigido em
  `alcance-do-titular-sobre-texto-proprio`: no Postgres o `UPDATE` só enxerga o
  que a policy de `SELECT` deixa ler, então uma promessa de alcance que não
  esteja na policy de leitura não existe.
- **Prazo de guarda.** A linha nominal é apagada 2 anos depois da Ação, por
  faxina agendada, no padrão de `notificacoes`. A contagem agregada por Ação
  permanece — não é dado pessoal. A faxina deixa rastro em
  `execucoes_de_faxina`, como a capability `observador-de-retencao` exige.
- **Versão nova de texto legal**, descrevendo a coleta de comparecimento e a
  finalidade de acompanhamento de envolvimento. O texto de autorização do
  responsável passa a citar presença.
- **Aviso de versão defasada e reaceite** — fecha `PENDENCIAS.md` 2.29. Quem
  está atrasado vê o que mudou e pode aceitar ou não.
- **Consentimento trava a COLETA, não só a consulta.** Sem aceite da versão que
  descreve a medição, a marca de presença é recusada. Gravar primeiro e filtrar
  depois guardaria dado provavelmente sensível por 2 anos sobre quem nunca
  consentiu com essa finalidade.
- Vale para **todas as idades**. Desbravadores (10-15) e Aventureiros (6-9)
  (`CATEGORIAS-DE-ACAO.md:6-18`) são justamente quem já faz chamada no papel. O
  corte de `maior_de_idade()` que o chat usa **não** se aplica aqui.

## Capabilities

### New Capabilities

- `presenca-em-acao`: quem esteve numa Ação, quem afirma isso, o que significa
  não ter sido marcado, o alcance do titular sobre a afirmação feita sobre ele,
  e por quanto tempo a afirmação é guardada.
- `versao-aceita-e-vigente`: o que acontece quando a versão do texto legal que
  a pessoa aceitou não é mais a vigente — o aviso com destaque do art. 8º, §6º,
  o reaceite, e a recusa de tratamento de finalidade que a versão aceita não
  cobre.

### Modified Capabilities

Nenhuma. A capability `observador-de-retencao` já exige rastro de **toda**
faxina de retenção, então a faxina nova entra sob a regra existente sem alterá-la.

## Impact

**Banco** — colunas novas em `public.confirmacoes_acao` e `public.acoes`;
tabela nova para a contestação; policies e `grant` recortados por coluna, no
padrão de `20260817120000_mensagens_insert_por_coluna.sql`; faxina agendada
nova; entrada nova em `public.versoes_texto_legal`.

**`excluir_minha_conta`** — toda coluna nova que referencie `perfis(id)` precisa
ser conferida contra a anonimização, como `fixada_por` e `removida_por` já são.
Herança presumida não conta: tem que ser provada em teste.

**App** — `lib/features/action/` (marcar presença, fechar lista),
`lib/features/profile/` (ver e contestar marca sobre si), `lib/features/legal/`
(versão nova, aviso de defasagem, reaceite).

**Documentos de ledger** — `MAPA-DE-DADOS.md` ganha a linha de presença com
`arquivo:linha`; `PENDENCIAS.md` 2.29 fecha e ganha a pendência jurídica nova
descrita abaixo.

**Risco jurídico que esta change registra e NÃO resolve**: presença em evento
religioso é provavelmente dado sensível do art. 5º, II — mesma família de
`igreja_id`, e `REVISAO-JURIDICA.md:211` já concluiu que *"'é a rede da própria
igreja' NÃO muda a base legal"*, porque a LGPD não tem o equivalente ao GDPR
art. 9(2)(d). **[EM ABERTO — precisa de advogado]**: se o consentimento por
versão basta como "específico e destacado" do art. 11, I, ou se exige caixa
própria. Mesma família do achado A-2 e da pendência 2.16.

É também o **primeiro dado do app escrito por terceiro sobre o titular**. Nada
parecido existe hoje: `mensagens.texto` é do autor, `denuncias_mensagem.motivo`
é de quem denuncia. Aqui alguém afirma um fato sobre outra pessoa, e é isso que
a contestação existe para equilibrar.

**Fora de escopo, de propósito**: lista nominal de afastamento ou queda relativa
(change separada, só viável com histórico); painel agregado de saúde de Grupo
(change `saude-de-grupo`); fechar a leitura de `authenticated` sobre as tabelas
de Ação e Grupo (é sobre superfície de API, merece ticket próprio).
