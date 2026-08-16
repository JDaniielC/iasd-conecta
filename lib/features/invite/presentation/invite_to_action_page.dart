import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../domain/invite_contact_group.dart';
import '../invite_providers.dart';

/// Convidar gente para uma Ação (change `convite-para-acao`).
///
/// A lista vem dos Grupos de quem convida, agrupada, numa chamada só. O Grupo
/// é o contexto do convite e não um detalhe visual: a mesma pessoa em dois
/// Grupos aparece nas duas seções, e convidá-la por um não a tira do outro.
class InviteToActionPage extends ConsumerStatefulWidget {
  const InviteToActionPage({super.key, required this.actionId});

  final String actionId;

  @override
  ConsumerState<InviteToActionPage> createState() => _InviteToActionPageState();
}

class _InviteToActionPageState extends ConsumerState<InviteToActionPage> {
  /// Seleção por Grupo — a mesma pessoa pode estar marcada em dois.
  final _selected = <String, Set<String>>{};
  bool _sending = false;

  /// Quem ficou de fora da última tentativa, por Grupo, com o nome para dizer
  /// nominalmente. Nunca afirmamos sucesso quando a chamada falhou.
  Map<String, Set<String>> _failed = const {};
  String? _summary;
  bool _summaryIsFailure = false;

  int get _totalSelected =>
      _selected.values.fold(0, (sum, s) => sum + s.length);

  void _toggle(String groupId, String userId, bool checked) {
    setState(() {
      final s = _selected[groupId] ??= <String>{};
      checked ? s.add(userId) : s.remove(userId);
    });
  }

  Future<void> _invite(List<InviteContactGroup> groups) async {
    setState(() {
      _sending = true;
      _summary = null;
      _failed = const {};
    });

    final repo = ref.read(inviteRepositoryProvider);
    final nameById = {
      for (final g in groups)
        for (final c in g.contacts) c.userId: c.displayName,
    };

    var sent = 0;
    final failures = <String, Set<String>>{};

    for (final entry in _selected.entries) {
      if (entry.value.isEmpty) continue;
      try {
        final results =
            await repo.invite(widget.actionId, entry.key, entry.value.toList());
        for (final r in results) {
          if (r.succeeded) {
            sent++;
          } else {
            (failures[entry.key] ??= <String>{}).add(r.userId);
          }
        }
      } catch (_) {
        // A rede caiu ou o banco recusou este Grupo inteiro. Os Grupos já
        // enviados PERMANECEM — não desfazemos nada, e a tela não pode dizer
        // que deu certo.
        failures[entry.key] = {...entry.value};
      }
    }

    if (!mounted) return;
    final failedNames = [
      for (final e in failures.entries)
        for (final uid in e.value) nameById[uid] ?? 'alguém'
    ];
    setState(() {
      _sending = false;
      _failed = failures;
      _selected
        ..clear()
        ..addAll(failures);
      _summaryIsFailure = failedNames.isNotEmpty;
      _summary = failedNames.isEmpty
          ? '$sent convite(s) enviado(s).'
          : '$sent enviado(s). Ficaram de fora: ${failedNames.join(', ')}.';
    });
    ref.invalidate(inviteContactsProvider(widget.actionId));
  }

  @override
  Widget build(BuildContext context) {
    final contactsAsync = ref.watch(inviteContactsProvider(widget.actionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Convidar')),
      body: contactsAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não deu pra carregar seus contatos.')),
        data: (groups) {
          if (groups.isEmpty) return const _EmptyGroups();
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    for (final g in groups) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.sm),
                        child: Text(
                          g.groupName,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                      for (final c in g.contacts)
                        CheckboxListTile(
                          contentPadding: EdgeInsets.zero,
                          title: Text(c.displayName),
                          subtitle: c.alreadyConfirmed
                              ? const Text('Confirmou presença')
                              : c.alreadyInvited
                              ? const Text('Já convidado — sem resposta')
                              : (_failed[g.groupId]?.contains(c.userId) ??
                                      false)
                                  ? const Text('Não deu certo — dá pra tentar '
                                      'de novo')
                                  : null,
                          value: c.alreadyInvited ||
                              (_selected[g.groupId]?.contains(c.userId) ??
                                  false),
                          // Quem já foi convidado por este Grupo não é
                          // selecionável: convidar de novo não é erro, mas
                          // oferecer o botão sugere que faltava algo.
                          onChanged: c.alreadyInvited
                              ? null
                              : (v) => _toggle(g.groupId, c.userId, v ?? false),
                        ),
                    ],
                  ],
                ),
              ),
              if (_summary != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Text(
                    _summary!,
                    style: TextStyle(
                      color: _summaryIsFailure
                          ? Theme.of(context).colorScheme.error
                          : null,
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.all(AppSpacing.md),
                child: SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: _sending || _totalSelected == 0
                        ? null
                        : () => _invite(groups),
                    child: Text(
                      _sending
                          ? 'Enviando...'
                          : _failed.isNotEmpty
                              ? 'Tentar de novo ($_totalSelected)'
                              : 'Convidar ($_totalSelected)',
                    ),
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A lista de quem dá pra convidar vem dos seus Grupos.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.sm),
            const Text(
              'Entre num Grupo e as pessoas dele aparecem aqui.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            FilledButton(
              onPressed: () => context.push('/grupos'),
              child: const Text('Ver Grupos'),
            ),
          ],
        ),
      ),
    );
  }
}
