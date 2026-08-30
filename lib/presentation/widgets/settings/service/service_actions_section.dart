import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_primary_action.dart';
import 'package:fluent_ui/fluent_ui.dart';

/// **Organism** — install, start, stop, restart and remove service actions.
class ServiceActionsSection extends StatelessWidget {
  const ServiceActionsSection({
    required this.provider,
    required this.serviceActionsEnabled,
    required this.onRefresh,
    required this.onInstall,
    required this.onStart,
    required this.onRestart,
    required this.onStop,
    required this.onUninstall,
    super.key,
  });

  final WindowsServiceProvider provider;
  final bool serviceActionsEnabled;
  final VoidCallback onRefresh;
  final VoidCallback onInstall;
  final VoidCallback onStart;
  final VoidCallback onRestart;
  final VoidCallback onStop;
  final VoidCallback onUninstall;

  @override
  Widget build(BuildContext context) {
    final actionsDisabled = !serviceActionsEnabled || provider.isLoading;

    return AppSectionCard(
      title: appLocaleString(context, 'Ações', 'Actions'),
      description: appLocaleString(
        context,
        'Ações operacionais do serviço com prioridade para o fluxo principal.',
        'Operational service actions with emphasis on the primary flow.',
      ),
      child: Wrap(
        spacing: AppSpacing.sm,
        runSpacing: AppSpacing.sm,
        children: [
          ServicePrimaryAction(
            provider: provider,
            actionsDisabled: actionsDisabled,
            serviceActionsEnabled: serviceActionsEnabled,
            onRefresh: onRefresh,
            onInstall: onInstall,
            onStart: onStart,
            onRestart: onRestart,
          ),
          if (serviceActionsEnabled)
            AppButton(
              label: appLocaleString(
                context,
                'Atualizar status',
                'Refresh status',
              ),
              onPressed: provider.isLoading ? null : onRefresh,
            ),
          if (provider.isRunning)
            AppButton(
              label: appLocaleString(context, 'Parar', 'Stop'),
              onPressed: actionsDisabled ? null : onStop,
            ),
          if (provider.isInstalled)
            AppButton(
              label: appLocaleString(
                context,
                'Remover serviço',
                'Remove service',
              ),
              onPressed: actionsDisabled ? null : onUninstall,
            ),
        ],
      ),
    );
  }
}
