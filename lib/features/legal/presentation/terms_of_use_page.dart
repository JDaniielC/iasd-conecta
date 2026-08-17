import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../legal_metadata.dart';
import 'widgets/legal_text.dart';

/// Termos de Uso da Rede IASD Vitória de Santo Antão.
///
/// Ver MAPA-DE-DADOS.md (raiz do repo) para a evidência de cada regra
/// descrita aqui, e REVISAO-JURIDICA.md para o que ainda depende de
/// confirmação jurídica.
class TermsOfUsePage extends StatelessWidget {
  const TermsOfUsePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Termos de Uso')),
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
              'Estes termos explicam as regras de uso deste app. Ao criar um '
              'Perfil ou uma Conta, você concorda com elas. Se você só '
              'navega sem se cadastrar (Visitante), as regras sobre '
              'cadastro e participação não valem para você — só as de '
              'conduta e as de propriedade do conteúdo.',
            ),

            const LegalHeading('O que é este app'),
            const LegalParagraph(
              'Uma ferramenta de organização comunitária para os membros '
              'ativos da Igreja Adventista do Sétimo Dia do distrito de '
              'Vitória de Santo Antão descobrirem e se conectarem através '
              'de Grupos (comunidades permanentes, como um clube ou um '
              'ministério) e Ações (eventos pontuais, com data e hora). Este '
              'app não é um canal oficial de comunicação da igreja nem '
              'substitui a liderança pastoral — é um espaço mantido de '
              'forma independente para facilitar a organização entre '
              'membros.',
            ),

            const LegalHeading('Cadastro: Perfil e Conta'),
            const LegalBullet(
              'Perfil é o cadastro padrão: nome, gênero, idade e '
              'consentimento LGPD, sem exigir e-mail ou senha. Ele vive só '
              'no aparelho — se você reinstalar o app ou trocar de '
              'aparelho antes de virar Conta, o Perfil se perde.',
            ),
            const LegalBullet(
              'Conta é um upgrade opcional: vincula e-mail e senha, para '
              'recuperar o mesmo cadastro em outro aparelho. Só é '
              'obrigatória se você quiser se declarar Administrador do '
              'distrito ou Líder/Diretor de Ministério — papéis cuja '
              'identificação é pública e não pode se perder com uma '
              'reinstalação.',
            ),
            const LegalBullet(
              'Menor de 18 anos precisa definir um Apelido antes de '
              'concluir o cadastro. O Apelido substitui o nome real em '
              'qualquer exibição pública.',
            ),
            const LegalBullet(
              'O nome informado passa por uma checagem automática contra '
              'palavras ofensivas. Nome recusado precisa ser trocado antes '
              'do cadastro ser concluído.',
            ),
            const LegalBullet(
              'As conversas de Grupo e de Ação são só para quem tem 18 anos '
              'ou mais. Todo o resto do app funciona igual para quem tem '
              'menos — a regra vale só para a conversa.',
            ),

            const LegalHeading('Conduta esperada'),
            const LegalParagraph(
              'Este app serve a uma comunidade real. Ao usá-lo, você '
              'concorda em:',
            ),
            const LegalBullet(
              'não usar nome, Apelido, nome de Grupo ou de Ação ofensivo, '
              'falso ou que se passe por outra pessoa;',
            ),
            const LegalBullet(
              'informar dados verdadeiros sobre você — gênero e idade '
              'incluídos, já que ambos afetam regras do app (como a '
              'composição da Dupla Missionária e a exigência de Apelido);',
            ),
            const LegalBullet(
              'respeitar que Participar de um Grupo, confirmar presença '
              'numa Ação e votar numa Rodada são públicos para outros '
              'participantes, e agir de acordo.',
            ),

            const LegalHeading('Papéis dentro do app'),
            const LegalBullet(
              'Dono do Grupo administra o Grupo que criou (ou para o qual '
              'recebeu a posse): edita informações, remove participante, '
              'encerra Rodada de votação antes do prazo e cancela Ação do '
              'Grupo.',
            ),
            const LegalBullet(
              'Administrador do distrito gerencia a lista de igrejas do '
              'distrito e pode cancelar qualquer Ação. É promovido só por '
              'outro Administrador já existente, nunca por autodeclaração.',
            ),
            const LegalBullet(
              'Líder/Diretor de Ministério é uma autodeclaração, confirmada '
              'ou rejeitada pelo Administrador do distrito, com identificação '
              'pública no Grupo. O título expira todo mês de janeiro e '
              'precisa ser redeclarado.',
            ),
            const LegalParagraph(
              'Nenhum desses papéis representa cargo oficial da igreja '
              'nem substitui a autoridade de pastores, diretores de '
              'departamento ou outra liderança eclesiástica — são papéis de '
              'administração do app.',
            ),

            const LegalHeading('Conteúdo que você envia'),
            const LegalParagraph(
              'Você continua responsável pelo que escreve (nome de Grupo, '
              'de Ação, detalhes, horário, local). Podemos recusar ou '
              'remover conteúdo que viole estes termos, especialmente nome '
              'ofensivo bloqueado pela checagem automática.',
            ),

            const LegalHeading('Conversas em Grupos e Ações'),
            const LegalParagraph(
              'Cada Grupo e cada Ação tem uma conversa, para combinar o que '
              'precisa ser combinado. Só texto, até 2000 caracteres por '
              'mensagem, e só para quem tem 18 anos ou mais. As regras '
              'abaixo valem para toda mensagem que você escrever.',
            ),
            const LegalBullet(
              'Você responde pelo que escreve. A mensagem é sua, sai com o '
              'seu nome para as outras pessoas da conversa, e a '
              'responsabilidade pelo conteúdo é de quem escreveu — não do '
              'app, não do Dono do Grupo.',
            ),
            const LegalBullet(
              'Não escreva dado pessoal de outra pessoa: telefone, endereço, '
              'situação de saúde, nem informação sobre criança ou '
              'adolescente. Escreva o necessário para combinar a atividade.',
            ),
            const LegalBullet(
              'Não use a conversa para ofender, ameaçar, discriminar, '
              'constranger, fazer propaganda ou vender. Além de a mensagem '
              'ser removida, o Dono do Grupo pode remover você do Grupo.',
            ),
            // A change `filtro-e-intervalo-de-mensagem` tornou FALSA a frase
            // que estava aqui ("nada do que você escreve é checado antes de
            // aparecer"). Existe filtro, ele recusa na ESCRITA
            // (`mensagens_filtro_de_palavra_trigger`, 20260816160000:223), e
            // regra que recusa conteúdo sem estar escrita em lugar nenhum é a
            // pior versão disso.
            //
            // O LIMITE do filtro entra no mesmo fôlego, e não é rodapé: a
            // lista casa palavra inteira, então falso negativo é o caso comum
            // (design.md → Risks). Prometer detecção de contexto, sigla ou
            // grafia trocada seria promessa que o código não cumpre.
            const LegalBullet(
              'Antes de a mensagem sair, o app confere se ela tem alguma '
              'palavra que este distrito não aceita. Se tiver, a mensagem não '
              'é enviada: ela não chega a ser gravada e ninguém na conversa '
              'vê nada. Você fica sabendo na hora qual palavra causou a '
              'recusa, o texto que você digitou continua no campo, e dá para '
              'corrigir e mandar de novo.',
            ),
            const LegalBullet(
              'Essa conferência é limitada, e é honesto dizer o quanto: ela '
              'compara palavras inteiras com uma lista. Não entende contexto, '
              'não pega palavra escrita de propósito com letra trocada ou '
              'espaço no meio, nem ofensa montada sem palavrão — e esse é o '
              'caso mais comum. O filtro tira o óbvio da frente; para todo o '
              'resto, o caminho continua sendo denunciar a mensagem, e a '
              'moderação continua sendo humana.',
            ),
            const LegalBullet(
              'A mesma conferência vale para o motivo que você escreve ao '
              'denunciar uma mensagem. Se o motivo tiver palavra da lista, a '
              'denúncia não é registrada, e o aviso diz qual palavra foi.',
            ),
            const LegalBullet(
              'A lista de palavras não fica à vista no app e é mantida fora '
              'dele. Se uma palavra comum foi recusada e você acha que não '
              'deveria, escreva para ${LegalMetadata.contactEmail}: uma '
              'pessoa lê e decide. A recusa é automática; a revisão dela é '
              'humana.',
            ),
            const LegalBullet(
              'Existe um limite de ritmo, contado por conversa: 3 segundos '
              'entre uma mensagem sua e a seguinte, e no máximo 20 mensagens '
              'suas a cada 5 minutos na mesma conversa. É para ninguém '
              'conseguir encher o espaço de todo mundo. O limite conta '
              'separado em cada Grupo e em cada Ação — falar em dois lugares '
              'ao mesmo tempo não atrapalha.',
            ),
            const LegalBullet(
              'Passar do limite é só esperar. Você não é bloqueado, não é '
              'silenciado, não entra em lista nenhuma, e isso não pesa contra '
              'você depois. O app mostra quanto falta e libera o envio '
              'sozinho quando o tempo passa. E nada é guardado sobre a '
              'tentativa recusada: não fica registro de que você tentou '
              'enviar e não deu.',
            ),
            const LegalBullet(
              'Mensagem enviada não se edita. Errou, remove — não reescreve. '
              'E remover é definitivo: o texto não fica guardado em lugar '
              'nenhum, nem para quem removeu. Quem remove precisa ler antes, '
              'porque depois não dá para reconsiderar.',
            ),
            const LegalBullet(
              'Quem pode remover uma mensagem: quem a escreveu; o Dono do '
              'Grupo, na conversa do Grupo dele; o criador da Ação e o Dono '
              'do Grupo dela, na conversa da Ação; e o Administrador do '
              'distrito, em qualquer conversa. Mais ninguém.',
            ),
            const LegalBullet(
              'Qualquer pessoa que lê a conversa pode denunciar uma '
              'mensagem, e o motivo é obrigatório. A denúncia é vista só por '
              'quem pode resolvê-la, e não pela pessoa denunciada. O motivo '
              'que você escrever fica registrado como a história do caso, '
              'inclusive depois de a mensagem deixar de existir.',
            ),
            const LegalBullet(
              'Em Grupo arquivado a conversa vira só leitura: o histórico '
              'continua lá para quem participava, e ninguém escreve mais '
              'nada.',
            ),
            const LegalParagraph(
              'A conversa do Grupo fica guardada sem prazo; a da Ação é '
              'apagada 30 dias depois da data e hora dela. Isso, e o que '
              'acontece com as suas mensagens quando você exclui a conta, '
              'está na Política de Privacidade.',
            ),
            const LegalParagraph(
              'A conversa não é canal de emergência nem canal oficial da '
              'igreja. Não conte com ela para avisar algo urgente: pode não '
              'haver ninguém lendo do outro lado.',
            ),

            const LegalHeading('Disponibilidade do app'),
            const LegalParagraph(
              'Este app é mantido de forma independente. Fazemos o '
              'possível para mantê-lo no ar, mas não garantimos '
              'disponibilidade contínua nem ausência de erros.',
            ),

            const LegalHeading('Encerramento de conta'),
            const LegalParagraph(
              'Você pode excluir sua conta a qualquer momento, sozinho, pelo '
              'app. Se você for Dono de um Grupo ou tiver uma Rodada de '
              'votação aberta, elas passam automaticamente para o '
              'Administrador do distrito, para que ninguém perca o Grupo de '
              'que participa. A exclusão é definitiva, e o registro das Ações '
              'que já aconteceram permanece, com você identificado apenas '
              'como "Membro removido". O texto das mensagens que você '
              'escreveu nas conversas é apagado junto, restando só a marca '
              'de que houve uma mensagem ali. Mensagem escrita por outra '
              'pessoa que cite você não é apagada por isso — para tirá-la do '
              'ar, o caminho é a denúncia. Os detalhes estão na Política de '
              'Privacidade.',
            ),
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.md),
              child: TextButton(
                onPressed: () => context.push('/privacidade'),
                child: const Text('Ler a Política de Privacidade completa'),
              ),
            ),

            const LegalHeading('Alterações nestes termos'),
            const LegalParagraph(
              'Se mudarmos uma regra que afete o que você já faz no app, '
              'publicamos uma nova versão com data e número atualizados e '
              'avisamos antes dela valer para quem já está cadastrado.',
            ),

            const LegalHeading('Lei aplicável'),
            const LegalParagraph(
              'Estes termos seguem a lei brasileira, em especial a Lei '
              'Geral de Proteção de Dados (LGPD, Lei 13.709/2018) e o '
              'Marco Civil da Internet (Lei 12.965/2014).',
            ),
          ],
        ),
      ),
    );
  }
}
