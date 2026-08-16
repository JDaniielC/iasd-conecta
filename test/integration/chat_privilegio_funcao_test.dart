import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — quem pode CHAMAR as funções, não só o que
/// elas respondem.
///
/// Achado pelo agente `pentest-etico` em 2026-08-14, e é uma armadilha do
/// Postgres que não se vê lendo a migration: **função nova nasce com `EXECUTE`
/// para `PUBLIC`**. O `grant execute ... to authenticated` que a migration
/// escreve ACRESCENTA um privilégio; não substitui o que já estava lá. Sem um
/// `revoke ... from public` explícito, `anon` — a role que o PostgREST usa em
/// requisição sem `Authorization` — herda o direito de chamar.
///
/// O caso que dói é `expurgar_mensagens_de_acao()`: `security definer`, faz
/// `delete` global, e a chave publicável está no bundle público do app. Qualquer
/// pessoa com `curl` disparava uma varredura de junção com `delete`, sem login.
/// O dano de dado é limitado — só apaga o que já venceu —, mas escrita
/// destrutiva alcançável sem autenticação não é o que a migration dizia
/// oferecer.
///
/// Este teste olha o PRIVILÉGIO, não o resultado. Um teste que só conferisse
/// "anon não lê mensagem" continuaria verde com a RPC aberta, porque as duas
/// coisas são barreiras diferentes.

void main() {
  late Connection conn;

  /// Todas as funções que esta change criou. A lista é explícita de propósito:
  /// função nova acrescentada aqui depois e esquecida na lista passa batida, e
  /// o modo de falha é exatamente este achado de novo.
  const functions = [
    'public.maior_de_idade()',
    'public.pode_ver_chat_grupo(uuid)',
    'public.pode_ver_chat_acao(uuid)',
    'public.pode_moderar_espaco(uuid, uuid)',
    'public.pode_moderar_mensagem(uuid, uuid, uuid)',
    'public.expurgar_mensagens_de_acao()',
  ];

  Future<bool> canExecute(String role, String signature) async {
    final r = await conn.execute(
      Sql.named('select has_function_privilege(@r, @f, \'execute\')'),
      parameters: {'r': role, 'f': signature},
    );
    return r.first[0]! as bool;
  }

  setUpAll(() async {
    conn = await openTestConnection();
  });

  tearDownAll(() => conn.close());

  test('anon não pode chamar nenhuma função do chat', () async {
    for (final f in functions) {
      expect(
        await canExecute('anon', f),
        isFalse,
        reason:
            '$f está aberta a anon — falta `revoke execute ... from public`',
      );
    }
  });

  test('authenticated continua podendo chamar todas', () async {
    // O `revoke from public` não pode ter levado junto quem precisa: o app É o
    // segundo gatilho do expurgo, e as funções de acesso são chamadas de dentro
    // das policies.
    for (final f in functions) {
      expect(await canExecute('authenticated', f), isTrue, reason: f);
    }
  });

  test(
    'anon chamando o expurgo é recusado de verdade, não só no catálogo',
    () async {
      Object? error;
      try {
        await asVisitor(
          conn,
          () => conn.execute('select public.expurgar_mensagens_de_acao()'),
        );
      } catch (e) {
        error = e;
      }
      expect(
        error,
        isA<ServerException>(),
        reason: 'RPC destrutiva alcançável sem autenticação',
      );
    },
  );
}
