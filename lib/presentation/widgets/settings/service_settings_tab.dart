import 'dart:async';
import 'dart:io' show Platform, exit;

import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/domain/services/i_scheduler_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_actions_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_compatibility_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_error_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_info_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_local_schedule_timer_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_status_section.dart';
import 'package:backup_database/presentation/widgets/settings/service/service_uac_waiting_banner.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class ServiceSettingsTab extends StatefulWidget {
  const ServiceSettingsTab({super.key});

  @override
  State<ServiceSettingsTab> createState() => _ServiceSettingsTabState();
}

class _ServiceSettingsTabState extends State<ServiceSettingsTab> {
  late final ClipboardService _clipboardService;
  bool _localScheduleTimerEnabled = true;
  bool _isLoadingScheduleTimerPref = true;

  @override
  void initState() {
    super.initState();
    _clipboardService = getIt<ClipboardService>();
    unawaited(_loadLocalScheduleTimerPreference());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      unawaited(context.read<WindowsServiceProvider>().checkStatus());
    });
  }

  Future<void> _loadLocalScheduleTimerPreference() async {
    try {
      final enabled = await getIt<IUserPreferencesRepository>()
          .getLocalScheduleTimerEnabled();
      if (mounted) {
        setState(() {
          _localScheduleTimerEnabled = enabled;
          _isLoadingScheduleTimerPref = false;
        });
      }
    } on Object catch (e, s) {
      LoggerService.warning(
        'Erro ao carregar preferência do timer de agendamento',
        e,
        s,
      );
      if (mounted) {
        setState(() => _isLoadingScheduleTimerPref = false);
      }
    }
  }

  Future<void> _setLocalScheduleTimerEnabled(bool enabled) async {
    if (!mounted) {
      return;
    }
    setState(() => _localScheduleTimerEnabled = enabled);
    final serviceRunning = context.read<WindowsServiceProvider>().isRunning;
    await getIt<IUserPreferencesRepository>().setLocalScheduleTimerEnabled(
      enabled,
    );
    if (getIt.isRegistered<ISchedulerService>()) {
      final scheduler = getIt<ISchedulerService>();
      scheduler.stop();
      if (serviceRunning) {
        return;
      }
      if (enabled) {
        await scheduler.start();
      }
    }
  }

  Future<void> _copyCompatibilityDiagnostics(String summary) async {
    final payload = await _buildCompatibilityDiagnosticsPayload(summary);
    final copied = await _clipboardService.copyToClipboard(payload);
    if (!mounted) {
      return;
    }
    if (copied) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Diagnóstico de compatibilidade copiado para a área de transferência.',
          'Compatibility diagnostics copied to clipboard.',
        ),
      );
      return;
    }
    await MessageModal.showError(
      context,
      message: appLocaleString(
        context,
        'Não foi possível copiar o diagnóstico de compatibilidade.',
        'Could not copy compatibility diagnostics.',
      ),
    );
  }

  Future<void> _copyPath(String path) async {
    final copied = await _clipboardService.copyToClipboard(path);
    if (!mounted) {
      return;
    }
    if (copied) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: appLocaleString(
          context,
          'Caminho copiado para a área de transferência.',
          'Path copied to the clipboard.',
        ),
      );
      return;
    }
    await MessageModal.showError(
      context,
      message: appLocaleString(
        context,
        'Não foi possível copiar o caminho.',
        'Could not copy the path.',
      ),
    );
  }

  Future<void> _openParentDirectory(String filePath) async {
    final directoryPath = p.dirname(filePath);
    final uri = Uri.directory(directoryPath, windows: Platform.isWindows);
    final opened = await launchUrl(
      uri,
      mode: LaunchMode.externalApplication,
    );
    if (!mounted || opened) {
      return;
    }
    await FluentInfoBarFeedback.showWarning(
      context,
      message: appLocaleString(
        context,
        'Não foi possível abrir a pasta.',
        'Could not open the folder.',
      ),
    );
  }

  Future<String> _buildCompatibilityDiagnosticsPayload(String summary) async {
    final appVersion = await _resolveAppVersion();
    final timestampIso = DateTime.now().toIso8601String();
    return '[backup_database compatibility diagnostics]\n'
        'timestamp=$timestampIso\n'
        'app_version=$appVersion\n\n'
        '$summary';
  }

  Future<String> _resolveAppVersion() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (packageInfo.buildNumber.isNotEmpty) {
        return '${packageInfo.version}+${packageInfo.buildNumber}';
      }
      return packageInfo.version;
    } on Object catch (e, s) {
      LoggerService.warning('Falha ao resolver versão do app', e, s);
      return 'unknown';
    }
  }

  @override
  Widget build(BuildContext context) {
    final features = getIt<FeatureAvailabilityService>();
    final serviceUiOk = features.isWindowsServiceManagementEnabled;
    return Consumer<WindowsServiceProvider>(
      builder: (context, provider, _) {
        return SingleChildScrollView(
          padding: InheritedAppDensity.resolve(context).contentPadding,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (provider.isWaitingForUac) ...[
                ServiceUacWaitingBanner(operation: provider.operation),
                AppSpacing.gapLg,
              ],
              if (!serviceUiOk) ...[
                InfoBar(
                  title: Text(
                    appLocaleString(
                      context,
                      'Serviço do Windows',
                      'Windows Service',
                    ),
                  ),
                  content: Text(
                    localizeCompatibilityReason(
                      context,
                      reason: features.windowsServiceManagementDisabledReason,
                      fallbackPt: 'Não disponível nesta versão do Windows.',
                      fallbackEn: 'Not available on this Windows version.',
                    ),
                  ),
                  severity: InfoBarSeverity.warning,
                  isLong: true,
                ),
                AppSpacing.gapLg,
              ],
              ServiceStatusSection(
                statusText: _getStatusText(provider),
                provider: provider,
              ),
              if (provider.error != null) ...[
                AppSpacing.gapLg,
                ServiceErrorSection(provider: provider),
              ],
              AppSpacing.gapLg,
              ServiceActionsSection(
                provider: provider,
                serviceActionsEnabled: serviceUiOk,
                onRefresh: () => unawaited(provider.checkStatus()),
                onInstall: () => unawaited(_installService(context, provider)),
                onStart: () => unawaited(_startService(context, provider)),
                onRestart: () => unawaited(_restartService(context, provider)),
                onStop: () => unawaited(_stopService(context, provider)),
                onUninstall: () =>
                    unawaited(_uninstallService(context, provider)),
              ),
              AppSpacing.gapLg,
              ServiceLocalScheduleTimerSection(
                isLoading: _isLoadingScheduleTimerPref,
                enabled: _localScheduleTimerEnabled,
                serviceOwnsScheduler: provider.isRunning,
                onChanged: (bool enabled) {
                  unawaited(_setLocalScheduleTimerEnabled(enabled));
                },
              ),

              AppSpacing.gapLg,
              ServiceInfoSection(
                onCopyLogPath: () => unawaited(
                  _copyPath('${AppConstants.windowsServiceLogPath}\\'),
                ),
                onOpenLogFolder: () => unawaited(
                  _openParentDirectory(
                    '${AppConstants.windowsServiceLogPath}\\app.log',
                  ),
                ),
              ),
              AppSpacing.gapLg,
              ServiceCompatibilitySection(
                diagnostics: features.diagnosticSummary(),
                onCopyDiagnostics: () => unawaited(
                  _copyCompatibilityDiagnostics(features.diagnosticSummary()),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  String _getStatusText(WindowsServiceProvider provider) {
    if (provider.isLoading) {
      if (provider.isWaitingForUac) {
        return switch (provider.operation) {
          WindowsServiceOperation.install => appLocaleString(
            context,
            'Instalando... aguardando confirmação do UAC',
            'Installing... waiting for UAC confirmation',
          ),
          WindowsServiceOperation.uninstall => appLocaleString(
            context,
            'Removendo... aguardando confirmação do UAC',
            'Removing... waiting for UAC confirmation',
          ),
          WindowsServiceOperation.start => appLocaleString(
            context,
            'Iniciando... aguardando confirmação do UAC',
            'Starting... waiting for UAC confirmation',
          ),
          WindowsServiceOperation.stop => appLocaleString(
            context,
            'Parando... aguardando confirmação do UAC',
            'Stopping... waiting for UAC confirmation',
          ),
          WindowsServiceOperation.restart => appLocaleString(
            context,
            'Reiniciando... aguardando confirmação do UAC',
            'Restarting... waiting for UAC confirmation',
          ),
          WindowsServiceOperation.check => appLocaleString(
            context,
            'Verificando...',
            'Checking...',
          ),
          WindowsServiceOperation.none => appLocaleString(
            context,
            'Verificando...',
            'Checking...',
          ),
        };
      }
      return switch (provider.operation) {
        WindowsServiceOperation.install => appLocaleString(
          context,
          'Instalando...',
          'Installing...',
        ),
        WindowsServiceOperation.uninstall => appLocaleString(
          context,
          'Removendo...',
          'Removing...',
        ),
        WindowsServiceOperation.start => appLocaleString(
          context,
          'Iniciando...',
          'Starting...',
        ),
        WindowsServiceOperation.stop => appLocaleString(
          context,
          'Parando...',
          'Stopping...',
        ),
        WindowsServiceOperation.restart => appLocaleString(
          context,
          'Reiniciando...',
          'Restarting...',
        ),
        WindowsServiceOperation.check ||
        WindowsServiceOperation.none => appLocaleString(
          context,
          'Verificando...',
          'Checking...',
        ),
      };
    }
    if (provider.isStopPending) {
      return appLocaleString(
        context,
        'Parando (STOP_PENDING)',
        'Stopping (STOP_PENDING)',
      );
    }
    if (provider.isStartPending) {
      return appLocaleString(
        context,
        'Iniciando (START_PENDING)',
        'Starting (START_PENDING)',
      );
    }
    if (provider.isInstalled) {
      return provider.isRunning
          ? appLocaleString(
              context,
              'Instalado e em execução',
              'Installed and running',
            )
          : appLocaleString(context, 'Instalado', 'Installed');
    }
    return appLocaleString(context, 'Não instalado', 'Not installed');
  }

  Future<void> _installService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    if (!getIt<FeatureAvailabilityService>()
        .isWindowsServiceManagementEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Instalar serviço', 'Install service'),
      message: appLocaleString(
        context,
        'Deseja instalar o Backup Database como serviço do Windows?\n\nO serviço será configurado para:\n- Iniciar automaticamente com o Windows\n- Executar sem usuário logado\n- Rodar com conta LocalSystem\n\nEnquanto este aplicativo estiver aberto, o serviço não consegue ficar em execução (mutex de instância única). Depois de registrar, use "Fechar o aplicativo e iniciar o serviço".\n\nRequisitos:\n- Configure os backups antes de instalar\n- Certifique-se de ter permissões de administrador',
        'Do you want to install Backup Database as a Windows service?\n\nThe service will be configured to:\n- Start automatically with Windows\n- Run without a logged-in user\n- Run under the LocalSystem account\n\nWhile this app is open the service cannot stay running (single-instance mutex). After registration, use "Close the app and start the service".\n\nRequirements:\n- Configure backups before installing\n- Ensure you have administrator permissions',
      ),
      confirmLabel: appLocaleString(context, 'Instalar', 'Install'),
      confirmIcon: FluentIcons.download,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final fallbackError = appLocaleString(
      this.context,
      'Erro desconhecido ao instalar serviço.',
      'Unknown error while installing service.',
    );
    final outcome = await provider.installService();
    if (!mounted) {
      return;
    }
    await _showInstallOutcome(
      provider: provider,
      outcome: outcome,
      fallbackError: fallbackError,
    );
  }

  Future<void> _showInstallOutcome({
    required WindowsServiceProvider provider,
    required WindowsServiceInstallOutcome outcome,
    required String fallbackError,
  }) async {
    switch (outcome) {
      case WindowsServiceInstallOutcome.failed:
        await MessageModal.showError(
          context,
          message: provider.error ?? fallbackError,
        );
      case WindowsServiceInstallOutcome.registeredAndRunning:
        await MessageModal.showSuccess(
          context,
          message: appLocaleString(
            context,
            'Serviço instalado com sucesso!\n\nO serviço está em execução e iniciará automaticamente com o Windows.',
            'Service installed successfully!\n\nThe service is running and will start automatically with Windows.',
          ),
        );
      case WindowsServiceInstallOutcome.registeredStartFailed:
        await MessageModal.showError(
          context,
          message: provider.error ?? fallbackError,
        );
      case WindowsServiceInstallOutcome.registeredBlockedByUiInstance:
        final closeAndStart = await MessageModal.showConfirm(
          context,
          title: appLocaleString(
            context,
            'Serviço instalado',
            'Service installed',
          ),
          message: appLocaleString(
            context,
            'O serviço foi registrado, mas não pode ficar em execução enquanto este aplicativo estiver aberto (mutex de instância única, exit 77).\n\nFeche o aplicativo para o serviço iniciar. Ele também iniciará automaticamente com o Windows.',
            'The service was registered, but it cannot stay running while this app is open (single-instance mutex, exit 77).\n\nClose the app so the service can start. It will also start automatically with Windows.',
          ),
          confirmLabel: appLocaleString(
            context,
            'Fechar o aplicativo e iniciar o serviço',
            'Close the app and start the service',
          ),
          confirmIcon: FluentIcons.play,
        );
        if (!closeAndStart || !mounted) {
          return;
        }
        final handedOff = await provider.scheduleStartAfterUiExit();
        if (!mounted) {
          return;
        }
        if (!handedOff) {
          await MessageModal.showError(
            context,
            message:
                provider.error ??
                appLocaleString(
                  context,
                  'Não foi possível agendar o início do serviço. Feche o aplicativo e use Iniciar, ou confirme o prompt UAC.',
                  'Could not schedule the service start. Close the app and click Start, or confirm the UAC prompt.',
                ),
          );
          return;
        }
        await AppCleanup.cleanup();
        exit(0);
    }
  }

  Future<void> _uninstallService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    if (!getIt<FeatureAvailabilityService>()
        .isWindowsServiceManagementEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Remover serviço', 'Remove service'),
      message: appLocaleString(
        context,
        'Deseja realmente remover o serviço do Windows?\n\nOs agendamentos e configurações não serão perdidos, mas o serviço não executará mais automaticamente.',
        'Do you really want to remove the Windows service?\n\nSchedules and settings will not be lost, but the service will no longer run automatically.',
      ),
      confirmLabel: appLocaleString(context, 'Remover', 'Remove'),
      confirmIcon: FluentIcons.delete,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final successText = appLocaleString(
      this.context,
      'Serviço removido com sucesso!',
      'Service removed successfully!',
    );
    final fallbackError = appLocaleString(
      this.context,
      'Erro desconhecido ao remover serviço.',
      'Unknown error while removing service.',
    );
    final success = await provider.uninstallService();
    if (!mounted) {
      return;
    }
    await _showOperationResult(
      success: success,
      successMessage: successText,
      errorMessage: provider.error ?? fallbackError,
    );
  }

  Future<void> _startService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    if (!getIt<FeatureAvailabilityService>()
        .isWindowsServiceManagementEnabled) {
      return;
    }
    final successText = appLocaleString(
      this.context,
      'Serviço iniciado com sucesso!',
      'Service started successfully!',
    );
    final fallbackError = appLocaleString(
      this.context,
      'Erro ao iniciar serviço.',
      'Error starting service.',
    );
    final success = await provider.startService();
    if (!mounted) {
      return;
    }
    await _showOperationResult(
      success: success,
      successMessage: successText,
      errorMessage: provider.error ?? fallbackError,
    );
  }

  Future<void> _restartService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    if (!getIt<FeatureAvailabilityService>()
        .isWindowsServiceManagementEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Reiniciar serviço', 'Restart service'),
      message: appLocaleString(
        context,
        'Deseja reiniciar o serviço?\n\nO serviço será parado e iniciado novamente. Os backups em execução serão interrompidos.',
        'Do you want to restart the service?\n\nThe service will be stopped and started again. Running backups will be interrupted.',
      ),
      confirmLabel: appLocaleString(context, 'Reiniciar', 'Restart'),
      confirmIcon: FluentIcons.sync,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final successText = appLocaleString(
      this.context,
      'Serviço reiniciado com sucesso!',
      'Service restarted successfully!',
    );
    final fallbackError = appLocaleString(
      this.context,
      'Erro ao reiniciar serviço.',
      'Error restarting service.',
    );
    final success = await provider.restartService();
    if (!mounted) {
      return;
    }
    await _showOperationResult(
      success: success,
      successMessage: successText,
      errorMessage: provider.error ?? fallbackError,
    );
  }

  Future<void> _stopService(
    BuildContext context,
    WindowsServiceProvider provider,
  ) async {
    if (!getIt<FeatureAvailabilityService>()
        .isWindowsServiceManagementEnabled) {
      return;
    }
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Parar serviço', 'Stop service'),
      message: appLocaleString(
        context,
        'Deseja parar o serviço?\n\nOs backups agendados não serão executados até que o serviço seja iniciado novamente.',
        'Do you want to stop the service?\n\nScheduled backups will not run until the service is started again.',
      ),
      confirmLabel: appLocaleString(context, 'Parar', 'Stop'),
      confirmIcon: FluentIcons.stop,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final successText = appLocaleString(
      this.context,
      'Serviço parado com sucesso!',
      'Service stopped successfully!',
    );
    final fallbackError = appLocaleString(
      this.context,
      'Erro ao parar serviço.',
      'Error stopping service.',
    );
    final success = await provider.stopService();
    if (!mounted) {
      return;
    }
    await _showOperationResult(
      success: success,
      successMessage: successText,
      errorMessage: provider.error ?? fallbackError,
    );
  }

  Future<void> _showOperationResult({
    required bool success,
    required String successMessage,
    required String errorMessage,
  }) async {
    if (!mounted) {
      return;
    }
    if (success) {
      await MessageModal.showSuccess(context, message: successMessage);
      return;
    }
    await MessageModal.showError(context, message: errorMessage);
  }
}
