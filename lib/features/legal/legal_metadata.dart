/// Versão e data de vigência dos textos legais (Política de Privacidade e
/// Termos de Uso).
///
/// Consentimento colhido sob uma versão não cobre finalidade que uma versão
/// posterior venha a adicionar — por isso a versão fica num só lugar, visível
/// nas duas páginas.
///
/// Desde a feature 017, o banco registra qual texto cada pessoa aceitou:
/// `public.perfis.consentimento_lgpd_versao` e
/// `consentimento_lgpd_igreja_versao` são carimbadas pelo gatilho
/// `perfis_carimbar_consentimento`, a partir de
/// `public.versao_texto_legal_vigente()`. O cliente diz SE aceitou; o banco diz
/// QUANDO e SOB QUAL TEXTO.
///
/// **[version] é a gêmea de exibição da linha correspondente em
/// `public.versoes_texto_legal`.** Não dá para derivar uma da outra: o texto
/// legal está compilado no binário, e a versão é metadado dele. Publicar texto
/// novo muda as duas **no mesmo commit** — semear a linha na migration e mudar
/// a constante aqui. `test/integration/versao_texto_legal_registro_test.dart`
/// falha se divergirem, porque a divergência não daria erro: gravaria em cada
/// cadastro novo uma versão diferente da que a pessoa leu na tela.
///
/// Aceites anteriores à feature 017 ficam com versão nula, de propósito —
/// `null` quer dizer *desconhecida*, e preenchê-la seria um palpite
/// apresentado como fato. Ver MAPA-DE-DADOS.md, seção Consentimento.
abstract final class LegalMetadata {
  /// 1.2 (feature 021): o voto deixou de ser público.
  ///
  /// 1.3 (feature 015): a seção de crianças passou a descrever a autorização
  /// do responsável, que antes não existia. Sobe porque o texto exibido mudou
  /// de verdade — e desta vez a mudança ADICIONA um tratamento (nome e contato
  /// de um terceiro), então quem se cadastrar a partir de agora aceita algo
  /// diferente de quem se cadastrou antes. É exatamente a distinção que a
  /// feature 017 passou a registrar.
  ///
  /// 1.4 (feature 013): o app passou a hospedar imagens enviadas por Usuários,
  /// visíveis a qualquer pessoa na internet. A Política ganhou a seção de
  /// imagens de capa — finalidade, quem vê, por quanto tempo, como pedir
  /// remoção — e a declaração de que o app **não** solicita nem verifica
  /// autorização de responsável para imagem de menor. Sobe porque a mudança
  /// ADICIONA um tratamento: quem se cadastrar agora aceita algo diferente de
  /// quem se cadastrou antes.
  /// 1.5 (change `chat-de-grupo-e-acao`): o app passou a guardar TEXTO LIVRE
  /// escrito por uma pessoa para outras. É a categoria de dado mais diferente
  /// que já entrou aqui — o único dado do app cujo conteúdo não dá para
  /// declarar de antemão, e por isso o único que precisa de moderação humana,
  /// corte por idade e prazo de descarte. A Política ganhou finalidade, quem
  /// lê, o corte de 18 anos, os 30 dias de retenção da conversa de Ação, o
  /// alcance do Administrador do distrito, e o limite de que mensagem de
  /// TERCEIRO que cite a pessoa não sai pela exclusão de conta. Sobe porque
  /// ADICIONA tratamento: quem se cadastrar agora aceita algo diferente de
  /// quem se cadastrou antes.
  /// 1.6 (change `filtro-e-intervalo-de-mensagem`): o app passou a RECUSAR o
  /// que a pessoa escreve, na escrita, sem ninguém no meio — filtro de palavra
  /// na mensagem e no motivo da denúncia, e limite de ritmo de 3 s e 20 por 5
  /// minutos por conversa. **Nenhum dado pessoal novo é tratado**: o filtro não
  /// guarda nada e o ritmo se calcula do `created_at` que a mensagem já tinha.
  /// Sobe assim mesmo, e o precedente é a 1.2, que também não adicionou
  /// tratamento: quem aceitou a 1.5 leu nos Termos que "nada do que você
  /// escreve é checado antes de aparecer", e isso deixou de ser verdade. Versão
  /// existe para separar quem leu a afirmação antiga de quem leu a nova —
  /// manter 1.5 seria carimbar os dois grupos como se tivessem lido o mesmo
  /// texto. Some-se que a recusa é decisão automatizada com efeito sobre o
  /// titular (art. 20), e o direito de revisão só se exerce sobre uma regra que
  /// a pessoa sabe que existe.
  ///
  /// A Política de Privacidade entrou nesta versão junto com os Termos, e não
  /// por simetria: ela tinha a MESMA afirmação falsa, no documento que existe
  /// para não mentir para a titular. Publicar 1.6 sem corrigi-la teria
  /// carimbado consentimento sob texto com afirmação falsa dentro.
  ///
  /// 1.7 (change `mensagem-fixada`): a promessa de prazo GANHOU EXCEÇÃO. Até
  /// aqui a Política dizia, sem ressalva, que as mensagens da Ação são apagadas
  /// 30 dias depois do encontro. Desde 20260817160000 o expurgo tem
  /// `and fixada_em is null`, e mensagem fixada não expira — no máximo 3 por
  /// conversa. Manter a 1.6 seria carimbar consentimento sob um texto que a
  /// migration acabou de tornar falso, que é exatamente o caso da 1.6.
  ///
  /// **Nenhum dado pessoal novo**, além de quem fixou e quando. O que muda é
  /// mais forte do que dado novo: muda por quanto tempo o dado que já existia
  /// permanece, e prazo declarado é a promessa que a titular usa para decidir
  /// o que escreve. Sobe também porque a exceção é acionável por OUTRA pessoa
  /// sobre texto seu, e o contrapeso — o autor sempre desfixa a própria
  /// mensagem — só serve a quem sabe que ele existe.
  ///
  /// 1.8 (change `alcance-do-titular-sobre-texto-proprio`): o contrapeso da
  /// 1.7 — "o autor sempre desfixa a própria mensagem" — não se cumpria fora
  /// da conversa. Medido em 2026-08-17 (`PENDENCIAS.md` 2.28): autor que saiu
  /// do Grupo ou desistiu da Ação tinha `pode_moderar_mensagem = true` e o
  /// `update` afetava zero linhas, porque a policy de `select` esconde a
  /// linha e um `update` não alcança linha que não lê. A Política 1.7
  /// declarava esse limite e mandava escrever para o e-mail de contato. Esta
  /// change cria um segundo caminho de desfixe — `desfixar_minha_mensagem`,
  /// alcançável de "Meu Perfil", sem depender de ler a conversa — e o texto
  /// deixa de prometer e-mail porque o app já resolve sozinho. Sobe pelo
  /// mesmo critério da 1.6: **nenhum dado pessoal novo**, mas uma afirmação
  /// que era limite passou a ser falsa (o botão não fica mais só dentro da
  /// conversa), e manter a 1.7 carimbaria consentimento sob texto que a
  /// mudança acabou de tornar impreciso.
  ///
  /// 1.9 (change `denuncia-como-registro`): o motivo de denúncia GANHOU
  /// PRAZO e passou a sair com a exclusão de conta de quem denunciou. Até
  /// aqui a Política afirmava, sem ressalva, que o motivo "não expira com o
  /// tempo" e que a exclusão de conta não o alcançava — as duas frases eram
  /// verdadeiras no código (PENDENCIAS.md 2.14) e a promessa de registro
  /// eterno tinha um custo que ninguém tinha decidido pagar: guardar para
  /// sempre o que uma pessoa escreveu sobre outra. Agora, com desfecho
  /// registrado, o motivo dura mais 30 dias e então some — o desfecho e o
  /// instante permanecem, o texto não; e sai imediatamente se quem
  /// denunciou excluir a conta antes disso. Pendente continua sem prazo,
  /// porque denúncia esquecida sem julgar é o pior resultado para quem
  /// denunciou.
  ///
  /// **Sobe porque a mudança é mais restritiva sobre dado que já existia**,
  /// mesmo caso da 1.7: reduz por quanto tempo o motivo permanece, e
  /// consentimento colhido sob a promessa antiga (eterno, sobrevivendo à
  /// exclusão de conta) não cobre a nova (prazo de 30 dias, some com a
  /// conta). Nenhum dado pessoal novo é tratado.
  static const version = '1.9';
  static const effectiveDate = '30 de agosto de 2026';

