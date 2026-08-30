import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogScheduleFields extends StatelessWidget {
  const ScheduleDialogScheduleFields({
    required this.scheduleType,
    required this.hour,
    required this.minute,
    required this.selectedDaysOfWeek,
    required this.selectedDaysOfMonth,
    required this.intervalMinutesController,
    required this.onHourChanged,
    required this.onMinuteChanged,
    required this.onDayOfWeekToggled,
    required this.onDayOfMonthToggled,
    required this.onIntervalMinutesChanged,
    super.key,
  });

  final ScheduleType scheduleType;
  final int hour;
  final int minute;
  final List<int> selectedDaysOfWeek;
  final List<int> selectedDaysOfMonth;
  final TextEditingController intervalMinutesController;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;
  final void Function(int dayNumber, bool selected) onDayOfWeekToggled;
  final void Function(int day, bool selected) onDayOfMonthToggled;
  final ValueChanged<int> onIntervalMinutesChanged;

  @override
  Widget build(BuildContext context) {
    switch (scheduleType) {
      case ScheduleType.daily:
        return _TimeSelector(
          hour: hour,
          minute: minute,
          onHourChanged: onHourChanged,
          onMinuteChanged: onMinuteChanged,
        );
      case ScheduleType.weekly:
        return Column(
          children: [
            _DayOfWeekSelector(
              selectedDaysOfWeek: selectedDaysOfWeek,
              onToggled: onDayOfWeekToggled,
            ),
            const SizedBox(height: 16),
            _TimeSelector(
              hour: hour,
              minute: minute,
              onHourChanged: onHourChanged,
              onMinuteChanged: onMinuteChanged,
            ),
          ],
        );
      case ScheduleType.monthly:
        return Column(
          children: [
            _DayOfMonthSelector(
              selectedDaysOfMonth: selectedDaysOfMonth,
              onToggled: onDayOfMonthToggled,
            ),
            const SizedBox(height: 16),
            _TimeSelector(
              hour: hour,
              minute: minute,
              onHourChanged: onHourChanged,
              onMinuteChanged: onMinuteChanged,
            ),
          ],
        );
      case ScheduleType.interval:
        return _IntervalSelector(
          controller: intervalMinutesController,
          onIntervalMinutesChanged: onIntervalMinutesChanged,
        );
    }
  }
}

class _TimeSelector extends StatelessWidget {
  const _TimeSelector({
    required this.hour,
    required this.minute,
    required this.onHourChanged,
    required this.onMinuteChanged,
  });

  final int hour;
  final int minute;
  final ValueChanged<int> onHourChanged;
  final ValueChanged<int> onMinuteChanged;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Expanded(
          child: AppDropdown<int>(
            label: 'Hora',
            value: hour,
            placeholder: const Text('Hora'),
            items: List.generate(24, (int index) {
              return ComboBoxItem<int>(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (int? value) {
              if (value != null) {
                onHourChanged(value);
              }
            },
          ),
        ),
        const SizedBox(width: 16),
        Expanded(
          child: AppDropdown<int>(
            label: 'Minuto',
            value: minute,
            placeholder: const Text('Minuto'),
            items: List.generate(60, (int index) {
              return ComboBoxItem<int>(
                value: index,
                child: Text(index.toString().padLeft(2, '0')),
              );
            }),
            onChanged: (int? value) {
              if (value != null) {
                onMinuteChanged(value);
              }
            },
          ),
        ),
      ],
    );
  }
}

class _DayOfWeekSelector extends StatelessWidget {
  const _DayOfWeekSelector({
    required this.selectedDaysOfWeek,
    required this.onToggled,
  });

  final List<int> selectedDaysOfWeek;
  final void Function(int dayNumber, bool selected) onToggled;

  static const List<String> _days = [
    'Seg',
    'Ter',
    'Qua',
    'Qui',
    'Sex',
    'Sáb',
    'Dom',
  ];

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 8,
      children: List.generate(7, (int index) {
        final dayNumber = index + 1;
        final isSelected = selectedDaysOfWeek.contains(dayNumber);

        return Padding(
          padding: const EdgeInsets.only(right: 8, bottom: 8),
          child: Checkbox(
            checked: isSelected,
            onChanged: (bool? value) {
              onToggled(dayNumber, value ?? false);
            },
            content: Text(_days[index]),
          ),
        );
      }),
    );
  }
}

class _DayOfMonthSelector extends StatelessWidget {
  const _DayOfMonthSelector({
    required this.selectedDaysOfMonth,
    required this.onToggled,
  });

  final List<int> selectedDaysOfMonth;
  final void Function(int day, bool selected) onToggled;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 4,
      runSpacing: 4,
      children: List.generate(31, (int index) {
        final day = index + 1;
        final isSelected = selectedDaysOfMonth.contains(day);

        return Padding(
          padding: const EdgeInsets.only(right: 4, bottom: 4),
          child: Checkbox(
            checked: isSelected,
            onChanged: (bool? value) {
              onToggled(day, value ?? false);
            },
            content: Text(day.toString()),
          ),
        );
      }),
    );
  }
}

class _IntervalSelector extends StatelessWidget {
  const _IntervalSelector({
    required this.controller,
    required this.onIntervalMinutesChanged,
  });

  final TextEditingController controller;
  final ValueChanged<int> onIntervalMinutesChanged;

  @override
  Widget build(BuildContext context) {
    return NumericField(
      controller: controller,
      label: 'Intervalo (minutos)',
      hint: 'Ex: 60 para cada hora',
      prefixIcon: FluentIcons.timer,
      minValue: 1,
      onChanged: (String value) {
        final minutes = int.tryParse(value) ?? 60;
        onIntervalMinutesChanged(minutes);
      },
    );
  }
}
