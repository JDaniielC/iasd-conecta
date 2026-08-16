import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao`, tarefa 1.4 — teste de unidade das TRÊS
/// funções de acesso, isolado das policies de `mensagens`.
///
/// POR QUE ISOLADO, e é a razão de o arquivo existir junto de
/// `chat_acesso_grupo_test`/`chat_acesso_acao_test`, que já contam mensagens:
/// função e policy são DUAS barreiras. Um teste que só olha `count(*)` em
/// `mensagens` devolve o mesmo zero quando a função disse "não" e quando a
/// policy nem chamou a função — e as duas causas se consertam em lugares
/// diferentes. Aqui nenhuma linha de `mensagens` é criada: só
/// `select public.maior_de_idade()`,
/// `select public.pode_ver_chat_grupo(@g)` e
/// `select public.pode_ver_chat_acao(@a)`.
///
/// A MATRIZ, e o número real: 7 papéis × 3 idades = **21 credenciais**, cada
/// uma medida contra as 3 funções = **63 casos**. A idade multiplica tudo
/// porque `maior_de_idade()` está do lado de FORA do `or` das duas outras — é
/// a asserção que pega quem "uniformizar" as funções e mover o corte para
/// dentro de um braço só.
///
/// Os papéis, e o braço da função que cada um isola:
///   estranho       nenhum braço — o controle negativo
///   participante   `participacoes_grupo` em `pode_ver_chat_grupo`
///   dono           dono do Grupo DA AÇÃO em `pode_ver_chat_acao` (e o braço de
///                  participação no Grupo, que o gatilho de Dono lhe dá)
///   criador        `a.criador_id = auth.uid()`
///   confirmado     `confirmacoes_acao` com status `confirmado`
///   fila           `confirmacoes_acao` com status `fila` — a função não olha o
///                  status, e é isso que este papel prova
///   administrador  `administradores_distrito`, nos DOIS espaços
///
/// Dois cuidados na montagem, sem os quais um papel testaria o braço do vizinho:
/// a Ação do papel `dono` é criada por outra pessoa (senão ele seria criador
/// também), e a autoconfirmação que `acoes_criador_vira_confirmado` dá ao papel
/// `criador` é apagada (senão ele passaria pelo braço de confirmação).

/// A pessoa que monta o cenário. Não é credencial da matriz — só existe para
/// ser a dona do Grupo palco, a criadora da Ação palco e a criadora da Ação do
/// papel `dono`.
const _uidStage = 'cb000000-0000-0000-0000-0000000000ff';

/// Vagas da Ação palco: o gatilho já ocupa uma com quem criou, sobram três —
/// exatamente os três `confirmado` da matriz. Os três `fila` estouram o limite.
const _stageSlots = 4;

enum _Age { adult, minor, anonymized }

class _Role {
  const _Role(this.name, {required this.seesGroup, required this.seesAction});

  final String name;

  /// Esperado para a credencial ADULTA. Menor e anonimizada são falsas em
  /// todas as células, e é a matriz inteira que prova isso.
  final bool seesGroup;
  final bool seesAction;
}

const _roles = <_Role>[
  _Role('estranho', seesGroup: false, seesAction: false),
  _Role('participante do Grupo', seesGroup: true, seesAction: false),
  _Role('dono do Grupo', seesGroup: true, seesAction: true),
  _Role('criador da Ação', seesGroup: false, seesAction: true),
  _Role('confirmado na Ação', seesGroup: false, seesAction: true),
  // `fila` DEPOIS de `confirmado` na lista, e a ordem é significativa: a
  // montagem confirma nesta ordem, e é o que faz os três primeiros ocuparem as
  // vagas e os três seguintes caírem na fila.
  _Role('na fila da Ação', seesGroup: false, seesAction: true),
  _Role('Administrador do distrito', seesGroup: true, seesAction: true),
];

class _Credential {
  _Credential({required this.role, required this.age, required this.uid});

  final _Role role;
  final _Age age;
  final String uid;

  late String groupTarget;
  late String actionTarget;

  bool get isOfAge => age == _Age.adult;
  bool get expectsGroup => isOfAge && role.seesGroup;
  bool get expectsAction => isOfAge && role.seesAction;

  String get label => '${role.name} · ${_ageLabels[age]}';
}

const _ageLabels = {
  _Age.adult: '30 anos',
  _Age.minor: '17 anos',
  _Age.anonymized: 'idade nula (anonimizado)',
};

void main() {
  late Connection conn;
  late String stageGroupId;
  late String stageActionId;

  final credentials = <_Credential>[];
  var nextId = 1;
  for (final role in _roles) {
    for (final age in _Age.values) {
      final suffix = nextId.toRadixString(16).padLeft(2, '0');
      nextId++;
      credentials.add(
        _Credential(
          role: role,
          age: age,
          uid: 'cb000000-0000-0000-0000-0000000000$suffix',
        ),
      );
    }
  }

  /// Criados para os papéis que precisam de espaço próprio. Guardados para a
  /// limpeza, que não pode apagar por padrão — outro arquivo casaria.
  final ownGroupIds = <String>[];
  final ownActionIds = <String>[];
  final roundIds = <String>[];

  Future<void> confirmPresence(String uid, String actionId) =>
      asUser(conn, uid, () async {
        await conn.execute(
          Sql.named(
            'insert into public.confirmacoes_acao (acao_id, usuario_id) '
            'values (@a, @u)',
          ),
          parameters: {'a': actionId, 'u': uid},
        );
      });

  Future<String> statusOf(String uid, String actionId) async {
    final r = await conn.execute(
      Sql.named(
        'select status from public.confirmacoes_acao '
        'where acao_id = @a and usuario_id = @u',
      ),
      parameters: {'a': actionId, 'u': uid},
    );
    return r.single.toColumnMap()['status']! as String;
  }

  setUpAll(() async {
    conn = await openTestConnection();

    await createTestProfileWithAge(conn, _uidStage, name: 'Palco CB', age: 40);
    for (final c in credentials) {
      await createTestProfileWithAge(
        conn,
        c.uid,
        name: 'Pessoa ${c.uid.substring(30)}',
        // A credencial anonimizada nasce adulta e perde a idade no fim da
        // montagem: sem idade ela não entraria em Grupo nem confirmaria
        // presença, e o que se quer medir é a idade, não o cenário.
        age: c.age == _Age.minor ? 17 : 30,
      );
    }

    stageGroupId = await createGroup(
      conn,
      ownerId: _uidStage,
      name: 'Grupo palco CB',
    );
    final stage = await conn.execute(
      Sql.named(
        "insert into public.acoes (nome, data_hora, local, criador_id, "
        "limite_vagas) values ('Ação palco CB', now() + interval '5 days', "
        "'Sede', @c, $_stageSlots) returning id",
      ),
      parameters: {'c': _uidStage},
    );
    stageActionId = stage.single.toColumnMap()['id']! as String;

    for (final c in credentials) {
      c.groupTarget = stageGroupId;
      c.actionTarget = stageActionId;

      switch (c.role.name) {
        case 'participante do Grupo':
          await joinGroup(conn, stageGroupId, c.uid);
        case 'dono do Grupo':
          final ownGroup = await createGroup(
            conn,
            ownerId: c.uid,
            name: 'Grupo de ${c.uid.substring(30)} CB',
          );
          ownGroupIds.add(ownGroup);
          // A Ação é criada por OUTRA pessoa de propósito — ver o cabeçalho.
          await joinGroup(conn, ownGroup, _uidStage);
          final round = await createVotingRound(
            conn,
            groupId: ownGroup,
            openedBy: _uidStage,
          );
          roundIds.add(round);
          final ownAction = await createGroupAction(
            conn,
            creatorId: _uidStage,
            roundId: round,
            name: 'Ação do Grupo de ${c.uid.substring(30)} CB',
          );
          ownActionIds.add(ownAction);
          c.groupTarget = ownGroup;
          c.actionTarget = ownAction;
        case 'criador da Ação':
          final ownAction = await createLooseAction(
            conn,
            creatorId: c.uid,
            name: 'Ação de ${c.uid.substring(30)} CB',
          );
          ownActionIds.add(ownAction);
          // Apaga a autoconfirmação do gatilho — ver o cabeçalho.
          await conn.execute(
            Sql.named(
              'delete from public.confirmacoes_acao '
              'where acao_id = @a and usuario_id = @u',
            ),
            parameters: {'a': ownAction, 'u': c.uid},
          );
          c.actionTarget = ownAction;
        case 'confirmado na Ação':
        case 'na fila da Ação':
          await confirmPresence(c.uid, stageActionId);
        case 'Administrador do distrito':
          await createTestDistrictAdmin(conn, c.uid);
      }
    }

    await conn.execute(
      Sql.named(
        'update public.perfis set idade = null, anonimizado_em = now() '
        'where id = any(@us::uuid[])',
      ),
      parameters: {
        'us': credentials
            .where((c) => c.age == _Age.anonymized)
            .map((c) => c.uid)
            .toList(),
      },
    );
  });

  tearDownAll(() async {
    final actions = [stageActionId, ...ownActionIds];
    await conn.execute(
      Sql.named(
        'delete from public.confirmacoes_acao where acao_id = any(@as::uuid[])',
      ),
      parameters: {'as': actions},
    );
    await conn.execute(
      Sql.named(
        'update public.rodadas_votacao set vencedora_id = null '
        'where id = any(@rs::uuid[])',
      ),
      parameters: {'rs': roundIds},
    );
    await conn.execute(
      Sql.named('delete from public.acoes where id = any(@as::uuid[])'),
      parameters: {'as': actions},
    );
    await conn.execute(
      Sql.named(
        'delete from public.rodadas_votacao where id = any(@rs::uuid[])',
      ),
      parameters: {'rs': roundIds},
    );
    await conn.execute(
      Sql.named('delete from public.grupos where id = any(@gs::uuid[])'),
      parameters: {
        'gs': [stageGroupId, ...ownGroupIds],
      },
    );
    await conn.execute(
      Sql.named(
        'delete from public.administradores_distrito '
        'where usuario_id = any(@us::uuid[])',
      ),
      parameters: {'us': credentials.map((c) => c.uid).toList()},
    );
    for (final c in credentials) {
      await cleanUpTestUser(conn, c.uid);
    }
    await cleanUpTestUser(conn, _uidStage);
    await conn.close();
  });

  test('a montagem produziu confirmado E fila, não seis confirmados', () async {
    // Sem esta asserção o papel `fila` viraria um segundo `confirmado` em
    // silêncio, e o braço que ele existe para provar — que a função NÃO olha o
    // status — ficaria sem teste, com a matriz toda verde.
    for (final c in credentials.where(
      (c) => c.role.name == 'confirmado na Ação',
    )) {
      expect(
        await statusOf(c.uid, stageActionId),
        'confirmado',
        reason: c.label,
      );
    }
    for (final c in credentials.where(
      (c) => c.role.name == 'na fila da Ação',
    )) {
      expect(await statusOf(c.uid, stageActionId), 'fila', reason: c.label);
    }
  });

  for (final c in credentials) {
    test(c.label, () async {
      await asUser(conn, c.uid, () async {
        expect(
          await isOfAge(conn),
          c.isOfAge,
          reason: 'maior_de_idade() — ${c.label}',
        );
        expect(
          await canSeeGroupChat(conn, c.groupTarget),
          c.expectsGroup,
          reason: 'pode_ver_chat_grupo() — ${c.label}',
        );
        expect(
          await canSeeActionChat(conn, c.actionTarget),
          c.expectsAction,
          reason: 'pode_ver_chat_acao() — ${c.label}',
        );
      });
    });
  }
}
