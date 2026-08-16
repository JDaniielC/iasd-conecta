import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../chat_providers.dart';
import '../domain/chat_state.dart';
import '../domain/message.dart';

/// A conversa de um Grupo ou de uma Ação.
///
/// TELA PRÓPRIA, e não uma aba dentro da página de detalhe: as duas páginas de
/// detalhe são coluna única e não têm abas, e na largura de celular — que é
/// onde este app se julga — uma conversa dentro de aba disputa espaço com o
/// teclado e com a rolagem da página que a contém. A entrada condicional
/// continua na página de detalhe, que é o que o requisito quer: só aparece
/// para quem pode ver.
class ChatPage extends ConsumerStatefulWidget {
  const ChatPage({
    required this.space,
    required this.title,
    this.readOnly = false,
    super.key,
  });

  final ChatSpace space;

  /// Nome do Grupo ou da Ação. Vem de fora porque esta tela não carrega o
  /// espaço — ela conversa, o detalhe apresenta.
  final String title;

  /// Grupo arquivado é histórico legível sem campo de envio. Não é caso de
  /// erro nem de tela vazia: o histórico é justamente o que sobra de um Grupo
  /// arquivado.
  final bool readOnly;

  @override
  ConsumerState<ChatPage> createState() => _ChatPageState();
}

/// O limite vive no `check` de `mensagens_texto_no_limite`. Repetido aqui
/// para a recusa nunca chegar como erro de servidor — a pessoa vê o contador
/// antes de apertar enviar.
const _maxLength = 2000;

class _ChatPageState extends ConsumerState<ChatPage> {
  final _controller = TextEditingController();
  final _scroll = ScrollController();
  var _sending = false;

  @override
  void dispose() {
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A TELA NÃO COMPÕE LISTA, e é a costura da convergência 5.
  ///
  /// Antes, ela guardava duas sobreposições próprias — a mensagem recém-enviada
  /// e as páginas anteriores — e as juntava com o estado do servidor no
  /// `build`. Eram dois dos quatro lugares onde a lista se compunha, e nos dois
  /// a cópia local ganhava do servidor em algum caminho: remover com o canal
  /// caído deixava o texto na tela de quem removeu, e o expurgo não alcançava
  /// as páginas antigas. Agora as três fontes moram no `ChatNotifier`, com uma
  /// regra só; aqui só se pede o que fazer.
  Future<void> _send() async {
    final text = _controller.text.trim();
    if (text.isEmpty || text.length > _maxLength) return;

    setState(() => _sending = true);
    try {
      await ref.read(chatProvider(widget.space).notifier).send(text);
      _controller.clear();
    } catch (_) {
      if (mounted) _warn('Não deu pra enviar agora. Tente de novo.');
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  String get _reportsRoute => widget.space.groupId != null
      ? '/grupos/${widget.space.groupId}/denuncias'
      : '/acoes/${widget.space.actionId}/denuncias';

  Future<void> _loadOlder() async {
    try {
      await ref.read(chatProvider(widget.space).notifier).loadOlder();
    } catch (_) {
      if (mounted) _warn('Não deu pra carregar o que veio antes.');
    }
  }

  void _warn(String message) {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(message)));
  }

  @override
  Widget build(BuildContext context) {
    final chatAsync = ref.watch(chatProvider(widget.space));

    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: [
          // Só para quem manda no espaço. Quem denunciou não vê esta lista nem
          // a própria denúncia — `pode_moderar_espaco` deixa denunciante e
          // denunciado de fora de propósito.
          if (ref.watch(canModerateSpaceProvider(widget.space)).value ?? false)
            IconButton(
              icon: const Icon(Icons.flag_outlined),
              tooltip: 'Mensagens denunciadas',
              onPressed: () => context.push(_reportsRoute),
            ),
        ],
      ),
      body: Column(
        children: [
          _ConnectionBanner(connection: chatAsync.value?.connection),
          Expanded(
            child: chatAsync.when(
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const _CenteredMessage('Não deu pra carregar a conversa.'),
              data: (state) {
                final messages = state.messages;
                if (messages.isEmpty) {
                  return const _CenteredMessage(
                    'Ninguém falou nada ainda.\n\n'
                    'Combinar o que levar, quem busca quem, a que horas — '
                    'é pra isso que esta conversa existe.',
                  );
                }
                return _MessageList(
                  messages: messages,
                  scroll: _scroll,
                  space: widget.space,
                  onLoadOlder: state.hasMoreOlder ? _loadOlder : null,
                  loadingOlder: state.loadingOlder,
                );
              },
            ),
          ),
          if (!widget.readOnly)
            _Composer(
              controller: _controller,
              sending: _sending,
              onSend: _send,
            ),
        ],
      ),
    );
  }
}

