import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/providers.dart';
import 'data/invite_repository.dart';
import 'domain/action_invite.dart';
import 'domain/invite_contact_group.dart';

final inviteRepositoryProvider = Provider<InviteRepository>((ref) {
  return InviteRepository(ref.watch(supabaseClientProvider));
});

/// Contatos convidáveis para uma Ação. `autoDispose` porque a lista muda com o
/// que já foi convidado, e reabrir a tela precisa refletir isso.
final inviteContactsProvider =
    FutureProvider.autoDispose.family<List<InviteContactGroup>, String>(
  (ref, actionId) =>
      ref.watch(inviteRepositoryProvider).fetchContacts(actionId),
);

final receivedInvitesProvider =
    FutureProvider.autoDispose<List<ReceivedInvite>>(
  (ref) => ref.watch(inviteRepositoryProvider).fetchReceivedInvites(),
);

/// Quantos convites estão em aberto agora — o contador da tela inicial.
///
/// Mitigação registrada no design para esta change não ter notificação: sem
/// push e sem e-mail, o convite só aparece quando a pessoa abre a tela, e o
/// contador é o que reduz o problema sem construir infraestrutura.
final openInvitesCountProvider = FutureProvider.autoDispose<int>((ref) async {
  final convites = await ref.watch(receivedInvitesProvider.future);
  final agora = ref.watch(clockProvider)();
  return convites.where((c) => c.isOpen(agora)).length;
});
