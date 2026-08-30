import 'dart:async';

import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/remote/remote_run_diagnostics_dialog.dart';
import 'package:fluent_ui/fluent_ui.dart';

class RemoteBackupProgressCard extends StatelessWidget {
  const RemoteBackupProgressCard({
    required this.provider,
    required this.onCancel,
    super.key,
  });

  final RemoteSchedulesProvider provider;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    final schedule = provider.schedules.firstWhere(
      (s) => s.id == provider.executingScheduleId,
      orElse: () => provider.schedules.first,
    );
    final backupError = provider.error;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                const ProgressRing(strokeWidth: 2),
                const SizedBox(width: AppSpacing.sm + AppSpacing.xs),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        appLocaleString(
                          context,
                          'Executando backup no servidor',
                          'Running backup on server',
                        ),
                        style: FluentTheme.of(context).typography.subtitle,
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Text(
                        schedule.name,
                        style: FluentTheme.of(context).typography.bodyStrong,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            if (provider.activeRunId != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText(
                appLocaleString(
                  context,
                  'Execução: ${provider.activeRunId}',
                  'Run: ${provider.activeRunId}',
                ),
                style: FluentTheme.of(context).typography.caption,
              ),
            ],
            if (provider.backupStep != null) ...[
              const SizedBox(height: AppSpacing.sm + AppSpacing.xs),
              Text(
                provider.backupStep!,
                style: FluentTheme.of(context).typography.caption,
              ),
            ],
            if (provider.backupMessage != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(
                provider.backupMessage!,
                style: FluentTheme.of(context).typography.body,
              ),
            ],
            if (backupError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText.rich(
                TextSpan(
                  text: appLocaleString(context, 'Erro: ', 'Error: '),
                  children: [
                    TextSpan(
                      text: backupError,
                      style: FluentTheme.of(context).typography.body?.copyWith(
                        color: context.colors.danger,
                      ),
                    ),
                  ],
                ),
              ),
            ],
            if (provider.backupProgress != null) ...[
              const SizedBox(height: AppSpacing.sm),
              ProgressBar(
                value: provider.backupProgress! * 100,
              ),
            ],
            const SizedBox(height: AppSpacing.md),
            Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                AppButton.primary(
                  label: appLocaleString(
                    context,
                    'Cancelar backup',
                    'Cancel backup',
                  ),
                  leading: const Icon(FluentIcons.cancel),
                  onPressed: onCancel,
                ),
                AppButton.icon(
                  icon: FluentIcons.diagnostic,
                  label: appLocaleString(
                    context,
                    'Diagnóstico',
                    'Diagnostics',
                  ),
                  onPressed: provider.activeRunId == null
                      ? null
                      : () => unawaited(
                          RemoteRunDiagnosticsDialog.show(
                            context,
                            provider: provider,
                            runId: provider.activeRunId!,
                            scheduleName: schedule.name,
                          ),
                        ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
