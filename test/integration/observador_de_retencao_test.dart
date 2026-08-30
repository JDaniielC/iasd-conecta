import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'db_test_helper.dart';

/// Change `observador-de-retencao` — o rastro em si, tarefas 3.1 a 3.8.
///
/// `execucoes_de_faxina` é GLOBAL, no mesmo sentido de `administradores_distrito`
/// e `mudancas`: `dart test` roda os arquivos em paralelo contra o mesmo
/// Postgres. Este arquivo evita colisão de duas formas —
///
///   - para provar o MECANISMO de registro (3.1/3.2/3.3/3.5/3.6), chama
///     `expurgar_mudancas()` e `expurgar_rastro()`, que hoje só ESTE arquivo
///     chama — nenhum outro toca essas duas funções;
///   - onde o valor importa (3.1/3.2/3.3), lê o RETORNO da própria chamada e
///     confere que é ele que foi persistido, em vez de assumir uma contagem
///     absoluta — o mesmo cuidado que `chat_expurgo_test.dart` documenta para
///     `expurgar_mensagens_de_acao()`, e pelo mesmo motivo: o número precisa
///     valer também na segunda rodada da suíte, sem reset entre elas.
///
/// 3.9 mora em `chat_expurgo_test.dart` (estendido, não substituído) e 3.6 em
/// `superficie_sem_sessao_test.dart` (a tabela entrou na lista existente).

const _uidAdmin = 'ab000000-0000-0000-0000-000000000001';
const _uidMember = 'ab000000-0000-0000-0000-000000000002';
const _uidActionOwner = 'ab000000-0000-0000-0000-000000000003';

/// Faxinas sintéticas, só deste arquivo — nunca colidem com as três reais
/// (`expurgar_mensagens_de_acao`, `expurgar_mudancas`, `expurgar_rastro`), que
/// outros arquivos também podem estar chamando ao mesmo tempo.
const _faxinaRastroVelha = 'teste_observador_rastro_velha';
const _faxinaRastroRecente = 'teste_observador_rastro_recente';

