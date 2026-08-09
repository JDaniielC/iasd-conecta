import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../group/group_providers.dart';
import '../../perfil/domain/perfil_guard.dart';
import '../action_providers.dart';
import '../domain/action.dart';

/// Detalhes de uma Ação avulsa: visível a Visitante e Usuário igualmente
/// (FR-010). Confirmar/desistir exige Perfil (FR-003/FR-004/FR-011).
class ActionDetailPage extends ConsumerWidget {
  const ActionDetailPage({super.key, required this.acaoId});

  final String acaoId;

  void _mostrarErro(BuildContext context, String mensagem) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(mensagem)));
  }

  Future<void> _confirmar(BuildContext context, WidgetRef ref) async {
    if (!PerfilGuard.exigirPerfil(context, ref)) return;
    try {
      await ref.read(actionRepositoryProvider).confirmAttendance(acaoId);
      ref.invalidate(attendeesProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra confirmar presença. Tente de novo.');
    }
  }

  Future<void> _desistir(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(actionRepositoryProvider).withdraw(acaoId);
      ref.invalidate(attendeesProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra desistir agora. Tente de novo.');
    }
  }

  Future<void> _cancelar(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(actionRepositoryProvider).cancelAction(acaoId);
      ref.invalidate(actionProvider(acaoId));
    } catch (_) {
      if (!context.mounted) return;
      _mostrarErro(context, 'Não deu pra cancelar agora. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final acaoAsync = ref.watch(actionProvider(acaoId));
    final confirmadosAsync = ref.watch(attendeesProvider(acaoId));
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
          final canCancel = acao.canCancel(
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
                    if (canCancel && !acao.isCancelled && acao.isConfirmed)
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Cancelar Ação',
                        onPressed: () => _cancelar(context, ref),
                      ),
                  ],
                ),
                if (acao.isCancelled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Cancelada',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (acao.isCandidateInVoting) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Ação candidata — ainda em votação numa Rodada.'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/rodadas/${acao.votingRoundId}'),
                        child: const Text('Ver Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(acao.dateTime)),
                Text(acao.local),
                if (acao.isMissionaryPair) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Dupla Missionária — visita a um(a) '
                    '${acao.visitedGender == VisitedGender.male ? 'homem' : 'mulher'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (acao.capacity != null) Text('Vagas: ${acao.capacity}'),
                if (acao.detalhes != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(acao.detalhes!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!acao.isCancelled)
                  ElevatedButton(
                    onPressed: minhaConfirmacao != null
                        ? () => _desistir(context, ref)
                        : () => _confirmar(context, ref),
                    child: Text(
                      minhaConfirmacao == null
                          ? 'Confirmar presença'
                          : (minhaConfirmacao.status == AttendanceStatus.fila
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
                          .where((c) => c.status == AttendanceStatus.confirmado)
                          .toList();
                      final fila = confirmados
                          .where((c) => c.status == AttendanceStatus.fila)
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