/// Diz o estado do canal, e só quando ele NÃO está bom.
///
/// Uma faixa permanente dizendo "ao vivo" vira ruído que ninguém lê — e aí,
/// quando ela mudar para "reconectando", ninguém lê também.
class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.connection});

  final ChatConnection? connection;

  @override
  Widget build(BuildContext context) {
    // Só aparece quando NÃO está bom. Uma faixa permanente dizendo "ao vivo"
    // vira ruído que ninguém lê — e aí, quando ela mudar para "reconectando",
    // ninguém lê também.
    if (connection == null || connection == ChatConnection.live) {
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final text = connection == ChatConnection.reconnecting
        ? 'Reconectando. O que chegar agora pode demorar a aparecer.'
        : 'Sem tempo real. A conversa funciona, mas você precisa reabrir para '
              'ver o que chegou.';

    return Container(
      width: double.infinity,
      color: theme.colorScheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.sm,
      ),
      child: Text(text, style: theme.textTheme.labelMedium),
    );
  }
}

class _MessageList extends ConsumerWidget {
  const _MessageList({
    required this.messages,
    required this.scroll,
    required this.space,
    required this.onLoadOlder,
    required this.loadingOlder,
  });

  final List<Message> messages;
  final ScrollController scroll;
  final ChatSpace space;

  /// Nulo quando não há mais o que carregar. O botão some, em vez de continuar
  /// oferecendo uma ida ao servidor que não traz nada.
  final Future<void> Function()? onLoadOlder;
  final bool loadingOlder;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // O item extra vai no FIM da lista invertida, que é o topo da tela — onde
    // a pessoa chega quando rola para trás procurando o que veio antes.
    final extra = onLoadOlder == null ? 0 : 1;

    return ListView.builder(
      controller: scroll,
      // `reverse` mantém a conversa colada no fim sem cálculo de rolagem: a
      // mensagem nova nasce onde o olho já está.
      reverse: true,
      padding: const EdgeInsets.all(AppSpacing.md),
      itemCount: messages.length + extra,
      itemBuilder: (context, i) {
        if (i == messages.length) {
          return Center(
            child: loadingOlder
                ? const Padding(
                    padding: EdgeInsets.all(AppSpacing.md),
                    child: CircularProgressIndicator(),
                  )
                : TextButton(
                    onPressed: () => onLoadOlder!(),
                    child: const Text('Carregar o que veio antes'),
                  ),
          );
        }
        return _MessageTile(
          message: messages[messages.length - 1 - i],
          space: space,
        );
      },
    );
  }
}

class _MessageTile extends ConsumerWidget {
  const _MessageTile({required this.message, required this.space});

  final Message message;
  final ChatSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final uid = ref.watch(currentUserIdProvider);
    final isMine = message.authorId == uid;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            message.authorName ?? 'Alguém',
            style: theme.textTheme.labelMedium,
          ),
          const SizedBox(height: AppSpacing.xs),
          _MessageBody(message: message),
          if (message.tombstone == MessageTombstone.visible)
            _MessageActions(message: message, isMine: isMine, space: space),
        ],
      ),
    );
  }
}

/// As três lápides, com textos DISTINTOS.
///
/// "Removida" e "de conta excluída" são fatos diferentes, e quem lê merece
/// saber qual foi: um diz que alguém decidiu tirar aquilo dali, o outro diz que
/// a pessoa foi embora e levou o que era dela. Escrever a mesma frase para os
/// dois seria mais fácil e mentiria em metade dos casos.
class _MessageBody extends StatelessWidget {
  const _MessageBody({required this.message});

  final Message message;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.textTheme.bodyMedium?.copyWith(
      fontStyle: FontStyle.italic,
      color: theme.colorScheme.onSurfaceVariant,
    );

    return switch (message.tombstone) {
      MessageTombstone.visible => Text(
        message.text!,
        style: theme.textTheme.bodyMedium,
      ),
      MessageTombstone.removedByModeration => Text(
        'Mensagem removida.',
        style: muted,
      ),
      MessageTombstone.authorDeletedAccount => Text(
        'Mensagem de conta excluída.',
        style: muted,
      ),
    };
  }
}

