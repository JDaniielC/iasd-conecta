import 'package:flutter/material.dart' hide Action;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../cover_photo/cover_photo_providers.dart';
import '../../cover_photo/domain/cover_photo.dart';
import '../../cover_photo/presentation/cover_photo_widget.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../profile/domain/church.dart';
import '../../profile/domain/profile_guard.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../../group/group_providers.dart';
import '../action_providers.dart';
import '../domain/action.dart';

enum _ActionSortOrder { byDate, mostRecent, name }

const _allChurches = '__todas__';

const _periodOrder = [
  ActionPeriod.sabbath,
  ActionPeriod.today,
  ActionPeriod.thisWeek,
  ActionPeriod.other,
];

const _periodLabel = {
  ActionPeriod.sabbath: 'Sábado',
  ActionPeriod.today: 'Hoje',
  ActionPeriod.thisWeek: 'Essa semana',
  ActionPeriod.other: 'Outras datas',
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
  String _churchFilterId = _allChurches;
  _ActionSortOrder _sortOrder = _ActionSortOrder.byDate;
  bool _sabbathOnly = false;

  /// O marcador **como estava ao abrir a tela**, e não como está agora.
  ///
  /// Precisa ser uma cópia em memória porque [_loadAndMarkSeen] avança o
  /// marcador na mesma abertura: ler do repositório a cada `build` devolveria
  /// o valor já avançado, e nenhuma Ação de Grupo jamais apareceria como
  /// nova.
  DateTime? _lastSeen;

  @override
  void initState() {
    super.initState();
    // Abrir a tela é o que consome a novidade — mesmo ponto do ciclo de vida
    // que `NewsPage` usa. Fora do `build`, e uma vez só.
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadAndMarkSeen());
  }

  Future<void> _loadAndMarkSeen() async {
    final repository = ref.read(actionsSeenRepositoryProvider);
    // Ler ANTES de gravar. Invertido, o destaque de Grupo morreria em
    // silêncio: o marcador novo já seria posterior a toda Ação existente.
    final lastSeen = await repository.readLastSeenActionsDate();
    await repository.writeLastSeenActionsDate(ref.read(clockProvider)());
    if (!mounted) return;
    setState(() => _lastSeen = lastSeen);
  }

  @override
  Widget build(BuildContext context) {
    final actionsAsync = ref.watch(actionsWithChurchProvider);
    final countsAsync = ref.watch(confirmationCountsProvider);
    final churchesAsync = ref.watch(churchesProvider);
    final now = ref.watch(clockProvider)();
    // Uma consulta só para a lista inteira, como as capas e as contagens.
    // Sem Perfil/Conta a consulta nem sai do aparelho — conjunto vazio, e a
    // faixa fica só com as Ações avulsas.
    final myGroupIds = ref.watch(myGroupIdsProvider).value ?? const <String>{};
    final dismissed = ref.watch(dismissedHighlightsProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Ações'),
        actions: [
          IconButton(
            tooltip: 'Grupos/Ministérios',
            icon: const Icon(Icons.groups_outlined),
            onPressed: () => context.go('/grupos'),
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
            churchFilterId: _churchFilterId,
            sortOrder: _sortOrder,
            sabbathOnly: _sabbathOnly,
            onChurchFilterChanged: (v) => setState(() => _churchFilterId = v),
            onSortOrderChanged: (v) => setState(() => _sortOrder = v),
            onSabbathOnlyChanged: (v) => setState(() => _sabbathOnly = v),
          ),
          Expanded(
            child: actionsAsync.when(
              data: (items) {
                var filtered = _churchFilterId == _allChurches
                    ? items
                    : items.where((i) => i.churchId == _churchFilterId).toList();
                if (_sabbathOnly) {
                  filtered = filtered
                      .where((i) => isOnSabbath(i.action.dateTime))
                      .toList();
                }
                // FR-003: Ação encerrada some da listagem. Depois dos demais
                // filtros de propósito — assim nenhuma combinação de filtro de
                // Igreja ou "Só Sábado" deixa uma encerrada escapar.
                filtered = filtered
                    .where((i) =>
                        actionTimeStatus(i.action.dateTime, now) !=
                        ActionTimeStatus.ended)
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                final sorted = [...filtered]..sort(_comparator(_sortOrder));
                final byPeriod = <ActionPeriod, List<ActionWithChurch>>{};
                for (final item in sorted) {
                  final period = actionPeriod(item.action.dateTime, now);
                  byPeriod.putIfAbsent(period, () => []).add(item);
                }
                // Uma consulta só para todas as capas da lista, e a lista
                // pinta com o que já tem. Consulta por card faria N consultas
                // e faria cada card crescer quando a sua capa chegasse — o
                // pulo de layout que FR-007 proíbe.
                final covers = ref
                        .watch(actionCoverPhotosProvider(
                          coverPhotosKey([for (final i in sorted) i.action.id]),
                        ))
                        .value ??
                    const <String, CoverPhoto>{};
                // A faixa vive DENTRO do `ListView`, e não numa fatia fixa
                // acima dele: numa tela de celular com vários Grupos em
                // destaque, uma fatia fixa comeria a altura toda e deixaria a
                // lista por período inalcançável. Aqui ela rola junto, e
                // quando está vazia ocupa zero — nunca sobra um espaço morto.
                final highlights = [
                  for (final item in sorted)
                    if (!dismissed.contains(item.action.id))
                      if (actionHighlight(
                            item.action,
                            myGroupIds: myGroupIds,
                            lastSeen: _lastSeen,
                          )
                          case final highlight?)
                        (item: item, highlight: highlight),
                ];
                return ListView(
                  children: [
                    if (highlights.isNotEmpty) ...[
                      const _SectionHeader(name: 'Em destaque'),
                      for (final entry in highlights)
                        _ActionCard(
                          action: entry.item.action,
                          highlight: entry.highlight,
                          sabbathHighlight: actionPeriod(
                                entry.item.action.dateTime,
                                now,
                              ) ==
                              ActionPeriod.sabbath,
                          happeningNow: actionTimeStatus(
                                entry.item.action.dateTime,
                                now,
                              ) ==
                              ActionTimeStatus.happeningNow,
                          counts: countsAsync.value?[entry.item.action.id] ??
                              const ConfirmationCounts(),
                          cover: covers[entry.item.action.id],
                          onDismiss: () => ref
                              .read(dismissedHighlightsProvider.notifier)
                              .dismiss(entry.item.action.id),
                        ),
                    ],
                    for (final period in _periodOrder)
                      if (byPeriod[period]?.isNotEmpty ?? false) ...[
                        _SectionHeader(name: _periodLabel[period]!, highlighted: period == ActionPeriod.sabbath),
                        for (final item in byPeriod[period]!)
                          _ActionCard(
                            action: item.action,
                            sabbathHighlight: period == ActionPeriod.sabbath,
                            happeningNow: actionTimeStatus(
                                  item.action.dateTime,
                                  now,
                                ) ==
                                ActionTimeStatus.happeningNow,
                            counts: countsAsync.value?[item.action.id] ??
                                const ConfirmationCounts(),
                            cover: covers[item.action.id],
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

  int Function(ActionWithChurch, ActionWithChurch) _comparator(_ActionSortOrder sortOrder) {
    switch (sortOrder) {
      case _ActionSortOrder.byDate:
        return (a, b) => a.action.dateTime.compareTo(b.action.dateTime);
      case _ActionSortOrder.mostRecent:
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
    required this.onChurchFilterChanged,
    required this.onSortOrderChanged,
    required this.onSabbathOnlyChanged,
  });

  final AsyncValue<List<Church>> churchesAsync;
  final String churchFilterId;
  final _ActionSortOrder sortOrder;
  final bool sabbathOnly;
  final ValueChanged<String> onChurchFilterChanged;
  final ValueChanged<_ActionSortOrder> onSortOrderChanged;
  final ValueChanged<bool> onSabbathOnlyChanged;

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
                  onChanged: (v) => v == null ? null : onChurchFilterChanged(v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<_ActionSortOrder>(
                  initialValue: sortOrder,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: const [
                    DropdownMenuItem(value: _ActionSortOrder.byDate, child: Text('Data')),
                    DropdownMenuItem(value: _ActionSortOrder.mostRecent, child: Text('Mais recentes')),
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
            onSelected: onSabbathOnlyChanged,
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

class _ActionCard extends ConsumerWidget {
  const _ActionCard({
    required this.action,
    this.sabbathHighlight = false,
    this.happeningNow = false,
    this.counts = const ConfirmationCounts(),
    this.cover,
    this.highlight,
    this.onDismiss,
  });

  final Action action;

  /// Por que esta Ação está na faixa de destaque — nulo na lista por período,
  /// que é a mesma de sempre e não muda de aparência.
  final ActionHighlight? highlight;

  /// Fechar este item da faixa. Nulo fora da faixa: a lista por período não
  /// tem o que dispensar.
  final VoidCallback? onDismiss;

  /// Já resolvida pela lista, de propósito — o card não consulta nada.
  final CoverPhoto? cover;
  final bool sabbathHighlight;

  /// FR-002: entre a hora marcada e 4h depois, a Ação continua na lista e
  /// ganha sinalização — quem está a caminho precisa achá-la.
  final bool happeningNow;

  /// FR-009 a FR-013: contagem agregada, sem identidade de ninguém.
  final ConfirmationCounts counts;

  /// Texto da contagem (FR-010 a FR-013).
  ///
  /// Nunca "0": zero confirmado vira uma frase, porque o número solto não
  /// informa nada a quem está decidindo de qual Ação participar (FR-011).
  String get _attendanceLabel {
    final n = counts.confirmed;
    final capacity = action.capacity;

    final label = switch ((n, capacity)) {
      (0, _) => 'Ninguém confirmou ainda',
      (1, null) => '1 confirmado',
      (_, null) => '$n confirmados',
      _ => '$n de $capacity vagas',
    };

    // Lotada com fila: a fila aparece separada da contagem, nunca somada
    // (FR-013) — somar faria uma Ação de 10 vagas parecer ter 15 pessoas.
    if (counts.waiting > 0) {
      final waitingLabel = counts.waiting == 1
          ? '1 na fila de espera'
          : '${counts.waiting} na fila de espera';
      return '$label · Lotada · $waitingLabel';
    }
    return label;
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final scheme = Theme.of(context).colorScheme;
    final tertiary = scheme.tertiary;
    // Sábado fica com a borda quando as duas dimensões valem ao mesmo tempo,
    // e a origem passa a ser dita pela tarja de cima. São três cores na mesma
    // tela (tertiary/primary/secondaryContainer) e nenhuma pode virar a
    // outra — pintar duas bordas concorrentes no mesmo cartão era o jeito
    // certo de confundir as duas.
    final borderColor = sabbathHighlight
        ? tertiary
        : switch (highlight) {
            ActionHighlight.district => scheme.primary,
            ActionHighlight.myGroup => scheme.secondary,
            null => null,
          };
    final tint = sabbathHighlight
        ? tertiary
        : switch (highlight) {
            ActionHighlight.district => scheme.primary,
            ActionHighlight.myGroup => scheme.secondaryContainer,
            null => null,
          };
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      shape: borderColor == null
          ? null
          : RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: borderColor, width: 2),
            ),
      color: tint?.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (highlight != null)
            _HighlightBanner(highlight: highlight!, onDismiss: onDismiss),
          // Ação sem capa não deixa buraco: CoverPhotoView ocupa zero.
          CoverPhotoView(
            photo: cover,
            imageUrl: cover == null
                ? null
                : ref.read(coverPhotoRepositoryProvider).publicUrlFor(cover!),
            borderRadius: BorderRadius.zero,
          ),
          ListTile(
        leading: sabbathHighlight ? Icon(Icons.nights_stay, color: tertiary) : null,
        title: Text(action.name),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${DateFormat('dd/MM/yyyy HH:mm').format(action.dateTime)} · ${action.local}'
              '${action.isCancelled ? ' · Cancelada' : ''}'
              '${!action.isCancelled && happeningNow ? ' · Acontecendo agora' : ''}',
            ),
            Text(_attendanceLabel),
          ],
        ),
            isThreeLine: true,
            onTap: () => context.push('/acoes/${action.id}'),
          ),
        ],
      ),
    );
  }
}

/// Tarja no topo do cartão em destaque: diz de onde a Ação vem e oferece
/// fechar.
///
/// A origem vira texto, e não só cor: quem não distingue as três cores da
/// tela (ou usa o app no sol) continua sabendo por que aquele cartão está lá.
class _HighlightBanner extends StatelessWidget {
  const _HighlightBanner({required this.highlight, this.onDismiss});

  final ActionHighlight highlight;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (highlight) {
      ActionHighlight.district => (
          'Aberta a todo o distrito',
          Icons.campaign_outlined,
          scheme.primary,
        ),
      ActionHighlight.myGroup => (
          'Nova em um Grupo seu',
          Icons.fiber_new_outlined,
          scheme.secondary,
        ),
    };

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.xs, 0),
      child: Row(
        children: [
          Icon(icon, size: 18, color: color),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: Text(
              label,
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                  ),
            ),
          ),
          if (onDismiss != null)
            IconButton(
              tooltip: 'Tirar do destaque',
              icon: const Icon(Icons.close, size: 18),
              color: color,
              onPressed: onDismiss,
            ),
        ],
      ),
    );
  }
}
