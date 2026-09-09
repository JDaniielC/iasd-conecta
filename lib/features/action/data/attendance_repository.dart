import 'package:supabase_flutter/supabase_flutter.dart';

import '../../profile/domain/profile.dart';
import '../domain/attendance.dart';

/// Único ponto de acesso ao comparecimento.
///
/// TODA escrita daqui confere quantas linhas alcançou antes de voltar. No
/// Postgres uma policy que recusa não levanta exceção — ela faz a linha não
/// existir para aquela sessão, e o `update` volta com sucesso sobre nada
/// (`CLAUDE.md`, "Recusa de RLS é ausência, não erro"). Um método que não
/// olhasse o resultado faria a tela dizer "presença marcada" sobre nada.
///
/// A exceção é o fechamento da lista: lá a autoridade vive num gatilho, porque
/// a policy de `acoes` já aceita dono do Grupo e Administrador, e a recusa
/// chega como erro do Postgres. Os dois casos estão tratados.
class AttendanceRepository {
  const AttendanceRepository(this._client);

  final SupabaseClient _client;

  /// Marca que alguém esteve na Ação.
  ///
  /// O valor mandado é só o SINAL — o banco carimba `now()` e `auth.uid()`.
  Future<void> markAttendance({
    required String actionId,
    required String userId,
  }) async {
    final affected = await _client
        .from('confirmacoes_acao')
        .update({'compareceu_em': DateTime.now().toIso8601String()})
        .eq('acao_id', actionId)
        .eq('usuario_id', userId)
        .select('usuario_id');
    if (affected.isEmpty) {
      // Zero linhas aqui tem três causas possíveis, e a mensagem não pode
      // escolher uma: a lista já foi fechada, a Ação não é sua, ou a pessoa
      // ainda não aceitou a versão do texto legal que descreve este registro.
      // Dizer qual delas foi contaria a terceiro qual versão aquela pessoa
      // aceitou — dado do Perfil dela.
      throw StateError(
        'Não deu pra marcar a presença. A lista pode já ter sido fechada, ou '
        'a pessoa ainda precisa aceitar a versão atual da Política de '
        'Privacidade.',
      );
    }
  }

  /// Desfaz a marca. Campo nulo é ausência de sinal.
  Future<void> unmarkAttendance({
    required String actionId,
    required String userId,
  }) async {
    final affected = await _client
        .from('confirmacoes_acao')
        .update({'compareceu_em': null})
        .eq('acao_id', actionId)
        .eq('usuario_id', userId)
        .select('usuario_id');
    if (affected.isEmpty) {
      throw StateError(
        'Não deu pra desfazer a marca. A lista pode já ter sido fechada.',
      );
    }
  }

  /// Fecha a lista — o ato que transforma quem não foi marcado em ausente.
  Future<void> closeList(String actionId) async {
    try {
      final affected = await _client
          .from('acoes')
          .update({'presenca_fechada_em': DateTime.now().toIso8601String()})
          .eq('id', actionId)
          .select('id');
      if (affected.isEmpty) {
        throw StateError('Não deu pra fechar a lista. Tente de novo.');
      }
    } on PostgrestException catch (error) {
      // O gatilho recusa com mensagem própria, escrita para ser lida: "só quem
      // criou a Ação fecha a lista de presença dela", "a lista de presença só
      // fecha depois de a Ação acontecer". Repassar é melhor do que substituir
      // por um texto genérico.
      throw StateError(error.message);
    }
  }

  Future<AttendanceList> fetchAttendanceList(String actionId) async {
    final action = await _client
        .from('acoes')
        .select('presenca_fechada_em, presentes_no_fechamento')
        .eq('id', actionId)
        .maybeSingle();

    final rows = await _client
        .from('confirmacoes_acao')
        .select('usuario_id, compareceu_em, contestada_em')
        .eq('acao_id', actionId)
        .order('created_at');

    final marks = await Future.wait(rows.map((row) async {
      final profile = await _fetchPublicProfile(row['usuario_id'] as String);
      return AttendanceMark(
        profile: profile,
        attendedAt: _parseDate(row['compareceu_em']),
        disputed: row['contestada_em'] != null,
      );
    }));

    return AttendanceList(
      marks: marks,
      closedAt: _parseDate(action?['presenca_fechada_em']),
      presentAtClosing: action?['presentes_no_fechamento'] as int?,
    );
  }

