import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../cover_photo/presentation/cover_photo_widget.dart';
import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../group/group_providers.dart';
import '../../profile/domain/profile_guard.dart';
import '../action_providers.dart';
import '../domain/action.dart';

/// Detalhes de uma Ação avulsa: visível a Visitante e Usuário igualmente
/// (FR-010). Confirmar/desistir exige Perfil (FR-003/FR-004/FR-011).
class ActionDetailPage extends ConsumerWidget {
  const ActionDetailPage({super.key, required this.actionId});

  final String actionId;

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _confirm(BuildContext context, WidgetRef ref) async {
    if (!ProfileGuard.requireProfile(context, ref)) return;
    try {
      await ref.read(actionRepositoryProvider).confirmAttendance(actionId);
      ref.invalidate(attendeesProvider(actionId));
      // FR-015: a contagem da listagem reflete confirmação, desistência e
      // promoção da fila na próxima carga.
      ref.invalidate(confirmationCountsProvider);
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra confirmar presença. Tente de novo.');
    }
  }

  Future<void> _withdraw(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(actionRepositoryProvider).withdraw(actionId);
      ref.invalidate(attendeesProvider(actionId));
      // FR-015: a contagem da listagem reflete confirmação, desistência e
      // promoção da fila na próxima carga.
      ref.invalidate(confirmationCountsProvider);
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra desistir agora. Tente de novo.');
    }
  }

  Future<void> _cancel(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(actionRepositoryProvider).cancelAction(actionId);
      ref.invalidate(actionProvider(actionId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra cancelar agora. Tente de novo.');
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final actionAsync = ref.watch(actionProvider(actionId));
    final attendeesAsync = ref.watch(attendeesProvider(actionId));
    final uid = ref.watch(currentUserIdProvider);
    final myAttendances =
        attendeesAsync.value?.where((c) => c.profile.id == uid) ?? const [];
    final myAttendance = myAttendances.isEmpty ? null : myAttendances.first;

    return Scaffold(
      appBar: AppBar(title: const Text('Ação')),
      body: actionAsync.when(
        data: (action) {
          final isGroupOwner = action.groupId == null
              ? false
              : (ref.watch(groupProvider(action.groupId!)).value?.isOwner(uid) ?? false);
          final isDistrictAdmin =
              ref.watch(isDistrictAdminProvider).value ?? false;
          // FR-004/FR-005: Ação encerrada abre por link, mas não oferece mais
          // nenhum controle. FR-008: cancelada tem precedência no rótulo — é a
          // informação que explica por que ninguém foi.
          final isEnded = actionTimeStatus(
                action.dateTime,
                ref.watch(clockProvider)(),
              ) ==
              ActionTimeStatus.ended;
          final canCancel = action.canCancel(
            uid,
            isGroupOwner: isGroupOwner,
            isDistrictAdmin: isDistrictAdmin,
          );
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FR-003: quem criou a Ação, e o Administrador do distrito.
                //
                // Para quem criou, Ação cancelada ou encerrada não ganha capa
                // nova — é histórico, e a tela inteira já para de oferecer
                // controles. Para o **Administrador do distrito** a regra é
                // outra: FR-011 diz "qualquer Grupo ou Ação", e Ação encerrada
                // **mantém a capa** por FR-023. Sem esta exceção, uma imagem
                // imprópria numa Ação encerrada não teria como sair da tela.
                CoverPhotoEditor(
                  actionId: action.id,
                  // Cancelada ou encerrada é histórico: ninguém publica capa
                  // nova, nem o Administrador. Isso importa mais do que
                  // parece na cancelada — o gatilho de cancelamento só dispara
                  // na transição, então capa enviada DEPOIS não sairia por
                  // caminho nenhum.
                  canUpload: (action.creatorId == uid || isDistrictAdmin) &&
                      !action.isCancelled &&
                      !isEnded,
                  // Ação encerrada MANTÉM a capa (FR-023), e o Administrador
                  // precisa alcançá-la (FR-011).
                  canRemove: action.creatorId == uid || isDistrictAdmin,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        action.name,
                        style: Theme.of(context).textTheme.headlineMedium,
                      ),
                    ),
                    if (canCancel && !action.isCancelled && action.isConfirmed && !isEnded)
                      IconButton(
                        icon: const Icon(Icons.cancel_outlined),
                        tooltip: 'Cancelar Ação',
                        onPressed: () => _cancel(context, ref),
                      ),
                  ],
                ),
                if (!action.isCancelled && isEnded) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Encerrada',
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                ],
                if (action.isCancelled) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Cancelada',
                    style: TextStyle(color: Theme.of(context).colorScheme.error),
                  ),
                ],
                if (action.isCandidateInVoting) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Row(
                    children: [
                      const Expanded(
                        child: Text('Ação candidata — ainda em votação numa Rodada.'),
                      ),
                      TextButton(
                        onPressed: () => context.push('/rodadas/${action.votingRoundId}'),
                        child: const Text('Ver Rodada'),
                      ),
                    ],
                  ),
                ],
                const SizedBox(height: AppSpacing.md),
                Text(DateFormat('dd/MM/yyyy HH:mm').format(action.dateTime)),
                Text(action.local),
                if (action.isMissionaryPair) ...[
                  const SizedBox(height: AppSpacing.sm),
                  Text(
                    'Dupla Missionária — visita a um(a) '
                    '${action.visitedGender == VisitedGender.male ? 'homem' : 'mulher'}',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ],
                if (action.capacity != null) Text('Vagas: ${action.capacity}'),
                if (action.details != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(action.details!),
                ],
                const SizedBox(height: AppSpacing.lg),
                if (!action.isCancelled && !isEnded)
                  ElevatedButton(
                    onPressed: myAttendance != null
                        ? () => _withdraw(context, ref)
                        : () => _confirm(context, ref),
                    child: Text(
                      myAttendance == null
                          ? 'Confirmar presença'
                          : (myAttendance.status == AttendanceStatus.waitlist
                              ? 'Sair da fila de espera'
                              : 'Desistir'),
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text('Confirmados', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: attendeesAsync.when(
                    data: (attendees) {
                      final seated = attendees
                          .where((c) => c.status == AttendanceStatus.confirmed)
                          .toList();
                      final waitlist = attendees
                          .where((c) => c.status == AttendanceStatus.waitlist)
                          .toList();
                      // FR-023: lista vazia é mensagem, não lista numerada sem
                      // itens.
                      if (seated.isEmpty && waitlist.isEmpty) {
                        return const Text('Ninguém confirmou presença ainda.');
                      }
                      return ListView(
                        children: [
                          // FR-020/FR-022: numeração pelo índice renderizado,
                          // então ela é contígua depois de qualquer
                          // desistência — não há número guardado para ficar
                          // com buraco.
                          ...seated.indexed.map(
                            (e) => _AttendeeTile(
                              position: e.$1 + 1,
                              name: e.$2.profile.displayName,
                            ),
                          ),
                          if (waitlist.isNotEmpty) ...[
                            const Divider(),
                            const Text('Fila de espera'),
                            // FR-021: a fila tem numeração própria, recomeçando
                            // em 1.
                            ...waitlist.indexed.map(
                              (e) => _AttendeeTile(
                                position: e.$1 + 1,
                                name: e.$2.profile.displayName,
                                dense: true,
                              ),
                            ),
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

/// Uma pessoa na lista de Confirmados ou na fila, com a posição à frente.
///
/// A posição vai num `Semantics` com o nome junto (FR-024): sem isso, o leitor
/// de tela leria "1 ponto" e o nome como dois nós soltos, e o ponto viraria
/// pontuação sem sentido.
class _AttendeeTile extends StatelessWidget {
  const _AttendeeTile({
    required this.position,
    required this.name,
    this.dense = false,
  });

  final int position;
  final String name;
  final bool dense;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '$positionº: $name',
      excludeSemantics: true,
      child: ListTile(
        dense: dense,
        leading: Text(
          '$position.',
          style: Theme.of(context).textTheme.bodyMedium,
        ),
        title: Text(name),
      ),
    );
  }
}
