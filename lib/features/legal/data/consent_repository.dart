import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/consent_status.dart';
import '../domain/consent_tally.dart';

/// Único ponto de acesso à contagem de consentimentos por versão.
///
/// Vai por RPC, nunca por `select` direto em `perfis`: a política
/// `perfis_select_own` restringe a leitura à própria linha, e a agregação
/// precisa enxergar todas — mas sem devolver nenhuma. Mesmo padrão de
/// `ProfileRepository.fetchPublicProfile`.
class ConsentRepository {
  const ConsentRepository(this._client);

  final SupabaseClient _client;

  Future<List<ConsentTally>> fetchConsentTally() async {
    final rows = await _client.rpc('consentimentos_por_versao');
    return (rows as List)
        .map((row) => ConsentTally.fromMap(row as Map<String, dynamic>))
        .toList();
  }

  /// Compara a versão que a pessoa aceitou com a vigente.
  ///
  /// Devolve `null` para quem não tem Perfil — Visitante não tem aceite a
  /// comparar, e um aviso de "seus termos mudaram" para quem nunca aceitou
  /// nada seria falso.
  ///
  /// A versão vigente vem do BANCO, nunca de `LegalMetadata.version`: a
  /// constante é o que a tela exibe, e comparar a constante consigo mesma
  /// nunca acusaria uma divergência entre binário e catálogo.
  Future<ConsentStatus?> fetchMyConsentStatus() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return null;

    final row = await _client
        .from('perfis')
        .select('consentimento_lgpd_versao')
        .eq('id', uid)
        .maybeSingle();
    if (row == null) return null;

    final current = await _client.rpc('versao_texto_legal_vigente');

    return ConsentStatus.resolve(
      acceptedVersion: row['consentimento_lgpd_versao'] as String?,
      currentVersion: current as String,
    );
  }

  /// Reaceita o texto vigente.
  ///
  /// O cliente manda o SINAL; o gatilho `perfis_carimbar_consentimento` carimba
  /// `now()` e `versao_texto_legal_vigente()`. Valor de versão mandado daqui
  /// seria descartado pelo banco — e é por isso que esta função não manda um.
  ///
  /// Zero linhas afetadas não é sucesso silencioso: a policy deixa qualquer
  /// pessoa escrever na própria linha, então zero significa que a linha não
  /// existe, e a tela não pode dizer que atualizou o aceite sobre nada
  /// (`CLAUDE.md`, "Recusa de RLS é ausência, não erro").
  Future<void> acceptCurrentVersion() async {
    final uid = _client.auth.currentUser!.id;
    final affected = await _client
        .from('perfis')
        .update({
          'consentimento_lgpd_aceito_em': DateTime.now().toIso8601String(),
        })
        .eq('id', uid)
        .select('id');
    if (affected.isEmpty) {
      throw StateError(
        'Não deu pra registrar seu aceite agora. Verifique sua conexão e '
        'tente de novo.',
      );
    }
  }
}
