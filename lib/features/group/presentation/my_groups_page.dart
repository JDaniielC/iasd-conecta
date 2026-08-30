import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/theme/app_theme.dart';
import '../../navigation/presentation/app_bottom_nav.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../group_providers.dart';
import 'group_list_page.dart' show GroupCard;

/// Só os Grupos em que a pessoa participa (`myGroupIdsProvider`) — a mesma
/// consulta que já alimenta a faixa de destaque de Ações, agora com tela
/// própria. Sem Perfil o conjunto vem vazio (a consulta nem sai do aparelho),
/// e a tela mostra o convite pra conhecer os Grupos em vez de lista vazia sem
/// explicação.
class MyGroupsPage extends ConsumerWidget {
  const MyGroupsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final myIds = ref.watch(myGroupIdsProvider).value ?? const <String>{};
    final groupsAsync = ref.watch(groupsProvider);

    return Scaffold(
      appBar: AppBar(
        leading: IconButton(
          tooltip: 'Início',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Meus Grupos'),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.myGroups),
      body: Column(
        children: [
          const MissingProfileBanner(),
          Expanded(
            child: groupsAsync.when(
              data: (groups) {
                final mine = groups.where((g) => myIds.contains(g.id)).toList();
                if (mine.isEmpty) {
                  return _EmptyState(onBrowse: () => context.go('/grupos'));
                }
                return ListView(
                  children: [
                    for (final group in mine) GroupCard(group: group),
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) =>
                  const Center(child: Text('Não deu pra carregar seus Grupos agora.')),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptyState extends StatelessWidget {
  const _EmptyState({required this.onBrowse});

  final VoidCallback onBrowse;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'Você ainda não participa de nenhum Grupo.',
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.md),
            OutlinedButton(
              onPressed: onBrowse,
              child: const Text('Ver Grupos/Ministérios'),
            ),
          ],
        ),
      ),
    );
  }
}