void main() {
  late Connection conn;
  final groupIds = <String>[];

  Future<int> countRows(String sql, Map<String, Object?> params) async {
    final r = await conn.execute(Sql.named(sql), parameters: params);
    return r.first[0]! as int;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfile(conn, _uidMember, name: 'Membro AB');
    await createTestProfile(conn, _uidActionOwner, name: 'Criador AB');
    await createTestProfile(conn, _uidAdmin, name: 'Admin AB');
    await createTestDistrictAdmin(conn, _uidAdmin);
  });

  tearDownAll(() async {
    for (final g in groupIds) {
      await conn.execute(
        Sql.named('delete from public.mudancas where grupo_id = @g'),
        parameters: {'g': g},
      );
      await conn.execute(
        Sql.named('delete from public.grupos where id = @g'),
        parameters: {'g': g},
      );
    }
    await conn.execute(
      Sql.named(
        'delete from public.execucoes_de_faxina where faxina like @p',
      ),
      parameters: {'p': 'teste_observador_%'},
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito where usuario_id = @u',
      ),
      parameters: {'u': _uidAdmin},
    );
    for (final uid in [_uidMember, _uidActionOwner, _uidAdmin]) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  group('3.1/3.2 — apaga linhas ou não, e as duas ficam registradas', () {
    test(
      'apagou: instante, quantidade e faxina batem com o retorno; '
      'nada a apagar: registra zero',
      () async {
        final group = await createGroup(
          conn,
          ownerId: _uidActionOwner,
          name: 'Grupo AB 3.1',
        );
        groupIds.add(group);
        // O Dono entra por gatilho (`registrar_mudanca_participacao`), então
        // já existe UMA linha em `mudancas` para este Grupo. Empurra ela para
        // fora do prazo de 90 dias.
        await conn.execute(
          Sql.named(
            "update public.mudancas set created_at = now() - interval '91 days' "
            'where grupo_id = @g',
          ),
          parameters: {'g': group},
        );

        final before = DateTime.now().toUtc();
        final r1 = await conn.execute(
          "select public.expurgar_mudancas() as n",
        );
        final deleted = r1.single.toColumnMap()['n']! as int;
        expect(
          deleted,
          greaterThanOrEqualTo(1),
          reason: 'a linha de 91 dias deste Grupo estava vencida',
        );

        expect(
          await countRows(
            'select count(*) from public.mudancas where grupo_id = @g',
            {'g': group},
          ),
          0,
          reason: 'a linha vencida saiu de verdade',
        );

        final row1 = await conn.execute(
          "select quantas, disparada_por, quando "
          "from public.execucoes_de_faxina "
          "where faxina = 'expurgar_mudancas' order by quando desc limit 1",
        );
        final m1 = row1.single.toColumnMap();
        expect(
          m1['quantas'],
          deleted,
          reason: 'a linha registrada é a MESMA execução que acabou de rodar',
        );
        expect(
          (m1['quando']! as DateTime).isAfter(
            before.subtract(const Duration(seconds: 2)),
          ),
          isTrue,
          reason: 'o instante registrado é desta chamada, não de uma antiga',
        );

        // Rodando de novo, imediatamente: nada mais está vencido — "rodou e
        // não havia nada" precisa ficar registrado com ZERO, não silêncio.
        final r2 = await conn.execute(
          "select public.expurgar_mudancas() as n",
        );
        expect(r2.single.toColumnMap()['n'], 0);

        final row2 = await conn.execute(
          "select quantas from public.execucoes_de_faxina "
          "where faxina = 'expurgar_mudancas' order by quando desc limit 1",
        );
        expect(
          row2.single.toColumnMap()['quantas'],
          0,
          reason: '"rodou sem nada a apagar" tem que ser distinguível de '
              '"não rodou" — a linha existe, e diz zero',
        );
      },
    );
  });

  test('3.3 — disparada_por distingue cron de app, mesma faxina', () async {
    await conn.execute("select public.expurgar_mudancas('cron')");
    final cronRow = await conn.execute(
      "select disparada_por from public.execucoes_de_faxina "
      "where faxina = 'expurgar_mudancas' order by quando desc limit 1",
    );
    expect(cronRow.single.toColumnMap()['disparada_por'], 'cron');

    await conn.execute("select public.expurgar_mudancas('app')");
    final appRow = await conn.execute(
      "select disparada_por from public.execucoes_de_faxina "
      "where faxina = 'expurgar_mudancas' order by quando desc limit 1",
    );
    expect(appRow.single.toColumnMap()['disparada_por'], 'app');
  });

  test(
    '3.4 — registro que falha (constraint de disparada_por) não desfaz o delete',
    () async {
      final group = await createGroup(
        conn,
        ownerId: _uidActionOwner,
        name: 'Grupo AB 3.4',
      );
      groupIds.add(group);
      await conn.execute(
        Sql.named(
          "update public.mudancas set created_at = now() - interval '91 days' "
          'where grupo_id = @g',
        ),
        parameters: {'g': group},
      );

      // `disparada_por` só aceita 'cron'/'app' — este valor violando o CHECK
      // é como se quebra o registro DE VERDADE, pela superfície pública, sem
      // precisar revogar nem renomear nada.
      await conn.execute(
        "select public.expurgar_mudancas('nem-cron-nem-app')",
      );

      expect(
        await countRows(
          'select count(*) from public.mudancas where grupo_id = @g',
          {'g': group},
        ),
        0,
        reason: 'o delete já tinha acontecido quando o insert do registro '
            'falhou — a faxina não depende do rastro',
      );

      expect(
        await countRows(
          "select count(*) from public.execucoes_de_faxina "
          "where disparada_por = 'nem-cron-nem-app'",
          {},
        ),
        0,
        reason: 'o CHECK impede este valor de existir — se apareceu, o '
            '`exception when others` parou de engolir o erro',
      );
    },
  );

  group('3.5 — só o Administrador do distrito lê o rastro', () {
    test('Participante comum recebe zero linhas', () async {
      final rows = await asUser(
        conn,
        _uidMember,
        () => conn.execute('select * from public.execucoes_de_faxina'),
      );
      expect(rows, isEmpty);
    });

    test('Administrador do distrito recebe as linhas', () async {
      // Garante que existe ao menos uma linha antes de conferir a visão do
      // Administrador — as chamadas de 3.1/3.3 já deixaram, mas este teste
      // não deve depender da ordem de execução dos outros.
      await conn.execute("select public.expurgar_mudancas()");

      final rows = await asUser(
        conn,
        _uidAdmin,
        () => conn.execute('select * from public.execucoes_de_faxina limit 1'),
      );
      expect(rows, isNotEmpty);
    });
  });

  test(
    '3.7 — expurgo do rastro apaga o velho e preserva a mais recente de cada '
    'faxina, mesmo quando ela também já venceu',
    () async {
      // Faxina X: duas linhas, as DUAS vencidas (> 30 dias). A mais recente
      // das duas tem que sobreviver mesmo assim — é a exceção da tarefa 2.4.
      final oldest = await conn.execute(
        Sql.named(
          "insert into public.execucoes_de_faxina "
          "(faxina, quando, quantas, disparada_por) "
          "values (@f, now() - interval '60 days', 1, 'cron') returning id",
        ),
        parameters: {'f': _faxinaRastroVelha},
      );
      final oldestId = oldest.single.toColumnMap()['id']! as String;
      final newestOfOld = await conn.execute(
        Sql.named(
          "insert into public.execucoes_de_faxina "
          "(faxina, quando, quantas, disparada_por) "
          "values (@f, now() - interval '40 days', 2, 'cron') returning id",
        ),
        parameters: {'f': _faxinaRastroVelha},
      );
      final newestOfOldId = newestOfOld.single.toColumnMap()['id']! as String;

      // Faxina Y: uma linha recente (fica pela idade) e uma velha que NÃO é a
      // mais recente (some pela idade).
      final recent = await conn.execute(
        Sql.named(
          "insert into public.execucoes_de_faxina "
          "(faxina, quando, quantas, disparada_por) "
          "values (@f, now() - interval '5 days', 3, 'app') returning id",
        ),
        parameters: {'f': _faxinaRastroRecente},
      );
      final recentId = recent.single.toColumnMap()['id']! as String;
      final oldButNotLatest = await conn.execute(
        Sql.named(
          "insert into public.execucoes_de_faxina "
          "(faxina, quando, quantas, disparada_por) "
          "values (@f, now() - interval '40 days', 4, 'app') returning id",
        ),
        parameters: {'f': _faxinaRastroRecente},
      );
      final oldButNotLatestId =
          oldButNotLatest.single.toColumnMap()['id']! as String;

      Future<bool> exists(String id) async {
        final r = await conn.execute(
          Sql.named(
            'select 1 from public.execucoes_de_faxina where id = @id',
          ),
          parameters: {'id': id},
        );
        return r.isNotEmpty;
      }

      await conn.execute('select public.expurgar_rastro()');

      expect(
        await exists(oldestId),
        isFalse,
        reason: 'velha e NÃO é a mais recente da sua faxina',
      );
      expect(
        await exists(newestOfOldId),
        isTrue,
        reason: 'velha, mas É a mais recente — sem ela ninguém distingue '
            '"parada há muito tempo" de "nunca rodou"',
      );
      expect(await exists(recentId), isTrue, reason: 'dentro do prazo');
      expect(
        await exists(oldButNotLatestId),
        isFalse,
        reason: 'velha e superada pela linha recente da mesma faxina',
      );
    },
  );

  test(
    '3.8 — expurgar_mudancas() apaga o vencido (91 dias) e mantém o recente',
    () async {
      final groupOld = await createGroup(
        conn,
        ownerId: _uidActionOwner,
        name: 'Grupo AB 3.8 velho',
      );
      final groupRecent = await createGroup(
        conn,
        ownerId: _uidActionOwner,
        name: 'Grupo AB 3.8 recente',
      );
      groupIds.addAll([groupOld, groupRecent]);

      await conn.execute(
        Sql.named(
          "update public.mudancas set created_at = now() - interval '91 days' "
          'where grupo_id = @g',
        ),
        parameters: {'g': groupOld},
      );
      // O de `groupRecent` fica com o `created_at` real do gatilho — poucos
      // segundos atrás, bem dentro dos 90 dias.

      await conn.execute('select public.expurgar_mudancas()');

      expect(
        await countRows(
          'select count(*) from public.mudancas where grupo_id = @g',
          {'g': groupOld},
        ),
        0,
      );
      expect(
        await countRows(
          'select count(*) from public.mudancas where grupo_id = @g',
          {'g': groupRecent},
        ),
        1,
        reason: 'dentro do prazo, continua existindo e continua aparecendo '
            'para quem lê o histórico do Grupo',
      );
    },
  );
}
