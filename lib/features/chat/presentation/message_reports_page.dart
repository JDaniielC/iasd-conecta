import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../chat_providers.dart';
import '../domain/message_report.dart';

/// As mensagens denunciadas de um espaço, para quem manda nele.
///
/// O PORTÃO MORA AQUI, e não no `redirect` do roteador. É a lição da feature
/// 018, repetida porque continua valendo: o provider de autoridade é assíncrono
/// e vale `null` durante a navegação, então um `redirect` que compare
/// `value == false` nunca dispara e a tela abre para todo mundo. O banco
/// recusaria — a RLS devolve lista vazia —, mas "vazio" e "não é para você" são
/// coisas diferentes, e só uma delas se explica.
///
/// Quem denunciou NÃO vê esta lista, nem a própria denúncia, e o autor da
/// mensagem denunciada também não. `pode_moderar_espaco` deixa os dois de fora
/// de propósito: o denunciado é parte, não instância.
class MessageReportsPage extends ConsumerWidget {
  const MessageReportsPage({required this.space, super.key});

  final ChatSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final canModerate = ref.watch(canModerateSpaceProvider(space));

    return Scaffold(
      appBar: AppBar(title: const Text('Mensagens denunciadas')),
      body: canModerate.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const _NotForYou(),
        data: (allowed) => allowed
            ? ListView(
                padding: const EdgeInsets.all(AppSpacing.md),
                children: [
                  _SpaceReports(space: space),
                  // IRMÃO da lista do espaço, não filho do ramo `data:` dela.
                  // Enquanto morava lá dentro, uma falha daquela consulta
                  // levava as órfãs junto — e elas vêm de outro provider, que
                  // pode estar perfeitamente bem. Terceira vez que este bloco
                  // ficou inalcançável por onde ele mora, e a última.
                  const _OrphanReports(),
                ],
              )
            : const _NotForYou(),
      ),
    );
  }
}

class _NotForYou extends StatelessWidget {
  const _NotForYou();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.all(AppSpacing.lg),
      child: Center(
        child: Text(
          'Quem decide sobre mensagem denunciada é quem cuida deste espaço — '
          'o Dono do Grupo, quem criou a Ação, ou o Administrador do '
          'distrito.\n\n'
          'Se você denunciou alguma coisa, ela já foi registrada. Não é '
          'preciso denunciar de novo.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// As denúncias DAQUELE espaço. Devolve uma coluna, não uma lista rolável — a
/// rolagem é da página, para este bloco e o das órfãs rolarem juntos.
class _SpaceReports extends ConsumerWidget {
  const _SpaceReports({required this.space});

  final ChatSpace space;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final reportsAsync = ref.watch(messageReportsProvider(space));

    return reportsAsync.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (_, _) =>
          const Center(child: Text('Não deu pra carregar as denúncias agora.')),
      data: (reports) {
        final pending = reports
            .where((r) => r.state == MessageReportState.pending)
            .toList();
        // SEM early return quando a lista do espaço está vazia. A versão
        // anterior devolvia "Nenhuma mensagem denunciada aqui" antes de montar
        // esta lista, e com isso `_OrphanReports` — o bloco das denúncias que
        // perderam a mensagem no expurgo — só aparecia se o espaço tivesse,
        // por acaso, outra denúncia viva. O caso comum é o oposto: a denúncia
        // vira órfã justamente quando as mensagens daquele espaço foram
        // expurgadas. O bloco existia e estava morto onde mais importava.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (reports.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text('Nenhuma mensagem denunciada aqui.'),
              ),
            // As pendentes primeiro e sozinhas no topo: a lista existe para
            // decidir, e o que já foi decidido só serve de histórico.
            for (final r in pending) _ReportCard(report: r, space: space),
            if (reports.isNotEmpty && pending.isEmpty)
              const Padding(
                padding: EdgeInsets.only(bottom: AppSpacing.md),
                child: Text('Nada pendente. O que segue já foi decidido.'),
              ),
            for (final r in reports.where(
              (r) => r.state != MessageReportState.pending,
            ))
              _ReportCard(report: r, space: space),
          ],
        );
      },
    );
  }
}

class _ReportCard extends ConsumerWidget {
  const _ReportCard({required this.report, required this.space});

  final MessageReport report;
  final ChatSpace space;

