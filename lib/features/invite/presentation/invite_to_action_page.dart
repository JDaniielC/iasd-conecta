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
  final _selecionados = <String, Set<String>>{};
  bool _enviando = false;

  /// Quem ficou de fora da última tentativa, por Grupo, com o nome para dizer
  /// nominalmente. Nunca afirmamos sucesso quando a chamada falhou.
  Map<String, Set<String>> _falharam = const {};
  String? _resumo;
  bool _resumoEhFalha = false;

  int get _totalSelecionado =>
      _selecionados.values.fold(0, (soma, s) => soma + s.length);

  void _alternar(String groupId, String userId, bool marcado) {
    setState(() {
      final s = _selecionados[groupId] ??= <String>{};
      marcado ? s.add(userId) : s.remove(userId);
    });
  }

  Future<void> _convidar(List<InviteContactGroup> grupos) async {
    setState(() {
      _enviando = true;
      _resumo = null;
      _falharam = const {};
    });

    final repo = ref.read(inviteRepositoryProvider);
    final nomePorId = {
      for (final g in grupos)
        for (final c in g.contacts) c.userId: c.displayName,
    };

    var feitos = 0;
    final falhas = <String, Set<String>>{};

    for (final entry in _selecionados.entries) {
      if (entry.value.isEmpty) continue;
      try {
        final resultados =
            await repo.invite(widget.actionId, entry.key, entry.value.toList());
        for (final r in resultados) {
          if (r.succeeded) {
            feitos++;
          } else {
            (falhas[entry.key] ??= <String>{}).add(r.userId);
          }
        }
      } catch (_) {
        // A rede caiu ou o banco recusou este Grupo inteiro. Os Grupos já
        // enviados PERMANECEM — não desfazemos nada, e a tela não pode dizer
        // que deu certo.
        falhas[entry.key] = {...entry.value};
      }
    }

    if (!mounted) return;
    final nomesFalha = [
      for (final e in falhas.entries)
        for (final uid in e.value) nomePorId[uid] ?? 'alguém'
    ];
    setState(() {
      _enviando = false;
      _falharam = falhas;
      _selecionados
        ..clear()
        ..addAll(falhas);
      _resumoEhFalha = nomesFalha.isNotEmpty;
      _resumo = nomesFalha.isEmpty
          ? '$feitos convite(s) enviado(s).'
          : '$feitos enviado(s). Ficaram de fora: ${nomesFalha.join(', ')}.';
    });
    ref.invalidate(inviteContactsProvider(widget.actionId));
  }

  @override
  Widget build(BuildContext context) {
    final contatosAsync = ref.watch(inviteContactsProvider(widget.actionId));

    return Scaffold(
      appBar: AppBar(title: const Text('Convidar')),
      body: contatosAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não deu pra carregar seus contatos.')),
        data: (grupos) {
          if (grupos.isEmpty) return const _SemGrupos();
          return Column(
            children: [
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(AppSpacing.md),
                  children: [
                    for (final g in grupos) ...[
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
                              : (_falharam[g.groupId]?.contains(c.userId) ??
                                      false)
                                  ? const Text('Não deu certo — dá pra tentar '
                                      'de novo')
                                  : null,
                          value: c.alreadyInvited ||
                              (_selecionados[g.groupId]?.contains(c.userId) ??
                                  false),
                          // Quem já foi convidado por este Grupo não é
                          // selecionável: convidar de novo não é erro, mas
                          // oferecer o botão sugere que faltava algo.
                          onChanged: c.alreadyInvited
                              ? null
                              : (v) => _alternar(g.groupId, c.userId, v ?? false),
                        ),
                    ],
                  ],
                ),
              ),
              if (_resumo != null)
                Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.md, vertical: AppSpacing.sm),
                  child: Text(
                    _resumo!,
                    style: TextStyle(
                      color: _resumoEhFalha
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
                    onPressed: _enviando || _totalSelecionado == 0
                        ? null
                        : () => _convidar(grupos),
                    child: Text(
                      _enviando
                          ? 'Enviando...'
                          : _falharam.isNotEmpty
                              ? 'Tentar de novo ($_totalSelecionado)'
                              : 'Convidar ($_totalSelecionado)',
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

class _SemGrupos extends StatelessWidget {
  const _SemGrupos();

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
