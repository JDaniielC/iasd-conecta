import 'package:postgres/postgres.dart';
import 'package:test/test.dart';

import 'db_test_helper.dart';

/// Change `filtro-e-intervalo-de-mensagem`, tarefas 1.3 e 1.4 — a REGRA DE
/// CASAMENTO, isolada do gatilho.
///
/// Separado de `filtro_palavra_mensagem_test.dart` de propósito: lá se prova
/// que a mensagem é recusada, aqui se prova QUANDO a palavra casa. Um teste que
/// só olhasse a recusa passaria com um casamento por trecho — que é exatamente
/// o desenho que esta change trocou.
///
/// A diferença deliberada em relação a `nome_valido()`, que casa por trecho
/// (`20260806090000_nome_valido_security_definer.sql:38-41`): num nome de
/// cadastro, trecho é a regra certa; em texto corrido, produz recusa que
/// ninguém entende.
///
/// ISOLAMENTO NA SUÍTE PARALELA. `palavras_bloqueadas_mensagem` é tabela
/// GLOBAL, como `palavras_bloqueadas` — a palavra é a chave primária, não há
/// como escopar por UUID. Os arquivos que a semeiam tomam um lock consultivo de
/// sessão, mesmo mecanismo e mesmo motivo de `createTestDistrictAdmin`
/// (`db_test_helper.dart`): sem ele, um arquivo apagaria a palavra que o outro
/// acabou de inserir.

/// As palavras que este arquivo insere. Escolhidas para NÃO colidirem com a
/// lista de nomes (`palavras_bloqueadas`), que é outra tabela — a prova de que
/// as duas são independentes está em `filtro_palavra_mensagem_test.dart`.
const _blocked = 'xatoxo';
const _blockedWithAccent = 'xatôxa';

void main() {
  late Connection conn;

  Future<String?> matchedIn(String? text) async {
    final r = await conn.execute(
      Sql.named('select public.palavra_bloqueada_em(@t) as p'),
      parameters: {'t': text},
    );
    return r.single.toColumnMap()['p'] as String?;
  }

  setUpAll(() async {
    conn = await openTestConnection();
    await lockBlockedWordList(conn);
    await conn.execute(
      Sql.named(
        'insert into public.palavras_bloqueadas_mensagem (palavra) '
        'values (@a), (@b) on conflict do nothing',
      ),
      parameters: {'a': _blocked, 'b': _blockedWithAccent},
    );
  });

  tearDownAll(() async {
    await conn.execute(
      Sql.named(
        'delete from public.palavras_bloqueadas_mensagem '
        'where palavra = any(@ps::text[])',
      ),
      parameters: {
        'ps': [_blocked, _blockedWithAccent],
      },
    );
    await conn.close();
  });

  group('1.3 — a palavra é INTEIRA', () {
    test('palavra isolada casa, e a função devolve qual foi', () async {
      expect(await matchedIn('voce e um $_blocked mesmo'), _blocked);
    });

    test('a mesma sequência DENTRO de palavra maior não casa', () async {
      // É o caso que separa esta lista da de nomes. Com `like '%...%'` — a
      // regra de `nome_valido` — os três abaixo seriam recusados, e a pessoa
      // não teria como entender por quê.
      for (final legitimate in [
        '${_blocked}zinho',
        'super$_blocked',
        'a${_blocked}da',
      ]) {
        expect(
          await matchedIn('isto aqui e $legitimate'),
          isNull,
          reason: legitimate,
        );
      }
    });

    test('maiúscula, acento e ausência de acento casam igual', () async {
      // Os dois sentidos: palavra sem acento na lista casando texto COM acento,
      // e palavra com acento na lista casando texto SEM. `unaccent` está nos
      // dois lados justamente por isso.
      expect(await matchedIn('que ${_blocked.toUpperCase()}'), _blocked);
      expect(await matchedIn('que xatôxo'), _blocked);
      expect(await matchedIn('que xatoxa'), _blockedWithAccent);
    });

    test('pontuação não faz parte da palavra', () async {
      for (final text in [
        '$_blocked, sai daqui',
        'nao seja $_blocked.',
        'voce e $_blocked',
        '($_blocked)',
        'e $_blocked!',
        'linha\n$_blocked\noutra',
      ]) {
        expect(await matchedIn(text), _blocked, reason: text);
      }
    });

    test('texto limpo e texto nulo devolvem null', () async {
      expect(await matchedIn('quem leva o som?'), isNull);
      expect(await matchedIn(null), isNull);
    });

    test('lista vazia devolve null para tudo', () async {
      // Sem a lista, a mesma frase que acabou de ser recusada passa. É o
      // "lista vazia não desliga o filtro em silêncio" da spec pelo lado
      // observável: a passagem é consequência de a lista estar vazia, e volta
      // a ser recusa quando ela deixa de estar.
      await conn.execute('begin');
      await conn.execute('delete from public.palavras_bloqueadas_mensagem');
      expect(await matchedIn('voce e um $_blocked mesmo'), isNull);
      await conn.execute('rollback');
      expect(await matchedIn('voce e um $_blocked mesmo'), _blocked);
    });
  });

  group('1.4 — o filtro roda sob papel SEM acesso à lista', () {
    test('authenticated não lê a tabela da lista', () async {
      await conn.execute('set role authenticated');
      try {
        await expectLater(
          conn.execute('select palavra from public.palavras_bloqueadas_mensagem'),
          throwsA(isA<ServerException>()),
          reason:
              'sem grant, a leitura é RECUSADA — que é mais forte do que '
              'devolver zero linhas, e é a postura que palavras_bloqueadas '
              'já tem desde 20260806090000',
        );
      } finally {
        await conn.execute('reset role');
      }
    });

    test('authenticated também não CHAMA a função de casamento', () async {
      // Diferença deliberada em relação a `nome_valido`, que tem
      // `grant execute to authenticated` porque um `check` de `perfis` precisa
      // dela no contexto de quem insere — e paga por isso com um ataque de
      // dicionário em aberto. Aqui quem chama é gatilho `security definer`, que
      // roda como o dono: nenhuma sessão precisa do privilégio, então nenhuma
      // sessão o tem.
      await conn.execute('set role authenticated');
      try {
        await expectLater(
          conn.execute(
            Sql.named('select public.palavra_bloqueada_em(@t)'),
            parameters: {'t': 'qualquer coisa'},
          ),
          throwsA(isA<ServerException>()),
          reason:
              'a função inalcançável é o que fecha a adivinhação da lista uma '
              'palavra por vez',
        );
      } finally {
        await conn.execute('reset role');
      }
    });

    // A outra metade do cenário "filtro rodando sob papel sem acesso à lista"
    // — que o gatilho continua enxergando a lista COMPLETA sob `authenticated`
    // — mora em `filtro_palavra_mensagem_test.dart`, porque lá a escrita passa
    // por uma sessão de verdade. Sem aquele caso, o `security definer` não está
    // provado: como `invoker`, a função leria zero linhas (RLS sem policy não
    // levanta erro) e o filtro passaria a ACEITAR tudo, sem erro no app e sem
    // teste vermelho.
  });
}