  /// Controlador dos dados (LGPD). Confirmado pelo fundador em 24/07/2026.
  static const controllerName = 'JOSE DANIEL DESENVOLVIMENTO DE SOFTWARE LTDA';

  /// Canal único para exercício de direitos do titular e contato do
  /// encarregado/DPO (LGPD art. 41) — o próprio fundador, enquanto o app for
  /// pequeno o suficiente para não exigir um encarregado dedicado.
  static const contactEmail = 'jdaniielc@gmail.com';

  /// Região de hospedagem do Supabase em produção — escolhida para manter o
  /// dado em território brasileiro e evitar declarar transferência
  /// internacional (ver REVISAO-JURIDICA.md, item 4).
  ///
  /// **Verificada em 10/08/2026**: o projeto de produção roda mesmo em
  /// `South America (São Paulo)`. Evidência (saída literal do fornecedor, com
  /// data e quem leu) em `INFRA-PRODUCAO.md` § 2 — é de lá que a Política tira
  /// o direito de afirmar que o dado não sai do Brasil.
  ///
  /// A verificação vale para este projeto, não se herda: qualquer ambiente novo
  /// DEVE escolher esta região explicitamente na criação, porque ela não é o
  /// default do fornecedor e não é documentada como alterável depois. A
  /// exigência está em `INFRA-PRODUCAO.md` § 1.
  static const hostingRegion = 'sa-east-1 (São Paulo, Brasil)';
}
