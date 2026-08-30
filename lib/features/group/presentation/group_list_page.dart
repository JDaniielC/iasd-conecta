import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/group_by_church.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../cover_photo/cover_photo_providers.dart';
import '../../cover_photo/domain/cover_photo.dart';
import '../../cover_photo/presentation/cover_photo_widget.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../profile/domain/church.dart';
import '../../profile/domain/profile_guard.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../domain/group.dart';
import '../group_providers.dart';
import 'group_quick_view_sheet.dart';
import '../../navigation/presentation/app_bottom_nav.dart';

enum _GroupSortOrder { mostRecent, name, category }

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
  _GroupSortOrder _sortOrder = _GroupSortOrder.mostRecent;

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
        // Chega-se a `/grupos` por `context.go`, que não empilha rota — sem
        // este botão a tela fica sem saída (nenhum back automático, porque
        // não há nada para voltar).
        leading: IconButton(
          tooltip: 'Início',
          icon: const Icon(Icons.home_outlined),
          onPressed: () => context.go('/home'),
        ),
        title: const Text('Grupos/Ministérios'),
        // Ações e Notificações saíram daqui — a barra inferior já leva às
        // duas. O que sobra é só o que não tem lugar na barra: administração
        // do distrito e as duas entradas de sempre (Virar Conta, páginas
        // legais), tudo dentro de um menu só. Sete ícones soltos ao lado de
        // "Grupos/Ministérios" era o que estourava a AppBar num celular —
        // achado rodando o app no simulador.
        actions: [
          _ListMenuButton(hasProfile: hasProfile, hasAccount: hasAccount, isDistrictAdmin: isDistrictAdmin),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () async {
          if (!await ProfileGuard.requireProfile(context, ref)) return;
          if (!context.mounted) return;
          context.push('/grupos/novo');
        },
        child: const Icon(Icons.add),
      ),
      bottomNavigationBar: const AppBottomNav(current: AppTab.groups),
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
                final sorted = [...filtered]..sort(_comparator(_sortOrder));
                final sections = groupByChurch(sorted, (g) => g.churchId, nameByChurchId);
                // As capas vêm numa consulta só, e a lista só pinta quando
                // elas chegam. É o que impede o card de crescer depois de
                // pintado, que é o pulo de layout de FR-007. Enquanto não
                // chegam, os cards aparecem sem capa — e essa é a degradação
                // certa: melhor lista sem imagem do que lista que se mexe
                // debaixo do dedo de quem está lendo.
                final covers = ref
                        .watch(groupCoverPhotosProvider(
                          coverPhotosKey([for (final g in sorted) g.id]),
                        ))
                        .value ??
                    const <String, CoverPhoto>{};
                return ListView(
                  children: [
                    for (final section in sections) ...[
                      _SectionHeader(name: section.churchName),
                      for (final group in section.items)
                        GroupCard(group: group, cover: covers[group.id]),
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

  int Function(Group, Group) _comparator(_GroupSortOrder sortOrder) {
    switch (sortOrder) {
      case _GroupSortOrder.mostRecent:
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
              isExpanded: true,
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
              isExpanded: true,
              decoration: const InputDecoration(labelText: 'Ordenar por'),
              items: const [
                DropdownMenuItem(value: _GroupSortOrder.mostRecent, child: Text('Mais recentes')),
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

enum _ListMenuAction {
  churches,
  promote,
  pendingLeadership,
  suggestedActions,
  archivedGroups,
  consentVersions,
  reportedImages,
  upgradeAccount,
  privacy,
}

/// Tudo que não coube na barra inferior nem é a chamada principal da tela:
/// administração do distrito (só visível a quem administra) e as duas
/// entradas de sempre. Um menu só, não sete ícones soltos.
class _ListMenuButton extends StatelessWidget {
  const _ListMenuButton({
    required this.hasProfile,
    required this.hasAccount,
    required this.isDistrictAdmin,
  });

  final bool hasProfile;
  final bool hasAccount;
  final bool isDistrictAdmin;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<_ListMenuAction>(
      tooltip: 'Mais opções',
      onSelected: (action) => switch (action) {
        _ListMenuAction.churches => context.push('/district-admin/churches'),
        _ListMenuAction.promote => context.push('/district-admin/promote'),
        _ListMenuAction.pendingLeadership => context.push('/leadership/pending'),
        _ListMenuAction.suggestedActions =>
          context.push('/district-admin/suggested-actions'),
        _ListMenuAction.archivedGroups =>
          context.push('/district-admin/grupos-arquivados'),
        _ListMenuAction.consentVersions =>
          context.push('/district-admin/consentimentos'),
        _ListMenuAction.reportedImages =>
          context.push('/district-admin/imagens-denunciadas'),
        _ListMenuAction.upgradeAccount => context.push('/upgrade-conta'),
        _ListMenuAction.privacy => context.push('/privacidade'),
      },
      itemBuilder: (context) => [
        if (isDistrictAdmin) ...[
          const PopupMenuItem(
            value: _ListMenuAction.churches,
            child: ListTile(
              leading: Icon(Icons.church_outlined),
              title: Text('Igrejas do Distrito'),
            ),
          ),
          const PopupMenuItem(
            value: _ListMenuAction.promote,
            child: ListTile(
              leading: Icon(Icons.admin_panel_settings_outlined),
              title: Text('Promover Administrador'),
            ),
          ),
          const PopupMenuItem(
            value: _ListMenuAction.pendingLeadership,
            child: ListTile(
              leading: Icon(Icons.pending_actions_outlined),
              title: Text('Declarações de Líder/Diretor pendentes'),
            ),
          ),
          const PopupMenuItem(
            value: _ListMenuAction.suggestedActions,
            child: ListTile(
              leading: Icon(Icons.lightbulb_outline),
              title: Text('Ações Sugeridas'),
            ),
          ),
          const PopupMenuItem(
            value: _ListMenuAction.archivedGroups,
            child: ListTile(
              leading: Icon(Icons.archive_outlined),
              title: Text('Grupos/Ministérios arquivados'),
            ),
          ),
          const PopupMenuItem(
            value: _ListMenuAction.consentVersions,
            child: ListTile(
              leading: Icon(Icons.fact_check_outlined),
              title: Text('Versões de consentimento'),
            ),
          ),
          // SC-003: da tela em que a imagem aparece até a remoção, em até 3
          // toques. Por aqui são dois: abrir o menu e escolher.
          const PopupMenuItem(
            value: _ListMenuAction.reportedImages,
            child: ListTile(
              leading: Icon(Icons.flag_outlined),
              title: Text('Imagens denunciadas'),
            ),
          ),
        ],
        if (hasProfile && !hasAccount)
          const PopupMenuItem(
            value: _ListMenuAction.upgradeAccount,
            child: ListTile(
              leading: Icon(Icons.cloud_upload_outlined),
              title: Text('Virar Conta'),
            ),
          ),
        const PopupMenuItem(
          value: _ListMenuAction.privacy,
          child: ListTile(
            leading: Icon(Icons.privacy_tip_outlined),
            title: Text('Política de Privacidade e Termos de Uso'),
          ),
        ),
      ],
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

/// Cartão de Grupo — reusado pela lista completa (`/grupos`) e por
/// `MyGroupsPage` (`/meus-grupos`), por isso público.
class GroupCard extends ConsumerWidget {
  const GroupCard({super.key, required this.group, this.cover});

  final Group group;

  /// Já resolvida pela lista, de propósito — o card não consulta nada. Ver o
  /// comentário sobre pulo de layout em [GroupListPage].
  final CoverPhoto? cover;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // Abre a pré-visualização, não a tela cheia direto — "Ver detalhes"
        // dentro dela é que navega. Ver GroupQuickViewSheet.
        onTap: () => GroupQuickViewSheet.show(context, group),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Grupo sem capa não deixa buraco: CoverPhotoView ocupa zero.
            CoverPhotoView(
              photo: cover,
              imageUrl: cover == null
                  ? null
                  : ref.read(coverPhotoRepositoryProvider).publicUrlFor(cover!),
              borderRadius: BorderRadius.zero,
            ),
            ListTile(
              title: Text(group.name),
              subtitle: Text(group.category),
            ),
          ],
        ),
      ),
    );
  }
}
