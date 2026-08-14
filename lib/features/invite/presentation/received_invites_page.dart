import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';

import '../../../core/providers.dart';
import '../../../core/theme/app_theme.dart';
import '../../group/group_providers.dart';
import '../domain/action_invite.dart';
import '../invite_providers.dart';
import '../../notification/presentation/notification_badge.dart';

/// Convites recebidos (change `convite-para-acao`).
///
/// Esta change não tem notificação — sem push e sem e-mail, o convite aparece
/// quando a pessoa abre esta tela. É decisão registrada no design: construir
/// notificação aqui traria consentimento, opt-out e retenção junto.
class ReceivedInvitesPage extends ConsumerStatefulWidget {
  const ReceivedInvitesPage({super.key});

  @override
  ConsumerState<ReceivedInvitesPage> createState() =>
      _ReceivedInvitesPageState();
}

class _ReceivedInvitesPageState extends ConsumerState<ReceivedInvitesPage> {
  String? _grupoFiltrado;

  Future<void> _recusar(ReceivedInvite convite) async {
    try {
      await ref
          .read(inviteRepositoryProvider)
          .decline(convite.invite.actionId, convite.invite.groupId);
      ref.invalidate(receivedInvitesProvider);
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Não deu pra recusar agora. Tente de novo.')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final convitesAsync = ref.watch(receivedInvitesProvider);
    final meusGrupos = ref.watch(myGroupIdsProvider).value ?? const <String>{};
    final agora = ref.watch(clockProvider)();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Convites'),
        // Change `notificacoes-in-app`. O app não tem barra global, então o
        // indicador entra nas telas onde a pessoa LÊ — nunca nos
        // formulários, onde ele seria distração no meio de um fluxo.
        actions: const [NotificationBadge()],
      ),
      body: convitesAsync.when(
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (_, _) =>
            const Center(child: Text('Não deu pra carregar seus convites.')),
        data: (todos) {
          final abertos = todos.where((c) => c.isOpen(agora)).toList();
          if (abertos.isEmpty) return const _SemConvites();

          // As opções de filtro são os Grupos presentes nos convites
          // INTERSECCIONADOS com os Grupos de que a pessoa participa hoje. Por
          // isso o convite de um Grupo que ela deixou continua na lista sem
          // filtro, mas some das opções — o convite já foi entregue, e retirá-lo
          // em silêncio confundiria mais do que ajudaria.
          final opcoes = <String, String>{
            for (final c in abertos)
              if (meusGrupos.contains(c.invite.groupId))
                c.invite.groupId: c.groupName,
          };
          final filtrados = _grupoFiltrado == null
              ? abertos
              : abertos
                  .where((c) => c.invite.groupId == _grupoFiltrado)
                  .toList();

          return ListView(
            padding: const EdgeInsets.all(AppSpacing.md),
            children: [
              if (opcoes.isNotEmpty) ...[
                Wrap(
                  spacing: AppSpacing.sm,
                  children: [
                    for (final e in opcoes.entries)
                      FilterChip(
                        label: Text(e.value),
                        selected: _grupoFiltrado == e.key,
                        onSelected: (sel) => setState(
                            () => _grupoFiltrado = sel ? e.key : null),
                      ),
                  ],
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              Text(
                '${filtrados.length} convite(s) em aberto',
                style: Theme.of(context).textTheme.bodySmall,
              ),
              const SizedBox(height: AppSpacing.sm),
              for (final c in filtrados) _CartaoConvite(convite: c, aoRecusar: _recusar),
            ],
          );
        },
      ),
    );
  }
}

class _CartaoConvite extends StatelessWidget {
  const _CartaoConvite({required this.convite, required this.aoRecusar});

  final ReceivedInvite convite;
  final Future<void> Function(ReceivedInvite) aoRecusar;

  @override
  Widget build(BuildContext context) {
    // `isOpen` já garantiu que a Ação existe e é legível; a lista só chega aqui
    // com convite vivo.
    final acao = convite.action!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(acao.name, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: AppSpacing.xs),
            Text(
              '${DateFormat('dd/MM/yyyy HH:mm').format(acao.dateTime)} · ${acao.local}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            Text(
              'pelo Grupo ${convite.groupName}',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: AppSpacing.sm),
            Wrap(
              spacing: AppSpacing.sm,
              children: [
                FilledButton(
                  onPressed: () => context.push('/acoes/${acao.id}'),
                  child: const Text('Ver Ação'),
                ),
                TextButton(
                  onPressed: () => aoRecusar(convite),
                  child: const Text('Recusar'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _SemConvites extends StatelessWidget {
  const _SemConvites();

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: Padding(
        padding: EdgeInsets.all(AppSpacing.lg),
        child: Text(
          'Nenhum convite em aberto.\n\n'
          'Convites chegam de pessoas dos seus Grupos.',
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}
