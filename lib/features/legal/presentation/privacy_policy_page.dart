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
    final hasPerfil = ref.watch(hasPerfilProvider).value ?? false;
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
              'confirma presença numa Ação, propõe uma Ação candidata ou '
              'vota numa Rodada de votação.',
            ),
            const LegalBullet('Quais Grupos você participa.'),
            const LegalBullet('Em quais Ações você confirmou presença.'),
            const LegalBullet(
              'Em qual candidata você votou, dentro de uma Rodada de '
              'votação do seu Grupo — o voto não é anônimo entre os '
              'participantes do Grupo.',
            ),
            const LegalBullet(
              'Se você é Administrador do distrito, ou se autodeclarou '
              'Líder/Diretor de um Ministério — nesse último caso, mesmo '
              'enquanto a declaração ainda está pendente de confirmação.',
            ),
            const LegalParagraph(
              'Nunca ficam públicos, para ninguém: sua idade, seu telefone, '
              'seu gênero.',
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

            const LegalHeading('Seus direitos e como usar cada um'),
            const LegalBullet(
              'Confirmar o que temos sobre você (acesso): escreva para '
              '${LegalMetadata.contactEmail}. Hoje isso é respondido '
              'manualmente — ainda não existe uma tela própria de "meu '
              'perfil" para conferir sozinho.',
            ),
            const LegalBullet(
              'Corrigir um dado errado: mesmo canal, por e-mail, enquanto '
              'não existe tela de edição de perfil dentro do app.',
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
              'proteções automaticamente a partir dela.',
            ),
            const LegalParagraph(
              'O Apelido protege quem já está cadastrado de ter o nome '
              'exposto — mas não substitui a autorização de um responsável. '
              'Se você é pai, mãe ou responsável por uma criança (até 12 '
              'anos), o cadastro dela precisa ser feito por você ou com '
              'você presente, e é você quem aceita esta política e os '
              'Termos de Uso em nome dela. Para adolescente (13 a 17 anos), '
              'recomendamos o mesmo acompanhamento, mesmo quando a lei '
              'permite alguma flexibilidade nessa faixa.',
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
            if (hasPerfil) ...[
              const SizedBox(height: AppSpacing.lg),
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
