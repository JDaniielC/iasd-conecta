import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/voting_round.dart';
import '../voting_round_providers.dart';

/// Abertura de Rodada de votação (User Story 1) — só o prazo é informado;
/// quem participa do Grupo já é garantido pelo trigger no banco.
class CreateVotingRoundPage extends ConsumerStatefulWidget {
  const CreateVotingRoundPage({super.key, required this.groupId});

  final String groupId;

  @override
  ConsumerState<CreateVotingRoundPage> createState() => _CreateVotingRoundPageState();
}

class _CreateVotingRoundPageState extends ConsumerState<CreateVotingRoundPage> {
  DateTime? _deadline;
  bool _submitting = false;
  String? _error;

  Future<void> _pickDeadline() async {
    final now = DateTime.now();
    final date = await showDatePicker(
      context: context,
      initialDate: now.add(const Duration(days: 1)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(context: context, initialTime: TimeOfDay.now());
    if (time == null) return;
    setState(() {
      _deadline = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    });
  }

  Future<void> _open() async {
    final deadline = _deadline;
    if (deadline == null) {
      setState(() => _error = 'Escolha um prazo.');
      return;
    }
    final votingRound = NewVotingRound(deadline: deadline);
    if (!votingRound.isReadyToSubmit) {
      setState(() => _error = 'O prazo precisa ser no futuro.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      await ref.read(votingRoundRepositoryProvider).openRound(votingRound, groupId: widget.groupId);
      ref.invalidate(groupVotingRoundsProvider(widget.groupId));
      if (mounted) context.pop();
    } catch (_) {
      setState(() => _error = 'Não deu pra abrir a Rodada agora. Você participa deste Grupo?');
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Abrir Rodada de Votação')),
      body: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('Escolha até quando a votação fica aberta.'),
            const SizedBox(height: AppSpacing.lg),
            OutlinedButton(
              onPressed: _pickDeadline,
              child: Text(
                _deadline == null
                    ? 'Escolher prazo'
                    : DateFormat('dd/MM/yyyy HH:mm').format(_deadline!),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: AppSpacing.sm),
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ],
            const SizedBox(height: AppSpacing.lg),
            ElevatedButton(
              onPressed: _submitting ? null : _open,
              child: _submitting
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Abrir Rodada'),
            ),
          ],
        ),
      ),
    );
  }
}
