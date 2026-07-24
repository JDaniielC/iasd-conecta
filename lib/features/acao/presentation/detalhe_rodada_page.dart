import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/theme/app_theme.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../rodada_providers.dart';

/// Detalhes de uma Rodada de votação: candidatas + votar (User Story 2) +
/// encerrar antes do prazo, só Dono do Grupo (User Story 3).
class DetalheRodadaPage extends ConsumerWidget {
  const DetalheRodadaPage({super.key, required this.rodadaId});

  final String rodadaId;

  Future<void> _votar(BuildContext context, WidgetRef ref, String candidataId) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    await ref.read(rodadaRepositoryProvider).votar(rodadaId, candidataId);
    ref.invalidate(meuVotoProvider(rodadaId));
    ref.invalidate(candidatasProvider(rodadaId));
  }

  Future<void> _encerrar(WidgetRef ref) async {
    await ref.read(rodadaRepositoryProvider).fecharSeDevido(rodadaId, forcar: true);
    ref.invalidate(rodadaProvider(rodadaId));
    ref.invalidate(candidatasProvider(rodadaId));
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final rodadaAsync = ref.watch(rodadaProvider(rodadaId));
    final candidatasAsync = ref.watch(candidatasProvider(rodadaId));
    final meuVotoAsync = ref.watch(meuVotoProvider(rodadaId));

    return Scaffold(
      appBar: AppBar(title: const Text('Rodada de Votação')),
      body: rodadaAsync.when(
        data: (rodada) {
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  rodada.aberta ? 'Aberta' : 'Fechada',
                  style: Theme.of(context).textTheme.headlineMedium,
                ),
                Text('Prazo: ${DateFormat('dd/MM/yyyy HH:mm').format(rodada.prazo)}'),
                if (rodada.aberta) ...[
                  const SizedBox(height: AppSpacing.md),
                  Row(
                    children: [
                      ElevatedButton(
                        onPressed: () {
                          if (PerfilGuard.exigirPerfil(context, ref)) {
                            context.push('/rodadas/$rodadaId/candidatas/novo');
                          }
                        },
                        child: const Text('Propor Candidata'),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      OutlinedButton(
                        onPressed: () => _encerrar(ref),
                        child: const Text('Encerrar Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.lg),
                Text('Candidatas', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: candidatasAsync.when(
                    data: (candidatas) {
                      final meuVoto = meuVotoAsync.valueOrNull;
                      if (candidatas.isEmpty) {
                        return const Center(child: Text('Nenhuma candidata ainda.'));
                      }
                      return ListView.builder(
                        itemCount: candidatas.length,
                        itemBuilder: (context, index) {
                          final candidata = candidatas[index];
                          final votadaPorMim = meuVoto?.candidataId == candidata.id;
                          return Card(
                            child: ListTile(
                              title: Text(candidata.nome),
                              subtitle: Text(
                                '${DateFormat('dd/MM/yyyy HH:mm').format(candidata.dataHora)} · ${candidata.local}',
                              ),
                              onTap: () => context.push('/acoes/${candidata.id}'),
                              trailing: rodada.aberta
                                  ? OutlinedButton(
                                      onPressed: votadaPorMim
                                          ? null
                                          : () => _votar(context, ref, candidata.id),
                                      child: Text(votadaPorMim ? 'Seu voto' : 'Votar'),
                                    )
                                  : null,
                            ),
                          );
                        },
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Não deu pra carregar as candidatas.'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Rodada não encontrada.')),
      ),
    );
  }
}
