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

/// Largura **útil** (já descontado o respiro lateral da tela) abaixo da qual
/// a tela é tratada como celular.
///
/// É a largura onde "Todas as Igrejas" e "Mais recentes" ainda cabem lado a
/// lado nos dois filtros — medida, não um tamanho de aparelho escolhido a
/// dedo. Só a barra de filtro usa este limiar — a faixa de destaque não
/// precisa mais de corte por largura.
const _narrowContentWidth = 480.0;

/// Quantos cartões a faixa de destaque mostra antes de "ver mais".
///
/// Existe porque toda Ação avulsa entra na faixa **sem sair** da lista por
/// período (a spec exige as duas aparições): num distrito onde a maioria das
/// Ações é avulsa, uma faixa sem corte vira uma segunda cópia da lista e
/// empurra o primeiro cabeçalho de período para fora da tela.
///
/// Três serve no celular porque o cartão da faixa é baixo (80px medidos): num
/// iPhone 14 (390x844) o primeiro cabeçalho de período fica em y=800, dentro
/// da dobra. Chegou a ser dois enquanto o botão de fechar esticava o cartão
/// para 100px — tirado ele do fluxo, a conta voltou a fechar com três em
/// qualquer largura, e um número só é menos coisa para errar depois.
const _maxHighlightsCollapsed = 3;

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

  /// A faixa está aberta além dos [_maxHighlightsCollapsed] primeiros?
  bool _showAllHighlights = false;

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
    // Entrar nesta tela é o que consome a novidade. Quem detecta isso é o
    // provider `autoDispose`, não o ciclo de vida deste widget — ver
    // `lastSeenActionsProvider`.
    final lastSeen = ref.watch(lastSeenActionsProvider).value;
    // Observado pelo efeito, não pelo valor: é ele que avança o marcador, e só
    // depois que a lista e os Grupos carregaram. Ver `markActionsSeenProvider`.
    ref.watch(markActionsSeenProvider);

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
                // A faixa NÃO herda o filtro de Igreja. Medido em 2026-08-12:
                // filtrando por uma Igreja, a Ação nova de um Grupo meu
                // sediado em outra sumia da faixa — e o marcador avançava
                // assim mesmo, então ela não voltava. Quem deixa o filtro na
                // própria Igreja, que é o provável, deixaria de ver
                // exatamente a novidade que a faixa existe para mostrar.
                //
                // "Só Sábado" continua valendo aqui: ele diz "quero ver só o
                // que é do Sábado", e uma faixa cheia de Ação de outro dia
                // contrariaria o que a pessoa acabou de pedir.
                var bandItems = _sabbathOnly
                    ? items.where((i) => isOnSabbath(i.action.dateTime)).toList()
                    : items;
                bandItems = bandItems
                    .where((i) =>
                        actionTimeStatus(i.action.dateTime, now) !=
                        ActionTimeStatus.ended)
                    .toList();
                if (filtered.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                final sorted = [...filtered]..sort(_comparator(_sortOrder));
                final sortedBand = [...bandItems]..sort(_comparator(_sortOrder));
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
                  for (final item in sortedBand)
                    if (!dismissed.contains(item.action.id))
                      if (actionHighlight(
                            item.action,
                            myGroupIds: myGroupIds,
                            lastSeen: lastSeen,
                          )
                          case final highlight?)
                        (item: item, highlight: highlight),
                ]
                  // Novidade de Grupo primeiro. Herdando a ordem da lista (por
                  // data), a única Ação nova de um Grupo meu caía em 6º e
                  // sumia atrás do "ver mais" — justamente a que a pessoa não
                  // sabe que existe, que é o motivo de a faixa existir. Ação
                  // avulsa não some: ela está na faixa todo dia e continua
                  // logo abaixo. `sort` é estável em Dart, então entre iguais
                  // a ordem da lista se mantém.
                  ..sort((a, b) => a.highlight == b.highlight
                      ? 0
                      : a.highlight == ActionHighlight.myGroup
                          ? -1
                          : 1);
                final visibleHighlights = _showAllHighlights
                    ? highlights
                    : highlights.take(_maxHighlightsCollapsed).toList();
                final hiddenHighlights =
                    highlights.length - visibleHighlights.length;
                return ListView(
                  children: [
                    if (highlights.isNotEmpty) ...[
                      const _SectionHeader(name: 'Em destaque'),
                      for (final entry in visibleHighlights)
                        _HighlightCard(
                          action: entry.item.action,
                          highlight: entry.highlight,
                          sabbathHighlight: actionPeriod(
                                entry.item.action.dateTime,
                                now,
                              ) ==
                              ActionPeriod.sabbath,
                          onDismiss: () => ref
                              .read(dismissedHighlightsProvider.notifier)
                              .dismiss(entry.item.action.id),
                        ),
                      // Condição na lista inteira, não no que sobrou
                      // escondido: aberta e com os itens fechados um a um até
                      // sobrarem três, `hiddenHighlights` zera e o botão
                      // "Ver menos" ficaria sem nada a encolher.
                      if (highlights.length > _maxHighlightsCollapsed)
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                            ),
                            child: TextButton(
                              onPressed: () => setState(
                                () => _showAllHighlights = !_showAllHighlights,
                              ),
                              child: Text(
                                _showAllHighlights
                                    ? 'Ver menos'
                                    : hiddenHighlights == 1
                                        ? 'Ver mais 1 em destaque'
                                        : 'Ver mais $hiddenHighlights em destaque',
                              ),
                            ),
                          ),
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
    final church = DropdownButtonFormField<String>(
      initialValue: churchFilterId,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Igreja'),
      items: [
        const DropdownMenuItem(value: _allChurches, child: Text('Todas as Igrejas')),
        for (final c in churches) DropdownMenuItem(value: c.id, child: Text(c.name)),
      ],
      onChanged: (v) => v == null ? null : onChurchFilterChanged(v),
    );
    final sort = DropdownButtonFormField<_ActionSortOrder>(
      initialValue: sortOrder,
      isDense: true,
      decoration: const InputDecoration(labelText: 'Ordenar por'),
      items: const [
        DropdownMenuItem(value: _ActionSortOrder.byDate, child: Text('Data')),
        DropdownMenuItem(value: _ActionSortOrder.mostRecent, child: Text('Mais recentes')),
        DropdownMenuItem(value: _ActionSortOrder.name, child: Text('Nome (A-Z)')),
      ],
      onChanged: (v) => v == null ? null : onSortOrderChanged(v),
    );

    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Lado a lado só quando há largura para isso. Num celular de 390px
          // cada um ficava com ~170px e "Todas as Igrejas"/"Mais recentes"
          // estouravam a Row em 119px — texto cortado e a listra amarela do
          // Flutter em cima da tela de toda pessoa que abrisse /acoes no
          // telefone. O limiar é a largura onde os dois textos ainda cabem,
          // não um tamanho de aparelho.
          LayoutBuilder(
            builder: (context, constraints) {
              if (constraints.maxWidth < _narrowContentWidth) {
                return Column(
                  children: [church, const SizedBox(height: AppSpacing.sm), sort],
                );
              }
              return Row(
                children: [
                  Expanded(child: church),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(child: sort),
                ],
              );
            },
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
  });

  final Action action;

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
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
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
              // Change `acao-direcionada-a-grupo`: quem participa vê a Ação
              // restrita junto das demais, e precisa saber que ela é restrita —
              // senão combina no WhatsApp com quem não consegue nem abrir.
              // Aqui cabe texto: esta linha quebra, não corta.
              '${action.restrictedToGroup ? ' · Só do Grupo' : ''}'
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

