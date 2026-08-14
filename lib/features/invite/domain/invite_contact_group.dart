import 'invite_contact.dart';

/// Uma seção da tela de convidar: um Grupo e as pessoas dele.
///
/// A lista chega já agrupada do banco, numa chamada só. O Grupo é o contexto do
/// convite — é ele que vai junto na linha e que aparece para quem recebe como
/// explicação de origem.
class InviteContactGroup {
  const InviteContactGroup({
    required this.groupId,
    required this.groupName,
    required this.contacts,
  });

  final String groupId;
  final String groupName;
  final List<InviteContact> contacts;

  /// Quantas pessoas ainda dá para convidar por este Grupo.
  int get invitableCount => contacts.where((c) => !c.alreadyInvited).length;
}
