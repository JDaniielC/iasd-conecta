import 'package:supabase_flutter/supabase_flutter.dart';

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
}
