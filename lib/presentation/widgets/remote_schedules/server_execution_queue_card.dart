import 'dart:async';

import 'package:backup_database/application/dtos/remote/queued_execution_view.dart';
import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServerExecutionQueueCard extends StatelessWidget {
  const ServerExecutionQueueCard({
    required this.provider,
    required this.scheduleNameFor,
    super.key,
  });

  final RemoteSchedulesProvider provider;
  final String Function(RemoteSchedulesProvider provider, String scheduleId)
  scheduleNameFor;

  @override
  Widget build(BuildContext context) {
    final queueError = provider.executionQueueError;

    return AppCard(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    appLocaleString(
                      context,
                      'Fila no servidor',
                      'Server queue',
                    ),
                    style: FluentTheme.of(context).typography.subtitle,
                  ),
                ),
                AppIconButton(
                  label: appLocaleString(context, 'Atualizar', 'Refresh'),
                  icon: FluentIcons.refresh,
                  onPressed: provider.isLoadingExecutionQueue
                      ? null
                      : () => unawaited(provider.loadExecutionQueue()),
                ),
              ],
            ),
            if (queueError != null) ...[
              const SizedBox(height: AppSpacing.sm),
              SelectableText.rich(
                TextSpan(
                  text: queueError,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
            ] else if (provider.isLoadingExecutionQueue &&
                provider.executionQueue.isEmpty)
              const Padding(
                padding: EdgeInsets.symmetric(vertical: AppSpacing.sm),
                child: ProgressRing(strokeWidth: 2),
              )
            else if (provider.executionQueue.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: AppSpacing.sm),
                child: Text(
                  appLocaleString(
                    context,
                    'Nenhum backup aguardando na fila do servidor.',
                    'No backups waiting in the server queue.',
                  ),
                  style: FluentTheme.of(context).typography.body,
                ),
              )
            else
              ...provider.executionQueue.map(
                (item) => QueuedExecutionRow(
                  item: item,
                  scheduleLabel: scheduleNameFor(provider, item.scheduleId),
                  onCancel: () =>
                      _onCancelQueued(context, provider, item.runId),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _onCancelQueued(
    BuildContext context,
    RemoteSchedulesProvider provider,
    String runId,
  ) async {
    final success = await provider.cancelQueuedRemoteBackup(runId);
    if (!context.mounted) return;
    if (success) {
      unawaited(
        FluentInfoBarFeedback.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Item removido da fila do servidor.',
            'Item removed from server queue.',
          ),
        ),
      );
    } else {
      unawaited(
        MessageModal.showError(
          context,
          message: provider.error ?? 'Erro ao cancelar item da fila.',
        ),
      );
    }
  }
}

class QueuedExecutionRow extends StatelessWidget {
  const QueuedExecutionRow({
    required this.item,
    required this.scheduleLabel,
    required this.onCancel,
    super.key,
  });

  final QueuedExecutionView item;
  final String scheduleLabel;
  final VoidCallback onCancel;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.sm),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  scheduleLabel,
                  style: FluentTheme.of(context).typography.bodyStrong,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  appLocaleString(
                    context,
                    'Agendamento: ${item.scheduleId} · Posição ${item.queuedPosition}',
                    'Schedule: ${item.scheduleId} · Position ${item.queuedPosition}',
                  ),
                  style: FluentTheme.of(context).typography.caption,
                ),
                const SizedBox(height: AppSpacing.xs),
                SelectableText(
                  appLocaleString(
                    context,
                    'Execução: ${item.runId}',
                    'Run: ${item.runId}',
                  ),
                  style: FluentTheme.of(context).typography.caption,
                ),
              ],
            ),
          ),
          AppButton(
            label: appLocaleString(context, 'Cancelar', 'Cancel'),
            onPressed: onCancel,
          ),
        ],
      ),
    );
  }
}
