import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — a autoridade NÃO levanta o corte de idade.
///
/// Convergência 1. O cenário estava na spec desde o começo e nenhum arquivo o
/// exercitava: `chat_corte_de_idade_test` não cria Administrador, e
/// `chat_moderacao_test` só usa Administrador de 30 anos. Ninguém cruzava as
/// duas condições, e foi por essa fresta que o defeito passou por 380 testes
/// verdes.
///
/// O defeito: o corte parava em `mensagens`. `pode_moderar_espaco` não chamava
/// `maior_de_idade()`, e as três policies de `denuncias_mensagem` dependem só
/// dela — então um Administrador de 16 anos lia ZERO mensagens (certo) e lia as
/// denúncias com o `motivo` inteiro, e ainda as arquivava.
///
/// O `motivo` é texto livre escrito por uma pessoa sobre o que outra escreveu.
/// É a mesma categoria de dado que o corte etário existe para não entregar a
/// menor de idade — só que numa tabela ao lado.

const _uidOwner = '17000000-0000-0000-0000-000000000001';
const _uidMember = '17000000-0000-0000-0000-000000000002';
const _uidMinorAdmin = '17000000-0000-0000-0000-000000000003';
const _uidAdultAdmin = '17000000-0000-0000-0000-000000000004';
const _allUids = [_uidOwner, _uidMember, _uidMinorAdmin, _uidAdultAdmin];

void main() {
  late Connection conn;
  late String groupId, messageId, reportId;

  Future<int> visibleReports(String uid) => asUser(conn, uid, () async {
    final r = await conn.execute(
      Sql.named('select count(*) from public.denuncias_mensagem where id = @d'),
      parameters: {'d': reportId},
    );
    return r.first[0]! as int;
  });

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in [_uidOwner, _uidMember, _uidAdultAdmin]) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: 30,
      );
    }
    await createTestProfileWithAge(
      conn,
      _uidMinorAdmin,
      name: 'Admin Menor',
      age: 16,
    );
    await createTestDistrictAdmin(conn, _uidMinorAdmin);
    await createTestDistrictAdmin(conn, _uidAdultAdmin);

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo C3');
    await joinGroup(conn, groupId, _uidMember);
    await joinGroup(conn, groupId, _uidMinorAdmin);

    messageId = await seedMessage(
      conn,
      authorId: _uidOwner,
      groupId: groupId,
      text: 'algo que gerou denúncia',
    );
    final r = await conn.execute(
      Sql.named(
        'insert into public.denuncias_mensagem '
        '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d) '
        'returning id',
      ),
      parameters: {
        'm': messageId,
        'mo': 'motivo que descreve o que foi dito',
        'd': _uidMember,
      },
    );
    reportId = r.single.toColumnMap()['id']! as String;
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito '
        'where usuario_id = any(@us::uuid[])',
      ),
      parameters: {
        'us': [_uidMinorAdmin, _uidAdultAdmin],
      },
    );
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('Administrador de 16 anos não lê mensagem', () async {
    expect(await asUser(conn, _uidMinorAdmin, () => isOfAge(conn)), isFalse);
    expect(
      await asUser(
        conn,
        _uidMinorAdmin,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
    );
  });

  test('Administrador de 16 anos não lê DENÚNCIA — o motivo é texto livre '
      'igual', () async {
    expect(
      await visibleReports(_uidMinorAdmin),
      0,
      reason: 'o corte de idade não pode parar em mensagens',
    );
  });

  test('Administrador de 16 anos não resolve denúncia', () async {
    // Recusa por RLS de update é ZERO LINHA, não erro.
    final affected = await asUser(conn, _uidMinorAdmin, () async {
      final r = await conn.execute(
        Sql.named(
          "update public.denuncias_mensagem set estado = 'improcedente', "
          'resolvida_em = now() where id = @d',
        ),
        parameters: {'d': reportId},
      );
      return r.affectedRows;
    });
    expect(affected, 0);

    final state = await conn.execute(
      Sql.named('select estado from public.denuncias_mensagem where id = @d'),
      parameters: {'d': reportId},
    );
    expect(state.single.toColumnMap()['estado'], 'pendente');
  });

  test('Administrador de 30 anos continua lendo e resolvendo', () async {
    // O contraste é o que prova que o conserto acertou o alvo. Sem ele, um
    // corte que fechasse a denúncia para TODO mundo passaria nos três testes
    // acima e quebraria a moderação inteira em silêncio.
    expect(await visibleReports(_uidAdultAdmin), 1);

    final affected = await asUser(conn, _uidAdultAdmin, () async {
      final r = await conn.execute(
        Sql.named(
          "update public.denuncias_mensagem set estado = 'improcedente', "
          'resolvida_em = now() where id = @d',
        ),
        parameters: {'d': reportId},
      );
      return r.affectedRows;
    });
    expect(affected, 1);
  });
}
