import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/agrupar_por_igreja.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../profile/domain/church.dart';
import '../../profile/domain/profile_guard.dart';
import '../../profile/presentation/widgets/missing_profile_banner.dart';
import '../domain/group.dart';
import '../group_providers.dart';

enum _GroupSortOrder { maisRecentes, nome, categoria }

const _todasAsIgrejas = '__todas__';

/// Home do app: lista de Grupos, visível a Visitante e Usuário igualmente
/// (FR-005/FR-008 — sem exigir Perfil pra essa visualização). Agrupada por
/// Igreja, com filtro de Igreja e ordenação — um distrito com várias Igrejas
/// rapidamente vira uma lista longa e sem estrutura sem isso.
class GroupListPage extends ConsumerStatefulWidget {
  const GroupListPage({super.key});

  @override
  ConsumerState<GroupListPage> createState() => _GroupListPageState();
}

class _GroupListPageState extends ConsumerState<GroupListPage> {
  String _filtroIgrejaId = _todasAsIgrejas;
  _GroupSortOrder _ordenacao = _GroupSortOrder.maisRecentes;

  @override
  Widget build(BuildContext context) {
    final hasPerfil = ref.watch(hasPerfilProvider).value ?? false;
    final temConta = hasPerfil && ref.watch(authRepositoryProvider).temConta;
    final isDistrictAdmin = ref.watch(isDistrictAdminProvider).value ?? false;
    final gruposAsync = ref.watch(groupsProvider);
    final churchesAsync = ref.watch(churchesProvider);
    final nomePorIgrejaId = <String, String>{
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
          if (hasPerfil && !temConta)
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
          if (PerfilGuard.exigirPerfil(context, ref)) {
            context.push('/grupos/novo');
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
            onFiltroIgrejaChanged: (v) => setState(() => _filtroIgrejaId = v),
            onOrdenacaoChanged: (v) => setState(() => _ordenacao = v),
          ),
          Expanded(
            child: gruposAsync.when(
              data: (grupos) {
                final filtrados = _filtroIgrejaId == _todasAsIgrejas
                    ? grupos
                    : grupos.where((g) => g.igrejaId == _filtroIgrejaId).toList();
                if (filtrados.isEmpty) {
                  return const Center(child: Text('Nenhum Grupo ainda.'));
                }
                final ordenados = [...filtrados]..sort(_comparador(_ordenacao));
                final secoes = agruparPorIgreja(ordenados, (g) => g.igrejaId, nomePorIgrejaId);
                return ListView(
                  children: [
                    for (final secao in secoes) ...[
                      _SectionHeader(nome: secao.nomeIgreja),
                      for (final grupo in secao.itens) _GroupCard(grupo: grupo),
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

  int Function(Group, Group) _comparador(_GroupSortOrder ordenacao) {
    switch (ordenacao) {
      case _GroupSortOrder.maisRecentes:
        return (a, b) => b.createdAt.compareTo(a.createdAt);
      case _GroupSortOrder.nome:
        return (a, b) => a.nome.toLowerCase().compareTo(b.nome.toLowerCase());
      case _GroupSortOrder.categoria:
        return (a, b) => a.categoria.toLowerCase().compareTo(b.categoria.toLowerCase());
    }
  }
}

class _FilterBar extends StatelessWidget {
  const _FilterBar({
    required this.churchesAsync,
    required this.filtroIgrejaId,
    required this.ordenacao,
    required this.onFiltroIgrejaChanged,
    required this.onOrdenacaoChanged,
  });

  final AsyncValue<List<Church>> churchesAsync;
  final String filtroIgrejaId;
  final _GroupSortOrder ordenacao;
  final ValueChanged<String> onFiltroIgrejaChanged;
  final ValueChanged<_GroupSortOrder> onOrdenacaoChanged;

  @override
  Widget build(BuildContext context) {
    final churches = churchesAsync.value ?? const [];
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
      child: Row(
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
            child: DropdownButtonFormField<_GroupSortOrder>(
              initialValue: ordenacao,
              isDense: true,
              decoration: const InputDecoration(labelText: 'Ordenar por'),
              items: const [
                DropdownMenuItem(value: _GroupSortOrder.maisRecentes, child: Text('Mais recentes')),
                DropdownMenuItem(value: _GroupSortOrder.nome, child: Text('Nome (A-Z)')),
                DropdownMenuItem(value: _GroupSortOrder.categoria, child: Text('Categoria')),
              ],
              onChanged: (v) => v == null ? null : onOrdenacaoChanged(v),
            ),
          ),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.nome});

  final String nome;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.lg, AppSpacing.lg, AppSpacing.sm),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            nome,
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
  const _GroupCard({required this.grupo});

  final Group grupo;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xs),
      child: ListTile(
        title: Text(grupo.nome),
        subtitle: Text(grupo.categoria),
        onTap: () => context.push('/grupos/${grupo.id}'),
      ),
    );
  }
}
