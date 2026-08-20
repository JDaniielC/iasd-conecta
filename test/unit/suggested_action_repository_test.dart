import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/suggested_action/data/suggested_action_repository.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Change `cobertura-e-tdd`, convergência C1.1.
///
/// `delete` mandava `.delete().eq('id', id)` sem `.select()`, e por isso
/// reportava sucesso sobre zero linhas. Medido contra o Postgres local, sob
/// `authenticated` sem privilégio: `DELETE 0`, sem exceção, linha intacta —
/// ver `test/integration/acao_sugerida_remocao_test.dart`.
///
/// A cadeia do PostgREST é fingida à mão, e não com `mocktail`, porque
/// `PostgrestTransformBuilder` implementa `Future` — mockar `then` dá um teste
/// que prova o mock, não o repositório. Estes fakes só respondem o que a
/// cadeia real responderia, e nada mais.

class _FakeTransform extends Fake
    implements PostgrestTransformBuilder<PostgrestList> {
  _FakeTransform(this._rows);

  final PostgrestList _rows;

  @override
  Future<R> then<R>(
    FutureOr<R> Function(PostgrestList) onValue, {
    Function? onError,
  }) =>
      Future<PostgrestList>.value(_rows).then(onValue, onError: onError);
}

class _FakeFilter extends Fake implements PostgrestFilterBuilder<PostgrestList> {
  _FakeFilter(this._rows);

  final PostgrestList _rows;

  /// Listas em vez de campos mutáveis: `PostgrestBuilder` é `@immutable`, e um
  /// `bool` reatribuível herda o aviso do analisador.
  final List<(String, Object)> eqCalls = [];
  final List<String> selectCalls = [];

  @override
  PostgrestFilterBuilder<PostgrestList> eq(String column, Object value) {
    eqCalls.add((column, value));
    return this;
  }

  @override
  PostgrestTransformBuilder<PostgrestList> select([String columns = '*']) {
    selectCalls.add(columns);
    return _FakeTransform(_rows);
  }

  /// Awaitar o filtro direto é o que o código fazia ANTES do conserto — sem
  /// `.select()`, o `delete` volta com sucesso sem dizer quantas linhas
  /// afetou. Falhar aqui com a frase certa evita que o vermelho pareça um
  /// defeito do fake.
  @override
  Future<R> then<R>(
    FutureOr<R> Function(PostgrestList) onValue, {
    Function? onError,
  }) =>
      throw StateError(
        'o delete foi aguardado sem `.select()` — nada informa quantas linhas '
        'foram afetadas, e a recusa da policy passaria como sucesso',
      );
}

class _FakeQueryBuilder extends Fake implements SupabaseQueryBuilder {
  _FakeQueryBuilder(this.filter);

  final _FakeFilter filter;
  final List<String> deleteCalls = [];

  @override
  PostgrestFilterBuilder<PostgrestList> delete() {
    deleteCalls.add('delete');
    return filter;
  }
}

class _FakeClient extends Fake implements SupabaseClient {
  _FakeClient(this.queryBuilder);

  final _FakeQueryBuilder queryBuilder;
  final List<String> tables = [];

  @override
  SupabaseQueryBuilder from(String table) {
    tables.add(table);
    return queryBuilder;
  }
}

({SuggestedActionRepository repository, _FakeClient client, _FakeFilter filter})
    build(PostgrestList rowsAffected) {
  final filter = _FakeFilter(rowsAffected);
  final client = _FakeClient(_FakeQueryBuilder(filter));
  return (
    repository: SuggestedActionRepository(client),
    client: client,
    filter: filter,
  );
}

void main() {
  group('SuggestedActionRepository.delete', () {
    test('remove a linha certa da tabela certa', () async {
      final f = build([
        {'id': 's1'},
      ]);

      await f.repository.delete('s1');

      expect(f.client.tables, ['acoes_sugeridas']);
      expect(f.client.queryBuilder.deleteCalls, hasLength(1));
      expect(f.filter.eqCalls, [('id', 's1')]);
    });

    test('pede as linhas de volta — sem isso não dá pra saber se afetou alguma',
        () async {
      final f = build([
        {'id': 's1'},
      ]);

      await f.repository.delete('s1');

      expect(
        f.filter.selectCalls,
        isNotEmpty,
        reason: 'a policy que recusa não levanta exceção; quem denuncia a '
            'recusa é a lista de linhas afetadas vir vazia',
      );
    });

    test('zero linhas afetadas levanta, em vez de reportar sucesso sobre nada',
        () async {
      final f = build(const []);

      await expectLater(
        f.repository.delete('s1'),
        throwsA(
          isA<StateError>().having(
            (e) => e.message,
            'message',
            contains('Não deu pra remover'),
          ),
        ),
        reason: 'é a frase que a tela mostra, em vez de recarregar a lista com '
            'a sugestão ainda nela',
      );
    });
  });
}
