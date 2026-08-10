import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/theme/app_theme.dart';
import '../../leadership/leadership_providers.dart';
import '../domain/archive_preview.dart';
import '../group_providers.dart';

/// A confirmação de arquivar, com o estrago declarado ANTES (FR-003).
///
/// A prévia é **só leitura** — nenhuma consulta desta tela escreve nada. É isso
/// que torna FR-006 verdadeiro por construção: desistir não pode desfazer o que
/// não foi feito.
///
/// Devolve `true` só quando o arquivamento foi confirmado e concluído.
class ArchiveGroupSheet extends ConsumerStatefulWidget {
  const ArchiveGroupSheet({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<ArchiveGroupSheet> createState() => _ArchiveGroupSheetState();
}

class _ArchiveGroupSheetState extends ConsumerState<ArchiveGroupSheet> {
  bool _submitting = false;
  String? _error;

  Future<void> _archive() async {
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(groupRepositoryProvider).archiveGroup(widget.groupId);
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (_) {
      if (!mounted) return;
      setState(() => _error =
          'Não deu pra arquivar agora. Verifique sua conexão e tente de novo.');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final previewAsync = ref.watch(archivePreviewProvider(widget.groupId));
    final leadersAsync = ref.watch(currentLeadersProvider(widget.groupId));
    final text = Theme.of(context).textTheme;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.lg),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Arquivar este Grupo/Ministério?', style: text.titleLarge),
          const SizedBox(height: AppSpacing.md),
          previewAsync.when(
            loading: () => const LinearProgressIndicator(),
            error: (_, _) => const Text(
              'Não deu pra calcular o que será perdido. Tente de novo antes de '
              'arquivar.',
            ),
            data: (preview) => _PreviewBody(
              preview: preview,
              hasConfirmedLeader: (leadersAsync.value?.isNotEmpty) ?? false,
            ),
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            'O Grupo/Ministério não é apagado — ele sai de circulação. Só o '
            'Administrador do distrito pode trazê-lo de volta, e as Ações '
            'canceladas não voltam.',
            style: text.bodySmall,
          ),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.md),
            Text(
              _error!,
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
          ],
          const SizedBox(height: AppSpacing.lg),
          Row(
            children: [
              Expanded(
                child: OutlinedButton(
                  onPressed: _submitting
                      ? null
                      : () => Navigator.of(context).pop(false),
                  child: const Text('Desistir'),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: ElevatedButton(
                  onPressed: (_submitting || !previewAsync.hasValue)
                      ? null
                      : _archive,
                  child: Text(_submitting ? 'Arquivando…' : 'Arquivar'),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _PreviewBody extends StatelessWidget {
  const _PreviewBody({required this.preview, required this.hasConfirmedLeader});

  final ArchivePreview preview;
  final bool hasConfirmedLeader;

  String _people(int n) => n == 1 ? '1 pessoa' : '$n pessoas';

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;

    if (preview.nothingWillBeLost) {
      // Em palavras, não em quatro zeros: obrigar alguém a interpretar números
      // antes de uma ação irreversível é onde o erro acontece.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Nada será perdido: não há Ação marcada nem Rodada de votação em '
            'aberto neste Grupo/Ministério.',
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${_people(preview.members)} deixam de participar (voltam se ele '
            'for desarquivado).',
          ),
        ],
      );
    }

    // Rótulos montados fora da interpolação: ternário dentro de string com
    // aspas aninhadas é ilegível e engana ferramenta que lê o código.
    final actionsLabel = preview.futureActions == 1
        ? 'Ação marcada é cancelada'
        : 'Ações marcadas são canceladas';
    final roundsLabel = preview.openVotingRounds == 1
        ? 'Rodada de votação é encerrada'
        : 'Rodadas de votação são encerradas';

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Ao arquivar, isto acontece:'),
        const SizedBox(height: AppSpacing.sm),
        if (preview.futureActions > 0)
          Text(
            '• ${preview.futureActions} $actionsLabel, com '
            '${_people(preview.confirmedAttendances)} que já tinham '
            'confirmado presença.',
          ),
        if (preview.openVotingRounds > 0)
          Text(
            '• ${preview.openVotingRounds} $roundsLabel sem apurar vencedora, '
            'e as Ações candidatas são descartadas.',
          ),
        Text('• ${_people(preview.members)} deixam de participar.'),
        if (hasConfirmedLeader) ...[
          const SizedBox(height: AppSpacing.sm),
          Text(
            'A identificação pública do Líder/Diretor deste Ministério também '
            'sai do ar.',
            style: text.bodyMedium,
          ),
        ],
      ],
    );
  }
}
