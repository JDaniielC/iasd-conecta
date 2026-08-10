/// Gênero do Perfil. O valor gravado no banco continua em português
/// (`masculino`/`feminino`), porque schema e strings de UI são português por
/// decisão da constituição — só o identificador Dart é que é inglês.
enum Gender {
  male('masculino'),
  female('feminino');

  const Gender(this.dbValue);

  final String dbValue;
}

const _ageOfMajority = 18;

/// Dados de um Perfil ainda não enviado ao banco (formulário de cadastro).
///
/// A invariante "menor de idade precisa de Apelido" (FR-005) é espelhada aqui
/// só para feedback imediato na UI — quem garante de verdade é a constraint
/// `apelido_obrigatorio_menor` no banco (ver contracts/schema.sql).
class Profile {
  const Profile({
    required this.name,
    required this.gender,
    required this.age,
    required this.lgpdConsentAccepted,
    this.nickname,
    this.churchId,
    this.phone,
    this.churchLgpdConsentAccepted = false,
  });

  final String name;
  final Gender gender;
  final int age;
  final bool lgpdConsentAccepted;
  final String? nickname;
  final String? churchId;
  final String? phone;

  /// Consentimento destacado e recusável independentemente pro uso de
  /// "Igreja de origem" (dado sensível, LGPD art. 11 I) — só é exigido
  /// quando uma Igreja é escolhida (ver `consentimento_igreja_destacado`
  /// no banco).
  final bool churchLgpdConsentAccepted;

  bool get isMinor => age < _ageOfMajority;

  bool get needsNickname => isMinor && (nickname == null || nickname!.trim().isEmpty);

  bool get needsChurchConsent => churchId != null && churchId!.trim().isNotEmpty;

  /// Verdadeiro só quando o formulário está pronto para ser enviado —
  /// consentimento aceito, nome preenchido, Apelido presente se for menor,
  /// e consentimento destacado de Igreja presente se uma foi escolhida.
  bool get readyToSubmit =>
      lgpdConsentAccepted &&
      name.trim().isNotEmpty &&
      !needsNickname &&
      (!needsChurchConsent || churchLgpdConsentAccepted);

  /// As duas datas de consentimento aqui são **sinal**, não valor.
  ///
  /// O que o cliente legitimamente sabe é SE a caixa foi marcada. O instante e
  /// a versão do texto aceito são gravados pelo gatilho
  /// `perfis_carimbar_consentimento` (feature 017), a partir de
  /// `public.versao_texto_legal_vigente()` — para que os dois saiam do mesmo
  /// relógio e para que o registro não valha o que o cliente disser.
  ///
  /// Por isso **não há chave de versão neste mapa, e não deve haver**: mandar a
  /// versão é exatamente o que FR-004 proíbe. A ausência é a feature, não um
  /// esquecimento a ser "consertado" numa refatoração.
  Map<String, dynamic> toInsertMap({required String id}) {
    return {
      'id': id,
      'nome': name.trim(),
      'apelido': nickname?.trim().isEmpty ?? true ? null : nickname!.trim(),
      'igreja_id': churchId,
      'telefone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'genero': gender.dbValue,
      'idade': age,
      'consentimento_lgpd_aceito_em': DateTime.now().toUtc().toIso8601String(),
      'consentimento_lgpd_igreja_aceito_em':
          needsChurchConsent ? DateTime.now().toUtc().toIso8601String() : null,
    };
  }
}

/// Projeção pública de um Perfil (via RPC `perfil_publico`) — nunca contém
/// idade nem telefone (FR-004).
class PublicProfile {
  const PublicProfile({
    required this.id,
    required this.displayName,
    this.churchId,
  });

  final String id;
  final String displayName;
  final String? churchId;

  factory PublicProfile.fromMap(Map<String, dynamic> map) {
    return PublicProfile(
      id: map['id'] as String,
      displayName: map['nome_exibido'] as String,
      churchId: map['igreja_id'] as String?,
    );
  }
}
