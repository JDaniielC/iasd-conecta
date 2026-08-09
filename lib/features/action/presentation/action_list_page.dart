import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/domain/church.dart';
import '../../profile/domain/profile_guard.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../action_providers.dart';
import '../domain/action.dart';

enum _ActionSortOrder { data, maisRecentes, name }

const _allChurches = '__todas__';

const _periodOrder = [
  ActionPeriod.sabbath,
  ActionPeriod.hoje,
  ActionPeriod.essaSemana,
  ActionPeriod.outras,
];

const _periodLabel = {
  ActionPeriod.sabbath: 'Sábado',
  ActionPeriod.hoje: 'Hoje',
  ActionPeriod.essaSemana: 'Essa semana',
  ActionPeriod.outras: 'Outras datas',
};

/// Lista de Ações avulsas: visível a Visitante e Usuário igualmente
/// (FR-010 — sem exigir Perfil pra essa visualização). Agrupada por período
/// (Sábado/Hoje/Essa semana/Outras datas) — o que importa pra quem abre a
/// lista é "o que tem pra quando", não a estrutura administrativa por
/// Igreja. Sábado adventista (sexta 17:30 - sábado 17:30, `acaoNoSabado`)
/// ganha destaque visual e sempre vem primeiro.
class ActionListPage extends ConsumerStatefulWidget {
  const ActionListPage({super.key});

  @override
  ConsumerState<ActionListPage> createState() => _ActionListPageState();
}

class _ActionListPageState extends ConsumerState<ActionListPage> {
  String _filtroIgrejaId = _allChurches;
  _ActionSortOrder _sortOrder = _ActionSortOrder.data;
  bool _soSabado = false;

  @override
  Widget build(BuildContext context) {
    final actionsAsync = ref.watch(actionsWithChurchProvider);
    final churchesAsync = ref.watch(churchesProvider);
    final now = DateTime.now();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ações'),
        actions: [
          IconButton(
            tooltip: 'Grupos',
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => context.go('/home'),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (ProfileGuard.requireProfile(context, ref)) {
            context.push('/acoes/novo');
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const MissingProfileBanner(),
          _FilterBar(
            churchesAsync: churchesAsync,
            churchFilterId: _filtroIgrejaId,
            sortOrder: _sortOrder,
            sabbathOnly: _soSabado,
            onFiltroIgrejaChanged: (v) => setState(() => _filtroIgrejaId = v),
            onSortOrderChanged: (v) => setState(() => _sortOrder = v),
            onSoSabadoChanged: (v) => setState(() => _soSabado = v),
          ),
          Expanded(
            child: actionsAsync.when(
              data: (items) {
                var filtered = _filtroIgrejaId == _allChurches
                    ? items
                    : items.where((i) => i.churchId == _filtroIgrejaId).toList();
                if (_soSabado) {
                  filtered = filtered
                      .where((i) => isOnSabbath(i.action.dateTime))
                      .toList();
                }
                if (filtered.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                final sorted = [...filtered]..sort(_comparador(_sortOrder));
                final byPeriod = <ActionPeriod, List<ActionWithChurch>>{};
                for (final item in sorted) {
                  final period = actionPeriod(item.action.dateTime, now);
                  byPeriod.putIfAbsent(period, () => []).add(item);
                }
                return ListView(
                  children: [
                    for (final period in _periodOrder)
                      if (byPeriod[period]?.isNotEmpty ?? false) ...[
                        _SectionHeader(name: _periodLabel[period]!, highlighted: period == ActionPeriod.sabbath),
                        for (final item in byPeriod[period]!)
                          _ActionCard(
                            action: item.action,
                            sabbathHighlight: period == ActionPeriod.sabbath,
                          ),
                      ],
                  ],
                );
              },
              loading: () => const Center(child: CircularProgressIndicator()),
              error: (_, _) => const Center(child: Text('Não deu pra carregar as Ações agora.')),
            ),
          ),
        ],
      ),
    );
  }

  int Function(ActionWithChurch, ActionWithChurch) _comparador(_ActionSortOrder sortOrder) {
    switch (sortOrder) {
      case _ActionSortOrder.data:
        return (a, b) => a.action.dateTime.compareTo(b.action.dateTime);
      case _ActionSortOrder.maisRecentes:
        return (a, b) => b.action.createdAt.compareTo(a.action.createdAt);
      case _ActionSortOrder.name:
        return (a, b) => a.action.name.toLowerCase().compareTo(b.action.name.toLowerCase());
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.churchesAsync,
    required this.churchFilterId,
    required this.sortOrder,
    required this.sabbathOnly,
    required this.onFiltroIgrejaChanged,
    required this.onSortOrderChanged,
    required this.onSoSabadoChanged,
  });

  final AsyncValue<List<Church>> churchesAsync;
  final String churchFilterId;
  final _ActionSortOrder sortOrder;
  final bool sabbathOnly;
  final ValueChanged<String> onFiltroIgrejaChanged;
  final ValueChanged<_ActionSortOrder> onSortOrderChanged;
  final ValueChanged<bool> onSoSabadoChanged;

  @override
  Widget build(BuildContext context) {
    final churches = churchesAsync.value ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
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
                  onChanged: (v) => v == null ? null : onFiltroIgrejaChanged(v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<_ActionSortOrder>(
                  initialValue: sortOrder,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: const [
                    DropdownMenuItem(value: _ActionSortOrder.data, child: Text('Data')),
                    DropdownMenuItem(value: _ActionSortOrder.maisRecentes, child: Text('Mais recentes')),
                    DropdownMenuItem(value: _ActionSortOrder.name, child: Text('Nome (A-Z)')),
                  ],
                  onChanged: (v) => v == null ? null : onSortOrderChanged(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterChip(
            avatar: const Icon(Icons.nights_stay_outlined, size: 18),
            label: const Text('Só Sábado'),
            selected: sabbathOnly,
            onSelected: onSoSabadoChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.name, this.highlighted = false});

  final String name;
  final bool highlighted;

  @override
  Widget build(BuildContext context) {
    final color = highlighted ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (highlighted) ...[
                Icon(Icons.nights_stay, size: 18, color: color),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                name,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: color,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          Divider(height: AppSpacing.sm, color: highlighted ? color : null),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.action, this.sabbathHighlight = false});

  final Action action;
  final bool sabbathHighlight;

  @override
  Widget build(BuildContext context) {
    final tertiary = Theme.of(context).colorScheme.tertiary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      shape: sabbathHighlight
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: tertiary, width: 2),
            )
          : null,
      color: sabbathHighlight ? tertiary.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: sabbathHighlight ? Icon(Icons.nights_stay, color: tertiary) : null,
        title: Text(action.name),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy HH:mm').format(action.dateTime)} · ${action.local}'
          '${action.isCancelled ? ' · Cancelada' : ''}',
        ),
        onTap: () => context.push('/acoes/${action.id}'),
      ),
    );
  }
}
