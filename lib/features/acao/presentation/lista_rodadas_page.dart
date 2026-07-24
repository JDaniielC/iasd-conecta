import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../perfil/domain/perfil_guard.dart';
import '../rodada_providers.dart';

/// Lista de Rodadas de votação de um Grupo — visível a Visitante e Usuário
/// igualmente (FR-017).
class ListaRodadasPage extends ConsumerWidget {
  const ListaRodadasPage({super.key, required this.grupoId});

  final String grupoId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rodadasAsync = ref.watch(rodadasDoGrupoProvider(grupoId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rodadas de Votação')),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          if (PerfilGuard.exigirPerfil(context, ref)) {
            context.push('/grupos/$grupoId/rodadas/novo');
          }
        },
        child: const Icon(Icons.add),
      ),
      body: rodadasAsync.when(
        data: (rodadas) {
          if (rodadas.isEmpty) {
            return const Center(child: Text('Nenhuma Rodada ainda.'));
          }
          return ListView.builder(
            itemCount: rodadas.length,
            itemBuilder: (context, index) {
              final rodada = rodadas[index];
              return Card(
                child: ListTile(
                  title: Text(rodada.aberta ? 'Aberta' : 'Fechada'),
                  subtitle: Text(
                    'Prazo: ${DateFormat('dd/MM/yyyy HH:mm').format(rodada.prazo)}',
                  ),
                  onTap: () => context.push('/rodadas/${rodada.id}'),
                ),
              );
            },
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Não deu pra carregar as Rodadas agora.')),
      ),
    );
  }
}
