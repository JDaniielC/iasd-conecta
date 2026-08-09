import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '50000000-0000-0000-0000-000000000040';
const _uidOutro = '50000000-0000-0000-0000-000000000041';

void main() {
  late Connection conn;
  late Object acaoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidCriador, name: 'Criador Cancela');
    await criarPerfilDeTeste(conn, _uidOutro, name: 'Outro Cancela');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Ação Cancela', now() + interval '5 days', 'Sede', @criador) returning id",
      ),
      parameters: {'criador': _uidCriador},
    );
    acaoId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': acaoId},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
    await limparUsuarioDeTeste(conn, _uidOutro);
    await conn.close();
  });

  Future<void> comoUsuario(String uid, Future<void> Function() acao) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to '{\"sub\":\"$uid\",\"role\":\"authenticated\"}'",
    );
    try {
      await acao();
    } finally {
      await conn.execute('reset role');
    }
  }

  test('FR-008: quem não criou não consegue cancelar a Ação', () async {
    await comoUsuario(_uidOutro, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': acaoId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': acaoId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNull);
  });

  test('o criador consegue cancelar a própria Ação', () async {
    await comoUsuario(_uidCriador, () async {
      await conn.execute(
        Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
        parameters: {'acao': acaoId},
      );
    });

    final rows = await conn.execute(
      Sql.named('select cancelada_em from public.acoes where id = @acao'),
      parameters: {'acao': acaoId},
    );
    expect(rows.single.toColumnMap()['cancelada_em'], isNotNull);
  });
}
