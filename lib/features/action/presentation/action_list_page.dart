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

enum _ActionSortOrder { data, maisRecentes, nome }

const _todasAsIgrejas = '__todas__';

const _ordemPeriodos = [
  ActionPeriod.sabado,
  ActionPeriod.hoje,
  ActionPeriod.essaSemana,
  ActionPeriod.outras,
];

const _rotuloPeriodo = {
  ActionPeriod.sabado: 'Sábado',
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
  String _filtroIgrejaId = _todasAsIgrejas;
  _ActionSortOrder _ordenacao = _ActionSortOrder.data;
  bool _soSabado = false;

  @override
  Widget build(BuildContext context) {
    final acoesAsync = ref.watch(actionsWithChurchProvider);
    final churchesAsync = ref.watch(churchesProvider);
    final agora = DateTime.now();

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
          if (PerfilGuard.exigirPerfil(context, ref)) {
            context.push('/acoes/novo');
          }
        },
        child: const Icon(Icons.add),
      ),
      body: Column(
        children: [
          const PerfilAusenteBanner(),
          _FilterBar(
            churchesAsync: churchesAsync,
            filtroIgrejaId: _filtroIgrejaId,
            ordenacao: _ordenacao,
            soSabado: _soSabado,
            onFiltroIgrejaChanged: (v) => setState(() => _filtroIgrejaId = v),
            onOrdenacaoChanged: (v) => setState(() => _ordenacao = v),
            onSoSabadoChanged: (v) => setState(() => _soSabado = v),
          ),
          Expanded(
            child: acoesAsync.when(
              data: (itens) {
                var filtrados = _filtroIgrejaId == _todasAsIgrejas
                    ? itens
                    : itens.where((i) => i.igrejaId == _filtroIgrejaId).toList();
                if (_soSabado) {
                  filtrados = filtrados
                      .where((i) => isOnSabbath(i.acao.dateTime))
                      .toList();
                }
                if (filtrados.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                final ordenados = [...filtrados]..sort(_comparador(_ordenacao));
                final porPeriodo = <ActionPeriod, List<ActionWithChurch>>{};
                for (final item in ordenados) {
                  final periodo = actionPeriod(item.acao.dateTime, agora);
                  porPeriodo.putIfAbsent(periodo, () => []).add(item);
                }
                return ListView(
                  children: [
                    for (final periodo in _ordemPeriodos)
                      if (porPeriodo[periodo]?.isNotEmpty ?? false) ...[
                        _SectionHeader(nome: _rotuloPeriodo[periodo]!, destaque: periodo == ActionPeriod.sabado),
                        for (final item in porPeriodo[periodo]!)
                          _ActionCard(
                            acao: item.acao,
                            destaqueSabado: periodo == ActionPeriod.sabado,
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

  int Function(ActionWithChurch, ActionWithChurch) _comparador(_ActionSortOrder ordenacao) {
    switch (ordenacao) {
      case _ActionSortOrder.data:
        return (a, b) => a.acao.dateTime.compareTo(b.acao.dateTime);
      case _ActionSortOrder.maisRecentes:
        return (a, b) => b.acao.createdAt.compareTo(a.acao.createdAt);
      case _ActionSortOrder.nome:
        return (a, b) => a.acao.nome.toLowerCase().compareTo(b.acao.nome.toLowerCase());
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.churchesAsync,
    required this.filtroIgrejaId,
    required this.ordenacao,
    required this.soSabado,
    required this.onFiltroIgrejaChanged,
    required this.onOrdenacaoChanged,
    required this.onSoSabadoChanged,
  });

  final AsyncValue<List<Church>> churchesAsync;
  final String filtroIgrejaId;
  final _ActionSortOrder ordenacao;
  final bool soSabado;
  final ValueChanged<String> onFiltroIgrejaChanged;
  final ValueChanged<_ActionSortOrder> onOrdenacaoChanged;
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
                  initialValue: filtroIgrejaId,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Igreja'),
                  items: [
                    const DropdownMenuItem(value: _todasAsIgrejas, child: Text('Todas as Igrejas')),
                    for (final c in churches) DropdownMenuItem(value: c.id, child: Text(c.name)),
                  ],
                  onChanged: (v) => v == null ? null : onFiltroIgrejaChanged(v),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: DropdownButtonFormField<_ActionSortOrder>(
                  initialValue: ordenacao,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: const [
                    DropdownMenuItem(value: _ActionSortOrder.data, child: Text('Data')),
                    DropdownMenuItem(value: _ActionSortOrder.maisRecentes, child: Text('Mais recentes')),
                    DropdownMenuItem(value: _ActionSortOrder.nome, child: Text('Nome (A-Z)')),
                  ],
                  onChanged: (v) => v == null ? null : onOrdenacaoChanged(v),
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.sm),
          FilterChip(
            avatar: const Icon(Icons.nights_stay_outlined, size: 18),
            label: const Text('Só Sábado'),
            selected: soSabado,
            onSelected: onSoSabadoChanged,
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.nome, this.destaque = false});

  final String nome;
  final bool destaque;

  @override
  Widget build(BuildContext context) {
    final cor = destaque ? Theme.of(context).colorScheme.tertiary : Theme.of(context).colorScheme.primary;
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (destaque) ...[
                Icon(Icons.nights_stay, size: 18, color: cor),
                const SizedBox(width: AppSpacing.xs),
              ],
              Text(
                nome,
                style: Theme.of(context).textTheme.titleSmall?.copyWith(
                      color: cor,
                      fontWeight: FontWeight.bold,
                    ),
              ),
            ],
          ),
          Divider(height: AppSpacing.sm, color: destaque ? cor : null),
        ],
      ),
    );
  }
}

class _ActionCard extends StatelessWidget {
  const _ActionCard({required this.acao, this.destaqueSabado = false});

  final Action acao;
  final bool destaqueSabado;

  @override
  Widget build(BuildContext context) {
    final tertiary = Theme.of(context).colorScheme.tertiary;
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      shape: destaqueSabado
          ? RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: tertiary, width: 2),
            )
          : null,
      color: destaqueSabado ? tertiary.withValues(alpha: 0.08) : null,
      child: ListTile(
        leading: destaqueSabado ? Icon(Icons.nights_stay, color: tertiary) : null,
        title: Text(acao.nome),
        subtitle: Text(
          '${DateFormat('dd/MM/yyyy HH:mm').format(acao.dateTime)} · ${acao.local}'
          '${acao.isCancelled ? ' · Cancelada' : ''}',
        ),
        onTap: () => context.push('/acoes/${acao.id}'),
      ),
    );
  }
}
