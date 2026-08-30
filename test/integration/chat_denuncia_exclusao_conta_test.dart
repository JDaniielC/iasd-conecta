import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `denuncia-como-registro` — excluir a conta esvazia o `motivo` de
/// quem DENUNCIOU, na mesma transação, e não toca no motivo que outra pessoa
/// escreveu sobre mensagem dela. PENDENCIAS.md 2.14: as duas metades da
/// exclusão discordavam — as mensagens perdiam o texto, o motivo não.
///
/// `_uidReporter` NÃO é dono do Grupo nem Administrador de propósito: com
/// herança `excluir_minha_conta` exige herdeiro, e este arquivo estaria
/// testando aquela regra em vez desta.

const _uidOwner = 'd9000000-0000-0000-0000-000000000001';
const _uidAuthor = 'd9000000-0000-0000-0000-000000000002';
const _uidReporter = 'd9000000-0000-0000-0000-000000000003';
const _allUids = [_uidOwner, _uidAuthor, _uidReporter];

void main() {
  late Connection conn;
  late String groupId;
  late String ownReportId, thirdPartyReportId;

  Future<String?> motivoOf(String id) async {
    final r = await conn.execute(
      Sql.named('select motivo from public.denuncias_mensagem where id = @d'),
      parameters: {'d': id},
    );
    return r.single.toColumnMap()['motivo'] as String?;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    for (final uid in _allUids) {
      await createTestProfileWithAge(
        conn,
        uid,
        name: 'Pessoa ${uid.substring(0, 10)}',
        age: 30,
      );
    }
    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo C3');
    await joinGroup(conn, groupId, _uidAuthor);
    await joinGroup(conn, groupId, _uidReporter);

    final subjectMessage = await seedMessage(
      conn,
      authorId: _uidAuthor,
      groupId: groupId,
      text: 'mensagem denunciada pelo titular',
    );
    final reporterOwnMessage = await seedMessage(
      conn,
      authorId: _uidReporter,
      groupId: groupId,
      text: 'mensagem do próprio titular, denunciada por outra pessoa',
    );

    // SEM `returning`: quem denuncia não tem `select` liberado pela RLS na
    // própria denúncia, e `insert ... returning` levanta "new row violates
    // row-level security policy" quando a policy de select nega a linha
    // recém-criada — diferente de update/delete, que filtrariam em silêncio.
    // O id sai por uma leitura à parte, como `postgres`.
    await asUser(
      conn,
      _uidReporter,
      () => conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d)',
        ),
        parameters: {
          'm': subjectMessage,
          'mo': 'motivo escrito pelo titular, some com a conta dele',
          'd': _uidReporter,
        },
      ),
    );
    ownReportId = await conn
        .execute(
          Sql.named(
            'select id from public.denuncias_mensagem '
            'where mensagem_id = @m and denunciante_id = @d',
          ),
          parameters: {'m': subjectMessage, 'd': _uidReporter},
        )
        .then((r) => r.single.toColumnMap()['id']! as String);

    thirdPartyReportId = await asUser(
      conn,
      _uidOwner,
      () => conn.execute(
        Sql.named(
          'insert into public.denuncias_mensagem '
          '(mensagem_id, motivo, denunciante_id) values (@m, @mo, @d) '
          'returning id',
        ),
        parameters: {
          'm': reporterOwnMessage,
          'mo': 'motivo escrito por OUTRA pessoa sobre mensagem do titular',
          'd': _uidOwner,
        },
      ),
    ).then((r) => r.single.toColumnMap()['id']! as String);

    await asUser(
      conn,
      _uidReporter,
      () => conn.execute('select public.excluir_minha_conta()'),
    );
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    // TODOS os uids, incluindo _uidReporter — mesmo com a conta já excluída
    // por `excluir_minha_conta()` dentro do teste. `cleanUpTestUser` apaga
    // `perfis` (que sobrevive à exclusão, anonimizado) e só then tenta
    // `auth.users`, que já não existe: `delete` sem linha correspondente não
    // é erro. Pular o reporter aqui deixava o Perfil anonimizado (idade
    // NULA) para trás, e a segunda rodada da suíte — sem reset entre elas —
    // recriava `auth.users` mas `on conflict do nothing` em `perfis` mantinha
    // o Perfil velho, sem idade: `maior_de_idade()` passava a negar, e o
    // `insert` de denúncia do teste seguinte quebrava por RLS num teste que
    // não tinha nada a ver com isto.
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('o motivo escrito pelo titular esvaziou com a exclusão da conta',
      () async {
    expect(await motivoOf(ownReportId), isNull);
  });

  test('a denúncia continua existindo, com o desfecho que tiver', () async {
    final r = await conn.execute(
      Sql.named(
        'select estado, denunciante_id::text from '
        'public.denuncias_mensagem where id = @d',
      ),
      parameters: {'d': ownReportId},
    );
    final row = r.single.toColumnMap();
    expect(row['estado'], 'pendente');
    expect(
      row['denunciante_id'],
      _uidReporter,
      reason: 'denunciante_id NÃO é anulado — anular quebraria o índice '
          'único parcial',
    );
  });

  test(
    'o motivo que OUTRA pessoa escreveu sobre mensagem do titular '
    'continua existindo — é texto de outra pessoa',
    () async {
      expect(
        await motivoOf(thirdPartyReportId),
        'motivo escrito por OUTRA pessoa sobre mensagem do titular',
      );
    },
  );
}
