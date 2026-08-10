import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uid = '95000000-0000-0000-0000-000000000002';

/// Regressão da armadilha descrita em
/// `20260806090000_nome_valido_security_definer.sql`: com RLS ligada em
/// `palavras_bloqueadas` (que é como o projeto de produção nasce, por causa do
/// "Enable automatic RLS"), a moderação de nome pararia de bloquear qualquer
/// palavra — em silêncio, sem erro e sem teste vermelho, porque uma tabela com
/// RLS e sem policy devolve zero linhas em vez de recusar.
///
/// Os testes correm como `authenticated`, e não como superusuário, justamente
/// porque superusuário bypassa RLS e não veria a falha.
void main() {
  late Connection conn;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestUser(conn, _uid);
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.perfis where id = @id'),
      parameters: {'id': _uid},
    );
    await cleanUpTestUser(conn, _uid);
    await conn.close();
  });

  Future<void> comoAuthenticated() async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$_uid\",\"role\":\"authenticated\"}'",
    );
  }

  test('a lista de palavras bloqueadas não é legível por authenticated', () async {
    await comoAuthenticated();
    try {
      await expectLater(
        conn.execute('select palavra from public.palavras_bloqueadas'),
        throwsA(isA<ServerException>()),
        reason: 'sem GRANT, a leitura tem que ser recusada, não devolver lista vazia',
      );
    } finally {
      await conn.execute('reset role');
    }
  });

  test('nome com palavra bloqueada continua sendo recusado', () async {
    await comoAuthenticated();
    try {
      await expectLater(
        conn.execute(
          Sql.named(
            "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
            "values (@id, 'Fulano Idiota', 'masculino', 30, now())",
          ),
          parameters: {'id': _uid},
        ),
        throwsA(isA<ServerException>()),
        reason: 'se a função enxergasse a lista vazia, este insert passaria',
      );
    } finally {
      await conn.execute('reset role');
    }
  });

  test('nome limpo continua passando', () async {
    await comoAuthenticated();
    try {
      await conn.execute(
        Sql.named(
          "insert into public.perfis (id, nome, genero, idade, consentimento_lgpd_aceito_em) "
          "values (@id, 'Fulano de Tal', 'masculino', 30, now())",
        ),
        parameters: {'id': _uid},
      );
    } finally {
      await conn.execute('reset role');
    }
    final linhas = await conn.execute(
      Sql.named('select nome from public.perfis where id = @id'),
      parameters: {'id': _uid},
    );
    expect(linhas.single.first, 'Fulano de Tal');
  });
}
