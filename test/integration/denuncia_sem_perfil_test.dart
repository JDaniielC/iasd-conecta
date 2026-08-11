import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// FR-015 pelo lado do banco: **por que o cliente não pode assinar a denúncia
/// com o id de uma sessão sem Perfil.**
///
/// Existe para que o conserto do cliente não seja cargo cult. A FK
/// `denuncias_imagem_denunciante_id_fkey` aponta para `perfis`, e o app faz
/// `signInAnonymously` na inicialização — então todo Visitante tem sessão sem
/// necessariamente ter Perfil. Mandar esse id é o erro; mandar nulo é o
/// caminho.
const _uidOwner = '7f000000-0000-0000-0000-000000000001';
const _uidSessionWithoutProfile = '7f000000-0000-0000-0000-000000000002';

void main() {
  late Connection conn;
  late Object groupId;
  late Object photoId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidOwner, name: 'Dono DenunciaSemPerfil');
    // Sessão sem Perfil: existe em auth.users, NÃO existe em perfis. É o
    // estado de quem abre o app e nunca se cadastrou.
    await createTestUser(conn, _uidSessionWithoutProfile);

    final groupRows = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, horario, local, dono_id) "
        "values ('Grupo DenunciaSemPerfil', 'Ministério Jovem', 's', 'Sede', @dono) returning id",
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = groupRows.single.toColumnMap()['id']!;

    final photoRows = await conn.execute(
      Sql.named(
        'insert into public.fotos_capa (grupo_id, caminho, enviada_por) '
        "values (@g, 'grupo/denuncia-sem-perfil/x.jpg', @d) returning id",
      ),
      parameters: {'g': groupId, 'd': _uidOwner},
    );
    photoId = photoRows.single.toColumnMap()['id']!;
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.denuncias_imagem where foto_id = @f'),
      parameters: {'f': photoId},
    );
    await conn.execute(
      Sql.named('delete from public.fotos_capa where id = @f'),
      parameters: {'f': photoId},
    );
    await conn.execute(
      "delete from public.capas_a_remover where caminho = 'grupo/denuncia-sem-perfil/x.jpg'",
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await cleanUpTestUser(conn, _uidOwner);
    await cleanUpTestUser(conn, _uidSessionWithoutProfile);
    await conn.close();
  });

  Future<void> asSessionWithoutProfile(Future<void> Function() action) async {
    await conn.execute('set role authenticated');
    await conn.execute(
      "set request.jwt.claims to "
      "'{\"sub\":\"$_uidSessionWithoutProfile\",\"role\":\"authenticated\"}'",
    );
    try {
      await action();
    } finally {
      await conn.execute('reset role');
    }
  }

  test(
    'assinar com o id de uma sessão sem Perfil é RECUSADO pela FK — é o bug '
    'que o cliente cometia',
    () async {
      await asSessionWithoutProfile(() async {
        await expectLater(
          conn.execute(
            Sql.named(
              'insert into public.denuncias_imagem (foto_id, motivo, denunciante_id) '
              "values (@f, 'Aparece uma criança', @u)",
            ),
            parameters: {'f': photoId, 'u': _uidSessionWithoutProfile},
          ),
          throwsA(
            isA<ServerException>().having(
              (e) => e.code,
              'código',
              '23503',
            ),
          ),
        );
      });
    },
  );

  test(
    'a MESMA sessão denuncia sem assinar, e a denúncia é registrada — FR-015',
    () async {
      await asSessionWithoutProfile(() async {
        await conn.execute(
          Sql.named(
            'insert into public.denuncias_imagem (foto_id, motivo, denunciante_id) '
            "values (@f, 'Aparece uma criança', null)",
          ),
          parameters: {'f': photoId},
        );
      });

      final rows = await conn.execute(
        Sql.named(
          'select denunciante_id, estado from public.denuncias_imagem where foto_id = @f',
        ),
        parameters: {'f': photoId},
      );
      final row = rows.single.toColumnMap();
      expect(row['denunciante_id'], isNull);
      expect(row['estado'], 'pendente');
    },
  );
}
