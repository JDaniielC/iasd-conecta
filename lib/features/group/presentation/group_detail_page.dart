import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../cover_photo/presentation/cover_photo_widget.dart';
import '../../leadership/leadership_providers.dart';
import '../../profile/domain/profile_guard.dart';
import '../../district_admin/district_admin_providers.dart';
import '../../change_log/presentation/change_log_section.dart';
import '../group_providers.dart';
import 'archive_group_sheet.dart';
import '../../chat/chat_providers.dart';
import '../../notification/presentation/notification_badge.dart';

/// Detalhes de um Grupo: visível a Visitante e Usuário igualmente
/// (FR-005). Participar/sair exige Perfil (FR-006/FR-007/FR-008/FR-009).
class GroupDetailPage extends ConsumerWidget {
  const GroupDetailPage({super.key, required this.groupId});

  final String groupId;

  void _showError(BuildContext context, String message) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }

  Future<void> _join(BuildContext context, WidgetRef ref) async {
    if (!ProfileGuard.requireProfile(context, ref)) return;
    try {
      await ref.read(groupRepositoryProvider).join(groupId);
      ref.invalidate(membersProvider(groupId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(context, 'Não deu pra participar agora. Tente de novo.');
    }
  }

  Future<void> _leave(BuildContext context, WidgetRef ref) async {
    try {
      await ref.read(groupRepositoryProvider).leave(groupId);
      ref.invalidate(membersProvider(groupId));
    } catch (_) {
      if (!context.mounted) return;
      _showError(
        context,
        'Não deu pra sair do Grupo. Se você é o Dono, transfira a posse antes.',
      );
    }
  }

  Future<void> _archive(BuildContext context, WidgetRef ref) async {
    final archived = await showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      builder: (_) => ArchiveGroupSheet(groupId: groupId),
    );
    if (archived != true || !context.mounted) return;
    ref.invalidate(groupProvider(groupId));
    ref.invalidate(groupsProvider);
    context.go('/grupos');
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final groupAsync = ref.watch(groupProvider(groupId));
    final membersAsync = ref.watch(membersProvider(groupId));
    final uid = ref.watch(currentUserIdProvider);
    final isParticipant = membersAsync.value?.any((p) => p.id == uid) ?? false;

    return Scaffold(
      appBar: AppBar(
        title: const Text('Grupo/Ministério'),
        // Change `notificacoes-in-app`. O app não tem barra global, então o
        // indicador entra nas telas onde a pessoa LÊ — nunca nos
        // formulários, onde ele seria distração no meio de um fluxo.
        actions: const [NotificationBadge()],
      ),
      body: groupAsync.when(
        data: (group) {
          final isOwner = group.isOwner(uid);
          final isDistrictAdmin =
              ref.watch(isDistrictAdminProvider).value ?? false;
          return Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // FR-002/FR-003: a capa e, só para quem administra, as ações
                // de enviar/trocar/remover.
                //
                // Grupo arquivado é histórico e o Dono não mexe mais nele
                // (feature 014). Mas o Administrador do distrito **continua
                // podendo remover** — FR-011 diz "de qualquer Grupo ou Ação",
                // e uma imagem imprópria num Grupo arquivado continua
                // pública. Fechar isso deixaria a única saída ser a lista de
                // denúncias, e só se alguém denunciasse.
                CoverPhotoEditor(
                  groupId: groupId,
                  // Grupo arquivado é histórico: ninguém publica capa nova
                  // nele, nem o Administrador. Mas remover continua valendo
                  // para o Administrador — imagem imprópria num Grupo
                  // arquivado continua pública (FR-011).
                  canUpload: (isOwner || isDistrictAdmin) && !group.isArchived,
                  canRemove: isOwner || isDistrictAdmin,
                ),
                Row(
                  children: [
                    Expanded(
                      child: Text(group.name, style: Theme.of(context).textTheme.headlineMedium),
                    ),
                    // Change `chat-de-grupo-e-acao`. FORA do
                    // `if (!group.isArchived)` de propósito: Grupo arquivado
                    // mantém o histórico legível — é justamente o que sobra
                    // dele — e a tela da conversa é quem esconde o campo de
                    // envio. Esconder a entrada aqui trancaria o histórico
                    // junto com a escrita.
                    if (ref
                            .watch(canSeeChatProvider(ChatSpace.group(groupId)))
                            .value ??
                        false)
                      IconButton(
                        icon: const Icon(Icons.forum_outlined),
                        tooltip: 'Conversa',
                        onPressed: () =>
                            context.push('/grupos/$groupId/conversa'),
                      ),
                    if (!group.isArchived) ...[
                      IconButton(
                        icon: const Icon(Icons.how_to_vote_outlined),
                        tooltip: 'Rodadas de Votação',
                        onPressed: () =>
                            context.push('/grupos/$groupId/rodadas'),
                      ),
                      IconButton(
                        icon: const Icon(Icons.badge_outlined),
                        tooltip: 'Líder/Diretor de Ministério',
                        onPressed: () => context
                            .push('/grupos/$groupId/leadership/declare'),
                      ),
                    ],
                    if (isOwner && !group.isArchived)
                      IconButton(
                        icon: const Icon(Icons.edit_outlined),
                        onPressed: () => context.push('/grupos/$groupId/editar'),
                      ),
                    // FR-001/FR-002: Dono do Grupo ou Administrador do
                    // distrito, e mais ninguém. Grupo já arquivado não oferece
                    // a opção de novo (FR-009). Quem garante é a função no
                    // banco; isto aqui é só não oferecer o que seria recusado.
                    if ((isOwner || isDistrictAdmin) && !group.isArchived)
                      IconButton(
                        icon: const Icon(Icons.archive_outlined),
                        tooltip: 'Arquivar Grupo/Ministério',
                        onPressed: () => _archive(context, ref),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
                if (group.isArchived) ...[
                  // FR-013: alcançado por link direto, ele se apresenta como
                  // arquivado — não como erro. Quem chegou aqui por um link
                  // antigo merece saber o que aconteceu.
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.md),
                    decoration: BoxDecoration(
                      border: Border.all(
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      'Este Grupo/Ministério foi arquivado. Ele não aceita '
                      'novos participantes, Ações nem Rodadas de votação. '
                      'O que já aconteceu continua registrado.',
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                ],
                Text(group.category),
                if (group.schedule != null || group.location != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  if (group.schedule != null) Text('Horário: ${group.schedule}'),
                  if (group.location != null) Text('Local: ${group.location}'),
                ],
                if (group.details != null) ...[
                  const SizedBox(height: AppSpacing.md),
                  Text(group.details!),
                ],
                const SizedBox(height: AppSpacing.md),
                _LeadersSection(groupId: groupId),
                const SizedBox(height: AppSpacing.lg),
                if (!group.isArchived)
                  ElevatedButton(
                    onPressed: isParticipant
                        ? () => _leave(context, ref)
                        : () => _join(context, ref),
                    child: Text(
                      isParticipant ? 'Sair do Grupo/Ministério' : 'Participar',
                    ),
                  ),
                const SizedBox(height: AppSpacing.lg),
                Text('Participantes', style: Theme.of(context).textTheme.titleLarge),
                Expanded(
                  child: membersAsync.when(
                    // A seção de mudanças rola JUNTO com os participantes, no
                    // rodapé da mesma lista. Fora do `Expanded` ela não teria
                    // espaço; numa fatia fixa acima, comeria a altura da lista
                    // de participantes num celular.
                    data: (members) => ListView(
                      children: [
                        ...members.map((p) => ListTile(title: Text(p.displayName))),
                        const SizedBox(height: AppSpacing.lg),
                        ChangeLogSection.forGroup(groupId: groupId),
                      ],
                    ),
                    loading: () => const Center(child: CircularProgressIndicator()),
                    error: (_, _) => const Text('Não deu pra carregar os participantes.'),
                  ),
                ),
              ],
            ),
          );
        },
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) => const Center(child: Text('Grupo não encontrado.')),
      ),
    );
  }
}

/// FR-006/FR-007: identificação pública do(s) Líder(es)/Diretor(es)
/// confirmado(s) do ano corrente — visível até pra Visitante sem cadastro.
/// Sem confirmado nenhum, a seção não aparece (Grupo comum, não Ministério).
class _LeadersSection extends ConsumerWidget {
  const _LeadersSection({required this.groupId});

  final String groupId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final leadersAsync = ref.watch(currentLeadersProvider(groupId));
    final leaders = leadersAsync.value ?? const [];
    if (leaders.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Líder/Diretor', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(height: AppSpacing.sm),
        ...leaders.map((leader) => _LeaderName(userId: leader.userId)),
      ],
    );
  }
}

class _LeaderName extends ConsumerWidget {
  const _LeaderName({required this.userId});

  final String userId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final profileAsync = ref.watch(publicProfileProvider(userId));
    return Text(profileAsync.value?.displayName ?? '...');
  }
}
