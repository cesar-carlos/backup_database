import 'dart:async';

import 'package:backup_database/application/providers/license_provider.dart';
import 'package:backup_database/core/constants/license_features.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_labels.dart';
import 'package:backup_database/presentation/widgets/schedules/schedule_dialog/schedule_dialog_section_title.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:provider/provider.dart';

class ScheduleDialogScheduleSection extends StatelessWidget {
  const ScheduleDialogScheduleSection({
    required this.scheduleType,
    required this.onScheduleTypeCommitted,
    required this.backupType,
    required this.databaseType,
    required this.truncateLog,
    required this.onTruncateLogChanged,
    required this.scheduleFields,
    super.key,
    this.sybaseLogModeSelector,
  });

  final ScheduleType scheduleType;
  final ValueChanged<ScheduleType> onScheduleTypeCommitted;
  final BackupType backupType;
  final DatabaseType databaseType;
  final bool truncateLog;
  final ValueChanged<bool> onTruncateLogChanged;
  final Widget? sybaseLogModeSelector;
  final Widget scheduleFields;

  @override
  Widget build(BuildContext context) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const ScheduleDialogSectionTitle('Agendamento'),
        const SizedBox(height: 12),
        Consumer<LicenseProvider>(
          builder: (BuildContext context, LicenseProvider licenseProvider, _) {
            final license = licenseProvider.currentLicense;
            final hasInterval =
                licenseProvider.hasValidLicense &&
                (license?.hasFeature(LicenseFeatures.intervalSchedule) ??
                    false);

            return AppDropdown<ScheduleType>(
              label: 'Frequência',
              value: scheduleType,
              placeholder: const Text('Frequência'),
              items: ScheduleType.values.map((ScheduleType type) {
                final isIntervalBlocked =
                    type == ScheduleType.interval && !hasInterval;

                return ComboBoxItem<ScheduleType>(
                  value: type,
                  enabled: !isIntervalBlocked,
                  child: Row(
                    children: [
                      Expanded(
                        child: Row(
                          children: [
                            Flexible(
                              child: Text(
                                isIntervalBlocked
                                    ? '${ScheduleDialogLabels.scheduleTypeName(type)} (Requer licença)'
                                    : ScheduleDialogLabels.scheduleTypeName(
                                        type,
                                      ),
                                textAlign: TextAlign.start,
                                style: TextStyle(
                                  color: isIntervalBlocked
                                      ? FluentTheme.of(context)
                                            .resources
                                            .controlStrokeColorDefault
                                            .withValues(alpha: 0.4)
                                      : null,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            if (isIntervalBlocked) ...[
                              const SizedBox(width: 8),
                              Icon(
                                FluentIcons.lock,
                                size: 16,
                                color: FluentTheme.of(context)
                                    .resources
                                    .controlStrokeColorDefault
                                    .withValues(alpha: 0.4),
                              ),
                            ],
                          ],
                        ),
                      ),
                    ],
                  ),
                );
              }).toList(),
              onChanged: (ScheduleType? value) {
                if (value != null) {
                  final licenseInner = licenseProvider.currentLicense;
                  final hasIntervalInner =
                      licenseProvider.hasValidLicense &&
                      (licenseInner?.hasFeature(
                            LicenseFeatures.intervalSchedule,
                          ) ??
                          false);

                  if (value == ScheduleType.interval && !hasIntervalInner) {
                    unawaited(
                      FluentInfoBarFeedback.showWarning(
                        context,
                        message:
                            'Agendamento por intervalo requer uma licença válida. '
                            'Acesse Configurações > Licenciamento para mais informações.',
                      ),
                    );
                    return;
                  }

                  onScheduleTypeCommitted(value);
                }
              },
            );
          },
        ),
        const SizedBox(height: 16),
        if (backupType == BackupType.log &&
            databaseType == DatabaseType.sybase &&
            sybaseLogModeSelector != null)
          sybaseLogModeSelector!,
        if (backupType == BackupType.log && databaseType != DatabaseType.sybase)
          InfoLabel(
            label: 'Truncar log após backup',
            child: ToggleSwitch(
              checked: truncateLog,
              onChanged: onTruncateLogChanged,
            ),
          ),
        if (backupType == BackupType.log) const SizedBox(height: 8),
        if (backupType == BackupType.log && databaseType != DatabaseType.sybase)
          Text(
            'Quando habilitado, o backup de log libera espaço (SQL Server: '
            'padrão; Sybase: depende do motor).',
            style: FluentTheme.of(context).typography.caption,
          ),
        if (backupType == BackupType.log && databaseType == DatabaseType.sybase)
          Text(
            'Truncar: libera espaço. Renomear: recomendado para replicação '
            '(SQL Remote, MobiLink).',
            style: FluentTheme.of(context).typography.caption,
          ),
        const SizedBox(height: 16),
        scheduleFields,
      ],
    );
  }
}
