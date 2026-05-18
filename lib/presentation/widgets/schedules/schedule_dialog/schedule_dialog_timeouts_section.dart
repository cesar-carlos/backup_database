import 'package:backup_database/core/constants/schedule_dialog_strings.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogTimeoutsSection extends StatelessWidget {
  const ScheduleDialogTimeoutsSection({
    required this.backupTimeoutMinutesController,
    required this.verifyTimeoutMinutesController,
    required this.onBackupTimeoutMinutesParsed,
    required this.onVerifyTimeoutMinutesParsed,
    super.key,
  });

  final TextEditingController backupTimeoutMinutesController;
  final TextEditingController verifyTimeoutMinutesController;
  final ValueChanged<int> onBackupTimeoutMinutesParsed;
  final ValueChanged<int> onVerifyTimeoutMinutesParsed;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle(ScheduleDialogStrings.timeoutsSection),
        const SizedBox(height: 12),
        InfoLabel(
          label: ScheduleDialogStrings.backupTimeout,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 120,
                child: InfoLabel(
                  label: ScheduleDialogStrings.minutes,
                  child: NumericField(
                    controller: backupTimeoutMinutesController,
                    label: '',
                    minValue: 1,
                    maxValue: 1440,
                    onChanged: (String value) {
                      final minutes = int.tryParse(value) ?? 120;
                      onBackupTimeoutMinutesParsed(minutes);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  ScheduleDialogStrings.max24Hours,
                  style: FluentTheme.of(context).typography.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        InfoLabel(
          label: ScheduleDialogStrings.verifyTimeout,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              SizedBox(
                width: 120,
                child: InfoLabel(
                  label: ScheduleDialogStrings.minutes,
                  child: NumericField(
                    controller: verifyTimeoutMinutesController,
                    label: '',
                    minValue: 1,
                    maxValue: 1440,
                    onChanged: (String value) {
                      final minutes = int.tryParse(value) ?? 30;
                      onVerifyTimeoutMinutesParsed(minutes);
                    },
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  ScheduleDialogStrings.max24Hours,
                  style: FluentTheme.of(context).typography.caption,
                ),
              ),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Text(
          ScheduleDialogStrings.timeoutsDescription,
          style: FluentTheme.of(context).typography.caption,
        ),
      ],
    );
  }
}
