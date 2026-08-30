import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/image_report.dart';

class ImageReportRepository {
  ImageReportRepository(this._client);

  final SupabaseClient _client;

  /// Registra a denúncia. **Não exige Perfil** (FR-015).
  ///
  /// [reporterId] é decidido por quem chama, e **nunca** lido de
  /// `auth.currentUser` aqui. O motivo é um bug medido:
  ///
  /// O app faz `signInAnonymously` na inicialização
  /// (`lib/core/supabase_client.dart:21`), então **todo Visitante tem
  /// `currentUser`** — inclusive quem nunca criou Perfil. Usar esse id fazia o
  /// insert bater na FK `denuncias_imagem_denunciante_id_fkey` contra
  /// `perfis`, e a denúncia de quem não tem cadastro simplesmente não
  /// acontecia. Era o único caso que a US3 existe para atender.
  ///
  /// Ter sessão não é ter Perfil, e ser anônimo não é não ter Perfil — o app
  /// permite Perfil sem Conta desde a feature 001. O único sinal correto é
  /// `hasProfileProvider`, e ele mora na camada que chama.
  Future<void> report({
    required String photoId,
    required String reason,
    String? reporterId,
  }) async {
    await _client.from('denuncias_imagem').insert({
      'foto_id': photoId,
      'motivo': reason.trim(),
      'denunciante_id': reporterId,
    });
  }

  /// As pendências do Administrador do distrito, **agrupadas por imagem**
  /// (FR-018).
  ///
  /// O agrupamento acontece aqui, e não numa view: são poucas linhas, e uma
  /// view a mais no schema precisaria de política, grant e manutenção própria
  /// — mais peças do que o Princípio V justifica.
  ///
  /// A identidade de quem denunciou **não sai desta função**. A consulta nem
  /// pede a coluna: o que a tela não recebe, a tela não vaza (FR-020).
  Future<List<ReportedImage>> fetchPendingByImage() async {
    final rows = await _client
        .from('denuncias_imagem')
        .select('foto_id, motivo, created_at, fotos_capa!inner(caminho, grupo_id, acao_id)')
        .eq('estado', 'pendente')
        .order('created_at');

    final byPhoto = <String, List<Map<String, dynamic>>>{};
    for (final row in rows as List) {
      final map = row as Map<String, dynamic>;
      byPhoto.putIfAbsent(map['foto_id'] as String, () => []).add(map);
    }

    return [
      for (final entry in byPhoto.entries)
        ReportedImage(
          photoId: entry.key,
          reportCount: entry.value.length,
          reasons: [for (final r in entry.value) r['motivo'] as String],
          path: (entry.value.first['fotos_capa']
              as Map<String, dynamic>)['caminho'] as String,
          groupId: (entry.value.first['fotos_capa']
              as Map<String, dynamic>)['grupo_id'] as String?,
          actionId: (entry.value.first['fotos_capa']
              as Map<String, dynamic>)['acao_id'] as String?,
        ),
    ];
  }

  /// Resolve **removendo a imagem**.
  ///
  /// Apaga só a linha de `fotos_capa`; o arquivo sai pela fila. E as denúncias
  /// desta imagem somem junto, por cascade — é o encerramento automático de
  /// FR-019, e é por isso que não há um update de estado aqui: a linha da
  /// denúncia deixa de existir.
  ///
  /// Zero linhas é recusa: só quem administra o espaço da imagem a remove. A
  /// denúncia continua pendente, que é o estado verdadeiro.
  Future<void> resolveByRemovingImage(String photoId) async {
    final affected =
        await _client.from('fotos_capa').delete().eq('id', photoId).select('id');
    if (affected.isEmpty) {
      throw StateError('Essa imagem não saiu: você não administra este espaço.');
    }
  }

  /// Resolve como **improcedente**. A imagem fica; as denúncias sobre ela saem
  /// da lista de pendências.
  ///
  /// **SEM `.select()`, e é decidido, não esquecido.** O filtro carrega
  /// `.eq('estado', pendente)`, ou seja, a própria condição que a escrita vai
  /// mudar. Zero linhas quer dizer que a denúncia já saiu de pendente — outra
  /// pessoa moderando ganhou a corrida, e o resultado é o que esta chamada
  /// queria. Lançar aqui transformaria duas pessoas fazendo a coisa certa em
  /// erro na tela de uma delas.
  Future<void> dismiss(String photoId) async {
    await _client
        .from('denuncias_imagem')
        .update({
          'estado': ImageReportState.dismissed.dbValue,
          'resolvida_em': DateTime.now().toUtc().toIso8601String(),
        })
        .eq('foto_id', photoId)
        .eq('estado', ImageReportState.pending.dbValue);
  }
}
