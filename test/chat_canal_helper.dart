import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Dublê do servidor de tempo real, compartilhado pelos testes da change
/// `chat-de-grupo-e-acao`.
///
/// Existe para PROVOCAR a queda do canal. Num teste contra o Supabase de
/// verdade, derrubar o socket na hora certa é temporização, e temporização em
/// teste vira `retry` — que a change `estabilizar-suite-de-integracao` proíbe,
/// com razão.
///
/// Mora na raiz de `test/` porque `unit/` e `widget/` usam os dois: a mesma
/// queda que o `chat_reconexao_test` provoca no provider é a que os testes de
/// tela precisam para provar que a conversa funciona sem canal. Duas cópias
/// deste arquivo divergiriam, e a divergência apareceria como um teste verde
/// sobre um canal que o outro arquivo já sabia estar morto.
class MockSupabaseClient extends Mock implements SupabaseClient {}

class MockGoTrueClient extends Mock implements GoTrueClient {}

class MockRealtimeChannel extends Mock implements RealtimeChannel {}

class MockUser extends Mock implements User {}

/// Fallback do `any()` do mocktail para o callback de `onPostgresChanges`.
/// Precisa de tipo estático exato — lambda inline seria registrada como
/// `Null Function(...)` e o `any()` não a acharia.
void _ignorePayload(PostgresChangePayload _) {}

/// Registra os fallbacks do mocktail. Chamar de `setUpAll`.
void registerChatFallbacks() {
  registerFallbackValue('');
  registerFallbackValue(<String, dynamic>{});
  registerFallbackValue(MockRealtimeChannel());
  registerFallbackValue(_ignorePayload);
}

/// Deixa a fila de microtarefas correr. O provider emite depois de um `await`;
/// sem isto o teste leria o estado anterior.
Future<void> settleMicrotasks() => Future<void>.delayed(Duration.zero);

/// O servidor de tempo real inteiro em dublê, com as duas alavancas que
/// importam: [deliver] põe um evento no canal, [setStatus] derruba e levanta.
class FakeRealtime {
  FakeRealtime({bool signedIn = true}) {
    when(() => client.auth).thenReturn(_auth);
    when(() => _auth.currentUser).thenReturn(signedIn ? MockUser() : null);
    when(() => client.channel(any())).thenReturn(channel);
    when(() => client.removeChannel(any())).thenAnswer((_) async => 'ok');

    when(
      () => channel.onPostgresChanges(
        event: PostgresChangeEvent.all,
        schema: 'public',
        table: 'mensagens',
        filter: any(named: 'filter'),
        callback: any(named: 'callback'),
      ),
    ).thenAnswer((invocation) {
      _deliver =
          invocation.namedArguments[#callback]
              as void Function(PostgresChangePayload);
      return channel;
    });

    when(() => channel.subscribe(any())).thenAnswer((invocation) {
      _notifyStatus =
          invocation.positionalArguments.first
              as void Function(RealtimeSubscribeStatus, Object?);
      return channel;
    });
  }

  final client = MockSupabaseClient();
  final channel = MockRealtimeChannel();
  final _auth = MockGoTrueClient();

  late void Function(PostgresChangePayload) _deliver;
  late void Function(RealtimeSubscribeStatus, Object?) _notifyStatus;

  /// Põe um evento no canal, como o Postgres faria.
  void deliver(PostgresChangePayload payload) => _deliver(payload);

  /// Muda o estado da assinatura. `subscribed` é o canal de pé; `closed` é a
  /// queda. Sem chamar isto, o canal NUNCA sobe — que é o cenário
  /// "reconectando", e o certo para os testes que provam que a tela não depende
  /// dele.
  void setStatus(RealtimeSubscribeStatus status) => _notifyStatus(status, null);
}
