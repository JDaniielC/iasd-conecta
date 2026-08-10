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
    this.lgpdConsentAcceptedAt,
    this.churchLgpdConsentAcceptedAt,
  });

  final String name;

  /// Anuláveis porque o schema os nulificou na feature 009: o Perfil
  /// anonimizado de quem excluiu a conta tem `genero` e `idade` nulos. Ler um
  /// Perfil do banco precisa dar conta disso.
  final Gender? gender;
  final int? age;

  final bool lgpdConsentAccepted;
  final String? nickname;
  final String? churchId;
  final String? phone;

  /// Quando o consentimento foi dado. Só de leitura — quem grava é o gatilho
  /// `perfis_carimbar_consentimento` (feature 017). Existe aqui porque FR-002
  /// manda exibir a data a quem é dono dela.
  final DateTime? lgpdConsentAcceptedAt;
  final DateTime? churchLgpdConsentAcceptedAt;

  /// Consentimento destacado e recusável independentemente pro uso de
  /// "Igreja de origem" (dado sensível, LGPD art. 11 I) — só é exigido
  /// quando uma Igreja é escolhida (ver `consentimento_igreja_destacado`
  /// no banco).
  final bool churchLgpdConsentAccepted;

  bool get isMinor => age != null && age! < _ageOfMajority;

  bool get needsNickname => isMinor && (nickname == null || nickname!.trim().isEmpty);

  bool get needsChurchConsent => churchId != null && churchId!.trim().isNotEmpty;

  /// Verdadeiro só quando o formulário está pronto para ser enviado —
  /// consentimento aceito, nome preenchido, Apelido presente se for menor,
  /// e consentimento destacado de Igreja presente se uma foi escolhida.
  bool get readyToSubmit =>
      lgpdConsentAccepted &&
      name.trim().isNotEmpty &&
      age != null &&
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
      'genero': gender?.dbValue,
      'idade': age,
      'consentimento_lgpd_aceito_em': DateTime.now().toUtc().toIso8601String(),
      'consentimento_lgpd_igreja_aceito_em':
          needsChurchConsent ? DateTime.now().toUtc().toIso8601String() : null,
    };
  }

  /// Lê um Perfil do banco. As chaves são as colunas, em português.
  factory Profile.fromMap(Map<String, dynamic> map) {
    final churchConsentAt = map['consentimento_lgpd_igreja_aceito_em'];
    final genderValue = map['genero'] as String?;
    return Profile(
      name: map['nome'] as String,
      // `genero` e `idade` são anuláveis desde a feature 009 (Perfil
      // anonimizado). Ler sem cuidado aqui estouraria justamente na linha de
      // quem já pediu para sumir.
      gender: genderValue == null
          ? null
          : Gender.values.firstWhere((g) => g.dbValue == genderValue),
      age: map['idade'] as int?,
      // A coluna é `not null`: linha que existe é linha que consentiu.
      lgpdConsentAccepted: true,
      nickname: map['apelido'] as String?,
      churchId: map['igreja_id'] as String?,
      phone: map['telefone'] as String?,
      churchLgpdConsentAccepted: churchConsentAt != null,
      lgpdConsentAcceptedAt:
          DateTime.parse(map['consentimento_lgpd_aceito_em'] as String),
      churchLgpdConsentAcceptedAt: churchConsentAt == null
          ? null
          : DateTime.parse(churchConsentAt as String),
    );
  }

  /// As **cinco** colunas que a pessoa pode corrigir sozinha, e nenhuma outra.
  ///
  /// Deliberadamente NÃO é `toInsertMap`. Reusar aquele mapa num `UPDATE`
  /// reescreveria `consentimento_lgpd_aceito_em` a cada correção de telefone —
  /// a data da base legal viraria "a última vez que mexi no cadastro", que é
  /// perder o registro que a feature 017 acabou de criar. `idade` e `genero`
  /// ficam de fora porque decidem regra de domínio (Apelido obrigatório e
  /// composição de Dupla Missionária) e não são editáveis nesta feature.
  Map<String, dynamic> toUpdateMap() {
    return {
      'nome': name.trim(),
      'apelido': nickname?.trim().isEmpty ?? true ? null : nickname!.trim(),
      'igreja_id': churchId,
      'telefone': phone?.trim().isEmpty ?? true ? null : phone!.trim(),
      'consentimento_lgpd_igreja_aceito_em':
          churchLgpdConsentAcceptedAt?.toUtc().toIso8601String(),
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
