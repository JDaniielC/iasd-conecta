import 'package:flutter_test/flutter_test.dart';
import 'package:iasd_conecta/features/action/domain/action.dart';

void main() {
  // Fronteira exata, para o teste não ficar ambíguo (research.md D-001):
  // no instante `dateTime + 4h` cravado a Ação ainda está acontecendo agora;
  // encerra no primeiro instante depois disso.
  final marcada = DateTime(2026, 8, 8, 19, 15);

  group('actionTimeStatus', () {
    test('1s antes da hora marcada: ainda vai acontecer', () {
      expect(
        actionTimeStatus(marcada, marcada.subtract(const Duration(seconds: 1))),
        ActionTimeStatus.upcoming,
      );
    });

    test('na hora marcada cravada: acontecendo agora', () {
      expect(actionTimeStatus(marcada, marcada), ActionTimeStatus.happeningNow);
    });

    test('em dateTime + 4h cravado: ainda acontecendo agora', () {
      expect(
        actionTimeStatus(marcada, marcada.add(defaultActionDuration)),
        ActionTimeStatus.happeningNow,
      );
    });

    test('1s depois de dateTime + 4h: encerrada', () {
      expect(
        actionTimeStatus(
          marcada,
          marcada.add(defaultActionDuration).add(const Duration(seconds: 1)),
        ),
        ActionTimeStatus.ended,
      );
    });

    test('a duração padrão é de 4 horas', () {
      expect(defaultActionDuration, const Duration(hours: 4));
    });
  });
}
