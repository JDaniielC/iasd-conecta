import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../perfil/domain/perfil_guard.dart';
import '../../perfil/presentation/widgets/perfil_ausente_banner.dart';
import '../acao_providers.dart';

/// Lista de Ações avulsas: visível a Visitante e Usuário igualmente
/// (FR-010 — sem exigir Perfil pra essa visualização).
class ListaAcoesPage extends ConsumerWidget {
  const ListaAcoesPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acoesAsync = ref.watch(acoesProvider);

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
          Expanded(
            child: acoesAsync.when(
              data: (acoes) {
                if (acoes.isEmpty) {
                  return const Center(child: Text('Nenhuma Ação ainda.'));
                }
                return ListView.builder(
                  itemCount: acoes.length,
                  itemBuilder: (context, index) {
                    final acao = acoes[index];
                    return Card(
                      child: ListTile(
                        title: Text(acao.nome),
                        subtitle: Text(
                          '${DateFormat('dd/MM/yyyy HH:mm').format(acao.dataHora)} · ${acao.local}'
                          '${acao.cancelada ? ' · Cancelada' : ''}',
                        ),
                        onTap: () => context.push('/acoes/${acao.id}'),
                      ),
                    );
                  },
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
}
