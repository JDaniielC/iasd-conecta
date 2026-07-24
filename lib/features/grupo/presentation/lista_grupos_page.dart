import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../../perfil/presentation/widgets/perfil_ausente_banner.dart';
import '../grupo_providers.dart';

/// Home do app: lista de Grupos, visível a Visitante e Usuário igualmente
/// (FR-005/FR-008 — sem exigir Perfil pra essa visualização).
class ListaGruposPage extends ConsumerWidget {
  const ListaGruposPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPerfil = ref.watch(hasPerfilProvider).valueOrNull ?? false;
    final temConta = hasPerfil && ref.watch(authRepositoryProvider).temConta;
    final isDistrictAdmin = ref.watch(isDistrictAdminProvider).valueOrNull ?? false;
    final gruposAsync = ref.watch(gruposProvider);

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
          Expanded(
            child: gruposAsync.when(
              data: (grupos) {
                if (grupos.isEmpty) {
                  return const Center(child: Text('Nenhum Grupo ainda.'));
                }
                return ListView.builder(
                  itemCount: grupos.length,
                  itemBuilder: (context, index) {
                    final grupo = grupos[index];
                    return Card(
                      child: ListTile(
                        title: Text(grupo.nome),
                        subtitle: Text('${grupo.categoria} · ${grupo.horario}'),
                        onTap: () => context.push('/grupos/${grupo.id}'),
                      ),
                    );
                  },
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
}
