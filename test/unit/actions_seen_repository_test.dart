import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/data/actions_seen_repository.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// O marcador de "última vez que vi `/acoes`" tinha zero teste até aqui: todo
/// teste de widget substitui este repositório por um falso. Trocar a chave,
/// tirar o `.toUtc()` ou mudar o formato passava por toda a suíte verde, e o
/// sintoma seria toda Ação de Grupo deixando de ser nova de uma vez — ou nunca
/// deixando.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const repository = ActionsSeenRepository();

  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('instalação nova não tem marcador', () async {
    expect(await repository.readLastSeenActionsDate(), isNull);
  });

  test('a chave gravada é `acoes_ultima_vista`, em UTC ISO 8601', () async {
    // Instante local, que é o que `clockProvider` entrega.
    await repository.writeLastSeenActionsDate(DateTime(2026, 8, 12, 12, 0));

    final prefs = await SharedPreferences.getInstance();
    final cru = prefs.getString('acoes_ultima_vista');

    expect(cru, isNotNull);
    // Sem `Z` o valor volta como hora local e a comparação com `createdAt`
    // (que vem do banco em UTC) erraria pelo fuso — 3 horas, em Recife.
    expect(cru, endsWith('Z'));
    expect(DateTime.parse(cru!).isUtc, isTrue);
  });

  test('o que volta é o mesmo instante que entrou', () async {
    final gravado = DateTime(2026, 8, 12, 12, 0);
    await repository.writeLastSeenActionsDate(gravado);

    final lido = await repository.readLastSeenActionsDate();

    expect(lido, isNotNull);
    expect(lido!.isAtSameMomentAs(gravado), isTrue);
  });

  test('a comparação que a regra faz acerta dos dois lados', () async {
    final abertura = DateTime(2026, 8, 12, 12, 0);
    await repository.writeLastSeenActionsDate(abertura);
    final marcador = (await repository.readLastSeenActionsDate())!;

    // É exatamente o `createdAt.isAfter(lastSeen)` de `actionHighlight`.
    expect(abertura.add(const Duration(minutes: 1)).isAfter(marcador), isTrue);
    expect(abertura.subtract(const Duration(minutes: 1)).isAfter(marcador), isFalse);
  });

  test('gravar de novo substitui, não acumula', () async {
    await repository.writeLastSeenActionsDate(DateTime(2026, 8, 12, 12, 0));
    await repository.writeLastSeenActionsDate(DateTime(2026, 8, 13, 9, 0));

    final lido = await repository.readLastSeenActionsDate();

    expect(lido!.isAtSameMomentAs(DateTime(2026, 8, 13, 9, 0)), isTrue);
  });

  test('valor corrompido no armazenamento vira "sem marcador", não exceção', () async {
    // `DateTime.tryParse` devolve nulo; quem lê trata como instalação nova.
    // Estourar aqui deixaria a tela sem destaque nenhum e sem explicação.
    SharedPreferences.setMockInitialValues({'acoes_ultima_vista': 'não é data'});

    expect(await repository.readLastSeenActionsDate(), isNull);
  });
}
