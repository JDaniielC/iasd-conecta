import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';
import 'presenca_helper.dart';

/// Change `presenca-em-acao`, requisito "A idade não restringe o registro de
/// comparecimento" — e a trava que ele NÃO dispensa.
///
/// Comparecimento vale para qualquer idade: Desbravadores (10-15) e Aventureiros
/// (6-9) são justamente quem já faz chamada no papel. O corte de
/// `maior_de_idade()` que restringe a conversa não se aplica aqui.
///
/// O QUE PROTEGE MENOR DE 13 NÃO É A AUSÊNCIA DO REGISTRO — é a autorização do
/// responsável, e ela tem versão própria. Achado C-1 da convergência 1, medido
/// em 2026-09-09: a trava olhava só `consentimento_lgpd_versao`, então uma
/// criança de 10 anos tocando "Aceitar" no aviso da Home destravava a coleta
/// sobre si mesma, com o responsável tendo autorizado um texto anterior que não
/// menciona comparecimento.
///
/// E a autorização **não tem como ser atualizada**:
/// `perfis_protege_autorizacao_responsavel` levanta exceção em qualquer mudança
/// nas quatro colunas do responsável. Não é atraso — é impossibilidade. Por
/// isso a recusa é o comportamento correto, e não uma limitação temporária.

const _uidCreator = 'e9000000-0000-0000-0000-000000000001';
const _uidChildCurrent = 'e9000000-0000-0000-0000-000000000002';
const _uidChildOutdated = 'e9000000-0000-0000-0000-000000000003';
const _uidTeen = 'e9000000-0000-0000-0000-000000000004';
const _allUids = [
  _uidCreator,
  _uidChildCurrent,
  _uidChildOutdated,
  _uidTeen,
];

void main() {
  late Connection conn;

  Future<void> createChild(
    String uid, {
    required int age,
    required String guardianVersion,
  }) async {
    await createTestUser(conn, uid);
    await conn.execute(
      Sql.named(
        'insert into public.perfis (id, nome, apelido, genero, idade, '
        'consentimento_lgpd_aceito_em, responsavel_nome, responsavel_contato, '
        'autorizacao_responsavel_em, autorizacao_responsavel_versao) '
        "values (@id, @nome, 'Apelido', 'feminino', @idade, now(), "
        "'Responsável de Teste', 'responsavel@example.com', now(), @versao) "
        'on conflict (id) do nothing',
      ),
      parameters: {
        'id': uid,
        'nome': 'Criança $uid',
        'idade': age,
        'versao': guardianVersion,
      },
    );
  }

  Future<String> currentVersion() async {
    final r = await conn.execute('select public.versao_texto_legal_vigente()');
    return r.first[0]! as String;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidCreator, name: 'Criador menor');
    final current = await currentVersion();
    await createChild(_uidChildCurrent, age: 10, guardianVersion: current);
    await createChild(_uidChildOutdated, age: 10, guardianVersion: '0.0-antiga');
    // 15 anos: menor de idade, mas acima do limiar de criança — não tem
    // responsável registrado, e a trava que vale para ele é a comum.
    // Apelido junto com a idade, na mesma escrita: `apelido_obrigatorio_menor`
    // exige apelido abaixo de 18, e baixar a idade sozinha é recusado.
    await createTestProfile(conn, _uidTeen, name: 'Adolescente de teste');
    await conn.execute(
      Sql.named(
        "update public.perfis set idade = 15, apelido = 'Desbravador' "
        'where id = @id',
      ),
      parameters: {'id': _uidTeen},
    );
  });

  tearDownAll(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  tearDown(() async {
    await cleanUpPresenceFixtures(conn, _allUids);
  });

  Future<String> seedActionWith(String uid) async {
    final actionId = await createPastAction(conn, creatorId: _uidCreator);
    await seedConfirmation(conn, actionId, uid);
    return actionId;
  }

  test('criança com autorização do responsável na versão vigente é marcada',
      () async {
    final actionId = await seedActionWith(_uidChildCurrent);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidChildCurrent,
      markerId: _uidCreator,
    );

    expect(affected, 1);
  });

  test('adolescente acima do limiar de criança é marcado normalmente',
      () async {
    // O corte de 18 anos que restringe a conversa NÃO se aplica aqui — é o
    // ponto do requisito. Desbravadores são o público que mais acompanha
    // presença.
    final actionId = await seedActionWith(_uidTeen);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidTeen,
      markerId: _uidCreator,
    );

    expect(affected, 1);
  });

  test('criança com autorização de versão anterior NÃO é marcada', () async {
    final actionId = await seedActionWith(_uidChildOutdated);

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidChildOutdated,
      markerId: _uidCreator,
    );

    expect(affected, 0);
    final state = await attendanceOf(conn, actionId, _uidChildOutdated);
    expect(state.attendedAt, isNull);
  });

  test('reaceite da própria criança NÃO destrava a coleta sobre ela',
      () async {
    // ACHADO C-1, medido em 2026-09-09. A criança consegue mesmo reaceitar —
    // o `update` afeta uma linha e `consentimento_lgpd_versao` sobe. O que não
    // pode acontecer é isso valer como autorização: quem autoriza tratamento de
    // criança é o responsável, e a versão dele fica congelada por
    // `perfis_protege_autorizacao_responsavel`.
    final actionId = await seedActionWith(_uidChildOutdated);

    final reaccepted = await reacceptLegalText(conn, _uidChildOutdated);
    expect(reaccepted, 1, reason: 'o reaceite em si acontece');
    expect(
      await consentVersionOf(conn, _uidChildOutdated),
      await currentVersion(),
      reason: 'e sobe a versão do aceite da própria criança',
    );

    final affected = await markAttendance(
      conn,
      actionId: actionId,
      userId: _uidChildOutdated,
      markerId: _uidCreator,
    );

    expect(affected, 0, reason: 'mas a autorização do responsável não subiu');
  });

  test('a autorização do responsável não tem como ser atualizada', () async {
    // Não é atraso, é impossibilidade — e é isso que torna a recusa acima o
    // comportamento correto, e não uma limitação temporária a contornar.
    await expectLater(
      conn.execute(
        Sql.named(
          'update public.perfis set autorizacao_responsavel_versao = @v '
          'where id = @id',
        ),
        parameters: {'v': await currentVersion(), 'id': _uidChildOutdated},
      ),
      throwsA(isA<Exception>()),
    );
  });
}
