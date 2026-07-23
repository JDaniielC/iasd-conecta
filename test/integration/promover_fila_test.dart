import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

const _uidCriador = '50000000-0000-0000-0000-000000000032';
const _uidSegundo = '50000000-0000-0000-0000-000000000033';
const _uidTerceiro = '50000000-0000-0000-0000-000000000034';

void main() {
  late Connection conn;
  late Object acaoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await criarPerfilDeTeste(conn, _uidCriador, nome: 'Criador Promove');
    await criarPerfilDeTeste(conn, _uidSegundo, nome: 'Segundo Promove');
    await criarPerfilDeTeste(conn, _uidTerceiro, nome: 'Terceiro Promove');

    final rows = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, limite_vagas, criador_id) "
        "values ('Ação Promove', now() + interval '5 days', 'Sede', 1, @criador) returning id",
      ),
      parameters: {'criador': _uidCriador},
    );
    acaoId = rows.single.toColumnMap()['id']!;

    // dois entram na fila, em ordem
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @segundo)',
      ),
      parameters: {'acao': acaoId, 'segundo': _uidSegundo},
    );
    await conn.execute(
      Sql.named(
        'insert into public.confirmacoes_acao (acao_id, usuario_id) values (@acao, @terceiro)',
      ),
      parameters: {'acao': acaoId, 'terceiro': _uidTerceiro},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.acoes where id = @acao'),
      parameters: {'acao': acaoId},
    );
    await limparUsuarioDeTeste(conn, _uidCriador);
    await limparUsuarioDeTeste(conn, _uidSegundo);
    await limparUsuarioDeTeste(conn, _uidTerceiro);
    await conn.close();
  });

  test('FR-006: desistência do confirmado promove o mais antigo da fila', () async {
    // pré-condição: segundo e terceiro estão os dois em fila
    final antes = await conn.execute(
      Sql.named(
        'select usuario_id, status from public.confirmacoes_acao where acao_id = @acao order by created_at',
      ),
      parameters: {'acao': acaoId},
    );
    expect(antes.map((r) => r.toColumnMap()['status']).toList(), ['confirmado', 'fila', 'fila']);

    // criador desiste, libera a única vaga
    await conn.execute(
      Sql.named(
        'delete from public.confirmacoes_acao where acao_id = @acao and usuario_id = @criador',
      ),
      parameters: {'acao': acaoId, 'criador': _uidCriador},
    );

    final depois = await conn.execute(
      Sql.named('select usuario_id, status from public.confirmacoes_acao where acao_id = @acao'),
      parameters: {'acao': acaoId},
    );
    final mapa = {
      for (final r in depois) r.toColumnMap()['usuario_id']: r.toColumnMap()['status'],
    };
    expect(mapa[_uidSegundo], 'confirmado');
    expect(mapa[_uidTerceiro], 'fila');
  });
}
