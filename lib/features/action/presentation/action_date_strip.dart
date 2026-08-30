import 'package:flutter/material.dart';

import '../../../core/theme/app_theme.dart';

const _monthNames = [
  'Janeiro',
  'Fevereiro',
  'Março',
  'Abril',
  'Maio',
  'Junho',
  'Julho',
  'Agosto',
  'Setembro',
  'Outubro',
  'Novembro',
  'Dezembro',
];

// `date.weekday`: 1 = segunda ... 7 = domingo.
const _weekdayAbbrev = ['Seg', 'Ter', 'Qua', 'Qui', 'Sex', 'Sáb', 'Dom'];

DateTime _dayOnly(DateTime d) => DateTime(d.year, d.month, d.day);

/// Calendário de sete dias, pra filtrar Ações por data — sem sair de
/// `/acoes`. Não é um mês inteiro de propósito: sete cabe na largura de um
/// celular sem rolagem horizontal escondida, e "próxima semana"/"semana
/// passada" já cobre o que a pessoa vem checar (o que tem pra breve).
///
/// O mês exibido no cabeçalho é o do primeiro dia da semana visível — pode
/// ser diferente do último se a semana cruzar virada de mês, e está certo
/// assim: o cabeçalho descreve "onde a janela começa", não resume os sete.
class ActionDateStrip extends StatelessWidget {
  const ActionDateStrip({
    super.key,
    required this.weekStart,
    required this.selectedDate,
    required this.datesWithActions,
    required this.onPreviousWeek,
    required this.onNextWeek,
    required this.onSelectDate,
  });

  final DateTime weekStart;
  final DateTime? selectedDate;

  /// Truncado pro dia (sem hora) — comparado só por igualdade de dia.
  final Set<DateTime> datesWithActions;

  final VoidCallback onPreviousWeek;
  final VoidCallback onNextWeek;

  /// `null` quando o dia tocado já estava selecionado — alterna, não só marca.
  final ValueChanged<DateTime?> onSelectDate;

  @override
  Widget build(BuildContext context) {
    final days = [for (var i = 0; i < 7; i++) weekStart.add(Duration(days: i))];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            IconButton(
              tooltip: 'Semana anterior',
              icon: const Icon(Icons.chevron_left),
              onPressed: onPreviousWeek,
            ),
            Expanded(
              child: Text(
                _monthNames[weekStart.month - 1],
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Próxima semana',
              icon: const Icon(Icons.chevron_right),
              onPressed: onNextWeek,
            ),
          ],
        ),
        SizedBox(
          height: 64,
          child: Row(
            children: [
              for (final day in days)
                Expanded(child: _DayCell(
                  day: day,
                  selected: selectedDate != null && _dayOnly(selectedDate!) == _dayOnly(day),
                  hasAction: datesWithActions.contains(_dayOnly(day)),
                  onTap: () {
                    final already = selectedDate != null &&
                        _dayOnly(selectedDate!) == _dayOnly(day);
                    onSelectDate(already ? null : _dayOnly(day));
                  },
                )),
            ],
          ),
        ),
      ],
    );
  }
}

class _DayCell extends StatelessWidget {
  const _DayCell({
    required this.day,
    required this.selected,
    required this.hasAction,
    required this.onTap,
  });

  final DateTime day;
  final bool selected;
  final bool hasAction;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Material(
        color: selected ? AppColors.navy : Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text(
                  _weekdayAbbrev[day.weekday - 1],
                  style: Theme.of(context).textTheme.labelSmall?.copyWith(
                        color: selected ? Colors.white70 : null,
                      ),
                ),
                Text(
                  '${day.day}',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: selected ? Colors.white : null,
                        fontWeight: FontWeight.bold,
                      ),
                ),
                SizedBox(
                  height: 6,
                  child: hasAction
                      ? Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            color: selected ? Colors.white : scheme.primary,
                          ),
                        )
                      : null,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
