import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ScheduleDialogSybaseLogModeSelector extends StatelessWidget {
  const ScheduleDialogSybaseLogModeSelector({
    required this.logBackupMode,
    required this.truncateLog,
    required this.onChanged,
    super.key,
  });

  final SybaseLogBackupMode? logBackupMode;
  final bool truncateLog;
  final ValueChanged<SybaseLogBackupMode> onChanged;

  @override
  Widget build(BuildContext context) {
    final effectiveMode =
        logBackupMode ??
        (truncateLog ? SybaseLogBackupMode.truncate : SybaseLogBackupMode.only);
    return AppDropdown<SybaseLogBackupMode>(
      label: 'Modo de log após backup',
      value: effectiveMode,
      items: const [
        ComboBoxItem(
          value: SybaseLogBackupMode.truncate,
          child: Text('Truncar (liberar espaço)'),
        ),
        ComboBoxItem(
          value: SybaseLogBackupMode.only,
          child: Text('Apenas backup (sem alterar log)'),
        ),
        ComboBoxItem(
          value: SybaseLogBackupMode.rename,
          child: Text('Renomear (recomendado para replicação)'),
        ),
      ],
      onChanged: (SybaseLogBackupMode? value) {
        if (value != null) {
          onChanged(value);
        }
      },
    );
  }
}
