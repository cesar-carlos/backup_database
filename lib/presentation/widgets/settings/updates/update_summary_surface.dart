import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/updates/update_settings_labels.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Molecule** — chips + last-check summary for the updater.
class UpdateSummarySurface extends StatelessWidget {
  const UpdateSummarySurface({
    required this.provider,
    required this.lastCheckLabel,
    super.key,
  });

  final AutoUpdateProvider provider;
  final String lastCheckLabel;

  AppStatusChipTone _statusTone() {
    switch (provider.status) {
      case AppUpdateStatus.updateAvailable:
      case AppUpdateStatus.upToDate:
      case AppUpdateStatus.handoffCompleted:
        return AppStatusChipTone.success;
      case AppUpdateStatus.checking:
      case AppUpdateStatus.downloading:
      case AppUpdateStatus.installing:
        return AppStatusChipTone.info;
      case AppUpdateStatus.blockedByActiveBackup:
      case AppUpdateStatus.blockedByOtherInstance:
      case AppUpdateStatus.disabled:
        return AppStatusChipTone.warning;
      case AppUpdateStatus.error:
        return AppStatusChipTone.danger;
      case AppUpdateStatus.idle:
        return AppStatusChipTone.neutral;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: context.colors.outline.withValues(alpha: 0.08),
        borderRadius: AppRadius.circularMd,
        border: Border.all(
          color: context.colors.outline.withValues(alpha: 0.22),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            crossAxisAlignment: WrapCrossAlignment.center,
            children: [
              AppStatusChip(
                label: autoUpdateStageText(context, provider.currentStage),
                tone: _statusTone(),
                icon: FluentIcons.update_restore,
              ),
              if (provider.targetVersion != null)
                AppStatusChip(
                  label: 'v${provider.targetVersion}',
                  tone: AppStatusChipTone.info,
                ),
              if (provider.currentVersion != null)
                AppStatusChip(
                  label:
                      '${appLocaleString(context, 'Atual', 'Current')}: v${provider.currentVersion}',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            autoUpdateStatusText(context, provider),
            style: FluentTheme.of(context).typography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${appLocaleString(context, 'Ultima verificacao', 'Last check')}: $lastCheckLabel',
            style: FluentTheme.of(context).typography.caption,
          ),
        ],
      ),
    );
  }
}
