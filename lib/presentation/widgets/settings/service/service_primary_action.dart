import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/service/windows_service_uac.dart';
import 'package:fluent_ui/fluent_ui.dart';

class ServicePrimaryAction extends StatelessWidget {
  const ServicePrimaryAction({
    required this.provider,
    required this.actionsDisabled,
    required this.serviceActionsEnabled,
    required this.onRefresh,
    required this.onInstall,
    required this.onStart,
    required this.onRestart,
    super.key,
  });

  final WindowsServiceProvider provider;
  final bool actionsDisabled;
  final bool serviceActionsEnabled;
  final VoidCallback onRefresh;
  final VoidCallback onInstall;
  final VoidCallback onStart;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    if (!serviceActionsEnabled) {
      return AppButton.primary(
        label: appLocaleString(
          context,
          'Atualizar status',
          'Refresh status',
        ),
        onPressed: provider.isLoading ? null : onRefresh,
      );
    }

    final String idleLabel;
    final VoidCallback onPressed;
    if (!provider.isInstalled) {
      idleLabel = appLocaleString(
        context,
        'Instalar serviço',
        'Install service',
      );
      onPressed = onInstall;
    } else if (!provider.isRunning) {
      idleLabel = appLocaleString(context, 'Iniciar', 'Start');
      onPressed = onStart;
    } else {
      idleLabel = appLocaleString(context, 'Reiniciar', 'Restart');
      onPressed = onRestart;
    }

    final isUacWait =
        provider.isLoading && isUacElevatedOperationType(provider.operation);

    return AppButton.primary(
      label: idleLabel,
      onPressed: actionsDisabled ? null : onPressed,
      isLoading: isUacWait,
      loadingLabel: _loadingActionLabel(context),
    );
  }

  String _loadingActionLabel(BuildContext context) {
    return switch (provider.operation) {
      WindowsServiceOperation.install ||
      WindowsServiceOperation.uninstall => appLocaleString(
        context,
        'Aguardando confirmação do Windows (UAC)...',
        'Waiting for Windows confirmation (UAC)...',
      ),
      WindowsServiceOperation.start => appLocaleString(
        context,
        'Iniciando... aguardando UAC',
        'Starting... waiting for UAC',
      ),
      WindowsServiceOperation.stop => appLocaleString(
        context,
        'Parando... aguardando UAC',
        'Stopping... waiting for UAC',
      ),
      WindowsServiceOperation.restart => appLocaleString(
        context,
        'Reiniciando... aguardando UAC',
        'Restarting... waiting for UAC',
      ),
      _ => appLocaleString(context, 'Processando...', 'Processing...'),
    };
  }
}
