import 'package:supabase_flutter/supabase_flutter.dart';

import '../domain/app_notification.dart';

/// Único ponto de acesso a `notificacoes`.
///
/// Lê **sempre** de `notificacoes_ativas`, nunca da tabela crua. Não é
/// preferência: o contador e a lista precisam bater, e é requisito. Duas
/// consultas com o mesmo `where` escrito duas vezes divergem na primeira
/// mudança; uma view não.
class NotificationRepository {
  NotificationRepository(this._client);

  final SupabaseClient _client;

  static const _view = 'notificacoes_ativas';

  /// Quantos avisos a lista traz. Teto explícito porque esta é a tabela que
  /// **vai** crescer — o expurgo só alcança o que já foi lido, então quem nunca
  /// abre a tela acumula não lidas indefinidamente.
  static const pageSize = 50;

  /// A lista, com nome de quem provocou, nome da Ação e nome do Grupo.
  ///
  /// `acao_nome` vem da própria view, que já junta `acoes` — pedir um embed
  /// `acoes(nome)` faria o PostgREST juntar a tabela de novo e reavaliar a
  /// policy dela mais uma vez.
  ///
  /// Os nomes das pessoas saem de `perfil_publico`, uma chamada por ATOR
  /// DISTINTO e não por linha, e as chamadas vão **concorrentes**: em série,
  /// cada uma esperava a anterior, e a latência somava em rede de celular.
  /// Nunca de um `select` direto em `perfis`: é `perfil_publico` que devolve o
  /// Apelido no lugar do nome quando a pessoa é menor de idade.
  Future<List<AppNotification>> fetch() async {
    final rows = await _client
        .from(_view)
        .select('*, grupos(nome)')
        .order('created_at', ascending: false)
        .limit(pageSize);

    final actors = rows
        .map((r) => r['ator_id'] as String?)
        .whereType<String>()
        .toSet()
        .toList();
    final resolved = await Future.wait(
      actors.map((uid) async {
        final r =
            await _client.rpc('perfil_publico', params: {'p_id': uid}) as List;
        return r.isEmpty
            ? null
            : MapEntry(
                uid, (r.first as Map<String, dynamic>)['nome_exibido'] as String);
      }),
    );
    final names = Map.fromEntries(resolved.whereType<MapEntry<String, String>>());

    return [
      for (final row in rows)
        ?AppNotification.fromMap(
          row,
          actorName: names[row['ator_id'] as String?],
          groupName: (row['grupos'] as Map<String, dynamic>?)?['nome'] as String?,
        ),
    ];
  }

  /// Quantas não lidas — pela MESMA view da lista.
  ///
  /// `count` e não `rows.length`: quem conta é o Postgres, e o número volta no
  /// cabeçalho sem trafegar linha nenhuma. Isto roda na abertura de oito telas,
  /// e antes trazia um uuid por aviso não lido só para produzir um inteiro.
  Future<int> unreadCount() async {
    return _client
        .from(_view)
        .count(CountOption.exact)
        .isFilter('lida_em', null);
  }

  /// Marca as informadas como lidas, num `update` só.
  ///
  /// Sem RPC: a policy garante que só as próprias mudam, e o `grant` de coluna
  /// garante que só `lida_em` muda. As duas barreiras juntas tornam a chamada
  /// direta segura.
  /// O valor enviado é apenas um marcador de "não nulo": um gatilho `before
  /// update` o substitui por `now()` do servidor. É o que impede o relógio do
  /// aparelho de decidir quando a retenção de 90 dias apaga a linha.
  Future<void> markRead(List<String> ids) async {
    if (ids.isEmpty) return;
    await _client
        .from('notificacoes')
        .update({'lida_em': DateTime.now().toUtc().toIso8601String()})
        .inFilter('id', ids)
        .isFilter('lida_em', null);
  }
}
