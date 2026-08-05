import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../perfil/domain/church.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../../perfil/presentation/widgets/perfil_ausente_banner.dart';
import '../acao_providers.dart';
import '../domain/acao.dart';

enum _OrdenacaoAcao { data, maisRecentes, nome }

const _todasAsIgrejas = '__todas__';

const _ordemPeriodos = [
  PeriodoAcao.sabado,
  PeriodoAcao.hoje,
  PeriodoAcao.essaSemana,
  PeriodoAcao.outras,
];

const _rotuloPeriodo = {
  PeriodoAcao.sabado: 'Sábado',
  PeriodoAcao.hoje: 'Hoje',
  PeriodoAcao.essaSemana: 'Essa semana',
  PeriodoAcao.outras: 'Outras datas',
};

/// Lista de Ações avulsas: visível a Visitante e Usuário igualmente
/// (FR-010 — sem exigir Perfil pra essa visualização). Agrupada por período
/// (Sábado/Hoje/Essa semana/Outras datas) — o que importa pra quem abre a
/// lista é "o que tem pra quando", não a estrutura administrativa por
/// Igreja. Sábado adventista (sexta 17:30 - sábado 17:30, `acaoNoSabado`)
/// ganha destaque visual e sempre vem primeiro.
class ListaAcoesPage extends ConsumerStatefulWidget {
  const ListaAcoesPage({super.key});

  @override
  ConsumerState<ListaAcoesPage> createState() => _ListaAcoesPageState();
}

class _ListaAcoesPageState extends ConsumerState<ListaAcoesPage> {
  String _filtroIgrejaId = _todasAsIgrejas;
  _OrdenacaoAcao _ordenacao = _OrdenacaoAcao.data;
  bool _soSabado = false;

  @override
  Widget build(BuildContext context) {
    final acoesAsync = ref.watch(acoesComIgrejaProvider);
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
          _FiltrosBar(
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
                      .where((i) => acaoNoSabado(i.acao.dataHora))
                      .toList();
                }
                if (filtrados.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                final ordenados = [...filtrados]..sort(_comparador(_ordenacao));
                final porPeriodo = <PeriodoAcao, List<AcaoComIgreja>>{};
                for (final item in ordenados) {
                  final periodo = periodoDaAcao(item.acao.dataHora, agora);
                  porPeriodo.putIfAbsent(periodo, () => []).add(item);
                }
                return ListView(
                  children: [
                    for (final periodo in _ordemPeriodos)
                      if (porPeriodo[periodo]?.isNotEmpty ?? false) ...[
                        _CabecalhoSecao(nome: _rotuloPeriodo[periodo]!, destaque: periodo == PeriodoAcao.sabado),
                        for (final item in porPeriodo[periodo]!)
                          _AcaoCard(
                            acao: item.acao,
                            destaqueSabado: periodo == PeriodoAcao.sabado,
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

  int Function(AcaoComIgreja, AcaoComIgreja) _comparador(_OrdenacaoAcao ordenacao) {
    switch (ordenacao) {
      case _OrdenacaoAcao.data:
        return (a, b) => a.acao.dataHora.compareTo(b.acao.dataHora);
      case _OrdenacaoAcao.maisRecentes:
        return (a, b) => b.acao.createdAt.compareTo(a.acao.createdAt);
      case _OrdenacaoAcao.nome:
        return (a, b) => a.acao.nome.toLowerCase().compareTo(b.acao.nome.toLowerCase());
    }
  }
}

class _FiltrosBar extends StatelessWidget {
  const _FiltrosBar({
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
  final _OrdenacaoAcao ordenacao;
  final bool soSabado;
  final ValueChanged<String> onFiltroIgrejaChanged;
  final ValueChanged<_OrdenacaoAcao> onOrdenacaoChanged;
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
                child: DropdownButtonFormField<_OrdenacaoAcao>(
                  initialValue: ordenacao,
                  isDense: true,
                  decoration: const InputDecoration(labelText: 'Ordenar por'),
                  items: const [
                    DropdownMenuItem(value: _OrdenacaoAcao.data, child: Text('Data')),
                    DropdownMenuItem(value: _OrdenacaoAcao.maisRecentes, child: Text('Mais recentes')),
                    DropdownMenuItem(value: _OrdenacaoAcao.nome, child: Text('Nome (A-Z)')),
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

class _CabecalhoSecao extends StatelessWidget {
  const _CabecalhoSecao({required this.nome, this.destaque = false});

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

class _AcaoCard extends StatelessWidget {
  const _AcaoCard({required this.acao, this.destaqueSabado = false});

  final Acao acao;
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
          '${DateFormat('dd/MM/yyyy HH:mm').format(acao.dataHora)} · ${acao.local}'
          '${acao.cancelada ? ' · Cancelada' : ''}',
        ),
        onTap: () => context.push('/acoes/${acao.id}'),
      ),
    );
  }
}
