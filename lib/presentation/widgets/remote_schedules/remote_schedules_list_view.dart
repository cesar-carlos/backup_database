import 'dart:async';

import 'package:backup_database/application/providers/remote_schedules_provider.dart';
import 'package:backup_database/application/providers/server_connection_provider.dart';
import 'package:backup_database/core/constants/route_names.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/presentation/widgets/schedules/schedules.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:go_router/go_router.dart';

/// **Organism** — remote schedule list with health and error banners.
class RemoteSchedulesListView extends StatelessWidget {
  const RemoteSchedulesListView({
    required this.provider,
    required this.connectionProvider,
    required this.onCreatePressed,
    required this.onToggleEnabled,
    required this.onDelete,
    required this.onRunNow,
    required this.onTransferDestinations,
    super.key,
  });

  final RemoteSchedulesProvider provider;
  final ServerConnectionProvider connectionProvider;
  final VoidCallback onCreatePressed;
  final void Function(Schedule schedule, bool enabled) onToggleEnabled;
  final ValueChanged<Schedule> onDelete;
  final ValueChanged<String> onRunNow;
  final ValueChanged<Schedule> onTransferDestinations;

  static bool isDisconnectionError(String message) {
    final lower = message.toLowerCase();
    return lower.contains('desconectado') ||
        lower.contains('conexao perdida') ||
        lower.contains('conexão perdida') ||
        lower.contains('reconecte-se');
  }

  @override
  Widget build(BuildContext context) {
    final partialError = provider.error;
    final health = connectionProvider.serverHealth;
    final isServerHealthy = connectionProvider.isServerHealthy;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (!isServerHealthy) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Servidor indisponível para backup',
                  'Server unavailable for backup',
                ),
              ),
              content: SelectableText(
                health?.message ??
                    appLocaleString(
                      context,
                      'Atualize o status do servidor ou aguarde a recuperação '
                          'antes de executar backups remotos.',
                      'Refresh server status or wait for recovery before '
                          'running remote backups.',
                    ),
              ),
              severity: health?.isUnhealthy ?? true
                  ? InfoBarSeverity.error
                  : InfoBarSeverity.warning,
              action: Button(
                onPressed: connectionProvider.isRefreshingStatus
                    ? null
                    : () => unawaited(
                        connectionProvider.refreshServerStatus(),
                      ),
                child: Text(
                  appLocaleString(
                    context,
                    'Atualizar status',
                    'Refresh status',
                  ),
                ),
              ),
            ),
          ),
        ],
        if (partialError != null) ...[
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.md),
            child: InfoBar(
              title: const Text('Aviso'),
              content: SelectableText.rich(
                TextSpan(
                  text: partialError,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: context.colors.danger,
                  ),
                ),
              ),
              severity: InfoBarSeverity.error,
              onClose: provider.clearError,
              action: isDisconnectionError(partialError)
                  ? Button(
                      onPressed: () {
                        provider.clearError();
                        context.go(RouteNames.serverLogin);
                      },
                      child: const Text('Reconectar'),
                    )
                  : null,
            ),
          ),
        ],
        CommandBar(
          mainAxisAlignment: MainAxisAlignment.end,
          primaryItems: [
            CommandBarButton(
              icon: const Icon(FluentIcons.add),
              label: Text(
                appLocaleString(
                  context,
                  'Novo agendamento remoto',
                  'New remote schedule',
                ),
              ),
              onPressed: provider.isUpdating || provider.isExecuting
                  ? null
                  : onCreatePressed,
            ),
            CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              onPressed: provider.isUpdating || provider.isExecuting
                  ? null
                  : () {
                      unawaited(provider.loadSchedules());
                      unawaited(provider.loadExecutionQueue());
                      unawaited(
                        connectionProvider.refreshServerStatus(),
                      );
                    },
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.md),
        Expanded(
          child: ListView.separated(
            itemCount: provider.schedules.length,
            separatorBuilder: (_, _) => const SizedBox(height: 8),
            itemBuilder: (context, index) {
              final schedule = provider.schedules[index];
              final isOperating =
                  schedule.id == provider.updatingScheduleId ||
                  schedule.id == provider.executingScheduleId;
              return ScheduleListItem(
                schedule: schedule,
                isOperating: isOperating,
                onToggleEnabled: schedule.id == provider.updatingScheduleId
                    ? null
                    : (enabled) => onToggleEnabled(schedule, enabled),
                onDelete:
                    schedule.id == provider.updatingScheduleId ||
                        schedule.id == provider.executingScheduleId
                    ? null
                    : () => onDelete(schedule),
                onRunNow:
                    schedule.id == provider.executingScheduleId ||
                        !schedule.enabled ||
                        !isServerHealthy
                    ? null
                    : () => onRunNow(schedule.id),
                onTransferDestinations:
                    schedule.id == provider.updatingScheduleId ||
                        schedule.id == provider.executingScheduleId
                    ? null
                    : () => onTransferDestinations(schedule),
              );
            },
          ),
        ),
      ],
    );
  }
}