  /// O que afirmaram sobre mim.
  ///
  /// Só linhas com marca: uma confirmação sem comparecimento não é uma
  /// afirmação de ninguém sobre ninguém, e listá-la sugeriria que é.
  Future<List<MyAttendanceRecord>> fetchMyAttendance() async {
    final uid = _client.auth.currentUser?.id;
    if (uid == null) return const [];

    final rows = await _client
        .from('confirmacoes_acao')
        .select('acao_id, compareceu_em, marcado_por, acoes(nome, data_hora)')
        .eq('usuario_id', uid)
        .not('compareceu_em', 'is', null);

    return Future.wait(rows.map((row) async {
      // `acoes` VEM NULO, e não é caso de borda — é o caso que a change existe
      // para cobrir. Achado C-2 da convergência 1, medido em 2026-09-09: para
      // quem saiu do Grupo de uma Ação restrita, a confirmação própria continua
      // legível (o braço `auth.uid() = usuario_id` na policy) e a Ação some
      // (`acoes_select_visivel`). Contado no banco: confirmações visíveis 1,
      // ações visíveis 0.
      //
      // Um `as Map<String, dynamic>` sobre nulo derrubava "Meu Perfil"
      // exatamente para a pessoa que a change alargou a policy para proteger. A
      // correção NÃO é alargar a leitura da Ação — há teste de contraprova
      // exigindo que ela continue invisível. É a linha sobreviver sem o nome,
      // dizendo o que sabe.
      final action = row['acoes'] as Map<String, dynamic>?;
      final markedBy = row['marcado_por'] as String?;
      final markerName = markedBy == null
          ? 'quem organizou'
          : (await _fetchPublicProfile(markedBy)).displayName;
      return MyAttendanceRecord(
        actionId: row['acao_id'] as String,
        actionName: action?['nome'] as String? ?? 'Ação que você não vê mais',
        actionDate: _parseDate(action?['data_hora']),
        attendedAt: _parseDate(row['compareceu_em'])!,
        markedByName: markerName,
        dispute: await _fetchDispute(row['acao_id'] as String, uid),
      );
    }));
  }

  Future<AttendanceDispute?> _fetchDispute(String actionId, String uid) async {
    final row = await _client
        .from('contestacoes_presenca')
        .select('contestada_em, decisao')
        .eq('acao_id', actionId)
        .eq('usuario_id', uid)
        .maybeSingle();
    if (row == null) return null;
    return AttendanceDispute(
      disputedAt: _parseDate(row['contestada_em'])!,
      decision: row['decisao'] as String?,
    );
  }

  /// Contesta a marca feita sobre mim.
  ///
  /// Recusa de `insert` no Postgres levanta exceção — não afeta zero linhas —,
  /// então aqui não há contagem a conferir.
  Future<void> disputeAttendance(String actionId) async {
    final uid = _client.auth.currentUser!.id;
    try {
      await _client.from('contestacoes_presenca').insert({
        'acao_id': actionId,
        'usuario_id': uid,
      });
    } on PostgrestException catch (_) {
      throw StateError(
        'Não deu pra registrar sua contestação. Talvez já exista uma.',
      );
    }
  }

  Future<List<PendingDispute>> fetchPendingDisputes(String actionId) async {
    final rows = await _client
        .from('contestacoes_presenca')
        .select('acao_id, usuario_id, contestada_em')
        .eq('acao_id', actionId)
        .isFilter('decisao', null);

    return Future.wait(rows.map((row) async {
      return PendingDispute(
        actionId: row['acao_id'] as String,
        profile: await _fetchPublicProfile(row['usuario_id'] as String),
        disputedAt: _parseDate(row['contestada_em'])!,
      );
    }));
  }

  /// Decide a contestação. `mantida` ou `desfeita`.
  ///
  /// Qualquer das duas tira a linha da contagem para sempre — a decisão diz
  /// se a marca continua afirmando comparecimento, não se ela volta a contar.
  Future<void> decideDispute({
    required String actionId,
    required String userId,
    required String decision,
  }) async {
    final affected = await _client
        .from('contestacoes_presenca')
        .update({'decisao': decision})
        .eq('acao_id', actionId)
        .eq('usuario_id', userId)
        .select('usuario_id');
    if (affected.isEmpty) {
      throw StateError(
        'Não deu pra registrar sua decisão. Ela pode já ter sido tomada.',
      );
    }
  }

  Future<PublicProfile> _fetchPublicProfile(String id) async {
    final rows = await _client.rpc('perfil_publico', params: {'p_id': id});
    final row = (rows as List).single as Map<String, dynamic>;
    return PublicProfile.fromMap(row);
  }

  DateTime? _parseDate(Object? value) =>
      value == null ? null : DateTime.parse(value as String);
}
