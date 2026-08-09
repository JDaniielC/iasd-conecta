import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/group_by_church.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../profile/domain/church.dart';
import '../../profile/domain/profile_guard.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../domain/group.dart';
import '../group_providers.dart';

enum _GroupSortOrder { maisRecentes, name, category }

const _allChurches = '__todas__';

/// Lista de Grupos, em `/grupos`, visível a Visitante e Usuário igualmente
/// (FR-005/FR-008 — sem exigir Perfil pra essa visualização). Agrupada por
/// Igreja, com filtro de Igreja e ordenação — um distrito com várias Igrejas
/// rapidamente vira uma lista longa e sem estrutura sem isso.
///
/// Deixou de ser a primeira tela na feature 010: a rota inicial passou a ser a
/// Home de propósito, e esta lista ganhou endereço próprio.
class GroupListPage extends ConsumerStatefulWidget {
  const GroupListPage({super.key});

  @override
  ConsumerState<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends ConsumerState<GroupListPage> {
  String _churchFilterId = _allChurches;
  _GroupSortOrder _sortOrder = _GroupSortOrder.maisRecentes;

  @override
  Widget build(BuildContext context) {
    final hasProfile = ref.watch(hasProfileProvider).value ?? false;
    final hasAccount = hasProfile && ref.watch(authRepositoryProvider).hasAccount;
    final isDistrictAdmin = ref.watch(isDistrictAdminProvider).value ?? false;
    final groupsAsync = ref.watch(groupsProvider);
    final churchesAsync = ref.watch(churchesProvider);
    final nameByChurchId = <String, String>{
      for (final c in churchesAsync.value ?? const []) c.id: c.name,
    };

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grupos'),
        actions: [
          IconButton(
            tooltip: 'Ações',
            icon: const Icon(Icons.event_outlined),
            onPressed: () => context.push('/acoes'),
          ),
          if (isDistrictAdmin) ...[
            IconButton(
              tooltip: 'Igrejas do Distrito',
              icon: const Icon(Icons.church_outlined),
              onPressed: () => context.push('/district-admin/churches'),
            ),
            IconButton(
              tooltip: 'Promover Administrador',
              icon: const Icon(Icons.admin_panel_settings_outlined),
              onPressed: () => context.push('/district-admin/promote'),
            ),
            IconButton(
              tooltip: 'Declarações de Líder/Diretor pendentes',
              icon: const Icon(Icons.pending_actions_outlined),
              onPressed: () => context.push('/leadership/pending'),
            ),
            IconButton(
              tooltip: 'Ações Sugeridas',
              icon: const Icon(Icons.lightbulb_outline),
              onPressed: () => context.push('/district-admin/suggested-actions'),
            ),
          ],
          if (hasProfile && !hasAccount)
            IconButton(
              tooltip: 'Virar Conta',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () => context.push('/upgrade-conta'),
            ),
          IconButton(
            tooltip: 'Política de Privacidade e Termos de Uso',
            icon: const Icon(Icons.privacy_tip_outlined),
            onPressed: () => context.push('/privacidade'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (ProfileGuard.requireProfile(context, ref)) {
            context.push('/grupos/novo');
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const MissingProfileBanner(),
          _FilterBar(
            churchesAsync: churchesAsync,
            churchFilterId: _churchFilterId,
            sortOrder: _sortOrder,
            onChurchFilterChanged: (v) => setState(() => _churchFilterId = v),
            onSortOrderChanged: (v) => setState(() => _sortOrder = v),
          ),
          Expanded(
            child: groupsAsync.when(
              data: (groups) {
                final filtered = _churchFilterId == _allChurches
                    ? groups
                    : groups.where((g) => g.churchId == _churchFilterId).toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Nenhum Grupo ainda.'));
                }
                final sorted = [...filtered]..sort(_comparador(_sortOrder));
                final sections = groupByChurch(sorted, (g) => g.churchId, nameByChurchId);
                return ListView(
                  children: [
                    for (final section in sections) ...[
                      _SectionHeader(name: section.churchName),
                      for (final group in section.items) _GroupCard(group: group),
                    ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Não deu pra carregar os Grupos agora.')),
            ),
          ),
        ],
      ),
    );
  }

  int Function(Group, Group) _comparador(_GroupSortOrder sortOrder) {
    switch (sortOrder) {
      case _GroupSortOrder.maisRecentes:
        return (a, b) => b.createdAt.compareTo(a.createdAt);
      case _GroupSortOrder.name:
        return (a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase());
      case _GroupSortOrder.category:
        return (a, b) => a.category.toLowerCase().compareTo(b.category.toLowerCase());
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.churchesAsync,
    required this.churchFilterId,
    required this.sortOrder,
    required this.onChurchFilterChanged,
    required this.onSortOrderChanged,
  });

  final AsyncValue<List<Church>> churchesAsync;
  final String churchFilterId;
  final _GroupSortOrder sortOrder;
  final ValueChanged<String> onChurchFilterChanged;
  final ValueChanged<_GroupSortOrder> onSortOrderChanged;

  @override
  Widget build(BuildContext context) {
    final churches = churchesAsync.value ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Row(
        children: [
          Expanded(
            child: DropdownButtonFormField<String>(
              initialValue: churchFilterId,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Igreja'),
              items: [
                const DropdownMenuItem(value: _allChurches, child: Text('Todas as Igrejas')),
                for (final c in churches) DropdownMenuItem(value: c.id, child: Text(c.name)),
              ],
              onChanged: (v) => v == null ? null : onChurchFilterChanged(v),
            ),
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: DropdownButtonFormField<_GroupSortOrder>(
              initialValue: sortOrder,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Ordenar por'),
              items: const [
                DropdownMenuItem(value: _GroupSortOrder.maisRecentes, child: Text('Mais recentes')),
                DropdownMenuItem(value: _GroupSortOrder.name, child: Text('Nome (A-Z)')),
                DropdownMenuItem(value: _GroupSortOrder.category, child: Text('Categoria')),
              ],
              onChanged: (v) => v == null ? null : onSortOrderChanged(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name});

  final String name;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            name,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold,
                ),
          ),
          const Divider(height: AppSpacing.sm),
        ],
      ),
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group});

  final Group group;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: ListTile(
        title: Text(group.name),
        subtitle: Text(group.category),
        onTap: () => context.push('/grupos/${group.id}'),
      ),
    );
  }
}
