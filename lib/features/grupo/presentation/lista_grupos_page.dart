import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../grupo_providers.dart';

/// Home do app: lista de Grupos, visível a Visitante e Usuário igualmente
/// (FR-005/FR-008 — sem exigir Perfil pra essa visualização).
class ListaGruposPage extends ConsumerWidget {
  const ListaGruposPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPerfil = ref.watch(hasPerfilProvider).valueOrNull ?? false;
    final temConta = hasPerfil && ref.watch(authRepositoryProvider).temConta;
    final gruposAsync = ref.watch(gruposProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grupos'),
        actions: [
          if (hasPerfil && !temConta)
            IconButton(
              tooltip: 'Virar Conta',
              icon: const Icon(Icons.cloud_upload_outlined),
              onPressed: () => context.push('/upgrade-conta'),
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
          if (!hasPerfil)
            Container(
              width: double.infinity,
              color: AppColors.surface,
              padding: const EdgeInsets.all(AppSpacing.md),
              child: Row(
                children: [
                  const Expanded(
                    child: Text('Crie um Perfil pra participar dos Grupos.'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/cadastro'),
                    child: const Text('Criar Perfil'),
                  ),
                ],
              ),
            ),
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