/// Cartão da faixa de destaque. Baixo de propósito.
///
/// **Por que não reusar `_ActionCard`.** A faixa não tira a Ação da lista por
/// período — a mesma Ação aparece nos dois lugares. Com o cartão cheio (capa,
/// contagem de confirmados, três linhas) medimos ~148px cada num celular:
/// três deles mais a barra de filtro enchiam a dobra inteira e a lista por
/// período nascia fora da tela. Aqui ficam só as três coisas que decidem se
/// vale abrir — de onde vem, o quê, e quando/onde. Capa e contagem estão a um
/// toque de distância, no cartão cheio logo abaixo.
class _HighlightCard extends StatelessWidget {
  const _HighlightCard({
    required this.action,
    required this.highlight,
    this.sabbathHighlight = false,
    this.onDismiss,
  });

  final Action action;
  final ActionHighlight highlight;
  final bool sabbathHighlight;
  final VoidCallback? onDismiss;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final (label, icon, color) = switch (highlight) {
      ActionHighlight.district => (
          'Todo o distrito',
          Icons.campaign_outlined,
          scheme.primary,
        ),
      ActionHighlight.myGroup => (
          'Novo no seu Grupo',
          Icons.fiber_new_outlined,
          scheme.secondary,
        ),
    };
    // Sábado fica com a borda quando as duas dimensões valem ao mesmo tempo, e
    // a origem passa a ser dita pela tarja. São três cores na mesma tela
    // (tertiary/primary/secondary) e nenhuma pode virar a outra — duas bordas
    // concorrentes no mesmo cartão era o jeito certo de confundi-las.
    final borderColor = sabbathHighlight ? scheme.tertiary : color;

    return Card(
      margin: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.xs,
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: borderColor, width: 2),
      ),
      color: borderColor.withValues(alpha: 0.08),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => context.push('/acoes/${action.id}'),
        // `Stack`, e não o botão dentro da `Row` do título: o alvo de toque de
        // 48px que SC-004 exige esticava a linha da tarja para 48 e abria um
        // vão entre ela e o nome da Ação, fora da escala do resto do cartão.
        // Sobreposto, ele mantém os 48 tocáveis e a linha volta à altura do
        // texto. O padding à direita é o que reserva o lugar dele.
        child: Stack(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(
                AppSpacing.md,
                AppSpacing.sm,
                AppSpacing.xl + AppSpacing.md,
                AppSpacing.sm,
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(icon, size: 16, color: color),
                      const SizedBox(width: AppSpacing.xs),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              Theme.of(context).textTheme.labelSmall?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.bold,
                                  ),
                        ),
                      ),
                      if (sabbathHighlight) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Icon(Icons.nights_stay,
                            size: 16, color: scheme.tertiary),
                      ],
                      // Ícone, e não texto: a linha de data logo abaixo é
                      // `maxLines: 1` com reticências, e mais um pedaço ali
                      // comeria o local. O `Tooltip` também é o rótulo que o
                      // leitor de tela anuncia.
                      if (action.restrictedToGroup) ...[
                        const SizedBox(width: AppSpacing.xs),
                        Tooltip(
                          message: 'Só para quem participa do Grupo',
                          child: Icon(Icons.lock_outline, size: 16, color: color),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: AppSpacing.xs),
                  Text(
                    action.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.titleSmall,
                  ),
                  Text(
                    '${DateFormat('dd/MM HH:mm').format(action.dateTime)} · ${action.local}'
                    '${action.isCancelled ? ' · Cancelada' : ''}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (onDismiss != null)
              Positioned(
                top: 0,
                right: 0,
                child: IconButton(
                  tooltip: 'Tirar do destaque',
                  icon: const Icon(Icons.close, size: 18),
                  color: color,
                  onPressed: onDismiss,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
