/// Uma pessoa convidável, dentro da seção de um Grupo.
///
/// `alreadyInvited` é por (pessoa, Grupo), não por pessoa: convidada pelo Grupo
/// Jovens, ela continua convidável pelo Grupo Música, porque são dois convites
/// distintos e é por esse campo que ela vai filtrar do outro lado.
class InviteContact {
  const InviteContact({
    required this.userId,
    required this.displayName,
    required this.alreadyInvited,
    required this.alreadyConfirmed,
  });

  final String userId;

  /// Vem de `coalesce(apelido, nome)` no banco — a mesma expressão de
  /// `perfil_publico`, que é a que protege menor de idade. Nunca montar este
  /// nome no cliente a partir de outra fonte.
  final String displayName;
  final bool alreadyInvited;

  /// Se a pessoa já confirmou presença nesta Ação. É o que fecha o
  /// acompanhamento de quem convidou: "já convidado" sozinho não distingue
  /// convite sem resposta de convite atendido.
  final bool alreadyConfirmed;
}
