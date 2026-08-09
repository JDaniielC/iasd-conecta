import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../group/group_providers.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../acao_providers.dart';
import '../domain/acao.dart';

/// Detalhes de uma Ação avulsa: visível a Visitante e Usuário igualmente
/// (FR-010). Confirmar/desistir exige Perfil (FR-003/FR-004/FR-011).
class DetalheAcaoPage extends ConsumerWidget {
  const DetalheAcaoPage({super.key, required this.acaoId});

  final String acaoId;

  void _mostrarErro(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _confirmar(BuildContext context, WidgetRef ref) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    try {
      await ref.read(acaoRepositoryProvider).confirmarPresenca(acaoId);
      ref.invalidate(confirmadosProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra confirmar presença. Tente de novo.');
    }
  }

  Future<void> _desistir(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(acaoRepositoryProvider).desistir(acaoId);
      ref.invalidate(confirmadosProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra desistir agora. Tente de novo.');
    }
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(acaoRepositoryProvider).cancelarAcao(acaoId);
      ref.invalidate(acaoProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra cancelar agora. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acaoAsync = ref.watch(acaoProvider(acaoId));
    final confirmadosAsync = ref.watch(confirmadosProvider(acaoId));
    final uid = ref.watch(currentUserIdProvider);
    final minhasConfirmacoes =
        confirmadosAsync.value?.where((c) => c.perfil.id == uid) ?? const [];
    final minhaConfirmacao = minhasConfirmacoes.isEmpty ? null : minhasConfirmacoes.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Ação')),
      body: acaoAsync.when(
        data: (acao) {
          final souDonoDoGrupo = acao.grupoId == null
              ? false
              : (ref.watch(groupProvider(acao.grupoId!)).value?.isOwner(uid) ?? false);
          final souAdministradorDoDistrito =
              ref.watch(isDistrictAdminProvider).value ?? false;
          final podeCancelar = acao.podeCancelar(
            uid,
            souDonoDoGrupo: souDonoDoGrupo,
            souAdministradorDoDistrito: souAdministradorDoDistrito,
          );
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        acao.nome,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (podeCancelar && !acao.cancelada && acao.confirmada)
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Cancelar Ação',
                        onPressed: () => _cancelar(context, ref),
                      ),
                  ],
                ),
                if (acao.cancelada) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Cancelada',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (acao.ehCandidataEmVotacao) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Ação candidata — ainda em votação numa Rodada.'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/rodadas/${acao.rodadaId}'),
                        child: const Text('Ver Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(acao.dataHora)),
                Text(acao.local),
                if (acao.isMissionaryPair) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Dupla Missionária — visita a um(a) '
                    '${acao.visitedGender == VisitedGender.male ? 'homem' : 'mulher'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (acao.limiteVagas != null) Text('Vagas: ${acao.limiteVagas}'),
                if (acao.detalhes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(acao.detalhes!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!acao.cancelada)
                  ElevatedButton(
                    onPressed: minhaConfirmacao != null
                        ? () => _desistir(context, ref)
                        : () => _confirmar(context, ref),
                    child: Text(
                      minhaConfirmacao == null
                          ? 'Confirmar presença'
                          : (minhaConfirmacao.status == StatusConfirmacao.fila
                              ? 'Sair da fila de espera'
                              : 'Desistir'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text('Confirmados', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: confirmadosAsync.when(
                    data: (confirmados) {
                      final vagas = confirmados
                          .where((c) => c.status == StatusConfirmacao.confirmado)
                          .toList();
                      final fila = confirmados
                          .where((c) => c.status == StatusConfirmacao.fila)
                          .toList();
                      return ListView(
                        children: [
                          ...vagas.map((c) => ListTile(title: Text(c.perfil.displayName))),
                          if (fila.isNotEmpty) ...[
                            const Divider(),
                            const Text('Fila de espera'),
                            ...fila.map((c) => ListTile(
                                  title: Text(c.perfil.displayName),
                                  dense: true,
                                )),
                          ],
                        ],
                      );
                    },
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Não deu pra carregar os confirmados.'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Ação não encontrada.')),
      ),
    );
  }
}
