import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCreator = '50000000-0000-0000-0000-000000000020';
const _uidMember = '50000000-0000-0000-0000-000000000021';

void main() {
  late Connection conn;
  late Object actionId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador Idem');
    await createTestProfile(conn, _uidMember, name: 'Participante Idem');
    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id) "
        "values ('Ação Idem', now() + interval '5 days', 'Sede', @criador) returning id",
      ),
      parameters: {'criador': _uidCreator},
    );
    actionId = rows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': actionId},
    );
    await cleanUpTestUser(conn, _uidCreator);
    await cleanUpTestUser(conn, _uidMember);
    await conn.close();
  });

  test('FR-012: confirmar presença duas vezes não duplica nem falha', () async {
    Future<void> confirmar() => conn.execute(
          Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) '
            'values (@acao, @usuario) on conflict (acao_id, usuario_id) do nothing',
          ),
          parameters: {'acao': actionId, 'usuario': _uidMember},
        );

    await confirmar();
    await confirmar();

    final rows = await conn.execute(
      Sql.named(
        'select count(*) as total from public.confirmacoes_acao '
        'where acao_id = @acao and usuario_id = @usuario',
      ),
      parameters: {'acao': actionId, 'usuario': _uidMember},
    );
    expect(rows.single.toColumnMap()['total'], 1);
  });
}
