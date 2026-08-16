import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../action/action_providers.dart';
import '../../group/group_providers.dart';
import '../chat_providers.dart';
import 'chat_page.dart';

/// Decide se mostra a conversa — e, quando não mostra, DIZ POR QUÊ.
///
/// Esconder a conversa sem explicação é o pior desfecho possível aqui: a pessoa
/// vê os outros combinando coisas e não descobre por que ficou de fora. Pior
/// ainda para quem é menor de 18, que é justamente quem tende a concluir que o
/// app está quebrado, ou que foi excluída por alguém.
///
/// Por isso duas perguntas separadas ao banco: `pode_ver_chat_*` responde
/// "não" do mesmo jeito por idade e por não pertencer ao espaço, e sem
/// distinguir as duas a tela só saberia dizer "não dá". `maior_de_idade()`
/// separa.
class ChatGatePage extends ConsumerWidget {
  const ChatGatePage({required this.space, super.key});

  final ChatSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canSee = ref.watch(canSeeChatProvider(space));
    final isOfAge = ref.watch(isOfAgeProvider);

    // Nome e "está arquivado" são DERIVADOS aqui, não recebidos por `extra` do
    // GoRouter. Este app roda na web: `extra` morre num F5, e com ele morreria
    // o `readOnly` — a tela voltaria com campo de envio num Grupo arquivado, e
    // a recusa só apareceria como erro de servidor depois de a pessoa escrever.
    // Um título errado seria feio; um campo de envio errado é mentira.
    final groupId = space.groupId;
    final title = groupId != null
        ? ref.watch(groupProvider(groupId)).value?.name ?? 'Conversa'
        : ref.watch(actionProvider(space.actionId!)).value?.name ?? 'Conversa';
    final readOnly =
        groupId != null &&
        (ref.watch(groupProvider(groupId)).value?.isArchived ?? false);

    return canSee.when(
      loading: () => _Frame(
        title: title,
        child: const Center(child: CircularProgressIndicator()),
      ),
      error: (_, _) => _Frame(
        title: title,
        child: const _Explanation(
          icon: Icons.error_outline,
          text: 'Não deu pra abrir a conversa agora. Tente de novo.',
        ),
      ),
      data: (allowed) {
        if (allowed) {
          return ChatPage(space: space, title: title, readOnly: readOnly);
        }
        // Enquanto a idade não voltou, não dá para escolher a explicação — e
        // chutar a errada é pior do que esperar meio segundo.
        if (isOfAge.value == false) {
          return _Frame(
            title: title,
            child: const _Explanation(
              icon: Icons.lock_outline,
              text:
                  'A conversa é só para quem tem 18 anos ou mais.\n\n'
                  'Não é uma restrição do Grupo nem uma decisão de ninguém '
                  'sobre você: é uma regra do app, porque aqui as pessoas '
                  'escrevem texto livre e não há como moderar isso a tempo '
                  'para menores de idade.\n\n'
                  'Tudo o mais continua seu: participar, votar, propor e '
                  'confirmar presença.',
            ),
          );
        }
        if (isOfAge.isLoading) {
          return _Frame(
            title: title,
            child: const Center(child: CircularProgressIndicator()),
          );
        }
        return _Frame(
          title: title,
          child: const _Explanation(
            icon: Icons.group_outlined,
            text:
                'A conversa é de quem está nesta atividade.\n\n'
                'Num Grupo, de quem participa. Numa Ação, de quem confirmou '
                'presença ou está na fila — mais quem criou a Ação e quem é '
                'Dono do Grupo dela.',
          ),
        );
      },
    );
  }
}

class _Frame extends StatelessWidget {
  const _Frame({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: child,
    );
  }
}

class _Explanation extends StatelessWidget {
  const _Explanation({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 48),
            const SizedBox(height: AppSpacing.md),
            Text(text, textAlign: TextAlign.center),
          ],
        ),
      ),
    );
  }
}