  Future<void> _resolve(
    BuildContext context,
    WidgetRef ref,
    MessageReportState state,
  ) async {
    try {
      await ref.read(chatRepositoryProvider).resolveReport(report.id, state);
      ref.invalidate(messageReportsProvider(space));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não deu pra registrar a decisão.')),
        );
      }
    }
  }

  Future<void> _removeMessage(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Remover a mensagem?'),
        content: const Text(
          'O texto vai sumir para todo mundo, inclusive para você, e não fica '
          'guardado em lugar nenhum. Leia antes: depois não dá para '
          'reconsiderar.',
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
      // UMA escrita, não duas. O desfecho da denúncia é gatilho no banco
      // (`mensagens_denuncias_acolhidas`), na mesma transação da remoção.
      // Como duas chamadas, a segunda podia falhar e deixar a denúncia
      // `pendente` sobre uma mensagem já removida — estado sem botão nenhum
      // que o resolvesse, porque o botão depende de a mensagem ainda existir.
      await ref.read(chatRepositoryProvider).removeMessage(report.messageId!);
      ref.invalidate(messageReportsProvider(space));
      // A CONVERSA TAMBÉM, e ela está montada atrás: esta tela é aberta por
      // `context.push` a partir dela, então o `chatProvider` daquele espaço
      // continua vivo e não fica sabendo da remoção. Com o canal caído, quem
      // moderou voltava e lia o texto que acabou de mandar tirar — medido na
      // convergência 6. `invalidate` e não uma chamada ao notifier: invalidar
      // provider sem ouvinte é no-op, então abrir esta tela por link direto
      // não paga a abertura de um canal só para removê-lo em seguida.
      ref.invalidate(chatProvider(space));
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Não deu pra remover a mensagem.')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final isPending = report.state == MessageReportState.pending;

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Motivo', style: theme.textTheme.labelMedium),
            Text(_reasonLine, style: theme.textTheme.bodyMedium),
            const SizedBox(height: AppSpacing.sm),
            Text('Mensagem', style: theme.textTheme.labelMedium),
            Text(_messageLine, style: theme.textTheme.bodyMedium),
            if (!isPending) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_stateLine, style: theme.textTheme.labelMedium),
            ],
            if (isPending && report.messageId != null && !report.messageRemoved)
              Wrap(
                children: [
                  TextButton(
                    onPressed: () => _removeMessage(context, ref),
                    child: const Text('Remover mensagem'),
                  ),
                  TextButton(
                    onPressed: () =>
                        _resolve(context, ref, MessageReportState.dismissed),
                    child: const Text('Improcedente'),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }

  /// O motivo, ou a explicação de por que ele não está mais aqui.
  ///
  /// **NÃO é "erro ao carregar".** `denuncia_prazo_do_motivo()` apaga o texto
  /// de uma denúncia já decidida, passado o prazo — o registro do ATO (motivo
  /// pendente NUNCA fica nulo, então isto só acontece com `state` resolvido)
  /// continua na tela via [_stateLine]; só o que a pessoa escreveu, não.
  String get _reasonLine =>
      report.reason ??
      'O motivo não existe mais — o prazo de guarda depois do desfecho já '
          'passou. O caso continua registrado, com a decisão ao lado.';

  String get _messageLine {
    if (report.messageId == null) {
      return 'A mensagem já não existe — passou o prazo de 30 dias da Ação.';
    }
    if (report.messageRemoved) return 'Já removida.';
    return report.messageText ??
        'O autor excluiu a conta, e o texto saiu com ele.';
  }

  String get _stateLine => switch (report.state) {
    MessageReportState.pending => 'Pendente',
    MessageReportState.messageRemoved => 'Resolvida: mensagem removida',
    MessageReportState.dismissed => 'Resolvida: improcedente',
    MessageReportState.noMessage =>
      'Encerrada sem decisão: a mensagem foi apagada pelo prazo antes de '
          'alguém analisar',
  };
}

/// As denúncias que perderam a mensagem no expurgo dos 30 dias.
///
/// Só o Administrador do distrito as alcança, e não é escolha de tela: o braço
/// de Administrador em `denuncias_mensagem_select_autoridade` é o único que não
/// depende da junção com `mensagens`, e depois do `on delete set null` não há
/// junção. Elas também não pertencem a espaço nenhum — o vínculo que dizia de
/// que Grupo ou Ação eram foi junto —, então aparecem no fim de qualquer lista
/// que um Administrador abra.
///
/// Existem porque a alternativa era pior: sem este bloco a linha sobrevivia no
/// banco e NINGUÉM a lia, enquanto a Política dizia ao denunciante que a
/// denúncia dele não some sem desfecho. Achado pelo agente
/// `promessa-vs-execucao` no fechamento da change.
class _OrphanReports extends ConsumerWidget {
  const _OrphanReports();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (!(ref.watch(isDistrictAdminProvider).value ?? false)) {
      return const SizedBox.shrink();
    }
    final orphans = ref.watch(orphanMessageReportsProvider).value ?? const [];
    if (orphans.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: AppSpacing.lg),
        Text('Sem mensagem', style: Theme.of(context).textTheme.titleMedium),
        const Padding(
          padding: EdgeInsets.only(bottom: AppSpacing.sm),
          child: Text(
            'A mensagem foi apagada pelo prazo de 30 dias antes de alguém '
            'analisar. De que conversa era, não dá mais para saber — e o '
            'motivo escrito por quem denunciou tem prazo próprio, contado '
            'deste desfecho sem mérito.',
          ),
        ),
        for (final r in orphans)
          Card(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Motivo',
                    style: Theme.of(context).textTheme.labelMedium,
                  ),
                  // `sem_mensagem` também tem `resolvida_em` (é um desfecho,
                  // só que sem mérito) — o motivo expira igual ao das outras.
                  Text(
                    r.reason ??
                        'O motivo não existe mais — o prazo de guarda depois '
                            'deste desfecho já passou.',
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}
