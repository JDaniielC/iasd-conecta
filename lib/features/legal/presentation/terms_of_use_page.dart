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
              'como "Membro removido". Os detalhes estão na Política de '
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