class _MessageActions extends ConsumerWidget {
  const _MessageActions({
    required this.message,
    required this.isMine,
    required this.space,
  });

  final Message message;
  final bool isMine;
  final ChatSpace space;

  Future<void> _remove(BuildContext context, WidgetRef ref) async {
    // REMOÇÃO PEDE CONFIRMAÇÃO E AVISA QUE É DEFINITIVO, porque é: o texto não
    // é guardado em lugar nenhum, nem para quem removeu. Quem remove precisa
    // ler antes, porque depois não dá para reconsiderar.
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover esta mensagem?'),
        content: const Text(
          'O texto vai sumir para todo mundo, inclusive para você, e não fica '
          'guardado em lugar nenhum. Não dá para desfazer.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Remover'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;

    try {
      // Pelo NOTIFIER, não pelo repositório direto: a remoção precisa aparecer
      // na tela de quem a pediu mesmo com o canal caído. Enquanto esta linha
      // chamava o repositório, o `update` acontecia no banco e o texto
      // continuava desenhado — sem erro e sem lápide —, e a spec de moderação
      // diz que o texto removido não volta para ninguém.
      await ref.read(chatProvider(space).notifier).remove(message.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você não pode remover esta mensagem.')),
        );
      }
    }
  }

  Future<void> _report(BuildContext context, WidgetRef ref) async {
    final controller = TextEditingController();
    // MOTIVO OBRIGATÓRIO, e a recusa é local: o `check` do banco também recusa
    // motivo vazio, mas chegar lá para ouvir não é resposta que se dê a quem
    // está denunciando alguma coisa.
    final reason = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Denunciar esta mensagem'),
        content: TextField(
          controller: controller,
          maxLines: 3,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'O que há de errado?',
            hintText: 'Conte com suas palavras. Quem analisa lê isto.',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () {
              final text = controller.text.trim();
              if (text.isEmpty) return;
              Navigator.pop(context, text);
            },
            child: const Text('Denunciar'),
          ),
        ],
      ),
    );
    controller.dispose();
    if (reason == null || !context.mounted) return;

    try {
      await ref.read(chatRepositoryProvider).reportMessage(message.id, reason);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Denúncia enviada. Quem cuida do espaço vai ver.'),
          ),
        );
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não deu pra denunciar agora.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    // Oferecer "Remover" a todo leitor era o que os Termos chamam de "mais
    // ninguém" desmentido pela tela. O banco recusava e a recusa aparecia
    // alto — mas só DEPOIS de a pessoa ler um diálogo dizendo "o texto vai
    // sumir para todo mundo" sobre uma mensagem que ela não podia tocar.
    final canModerate =
        ref.watch(canModerateSpaceProvider(space)).value ?? false;

    return Row(
      children: [
        if (isMine || canModerate)
          TextButton(
            onPressed: () => _remove(context, ref),
            child: const Text('Remover'),
          ),
        // Denunciar a própria mensagem não faz sentido: quem escreveu pode
        // simplesmente remover.
        if (!isMine)
          TextButton(
            onPressed: () => _report(context, ref),
            child: const Text('Denunciar'),
          ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.sending,
    required this.onSend,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onChanged);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onChanged);
    super.dispose();
  }

  void _onChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final length = widget.controller.text.trim().length;
    final tooLong = length > _maxLength;
    final canSend = !widget.sending && length > 0 && !tooLong;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 5,
                    // SEM `maxLength` no campo: cortar a digitação no 2000 faz
                    // a frase sumir por baixo do dedo sem explicação. O
                    // contador avisa, o botão fecha, e a pessoa decide o que
                    // tirar.
                    decoration: const InputDecoration(
                      hintText: 'Escreva uma mensagem',
                    ),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.send),
                  onPressed: canSend ? () => widget.onSend() : null,
                  tooltip: 'Enviar',
                ),
              ],
            ),
            // O contador só aparece quando começa a importar. Mostrar
            // "0/2000" numa conversa de "às 19h" é ruído.
            if (length > _maxLength - 200)
              Text(
                '$length/$_maxLength',
                style: Theme.of(context).textTheme.labelSmall?.copyWith(
                  color: tooLong ? Theme.of(context).colorScheme.error : null,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _CenteredMessage extends StatelessWidget {
  const _CenteredMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Text(text, textAlign: TextAlign.center),
      ),
    );
  }
}
