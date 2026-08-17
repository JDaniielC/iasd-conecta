import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';

import '../../../core/theme/app_theme.dart';
import '../legal_metadata.dart';
import 'widgets/legal_text.dart';

/// Política de Privacidade da Rede IASD Vitória de Santo Antão.
///
/// Todo dado, prazo e destino descrito aqui foi conferido no código antes de
/// escrever — ver MAPA-DE-DADOS.md (raiz do repo) para a evidência
/// `arquivo:linha` de cada afirmação. O que o código não faz, este texto não
/// promete (ver REVISAO-JURIDICA.md para o que ainda depende de confirmação
/// jurídica ou de decisão do responsável pelo app).
class PrivacyPolicyPage extends ConsumerWidget {
  const PrivacyPolicyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasProfile = ref.watch(hasProfileProvider).value ?? false;
    return Scaffold(
      appBar: AppBar(title: const Text('Política de Privacidade')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Rede IASD Vitória de Santo Antão',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'Versão ${LegalMetadata.version} — vigente desde ${LegalMetadata.effectiveDate}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const LegalParagraph(
              'Este app é uma rede social para os membros ativos da Igreja '
              'Adventista do Sétimo Dia do distrito de Vitória de Santo '
              'Antão descobrirem e se conectarem através de Grupos e Ações. '
              'Esta política explica, em português direto, quais dados seus '
              'a gente guarda, para quê, quem mais consegue ver, e o que '
              'você pode fazer a respeito. Ela vale para quem se cadastra '
              '(Usuário) e, nas partes sobre navegação livre, também para '
              'quem só visita sem se cadastrar (Visitante).',
            ),

            const LegalHeading('Quem é responsável pelos seus dados'),
            const LegalParagraph(
              '${LegalMetadata.controllerName} cria e mantém este app, e é '
              'responsável pelos dados tratados aqui (o que a lei chama de '
              '"controlador"). Para qualquer dúvida ou pedido sobre os seus '
              'dados, escreva para: ${LegalMetadata.contactEmail} — é '
              'também o contato do encarregado (DPO) pela proteção de '
              'dados deste app.',
            ),

            const LegalHeading('O que pedimos no cadastro, e por quê'),
            const LegalBullet(
              'Nome — para te identificar dentro do app. Passa por uma '
              'checagem contra palavras ofensivas antes de ser aceito.',
            ),
            const LegalBullet(
              'Apelido — só obrigatório se você tiver menos de 18 anos. '
              'Substitui o seu nome real em qualquer lugar visível a outras '
              'pessoas, para não expor o nome de uma criança ou adolescente.',
            ),
            const LegalBullet(
              'Gênero — usado só para montar corretamente a Dupla '
              'Missionária (a visita que precisa seguir uma regra de par por '
              'gênero). Não aparece no seu perfil visível a outras pessoas.',
            ),
            const LegalBullet(
              'Idade — usada para saber se você precisa de Apelido e para '
              'checar maioridade em papéis que exigem Conta (Administrador '
              'do distrito, Líder/Diretor de Ministério). Nunca é mostrada a '
              'nenhum outro Usuário ou Visitante.',
            ),
            const LegalBullet(
              'Telefone (opcional) — pode ficar em branco. Hoje nenhuma '
              'função do app usa esse campo além de guardá-lo; nenhuma outra '
              'pessoa o vê.',
            ),
            const LegalBullet(
              'Igreja de origem (opcional) — qual das mais de 15 igrejas do '
              'distrito você frequenta. Serve para destacar pra você '
              'Grupos e Ações da sua igreja — nunca restringe o que você vê '
              'ou faz, e pode ficar em branco.',
            ),
            const LegalBullet(
              'Consentimento — a data e hora em que você aceitou o uso '
              'desses dados, registrada junto do cadastro.',
            ),
            const LegalNote(
              'A LGPD trata dado sobre filiação a organização religiosa '
              'como uma categoria mais protegida (dado sensível). "Igreja '
              'de origem" se enquadra aí. Por isso esse campo é opcional — '
              'você participa do app inteiro sem preenchê-lo — e o '
              'consentimento que você dá no cadastro cobre expressamente '
              'esse uso, sempre que você optar por preencher.',
            ),
            const LegalParagraph(
              'Se você optar por criar uma Conta (e-mail e senha, para '
              'recuperar seu cadastro em outro aparelho), esse e-mail e essa '
              'senha ficam guardados pelo Supabase, nosso provedor de login '
              '— a senha sempre criptografada, nem quem mantém o app '
              'consegue lê-la.',
            ),

            const LegalHeading(
              'O que fica visível para outras pessoas — inclusive quem não '
              'é cadastrado',
            ),
            const LegalParagraph(
              'Este app existe para ajudar gente a se encontrar, então parte '
              'do que você faz aqui é pública por natureza — visível até '
              'para Visitante, sem login. Ficam públicos:',
            ),
            const LegalBullet(
              'Seu nome (ou Apelido, se você for menor de idade) e a igreja '
              'que escolheu, sempre que você participa de um Grupo, '
              'confirma presença numa Ação ou propõe uma Ação candidata.',
            ),
            const LegalBullet('Quais Grupos você participa.'),
            const LegalBullet('Em quais Ações você confirmou presença.'),
            const LegalBullet(
              'Se você é Administrador do distrito, ou se autodeclarou '
              'Líder/Diretor de um Ministério — nesse último caso, mesmo '
              'enquanto a declaração ainda está pendente de confirmação.',
            ),
            const LegalParagraph(
              'Nunca ficam públicos, para ninguém: sua idade, seu telefone, '
              'seu gênero.',
            ),
            const LegalParagraph(
              'O que você escreve nas conversas de Grupo e de Ação também '
              'não é público. Quem lê cada uma delas está na seção '
              '"Conversas em Grupos e Ações", logo abaixo.',
            ),
            const LegalParagraph(
              'Em qual candidata você votou também não fica público. Só você '
              'enxerga o seu voto — nem outros participantes do Grupo, nem '
              'quem abriu a Rodada de votação, nem o Dono do Grupo. Quando a '
              'Rodada fecha, o app conta os votos e anuncia a candidata '
              'vencedora, sem mostrar a ninguém quem votou em quê.',
            ),

            const LegalHeading('Imagens de capa de Grupo e de Ação'),
            const LegalParagraph(
              'Quem é Dono de um Grupo/Ministério, quem criou uma Ação e o '
              'Administrador do distrito podem enviar uma imagem de capa, '
              'para ilustrar. A finalidade é essa: dar cara ao Grupo ou à '
              'Ação, para quem procura reconhecer do que se trata.',
            ),
            const LegalBullet(
              'Quem consegue ver: qualquer pessoa na internet, inclusive quem '
              'não tem cadastro no app. A imagem fica num endereço público, '
              'como o nome do Grupo e o horário da Ação já ficam.',
            ),
            const LegalBullet(
              'Por quanto tempo: enquanto o Grupo ou a Ação existir, ou até '
              'alguém remover a imagem. Quando a Ação é cancelada, quando uma '
              'candidata perde a votação e é descartada, ou quando quem '
              'enviou apaga a conta, a imagem é removida junto.',
            ),
            // FR-012 escrito com o número medido, e não com o número
            // desejado. A verificação em fonte primária (research D-004) diz
            // "up to 60 seconds for the CDN cache to be invalidated" — a
            // invalidação é automática, mas não é síncrona. Escrever
            // "removida imediatamente" seria a divergência entre promessa e
            // execução que a constituição proíbe.
            const LegalBullet(
              'Como pedir a remoção, e o que acontece: qualquer pessoa pode '
              'denunciar uma imagem pelo próprio app, sem precisar de '
              'cadastro, ou escrever para ${LegalMetadata.contactEmail}. '
              'Ao ser removida, a imagem sai na hora do app e do nosso '
              'servidor. Quem já tiver o endereço direto dela guardado pode '
              'ainda conseguir abri-lo por até 60 segundos, enquanto a cópia '
              'em cache da internet expira. Depois disso, o endereço para de '
              'responder.',
            ),
            // FR-030: dizer o que o app NÃO faz é tão obrigatório quanto
            // dizer o que ele faz. Sem esta frase, a Política deixaria
            // subentendido um controle que não existe.
            const LegalParagraph(
              'O app pede a quem envia que use imagem ilustrativa e que não '
              'envie foto de pessoas — nunca de crianças ou adolescentes. '
              'Esse aviso aparece antes de cada envio. Mas é importante ser '
              'claro: o app não solicita nem verifica autorização de '
              'responsável para imagem em que apareça criança ou '
              'adolescente, e não analisa automaticamente o conteúdo do que '
              'é enviado. O controle é o aviso antes do envio e a denúncia '
              'depois. Se você vir uma imagem com uma criança, denuncie pelo '
              'app ou escreva para ${LegalMetadata.contactEmail} — nós '
              'removemos.',
            ),

            const LegalHeading('Conversas em Grupos e Ações'),
            const LegalParagraph(
              'Cada Grupo tem uma conversa, e cada Ação também. É onde as '
              'pessoas combinam quem leva o quê, onde é o ponto de encontro '
              'e o que mudou de última hora. Só texto: o app não aceita '
              'foto, áudio nem arquivo na conversa.',
            ),
            const LegalNote(
              'Esta é a única parte do app em que o dado é o que você '
              'escreve, e não um campo com forma conhecida. Nome, data e '
              'local a gente sabe de antemão o que são; uma mensagem, não. '
              'Por isso esta seção é mais detalhada que as outras — e por '
              'isso o que você escreve sobre outras pessoas importa tanto '
              'quanto o que você escreve sobre você.',
            ),
            const LegalBullet(
              'Quem lê a conversa de um Grupo: só quem participa daquele '
              'Grupo. Ela não é pública — Visitante não vê, não aparece em '
              'busca na internet, e quem não participa não alcança nem por '
              'fora do app. A regra vale no banco de dados, não só na tela.',
            ),
            const LegalBullet(
              'Quem lê a conversa de uma Ação: quem confirmou presença, quem '
              'está na fila de espera, quem criou a Ação e o Dono do Grupo '
              'dela, quando a Ação é de um Grupo. Quem desiste da Ação deixa '
              'de ler a conversa dela.',
            ),
            const LegalBullet(
              'Quem sai de um Grupo deixa de ler a conversa dele, inclusive '
              'as mensagens antigas. O que essa pessoa escreveu continua '
              'aparecendo para quem ficou — a conversa é de todo mundo que '
              'estava lá.',
            ),
            // Esta frase já foi escrita uma vez dizendo MENOS do que diz
            // agora, e a diferença é a razão de o texto legal ser conferido
            // contra o código: `pode_ver_chat_acao` não tinha o braço de
            // Administrador, embora o comentário e o spec daquela migration
            // declarassem que tinha. A conferência achou; a suíte não, porque
            // só provava moderação em chat de Grupo. Corrigido em
            // 20260813200000, com teste em chat_moderacao_test.dart.
            const LegalBullet(
              'O Administrador do distrito consegue ler e remover mensagem '
              'na conversa de qualquer Grupo e de qualquer Ação, mesmo sem '
              'participar. É poder amplo, e está escrito aqui de propósito: '
              'sem ele não haveria a quem recorrer quando o problema vem '
              'justamente de quem manda no espaço. O corte de 18 anos vale '
              'para ele também.',
            ),
            const LegalBullet(
              'Só quem tem 18 anos ou mais lê ou escreve. Quem tem menos, e '
              'quem está sem cadastro, não vê a conversa e não alcança as '
              'mensagens nem por fora do app. O corte usa a idade que você '
              'informou no cadastro — o app não tem como conferir se ela é '
              'verdadeira.',
            ),
            const LegalBullet(
              'Onde a conversa fica: no mesmo banco de dados do resto do '
              'app, no Supabase, em servidor no Brasil. Ela não passa por '
              'nenhum outro serviço e não sai do país.',
            ),
            // ESTE PARÁGRAFO AFIRMAVA O CONTRÁRIO até 2026-08-16, e a frase
            // antiga ("não existe leitura automática do que você escreve")
            // virou declaração FALSA no dia em que
            // `mensagens_filtro_de_palavra_trigger` (20260816160000) entrou.
            // Achado pelo `advogado-digital` ao revisar os Termos da change
            // `filtro-e-intervalo-de-mensagem` — os Termos estavam sendo
            // corrigidos e a Política tinha a mesma frase, num documento que
            // existe justamente para não mentir para a titular.
            //
            // O que se pode continuar afirmando é o que o código cumpre: a
            // comparação é com uma LISTA e nada mais, e o texto recusado não
            // é gravado nem guardado em lugar nenhum.
            const LegalParagraph(
              'Existe uma conferência automática no que você escreve, e ela '
              'é uma só: o app compara as palavras da mensagem com uma lista '
              'de palavras que este distrito não aceita. Se casar, a mensagem '
              'não é enviada. Fora isso não há leitura automática nenhuma — '
              'não há inteligência artificial, não há análise de conteúdo, e '
              'o app não varre as conversas atrás de nada. A mensagem '
              'recusada não é gravada, não é lida por ninguém e não fica '
              'registrada em lugar nenhum: ela simplesmente não acontece.',
            ),
            const LegalParagraph(
              'Quem lê é quem está na conversa, mais o Administrador do '
              'distrito nos casos acima. Para tudo o que a lista não pega — '
              'e é a maior parte, porque ela compara palavras inteiras e não '
              'entende contexto — a moderação continua humana e só começa '
              'quando alguém denuncia. A consequência disso é honesta de '
              'dizer: uma mensagem ofensiva que escape da lista fica no ar '
              'até alguém denunciar e alguém com autoridade no espaço abrir '
              'o app.',
            ),
            const LegalParagraph(
              'Quando uma mensagem é removida — por quem a escreveu, por '
              'quem manda no espaço ou pelo Administrador do distrito — o '
              'texto deixa de existir. Não guardamos cópia em lugar nenhum: '
              'nem num registro interno, nem para o Administrador consultar '
              'depois. Fica a marca de que houve uma mensagem ali, para a '
              'conversa continuar fazendo sentido, e o motivo que a pessoa '
              'escreveu ao denunciar.',
            ),
            const LegalParagraph('Por quanto tempo a conversa fica guardada:'),
            const LegalBullet(
              'Conversa de Ação: apagamos as mensagens 30 dias depois da '
              'data e hora da Ação. A conta corre a partir do encontro, e '
              'não de quando você escreveu. Depois disso elas deixam de '
              'existir.',
            ),
            const LegalBullet(
              'Conversa de Grupo: não tem prazo. As mensagens ficam '
              'enquanto o Grupo existir, inclusive depois de ele ser '
              'arquivado — nesse caso a conversa vira só leitura, e o '
              'histórico é justamente o que sobra dele.',
            ),
            // O prazo é promessa, e promessa de prazo exige executor. São
            // dois, de propósito: `cron.schedule('expurgar-mensagens-de-acao')`
            // (20260813200000:565-569) e a chamada do app em
            // `ChatRepository.fetchHistory` (chat_repository.dart:57). "Algumas
            // horas a mais" não é hedge: o cron roda 03:43 e o segundo gatilho
            // depende de alguém abrir uma conversa.
            const LegalBullet(
              'Quem apaga, na prática: uma rotina que roda todo dia no banco '
              'de dados, e mais uma segunda passagem que o próprio app '
              'dispara sempre que alguém abre uma conversa. São duas porque '
              'a primeira, sozinha, pode deixar de rodar — e prazo sem quem '
              'o cumpra não é prazo. Por isso uma mensagem pode sobreviver '
              'algumas horas além da marca exata dos 30 dias, até a '
              'passagem seguinte.',
            ),
            const LegalParagraph(
              'Quando alguém exclui a conta, o texto de todas as mensagens '
              'dessa pessoa é apagado, e no lugar fica a marca de mensagem '
              'de conta excluída. Existe um limite aqui, e ele precisa estar '
              'escrito com todas as letras: mensagem escrita por OUTRA '
              'pessoa que cite você não é apagada quando você exclui sua '
              'conta. Aquele texto é de outra pessoa, e a sua exclusão não '
              'alcança o que ela escreveu. Para tirar do ar uma mensagem '
              'assim, o caminho é denunciar — pelo próprio app ou '
              'escrevendo para ${LegalMetadata.contactEmail}.',
            ),
            const LegalParagraph(
              'Ao denunciar, o motivo que você escrever fica guardado como '
              'registro do caso, junto com a informação de que foi você quem '
              'denunciou. Ele não expira com o tempo, e continua existindo '
              'mesmo depois de as mensagens da Ação serem apagadas — uma '
              'denúncia que some sem desfecho é o pior resultado para quem '
              'denunciou. A denúncia é vista só por quem pode resolvê-la: o '
              'Dono do Grupo, o criador da Ação, o Dono do Grupo a que a Ação '
              'pertence, e o Administrador do distrito. Se você excluir sua '
              'conta, esse motivo continua '
              'registrado, ligado apenas ao seu Perfil anonimizado — '
              '"Membro removido".',
            ),
            const LegalParagraph(
              'Uma última coisa, e ela é um pedido: não escreva na conversa '
              'dado pessoal de outra pessoa — telefone, endereço, situação '
              'de saúde — nem informação sobre criança ou adolescente. '
              'Escreva o necessário para combinar a atividade. Como o app '
              'não analisa o que você escreve, esse cuidado é seu, e a '
              'regra está nos Termos de Uso.',
            ),

            const LegalHeading('Com quem compartilhamos'),
            const LegalBullet(
              'Supabase — provedor que guarda o banco de dados e cuida do '
              'login. O servidor fica na região ${LegalMetadata.hostingRegion}. '
              'O dado não sai do Brasil, então não há transferência '
              'internacional de dado a declarar aqui.',
            ),
            const LegalParagraph(
              'Não vendemos, não alugamos e não compartilhamos seus dados '
              'com mais ninguém. O app não usa ferramenta de anúncio, '
              'rastreamento de terceiro ou analytics de comportamento hoje.',
            ),

            const LegalHeading('Por quanto tempo guardamos'),
            const LegalParagraph(
              'Guardamos seu cadastro enquanto você não pedir a exclusão. '
              'Quando você sai de um Grupo, desiste de uma Ação ou troca de '
              'voto numa Rodada aberta, o registro antigo é apagado na '
              'hora — não fica arquivado escondido. Hoje não existe uma '
              'rotina automática que apague cadastro de quem parou de usar '
              'o app: o dado fica guardado até você pedir a exclusão, o que '
              'você pode fazer sozinho pelo app a qualquer momento.',
            ),
            const LegalParagraph(
              'Imagens de capa seguem o Grupo ou a Ação que ilustram — o '
              'prazo delas está na seção "Imagens de capa de Grupo e de '
              'Ação", acima.',
            ),
            const LegalParagraph(
              'As conversas têm prazos próprios: 30 dias depois da Ação, e '
              'sem prazo no Grupo. Estão detalhados na seção "Conversas em '
              'Grupos e Ações", acima.',
            ),

            const LegalHeading('Seus direitos e como usar cada um'),
            const LegalBullet(
              'Confirmar o que temos sobre você (acesso): abra "Meu Perfil" '
              'no app. Lá estão seu nome, Apelido, Igreja de origem, '
              'telefone, gênero, idade e a data em que você aceitou estes '
              'termos. Para qualquer coisa que a tela não mostre, escreva '
              'para ${LegalMetadata.contactEmail}.',
            ),
            const LegalBullet(
              'Corrigir um dado errado: nome, Apelido, Igreja de origem e '
              'telefone você corrige sozinho, na tela "Meu Perfil". Gênero e '
              'idade continuam sendo corrigidos por e-mail, em '
              '${LegalMetadata.contactEmail} — eles decidem regras do app '
              '(exigência de Apelido e composição de Dupla Missionária), e '
              'por isso não são editáveis sozinho por enquanto.',
            ),
            const LegalBullet(
              'Apagar sua conta e os dados dela: você mesmo faz, pelo app, em '
              '"Excluir conta". Apagamos seu nome, Apelido, telefone, Igreja '
              'de origem, gênero e idade, e seu acesso é encerrado na hora. '
              'Você sai dos Grupos de que participa e deixa de ocupar vaga em '
              'Ações que ainda vão acontecer. Se você for Dono de um Grupo ou '
              'tiver uma Rodada de votação aberta, elas passam para o '
              'Administrador do distrito — você não precisa transferir nada '
              'antes. A única situação em que o app recusa é quando você é o '
              'único Administrador do distrito: aí é preciso promover outro '
              'antes, senão o distrito fica sem quem o administre.',
            ),
            const LegalBullet(
              'O que você escreveu nas conversas: ao excluir a conta, o '
              'texto de todas as suas mensagens é apagado. No lugar fica '
              'apenas a marca de que houve uma mensagem ali, para a conversa '
              'continuar legível para quem ficou. Mensagem escrita por outra '
              'pessoa que cite você não sai por aí — o caminho é a denúncia, '
              'como explica a seção "Conversas em Grupos e Ações".',
            ),
            const LegalBullet(
              'O que continua existindo depois disso: o registro das Ações que '
              'já aconteceram, incluindo quem esteve presente, porque ele '
              'conta a história de outras pessoas também. Nesses registros '
              'você aparece como "Membro removido", sem nada que identifique '
              'quem era. Não há como desfazer nem recuperar — voltar significa '
              'um cadastro novo, sem ligação com o anterior.',
            ),
            const LegalBullet(
              'Retirar o consentimento a qualquer momento: mesmo canal — '
              'isso pode significar deixar de conseguir usar partes do app '
              'que dependem desse dado.',
            ),
            const LegalBullet(
              'Levar seus dados para outro lugar (portabilidade): '
              'respondemos manualmente, por e-mail, exportando o que temos '
              'num arquivo.',
            ),
            const LegalBullet(
              'Saber com quem compartilhamos: está na seção "Com quem '
              'compartilhamos", acima.',
            ),

            const LegalHeading('Crianças e adolescentes'),
            const LegalParagraph(
              'Este app é usado por crianças e adolescentes, porque '
              'atividades como Desbravadores (10 a 15 anos) e Aventureiros '
              '(6 a 9 anos) fazem parte da vida do distrito. Por isso:',
            ),
            const LegalBullet(
              'o nome real de quem é menor de idade nunca aparece '
              'publicamente — só o Apelido definido no cadastro;',
            ),
            const LegalBullet('a idade nunca é mostrada a mais ninguém;'),
            const LegalBullet(
              'o cadastro pergunta a idade logo no início, e aplica essas '
              'proteções automaticamente a partir dela;',
            ),
            const LegalBullet(
              'as conversas de Grupo e de Ação são só para quem tem 18 anos '
              'ou mais. Quem tem menos não lê e não escreve, e isso é '
              'conferido no banco de dados, não só na tela.',
            ),
            const LegalParagraph(
              'Para criança com menos de 13 anos, o cadastro só é concluído '
              'com a autorização de um responsável: o formulário pede o nome '
              'de quem autoriza, um contato dele, e uma caixa de autorização '
              'separada do aceite comum. Guardamos essas três coisas mais a '
              'data e a versão deste texto, para poder demonstrar que a '
              'autorização foi dada.',
            ),
            const LegalParagraph(
              'Duas coisas que é honesto dizer com todas as letras: o app '
              'NÃO verifica a identidade de quem marca essa caixa — não temos '
              'como saber se quem preencheu é mesmo o responsável — e o '
              'contato informado é REGISTRO, não canal: nunca escrevemos para '
              'ele. Para adolescente (13 a 17 anos), a lei não exige essa '
              'autorização, e nós recomendamos o acompanhamento de um '
              'responsável mesmo assim.',
            ),
            const LegalParagraph(
              'O nome e o contato do responsável são dados de uma pessoa que '
              'não usa o app. Só a própria criança e nós enxergamos esses '
              'campos — eles nunca aparecem para outros usuários — e eles são '
              'apagados junto quando a conta da criança é excluída.',
            ),
            const LegalParagraph(
              'Se você é o responsável e quer ver, corrigir ou apagar os '
              'dados da criança, escreva para ${LegalMetadata.contactEmail}. '
              'O contato que você registrou no cadastro é o que usamos para '
              'confirmar que quem está pedindo é quem autorizou. O Apelido '
              'protege quem já está cadastrado de ter o nome exposto, mas não '
              'substitui essa autorização.',
            ),

            const LegalHeading('Alterações nesta política'),
            const LegalParagraph(
              'Se mudarmos o que coletamos ou para que usamos, publicamos '
              'uma nova versão com data e número atualizados, e avisamos '
              'antes de qualquer mudança valer para quem já está '
              'cadastrado. O aceite dado numa versão não cobre finalidade '
              'nova que só a versão seguinte passe a ter.',
            ),

            const LegalHeading('Fale com a gente'),
            const LegalParagraph(
              '${LegalMetadata.controllerName} — ${LegalMetadata.contactEmail}.',
            ),

            // O direito de exclusão só é exercível se houver caminho até ele
            // dentro do app (FR-001). Enquanto não existe tela de "meu
            // perfil", este é o lugar coerente: fica ao lado do texto que
            // descreve o direito, e longe de um toque acidental na barra
            // principal.
            if (hasProfile) ...[
              const SizedBox(height: AppSpacing.lg),
              OutlinedButton(
                onPressed: () => context.push('/perfil'),
                child: const Text('Abrir Meu Perfil'),
              ),
              const SizedBox(height: AppSpacing.sm),
              OutlinedButton(
                onPressed: () => context.push('/delete-account'),
                style: OutlinedButton.styleFrom(foregroundColor: Colors.red),
                child: const Text('Excluir minha conta'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
