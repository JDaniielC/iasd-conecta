import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000035';
const _uidSegundo = '50000000-0000-0000-0000-000000000036';
const _uidTerceiro = '50000000-0000-0000-0000-000000000037';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador SaiFila');
    await createTestProfile(conn, _uidSegundo, name: 'Segundo SaiFila');
    await createTestProfile(conn, _uidTerceiro, name: 'Terceiro SaiFila');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) "
        "values ('Ação SaiFila', now() + interval '5 days', 'Sede', 1, @criador) returning id",
      ),
      parameters: {'criador': _uidCreator},
    );
    actionId = rows.single.toColumnMap()['id']!;

    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @segundo)',
      ),
      parameters: {'acao': actionId, 'segundo': _uidSegundo},
    );
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @terceiro)',
      ),
      parameters: {'acao': actionId, 'terceiro': _uidTerceiro},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': actionId},
    );
    await cleanUpTestUser(conn, _uidCreator);
    await cleanUpTestUser(conn, _uidSegundo);
    await cleanUpTestUser(conn, _uidTerceiro);
    await conn.close();
  });

  test(
    'sair da fila (sem ser confirmado) não promove ninguém e não afeta os demais',
    () async {
      // Segundo (fila) desiste da fila, sem nunca ter sido confirmado
      await conn.execute(
        Sql.named(
          'delete from public.confirmacoes_acao where acao_id = @acao and usuario_id = @segundo',
        ),
        parameters: {'acao': actionId, 'segundo': _uidSegundo},
      );

      final rows = await conn.execute(
        Sql.named('select usuario_id, status from public.confirmacoes_acao where acao_id = @acao'),
        parameters: {'acao': actionId},
      );
      final mapa = {
        for (final r in rows) r.toColumnMap()['usuario_id']: r.toColumnMap()['status'],
      };

      expect(mapa[_uidCreator], 'confirmado');
      expect(mapa[_uidTerceiro], 'fila');
      expect(mapa.containsKey(_uidSegundo), isFalse);
    },
  );
}
