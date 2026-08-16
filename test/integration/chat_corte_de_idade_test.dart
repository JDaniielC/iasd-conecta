import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'acao_restrita_helper.dart';
import 'chat_helper.dart';
import 'db_test_helper.dart';

/// Change `chat-de-grupo-e-acao` — o corte de 18 anos vale no BANCO.
///
/// Quatro credenciais, e cada uma falha por um motivo diferente:
///   17 anos      -> tem Perfil, tem idade, idade < 18
///   18 anos      -> passa
///   Visitante    -> sessão anônima SEM Perfil: a consulta não acha linha
///   anonimizado  -> tem Perfil, mas `idade` virou nula, e `null >= 18` é NULL
///
/// O último é o que justifica o `idade is not null` explícito na função. Dentro
/// de `exists` daria no mesmo; escrito é o que se lê numa revisão — e é o caso
/// que uma pessoa apressada removeria por achar redundante.

const _uidOwner = 'ab000000-0000-0000-0000-000000000001';
const _uid17 = 'ab000000-0000-0000-0000-000000000002';
const _uid18 = 'ab000000-0000-0000-0000-000000000003';
const _uidAnonymized = 'ab000000-0000-0000-0000-000000000004';

/// Visitante: sem cadastro, e por isso sem linha em `perfis`. Tem sessão.
const _uidVisitor = 'ab000000-0000-0000-0000-0000000000f0';
const _allUids = [_uidOwner, _uid17, _uid18, _uidAnonymized];

void main() {
  late Connection conn;
  late String groupId;

  setUpAll(() async {
    conn = await openTestConnection();
    await createTestProfileWithAge(conn, _uidOwner, name: 'Dona AB', age: 40);
    await createTestProfileWithAge(conn, _uid17, name: 'Quase AB', age: 17);
    await createTestProfileWithAge(conn, _uid18, name: 'Recem AB', age: 18);
    await createTestProfileWithAge(
      conn,
      _uidAnonymized,
      name: 'Vai Sair AB',
      age: 30,
    );

    await createTestVisitor(conn, _uidVisitor);

    groupId = await createGroup(conn, ownerId: _uidOwner, name: 'Grupo AB');
    for (final uid in [_uid17, _uid18, _uidAnonymized]) {
      await joinGroup(conn, groupId, uid);
    }
    await seedMessage(conn, authorId: _uidOwner, groupId: groupId);
  });

  tearDownAll(() async {
    await clearGroupChat(conn, groupId);
    await conn.execute(
      Sql.named('delete from public.grupos where id = @g'),
      parameters: {'g': groupId},
    );
    // FORA de `_allUids` de propósito: em outros arquivos uma lista com esse
    // nome ALIMENTA `createTestProfile`, e Visitante é justamente quem não tem
    // Perfil. Mesmo nome, dois contratos — a limpeza dele vem à parte.
    await cleanUpTestUser(conn, _uidVisitor);
    for (final uid in _allUids) {
      await cleanUpTestUser(conn, uid);
    }
    await conn.close();
  });

  test('17 anos não lê e não escreve, mesmo participando do Grupo', () async {
    expect(await asUser(conn, _uid17, () => isOfAge(conn)), isFalse);
    expect(
      await asUser(
        conn,
        _uid17,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
    );
    Object? error;
    try {
      await asUser(
        conn,
        _uid17,
        () => writeMessage(conn, authorId: _uid17, groupId: groupId),
      );
    } catch (e) {
      error = e;
    }
    expect(error, isA<ServerException>());
  });

  test('18 anos lê e escreve', () async {
    expect(await asUser(conn, _uid18, () => isOfAge(conn)), isTrue);
    expect(
      await asUser(
        conn,
        _uid18,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      greaterThan(0),
    );
    final id = await asUser(
      conn,
      _uid18,
      () => writeMessage(conn, authorId: _uid18, groupId: groupId, text: 'oi'),
    );
    expect(id, isNotEmpty);
  });

  test('Visitante sem cadastro não passa no corte, e lê 0', () async {
    // ESTE é o Visitante do app: sem cadastro, mas COM sessão —
    // `signInAnonymously` no arranque. Até 2026-08-16 este arquivo o
    // representava como `anon`, que é a requisição sem credencial nenhuma, e
    // com isso o cenário "Visitante abre um Grupo" nunca teve prova: o que se
    // media era o `grant`, não a regra.
    //
    // Ele chega à função e à policy, e as duas respondem NÃO — sem linha em
    // `perfis` não há idade, e `maior_de_idade()` é falso. É "consultei e você
    // não tem idade", que é diferente de "você não pergunta" (ver o teste
    // seguinte).
    expect(
      await asVisitor(conn, _uidVisitor, () => isOfAge(conn)),
      isFalse,
      reason: 'sem Perfil não há idade, e o corte falha fechado',
    );
    expect(
      await asVisitor(
        conn,
        _uidVisitor,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
      reason: 'a policy filtra, e a resposta é lista vazia — não erro',
    );
  });

  test('sem sessão nenhuma — nem chama, nem lê', () async {
    // Este teste esperava `false` de `maior_de_idade()` até 2026-08-14. Agora
    // espera RECUSA, e a mudança é a correção do achado do `pentest-etico`: as
    // funções da change tinham `execute` para `PUBLIC` — o padrão do Postgres
    // para função nova —, então `anon` chamava todas. O `revoke ... from
    // public` fechou isso, e a resposta deixou de ser "não" e passou a ser
    // "você não pergunta".
    //
    // A distinção importa, e é a razão de este teste ser IRMÃO do de cima em
    // vez de o mesmo: `false` significa "consultei e você não tem idade"; a
    // exceção significa que a barreira está uma camada antes. Quem afrouxar o
    // revoke por engano faz este teste voltar a ver `false`, que é o sinal —
    // e o de cima continua verde, porque ele mede outra coisa.
    Object? ageError;
    try {
      await asAnon(conn, () => isOfAge(conn));
    } catch (e) {
      ageError = e;
    }
    expect(ageError, isA<ServerException>());

    // Sem sessão também não há grant em `mensagens`, então nem chega à policy.
    Object? error;
    try {
      await asAnon(conn, () => visibleMessageCount(conn, groupId: groupId));
    } catch (e) {
      error = e;
    }
    expect(error, isA<ServerException>());
  });

  test('Perfil anonimizado lê 0 — idade nula não é maioridade', () async {
    await conn.execute(
      Sql.named(
        'update public.perfis set idade = null, anonimizado_em = now() where id = @u',
      ),
      parameters: {'u': _uidAnonymized},
    );
    expect(await asUser(conn, _uidAnonymized, () => isOfAge(conn)), isFalse);
    expect(
      await asUser(
        conn,
        _uidAnonymized,
        () => visibleMessageCount(conn, groupId: groupId),
      ),
      0,
    );
  });
}
