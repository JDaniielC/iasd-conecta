import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Feature 014, FR-016 — a identificação pública do Líder/Diretor sai do ar
/// quando o Ministério é arquivado.
///
/// Este arquivo existe porque esta é a única parte da feature que falha em
/// **silêncio**. `liderancas` não é tocada pelo arquivamento, de propósito: é o
/// registro de quem foi responsável perante a igreja, e apagá-lo seria reescrever
/// história. O preço é que **nada no banco impede** a declaração de continuar
/// legível — o filtro vive no cliente, em `leadership_repository.dart`.
///
/// O teste abaixo mede o **banco**, e por isso confirma o problema em vez de
/// escondê-lo: ele documenta que a linha continua lá e legível, e que o filtro do
/// cliente é a única barreira. Se um dia alguém decidir mover a barreira para o
/// banco, este arquivo é onde a decisão aparece.

const _uidOwner = '90000000-0000-0000-0000-000000000001';
const _uidLeader = '90000000-0000-0000-0000-000000000002';

/// Visitante: pessoa sem cadastro, e por isso sem linha em `perfis`. TEM
/// sessão — `signInAnonymously` no arranque do app. Até 2026-08-16 este arquivo
/// o representava como `anon`, que é a requisição sem credencial nenhuma e não
/// é o que o app produz.
const _uidVisitor = '90000000-0000-0000-0000-0000000000f2';

const _allUids = [_uidOwner, _uidLeader];

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfile(conn, uid, name: 'Pessoa ${uid.substring(31)}');
      await createTestVisitor(conn, _uidVisitor);
    }
    final g = await conn.execute(
      Sql.named(
        "insert into public.grupos (nome, categoria, dono_id) "
        "values ('Ministério Arquivar 014', 'Ministério Jovem', @dono) "
        'returning id',
      ),
      parameters: {'dono': _uidOwner},
    );
    groupId = g.first[0] as String;
    await conn.execute(
      Sql.named(
        'insert into public.liderancas '
        '(grupo_id, usuario_id, ano, confirmado_em, confirmado_por) '
        'values (@g, @u, extract(year from now())::int, now(), @o)',
      ),
      parameters: {'g': groupId, 'u': _uidLeader, 'o': _uidOwner},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named('delete from public.liderancas where grupo_id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test(
    'arquivar NÃO apaga a declaração de liderança — ela é histórico',
    () async {
      await conn.execute(
        Sql.named(
          'update public.grupos set arquivado_em = now(), '
          'arquivado_por = @o where id = @g',
        ),
        parameters: {'g': groupId, 'o': _uidOwner},
      );

      final r = await conn.execute(
        Sql.named('select count(*) from public.liderancas where grupo_id = @g'),
        parameters: {'g': groupId},
      );
      expect(
        (r.first[0] as num).toInt(),
        1,
        reason: 'quem foi responsável continua tendo sido',
      );
    },
  );

  test('a declaração continua LEGÍVEL no banco — o filtro é do cliente, e é a '
      'única barreira', () async {
    // Isto não é o comportamento desejado da tela; é o retrato honesto de
    // onde a barreira está. A consulta que a tela usa filtra
    // `grupos.arquivado_em is null` com um join `!inner`; se esse filtro
    // sair de `leadership_repository.dart`, o nome do Líder de um Ministério
    // arquivado volta a aparecer para Visitante sem cadastro, e nada aqui
    // no banco vai reclamar.
    await asVisitor(conn, _uidVisitor, () async {
      final r = await conn.execute(
        Sql.named('select count(*) from public.liderancas where grupo_id = @g'),
        parameters: {'g': groupId},
      );
      expect((r.first[0] as num).toInt(), 1);
    });

    // E a consulta COM o filtro do cliente devolve zero — é ela que a tela
    // faz.
    final filtered = await conn.execute(
      Sql.named(
        'select count(*) from public.liderancas l '
        'join public.grupos g on g.id = l.grupo_id '
        'where l.grupo_id = @g and g.arquivado_em is null',
      ),
      parameters: {'g': groupId},
    );
    expect((filtered.first[0] as num).toInt(), 0);
  });
}
