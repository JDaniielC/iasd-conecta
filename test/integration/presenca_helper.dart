import 'package:postgres/postgres.dart';

import 'acao_restrita_helper.dart';

/// Ferramentas comuns aos testes da change `presenca-em-acao`.
///
/// Todas as escritas passam por [asUser] de propósito: quem roda como
/// `postgres` é dono das tabelas, ignora RLS, e provaria exatamente nada sobre
/// as policies que esta change existe para criar. O que roda como `postgres`
/// aqui é só semeadura — criar a Ação e a confirmação que a policy vai julgar
/// depois.

/// Cria uma Ação que **já aconteceu**, que é a única sobre a qual faz sentido
/// afirmar comparecimento.
Future<String> createPastAction(
  Connection conn, {
  required String creatorId,
  String name = 'Ação passada de teste',
  String interval = "interval '-2 days'",
}) => createLooseAction(
  conn,
  creatorId: creatorId,
  name: name,
  interval: interval,
);

/// Semeia a confirmação (a INTENÇÃO), que é o que existia antes desta change.
///
/// Semeado como `postgres`: o alvo do teste é a policy de comparecimento, não a
/// de confirmação, que já tem cobertura própria desde a feature 004.
Future<void> seedConfirmation(
  Connection conn,
  String actionId,
  String userId,
) async {
  await conn.execute(
    Sql.named(
      'insert into public.confirmacoes_acao (acao_id, usuario_id) '
      'values (@acao, @usuario) on conflict do nothing',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
}

/// Marca comparecimento como [markerId] faria pelo app, e devolve quantas
/// linhas a escrita alcançou.
///
/// A asserção de recusa desta change é `affectedRows == 0`, nunca exceção: uma
/// policy que recusa faz a linha não existir para aquela sessão, e o `update`
/// volta com sucesso sobre nada (`CLAUDE.md`, "Recusa de RLS é ausência, não
/// erro").
///
/// O cliente manda o campo como SINAL; o VALOR é o `now()` do banco e o autor é
/// o `auth.uid()` da sessão, ambos carimbados por gatilho. Mesmo contrato de
/// `perfis_carimbar_consentimento`.
Future<int> markAttendance(
  Connection conn, {
  required String actionId,
  required String userId,
  required String markerId,
}) => asUser(conn, markerId, () async {
  final r = await conn.execute(
    Sql.named(
      'update public.confirmacoes_acao set compareceu_em = now() '
      'where acao_id = @acao and usuario_id = @usuario',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
  return r.affectedRows;
});

/// Desmarca comparecimento — o campo nulo é a ausência de sinal.
Future<int> unmarkAttendance(
  Connection conn, {
  required String actionId,
  required String userId,
  required String markerId,
}) => asUser(conn, markerId, () async {
  final r = await conn.execute(
    Sql.named(
      'update public.confirmacoes_acao set compareceu_em = null '
      'where acao_id = @acao and usuario_id = @usuario',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
  return r.affectedRows;
});

/// Lê o estado de comparecimento direto da tabela, sem RLS.
///
/// Ler como `postgres` é deliberado: a pergunta aqui é "o que ficou gravado",
/// e não "o que a sessão enxerga". Quem prova o segundo é o teste de alcance.
Future<({DateTime? attendedAt, String? markedBy, DateTime? disputedAt})>
attendanceOf(Connection conn, String actionId, String userId) async {
  final r = await conn.execute(
    Sql.named(
      'select compareceu_em, marcado_por, contestada_em '
      'from public.confirmacoes_acao '
      'where acao_id = @acao and usuario_id = @usuario',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
  final row = r.single.toColumnMap();
  return (
    attendedAt: row['compareceu_em'] as DateTime?,
    markedBy: row['marcado_por'] as String?,
    disputedAt: row['contestada_em'] as DateTime?,
  );
}

/// Fecha a lista de comparecimento como [closerId] faria, e devolve quantas
/// linhas a escrita alcançou.
Future<int> closeAttendanceList(
  Connection conn, {
  required String actionId,
  required String closerId,
}) => asUser(conn, closerId, () async {
  final r = await conn.execute(
    Sql.named(
      'update public.acoes set presenca_fechada_em = now() where id = @acao',
    ),
    parameters: {'acao': actionId},
  );
  return r.affectedRows;
});

/// Lê o estado de fechamento da Ação, sem RLS.
Future<({DateTime? closedAt, int? presentAtClosing})> closingOf(
  Connection conn,
  String actionId,
) async {
  final r = await conn.execute(
    Sql.named(
      'select presenca_fechada_em, presentes_no_fechamento '
      'from public.acoes where id = @acao',
    ),
    parameters: {'acao': actionId},
  );
  final row = r.single.toColumnMap();
  return (
    closedAt: row['presenca_fechada_em'] as DateTime?,
    presentAtClosing: row['presentes_no_fechamento'] as int?,
  );
}

/// Força a versão do aceite de um Perfil, para simular quem está defasado.
///
/// `perfis_carimbar_consentimento` impede escrever essa coluna por fora — é o
/// que evita backfill fabricado pelo cliente, e está certo. Para o teste, o
/// gatilho é desligado **só nesta sessão** com `session_replication_role`.
///
/// NÃO usar `alter table ... disable trigger` aqui, ao contrário de
/// `createTestDistrictAdmin`: aquilo é global e toma ACCESS EXCLUSIVE em
/// `perfis`, que praticamente todo arquivo da suíte usa — a suíte roda em
/// paralelo, e isso serializaria tudo, quando não travasse.
Future<void> setConsentVersion(
  Connection conn,
  String uid,
  String? version,
) async {
  await conn.execute('set session_replication_role = replica');
  try {
    await conn.execute(
      Sql.named(
        'update public.perfis set consentimento_lgpd_versao = @v where id = @id',
      ),
      parameters: {'v': version, 'id': uid},
    );
  } finally {
    await conn.execute('set session_replication_role = origin');
  }
}

/// Reaceita o texto legal vigente, como a pessoa faria pelo app.
///
/// O cliente manda o SINAL em `consentimento_lgpd_aceito_em`; o gatilho carimba
/// `now()` e `versao_texto_legal_vigente()`.
Future<int> reacceptLegalText(Connection conn, String uid) =>
    asUser(conn, uid, () async {
      final r = await conn.execute(
        Sql.named(
          'update public.perfis set consentimento_lgpd_aceito_em = now() '
          'where id = @id',
        ),
        parameters: {'id': uid},
      );
      return r.affectedRows;
    });

/// Lê a versão do aceite direto da tabela, sem RLS.
Future<String?> consentVersionOf(Connection conn, String uid) async {
  final r = await conn.execute(
    Sql.named(
      'select consentimento_lgpd_versao from public.perfis where id = @id',
    ),
    parameters: {'id': uid},
  );
  return r.single.toColumnMap()['consentimento_lgpd_versao'] as String?;
}

/// Contesta a marca feita sobre si, como [userId] faria pelo app.
///
/// Devolve quantas linhas a escrita alcançou. Zero é a recusa — nunca exceção.
Future<int> disputeAttendance(
  Connection conn, {
  required String actionId,
  required String userId,
  String? asWhom,
}) => asUser(conn, asWhom ?? userId, () async {
  final r = await conn.execute(
    Sql.named(
      'insert into public.contestacoes_presenca (acao_id, usuario_id) '
      'values (@acao, @usuario) on conflict do nothing',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
  return r.affectedRows;
});

/// Decide a contestação, como quem criou a Ação faria.
///
/// [decision] é `mantida` ou `desfeita` — chave de banco, portanto em
/// português, como manda a fronteira de idioma de `CONTEXT.md`.
Future<int> decideDispute(
  Connection conn, {
  required String actionId,
  required String userId,
  required String deciderId,
  required String decision,
}) => asUser(conn, deciderId, () async {
  final r = await conn.execute(
    Sql.named(
      'update public.contestacoes_presenca set decisao = @decisao '
      'where acao_id = @acao and usuario_id = @usuario',
    ),
    parameters: {
      'acao': actionId,
      'usuario': userId,
      'decisao': decision,
    },
  );
  return r.affectedRows;
});

/// Lê a contestação direto da tabela, sem RLS.
Future<({DateTime? disputedAt, String? decision, String? decidedBy})?>
disputeOf(Connection conn, String actionId, String userId) async {
  final r = await conn.execute(
    Sql.named(
      'select contestada_em, decisao, decidida_por '
      'from public.contestacoes_presenca '
      'where acao_id = @acao and usuario_id = @usuario',
    ),
    parameters: {'acao': actionId, 'usuario': userId},
  );
  if (r.isEmpty) return null;
  final row = r.single.toColumnMap();
  return (
    disputedAt: row['contestada_em'] as DateTime?,
    decision: row['decisao'] as String?,
    decidedBy: row['decidida_por'] as String?,
  );
}

/// Lê `public.presencas_computaveis` para uma Ação, com a identidade de
/// [readerId].
///
/// A view é o único lugar que define "esta linha conta" (design D-009). Ela é
/// `security_invoker`, então o que sai daqui depende da RLS de
/// `confirmacoes_acao` para aquela sessão — ler como `postgres` provaria nada.
Future<List<({String userId, bool present})>> computableRowsFor(
  Connection conn, {
  required String actionId,
  required String readerId,
}) => asUser(conn, readerId, () async {
  final r = await conn.execute(
    Sql.named(
      'select usuario_id, presente from public.presencas_computaveis '
      'where acao_id = @acao order by usuario_id',
    ),
    parameters: {'acao': actionId},
  );
  return [
    for (final row in r)
      (
        userId: row.toColumnMap()['usuario_id']! as String,
        present: row.toColumnMap()['presente']! as bool,
      ),
  ];
});

/// Cancela a Ação sem passar pela tela — semeadura, não exercício de policy.
Future<void> cancelAction(Connection conn, String actionId) async {
  await conn.execute(
    Sql.named('update public.acoes set cancelada_em = now() where id = @acao'),
    parameters: {'acao': actionId},
  );
}

/// Apaga tudo o que os testes desta change criam, escopado pelos UUIDs do
/// próprio arquivo.
///
/// Nunca apagar por padrão que outro arquivo possa casar: `dart test` roda os
/// arquivos em paralelo contra o mesmo Postgres.
Future<void> cleanUpPresenceFixtures(
  Connection conn,
  List<String> uids,
) async {
  await conn.execute(
    Sql.named(
      'delete from public.contestacoes_presenca '
      'where usuario_id = any(@ids::uuid[])',
    ),
    parameters: {'ids': uids},
  );
  // A ORDEM IMPORTA, e a primeira linha é a menos óbvia.
  // `rodadas_votacao.vencedora_id` aponta para `acoes`, e `acoes.rodada_id`
  // aponta de volta para `rodadas_votacao`. Apagar a Ação vencedora antes de
  // soltar o ponteiro viola a FK; apagar a Rodada antes viola a outra. Soltar
  // o ponteiro primeiro desfaz o ciclo.
  await conn.execute(
    Sql.named(
      'update public.rodadas_votacao set vencedora_id = null '
      'where aberta_por = any(@ids::uuid[])',
    ),
    parameters: {'ids': uids},
  );
  await conn.execute(
    Sql.named(
      'delete from public.acoes where criador_id = any(@ids::uuid[])',
    ),
    parameters: {'ids': uids},
  );
  await conn.execute(
    Sql.named(
      'delete from public.rodadas_votacao where aberta_por = any(@ids::uuid[])',
    ),
    parameters: {'ids': uids},
  );
  await conn.execute(
    Sql.named('delete from public.grupos where dono_id = any(@ids::uuid[])'),
    parameters: {'ids': uids},
  );
}
