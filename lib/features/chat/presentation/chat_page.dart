import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../chat_providers.dart';
import '../domain/chat_limits.dart';
import '../domain/chat_state.dart';
import '../domain/message.dart';
import '../domain/send_refusal.dart';
import '../domain/send_refusal_message.dart';

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

  /// A última recusa do banco, enquanto ela ainda importa.
  SendRefusal? _refusal;

  /// Quanto ainda falta para o envio reabrir. Nulo quando não há espera — é o
  /// caso da recusa por palavra, que se corrige editando o texto e não
  /// esperando.
  ///
  /// **CONTAGEM E NÃO HORÁRIO-ALVO.** Guardar um `DateTime` de quando libera e
  /// comparar com `DateTime.now()` parece mais correto, e é pior por dois
  /// motivos. O prático: `DateTime.now()` não anda em teste de widget — o
  /// relógio que `tester.pump` move é o dos `Timer`, não o do calendário —,
  /// então a contagem regressiva ficaria sem nenhuma prova de que anda. O de
  /// desenho: quem decide é o servidor, sempre. Esta contagem é cortesia para a
  /// pessoa não apertar em vão; se ela atrasar um segundo, o custo é um segundo
  /// de espera a mais, e nunca um envio liberado cedo demais.
  Duration? _remaining;

  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTextChanged);
  }

  @override
  void dispose() {
    _ticker?.cancel();
    _controller.removeListener(_onTextChanged);
    _controller.dispose();
    _scroll.dispose();
    super.dispose();
  }

  /// A faixa de palavra bloqueada some assim que a pessoa mexe no texto.
  ///
  /// **As duas recusas expiram de jeitos diferentes, e é por isso que existe
  /// este listener.** A de ritmo tem `retryAfter`, então o relógio a apaga
  /// sozinho. A de palavra não tem tempo — ela se corrige EDITANDO —, e sem
  /// isto ficava na tela até um envio dar certo: "a palavra X não é aceita,
  /// troque essa parte" continuava dito depois de a pessoa ter trocado.
  ///
  /// Só a de palavra sai daqui. Apagar a de ritmo ao digitar seria mentir ao
  /// contrário: o envio continua fechado, e a explicação de por quê tem de
  /// continuar à vista.
  void _onTextChanged() {
    if (_refusal?.kind == SendRefusalKind.blockedWord) _clearRefusal();
  }

  /// Registra a recusa e, quando ela é de ritmo, fecha o envio até dar a hora.
  ///
  /// **O TEXTO DIGITADO NÃO É TOCADO AQUI, e é metade do requisito.** Só o
  /// caminho de sucesso limpa o campo. Perder a frase por causa de uma recusa
  /// que se corrige esperando 3 segundos seria transformar um limite de ritmo
  /// numa punição.
  void _applyRefusal(SendRefusal refusal) {
    _ticker?.cancel();
    setState(() {
      _refusal = refusal;
      _remaining = refusal.retryAfter;
    });

    if (_remaining != null) {
      _startTicker();
      return;
    }

    // RECUSA DE RITMO SEM TEMPO. `retryAfter` nulo acontece quando o `hint` não
    // chega ou não é número — o caso que `SendRefusal._seconds` trata de
    // propósito. Aqui não há relógio para descontar, e sem esta guarda a faixa
    // ficava na tela para sempre: `_onTextChanged` só apaga a de palavra, e
    // nenhum outro caminho a alcançava.
    //
    // O envio fica ABERTO, e isso é decisão: a tela não sabe até quando esperar,
    // e fechar o botão por tempo indeterminado seria pior do que deixar a pessoa
    // tentar e o servidor decidir. O que expira é só a explicação, depois do
    // tempo de leitura dela.
    if (refusal.kind != SendRefusalKind.blockedWord) {
      _ticker = Timer(const Duration(seconds: 5), () {
        if (mounted) _clearRefusal();
      });
    }
  }

  /// Desconta um segundo por vez até liberar.
  void _startTicker() {
    // O ENVIO VOLTA SOZINHO. Sem o relógio, o botão ficaria fechado até a
    // pessoa digitar alguma coisa — e ela ficaria olhando um contador parado
    // sem saber se já pode tentar.
    _ticker = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) return timer.cancel();
      final left = _remaining! - const Duration(seconds: 1);
      if (left <= Duration.zero) {
        timer.cancel();
        _clearRefusal();
      } else {
        setState(() => _remaining = left);
      }
    });
  }

  void _clearRefusal() {
    _ticker?.cancel();
    setState(() {
      _refusal = null;
      _remaining = null;
    });
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
    if (_remaining != null) return;

    setState(() => _sending = true);
    try {
      await ref.read(chatProvider(widget.space).notifier).send(text);
      _controller.clear();
      if (mounted) _clearRefusal();
    } on SendRefusal catch (refusal) {
      // A recusa que o banco EXPLICA fica na tela, não num aviso que some. Um
      // `SnackBar` de três segundos para uma espera de três segundos é a pessoa
      // perdendo a explicação junto com o tempo.
      if (mounted) _applyRefusal(refusal);
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
          _PinnedBanner(
            pinned: chatAsync.value?.pinned ?? const [],
            space: widget.space,
          ),
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
              refusal: _refusal,
              remaining: _remaining,
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

/// A faixa de mensagens fixadas, acima da conversa.
///
/// **RECOLHIDA POR PADRÃO, e isto é requisito e não gosto.** O teto é 3 e a
/// mensagem vai a 2000 caracteres: três fixadas por extenso ocupam mais que uma
/// tela de celular inteira, e a conversa — que é o motivo de a pessoa ter
/// aberto — ficaria abaixo do primeiro rolar. Recolhida, cada fixada ocupa uma
/// linha; sob toque, a faixa expande.
///
/// O julgamento é NA LARGURA DE CELULAR, não no desktop: é onde a faixa compete
/// com a conversa, e onde o desenho quebra primeiro.
///
/// Expandida ela também tem teto de altura, e o resto rola DENTRO dela. Sem
/// isso, expandir devolveria o problema que recolher resolveu — só que depois
/// de um toque, que é pior, porque aí a pessoa não sabe como voltar.
///
/// Sem fixada, NADA ocupa espaço — nem uma faixa vazia dizendo que não há
/// nada fixado.
class _PinnedBanner extends StatefulWidget {
  const _PinnedBanner({required this.pinned, required this.space});

  final List<Message> pinned;
  final ChatSpace space;

  @override
  State<_PinnedBanner> createState() => _PinnedBannerState();
}

class _PinnedBannerState extends State<_PinnedBanner> {
  var _expanded = false;

  @override
  Widget build(BuildContext context) {
    if (widget.pinned.isEmpty) return const SizedBox.shrink();

    final theme = Theme.of(context);
    final count = widget.pinned.length;

    return Material(
      color: theme.colorScheme.surfaceContainerHighest,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          InkWell(
            onTap: () => setState(() => _expanded = !_expanded),
            child: Padding(
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  const Icon(Icons.push_pin_outlined, size: 18),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Text(
                      // O TETO APARECE QUANDO ESTÁ CHEIO, e só então. Dizer
                      // "1 de 3" o tempo todo transformaria um limite raro em
                      // ruído permanente; dizer "3 de 3" no momento em que ele
                      // passa a valer é a única hora em que o número informa
                      // alguma coisa. Sem isto, quem modera só descobre o
                      // limite depois de escolher a mensagem e levar a recusa.
                      switch (count) {
                        1 => '1 mensagem fixada',
                        final n when n >= ChatLimits.pinnedCeiling =>
                          '$n de ${ChatLimits.pinnedCeiling} mensagens fixadas',
                        final n => '$n mensagens fixadas',
                      },
                      style: theme.textTheme.labelLarge,
                    ),
                  ),
                  Icon(_expanded ? Icons.expand_less : Icons.expand_more),
                ],
              ),
            ),
          ),
          // A altura máxima é fração da TELA e não um número de pixels: o mesmo
          // valor fixo que caberia num celular grande engoliria um pequeno.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(context).height * 0.35,
            ),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final message in widget.pinned)
                    _PinnedTile(
                      message: message,
                      space: widget.space,
                      expanded: _expanded,
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Uma fixada na faixa. Recolhida mostra a PRIMEIRA LINHA; expandida, o texto
/// inteiro.
class _PinnedTile extends ConsumerWidget {
  const _PinnedTile({
    required this.message,
    required this.space,
    required this.expanded,
  });

  final Message message;
  final ChatSpace space;
  final bool expanded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final uid = ref.watch(currentUserIdProvider);
    final canModerate =
        ref.watch(canModerateSpaceProvider(space)).value ?? false;
    // DESFIXAR é da autoridade OU do autor, e o braço do autor é o que devolve
    // a ele o controle do prazo do que escreveu: fixada não expira.
    final canUnpin = canModerate || message.authorId == uid;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        0,
        AppSpacing.sm,
        AppSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.authorName ?? 'Alguém',
                  style: theme.textTheme.labelSmall,
                ),
                Text(
                  // A faixa NUNCA desenha lápide: o gatilho do banco desfixa a
                  // mensagem que perde o texto, então este `??` é piso e não
                  // caso. Uma marca de "mensagem removida" no alto do chat
                  // ocuparia vaga do teto sem informar nada.
                  message.text ?? '',
                  style: theme.textTheme.bodyMedium,
                  maxLines: expanded ? null : 1,
                  overflow: expanded
                      ? TextOverflow.clip
                      : TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
          if (canUnpin)
            IconButton(
              icon: const Icon(Icons.push_pin, size: 18),
              tooltip: 'Desfixar',
              onPressed: () => _unpin(context, ref),
            ),
        ],
      ),
    );
  }

  Future<void> _unpin(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(chatProvider(space).notifier).unpin(message.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você não pode desfixar esta mensagem.'),
          ),
        );
      }
    }
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

  /// Abre o diálogo de denúncia e insiste até dar certo ou a pessoa desistir.
  ///
  /// **O LAÇO É O PONTO, e ele nasceu de um efeito colateral desta change.** O
  /// filtro de palavra passou a valer no `motivo`, e a versão anterior deste
  /// método fechava o diálogo antes de escrever: a recusa chegava por
  /// `SnackBar`, o `controller` já tinha sido descartado, e o texto se perdia.
  ///
  /// Quem denuncia uma ofensa costuma CITAR a ofensa. O desenho antigo
  /// significava que denunciar um palavrão era ser recusado e ter de reescrever
  /// do zero — desestimulando exatamente o mecanismo em que a moderação deste
  /// app se apoia. Achado pelo agente `advogado-digital` na revisão dos Termos.
  ///
  /// Agora o texto vive fora do diálogo e sobrevive a quantas recusas
  /// acontecerem, e a explicação aparece DENTRO dele, colada ao campo que
  /// precisa mudar.
  Future<void> _report(BuildContext context, WidgetRef ref) async {
    var draft = '';
    String? refusalMessage;

    while (true) {
      // A partir da segunda volta há um `await` atrás: sem esta guarda, uma
      // tela fechada durante o envio reabriria o diálogo sobre nada.
      if (!context.mounted) return;

      final reason = await showDialog<String>(
        context: context,
        builder: (context) => _ReportDialog(
          initialText: draft,
          refusalMessage: refusalMessage,
        ),
      );
      if (reason == null || !context.mounted) return;
      draft = reason;

      try {
        await ref
            .read(chatRepositoryProvider)
            .reportMessage(message.id, reason);
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Denúncia enviada. Quem cuida do espaço vai ver.'),
            ),
          );
        }
        return;
      } on SendRefusal catch (refusal) {
        // Só a recusa que a pessoa CONSEGUE corrigir reabre o diálogo. Não há
        // limite de ritmo em denúncia — denunciar não é conversar, e um limite
        // aqui protegeria quem está sendo denunciado —, então na prática esta é
        // sempre a palavra bloqueada.
        refusalMessage = sendRefusalMessage(refusal);
      } catch (_) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Não deu pra denunciar agora.')),
          );
        }
        return;
      }
    }
  }

  /// Fixa, e explica quando não cabe mais.
  ///
  /// O TETO NÃO É ERRO, e a frase precisa dizer o que fazer: ele não passa com
  /// o tempo como as recusas de ritmo, então "tente mais tarde" seria mentira.
  /// O que libera vaga é desfixar. A recusa chega por `errcode` PT409 e o texto
  /// dela mora em `sendRefusalMessage`, junto com as outras — a tela nunca
  /// interpreta a mensagem crua do servidor.
  Future<void> _pin(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(chatProvider(space).notifier).pin(message.id);
    } on SendRefusal catch (refusal) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(sendRefusalMessage(refusal))));
      }
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Você não pode fixar esta mensagem.')),
        );
      }
    }
  }

  Future<void> _unpin(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(chatProvider(space).notifier).unpin(message.id);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Você não pode desfixar esta mensagem.'),
          ),
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
        // FIXAR é só da autoridade do espaço, e nem o autor entra — fixar
        // decide o que todo mundo vê primeiro, e tira a mensagem do prazo de
        // 30 dias. DESFIXAR aparece também para o autor, pelo motivo inverso:
        // é o que devolve a ele o controle do prazo do que escreveu.
        if (canModerate && !message.isPinned)
          TextButton(
            onPressed: () => _pin(context, ref),
            child: const Text('Fixar'),
          ),
        if (message.isPinned && (canModerate || isMine))
          TextButton(
            onPressed: () => _unpin(context, ref),
            child: const Text('Desfixar'),
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

/// O diálogo de denúncia. `StatefulWidget` e não um `AlertDialog` montado
/// inline, e o motivo é o ciclo de vida do `TextEditingController`.
///
/// Quem cria o controller precisa descartá-lo, e um controller criado ao lado do
/// `showDialog` só pode ser descartado depois que o `await` volta — que é ANTES
/// de a animação de saída terminar. O `TextField` ainda é reconstruído nesses
/// quadros finais e bate num controller morto ("A TextEditingController was
/// used after being disposed"). Medido pelo teste de widget da denúncia
/// recusada, que reabre o diálogo e é o único caminho que chega até lá.
///
/// Com o controller dentro de um `State`, quem escolhe a hora do `dispose` é o
/// Flutter, e ele escolhe certo.
///
/// O RASCUNHO NÃO MORA AQUI. Ele volta pelo `Navigator.pop` e é o chamador que
/// o guarda entre uma tentativa e outra — este widget é descartado a cada
/// recusa, e o que ele guardasse morreria junto.
class _ReportDialog extends StatefulWidget {
  const _ReportDialog({required this.initialText, this.refusalMessage});

  final String initialText;

  /// Por que a tentativa anterior foi recusada. Nulo na primeira.
  final String? refusalMessage;

  @override
  State<_ReportDialog> createState() => _ReportDialogState();
}

class _ReportDialogState extends State<_ReportDialog> {
  late final _controller = TextEditingController(text: widget.initialText);

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final refusalMessage = widget.refusalMessage;

    return AlertDialog(
      title: const Text('Denunciar esta mensagem'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // A explicação fica COLADA ao campo que precisa mudar. Num `SnackBar`
          // ela apareceria sobre a conversa, longe do texto que a pessoa
          // acabou de escrever e sem dizer onde mexer.
          if (refusalMessage != null) ...[
            Text(
              refusalMessage,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.error,
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
          TextField(
            controller: _controller,
            maxLines: 3,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'O que há de errado?',
              hintText: 'Conte com suas palavras. Quem analisa lê isto.',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancelar'),
        ),
        FilledButton(
          onPressed: () {
            // MOTIVO OBRIGATÓRIO, e a recusa de vazio é local: o `check` do
            // banco também recusa motivo vazio, mas chegar lá para ouvir não é
            // resposta que se dê a quem está denunciando alguma coisa.
            final text = _controller.text.trim();
            if (text.isEmpty) return;
            Navigator.pop(context, text);
          },
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
    this.refusal,
    this.remaining,
  });

  final TextEditingController controller;
  final bool sending;
  final Future<void> Function() onSend;

  /// A recusa em vigor, quando há uma.
  final SendRefusal? refusal;

  /// Quanto falta para o envio reabrir. Nulo quando não há espera.
  final Duration? remaining;

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
    final waiting = widget.remaining != null;
    final canSend = !widget.sending && length > 0 && !tooLong && !waiting;
    final refusal = widget.refusal;

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.sm),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            // A RECUSA VAI ACIMA DO CAMPO, e a largura de celular é o motivo.
            // Ao lado do campo ela espremeria a digitação; num `SnackBar` ela
            // sumiria antes da espera acabar. Aqui ela ocupa a linha inteira,
            // quebra em quantas linhas precisar e some sozinha quando o tempo
            // passa.
            if (refusal != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.sm),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      refusal.kind == SendRefusalKind.blockedWord
                          ? Icons.block_outlined
                          : Icons.schedule_outlined,
                      size: 18,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        sendRefusalMessage(refusal, remaining: widget.remaining),
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
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
