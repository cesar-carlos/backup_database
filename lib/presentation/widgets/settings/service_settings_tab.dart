import 'dart:async';
import 'dart:io' show Platform;

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
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
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
    setState(() => _localScheduleTimerEnabled = enabled);
    await getIt<IUserPreferencesRepository>().setLocalScheduleTimerEnabled(
      enabled,
    );
    if (getIt.isRegistered<ISchedulerService>()) {
      final scheduler = getIt<ISchedulerService>();
      scheduler.stop();
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
          padding: const EdgeInsets.all(24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
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
                const SizedBox(height: 24),
              ],
              _buildStatusSection(context, provider),
              if (provider.error != null) ...[
                const SizedBox(height: 24),
                _buildErrorSection(context, provider),
              ],
              const SizedBox(height: 24),
              _buildActionsSection(context, provider, serviceUiOk),
              const SizedBox(height: 24),
              _buildLocalScheduleTimerSection(context),
              const SizedBox(height: 24),
              _buildInfoSection(context),
              const SizedBox(height: 24),
              _buildCompatibilitySection(context, features),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCompatibilitySection(
    BuildContext context,
    FeatureAvailabilityService features,
  ) {
    final diagnostics = features.diagnosticSummary();
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Diagnóstico de compatibilidade',
        'Compatibility diagnostics',
      ),
      description: appLocaleString(
        context,
        'Snapshot técnico do ambiente Windows para suporte.',
        'Technical Windows environment snapshot for support.',
      ),
      child: Expander(
        header: Text(
          appLocaleString(
            context,
            'Ver diagnóstico detalhado',
            'View detailed diagnostics',
          ),
        ),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            SettingsTechnicalItem(
              title: appLocaleString(
                context,
                'Snapshot atual',
                'Current snapshot',
              ),
              value: diagnostics,
              description: appLocaleString(
                context,
                'Resumo técnico usado em troubleshooting.',
                'Technical summary used in troubleshooting.',
              ),
              onCopy: () =>
                  unawaited(_copyCompatibilityDiagnostics(diagnostics)),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStatusSection(
    BuildContext context,
    WindowsServiceProvider provider,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Status do serviço', 'Service status'),
      description: appLocaleString(
        context,
        'Estado atual do processo em background e da instalação do serviço.',
        'Current background process state and service installation state.',
      ),
      banner: _shouldShowUacInfoBar(provider)
          ? InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Aguardando confirmação do Administrador (UAC)',
                  'Waiting for Administrator confirmation (UAC)',
                ),
              ),
              content: Text(_getUacInfoBarMessage(provider)),
              severity: InfoBarSeverity.warning,
              isLong: true,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SettingsFactTile(
                label: appLocaleString(context, 'Estado', 'State'),
                value: _getStatusText(provider),
                caption: appLocaleString(
                  context,
                  'Situação observada pelo provedor neste instante.',
                  'State observed by the provider right now.',
                ),
              ),
              if (provider.status?.serviceName != null)
                SettingsFactTile(
                  label: appLocaleString(context, 'Serviço', 'Service'),
                  value: provider.status!.serviceName!,
                  caption: appLocaleString(
                    context,
                    'Nome registrado no Windows Service Manager.',
                    'Name registered in the Windows Service Manager.',
                  ),
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          AppStatusChip(
            label: _getStatusText(provider),
            tone: provider.isLoading
                ? AppStatusChipTone.info
                : provider.isRunning
                ? AppStatusChipTone.success
                : provider.isInstalled
                ? AppStatusChipTone.warning
                : AppStatusChipTone.neutral,
            icon: provider.isLoading
                ? FluentIcons.sync
                : provider.isRunning
                ? FluentIcons.play
                : provider.isInstalled
                ? FluentIcons.pause
                : FluentIcons.circle_ring,
          ),
        ],
      ),
    );
  }

  Widget _buildErrorSection(
    BuildContext context,
    WindowsServiceProvider provider,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Falha recente', 'Recent failure'),
      description: appLocaleString(
        context,
        'Último erro retornado ao consultar ou operar o serviço.',
        'Latest error returned while querying or operating the service.',
      ),
      child: InfoBar(
        title: Text(appLocaleString(context, 'Erro', 'Error')),
        content: SelectableText(provider.error!),
        severity: InfoBarSeverity.error,
        isLong: true,
      ),
    );
  }

  Widget _buildActionsSection(
    BuildContext context,
    WindowsServiceProvider provider,
    bool serviceActionsEnabled,
  ) {
    final actionsDisabled = !serviceActionsEnabled || provider.isLoading;
    final primaryAction = _buildPrimaryAction(
      context,
      provider,
      actionsDisabled,
      serviceActionsEnabled,
    );

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
          primaryAction,
          Button(
            onPressed: provider.isLoading ? null : () => provider.checkStatus(),
            child: Text(
              appLocaleString(context, 'Atualizar status', 'Refresh status'),
            ),
          ),
          if (provider.isInstalled && !provider.isRunning)
            Button(
              onPressed: actionsDisabled
                  ? null
                  : () => unawaited(_uninstallService(context, provider)),
              child: Text(
                appLocaleString(context, 'Remover serviço', 'Remove service'),
              ),
            ),
          if (provider.isRunning)
            Button(
              onPressed: actionsDisabled
                  ? null
                  : () => unawaited(_stopService(context, provider)),
              child: Text(appLocaleString(context, 'Parar', 'Stop')),
            ),
          if (provider.isInstalled && provider.isRunning)
            Button(
              onPressed: actionsDisabled
                  ? null
                  : () => unawaited(_uninstallService(context, provider)),
              child: Text(
                appLocaleString(context, 'Remover serviço', 'Remove service'),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildPrimaryAction(
    BuildContext context,
    WindowsServiceProvider provider,
    bool actionsDisabled,
    bool serviceActionsEnabled,
  ) {
    if (!serviceActionsEnabled) {
      return FilledButton(
        onPressed: provider.isLoading ? null : () => provider.checkStatus(),
        child: Text(
          appLocaleString(context, 'Atualizar status', 'Refresh status'),
        ),
      );
    }

    if (!provider.isInstalled) {
      return FilledButton(
        onPressed: actionsDisabled
            ? null
            : () => unawaited(_installService(context, provider)),
        child: Text(
          appLocaleString(context, 'Instalar serviço', 'Install service'),
        ),
      );
    }

    if (!provider.isRunning) {
      return FilledButton(
        onPressed: actionsDisabled
            ? null
            : () => unawaited(_startService(context, provider)),
        child: Text(appLocaleString(context, 'Iniciar', 'Start')),
      );
    }

    return FilledButton(
      onPressed: actionsDisabled
          ? null
          : () => unawaited(_restartService(context, provider)),
      child: Text(appLocaleString(context, 'Reiniciar', 'Restart')),
    );
  }

  Widget _buildLocalScheduleTimerSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Agendamento automático local',
        'Local automatic scheduling',
      ),
      description: appLocaleString(
        context,
        'Controla o timer local que verifica agendamentos vencidos.',
        'Controls the local timer that checks for due schedules.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (_isLoadingScheduleTimerPref)
            const ProgressRing()
          else
            SettingsToggleRow(
              title: appLocaleString(
                context,
                'Timer de verificação de agendamentos',
                'Schedule check timer',
              ),
              description: appLocaleString(
                context,
                'Quando desativado, apenas execuções manuais e comandos remotos continuam ativos.',
                'When off, only manual runs and remote commands continue to work.',
              ),
              value: _localScheduleTimerEnabled,
              onChanged: (bool enabled) {
                unawaited(_setLocalScheduleTimerEnabled(enabled));
              },
            ),
          if (!_isLoadingScheduleTimerPref && !_localScheduleTimerEnabled) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Reinício recomendado',
                  'Restart recommended',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'Reinicie o serviço do Windows ou o app em modo servidor para aplicar a preferência ao processo em background.',
                  'Restart the Windows service or the app in server mode so the background process applies this preference.',
                ),
              ),
              isLong: true,
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildInfoSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Informações', 'Information'),
      description: appLocaleString(
        context,
        'Referências operacionais do modo serviço em formato compacto.',
        'Operational service-mode references in a compact layout.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Wrap(
            spacing: AppSpacing.md,
            runSpacing: AppSpacing.md,
            children: [
              SettingsFactTile(
                label: appLocaleString(
                  context,
                  'Execução',
                  'Execution',
                ),
                value: appLocaleString(
                  context,
                  'Sem usuário logado',
                  'Without logged-in user',
                ),
                caption: appLocaleString(
                  context,
                  'Backups continuam mesmo sem sessão aberta.',
                  'Backups keep running without an open session.',
                ),
              ),
              SettingsFactTile(
                label: appLocaleString(
                  context,
                  'Inicialização',
                  'Startup',
                ),
                value: appLocaleString(
                  context,
                  'Automática com o Windows',
                  'Automatic with Windows',
                ),
                caption: appLocaleString(
                  context,
                  'Quando o serviço está instalado e habilitado.',
                  'When the service is installed and enabled.',
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          SettingsTechnicalItem(
            title: appLocaleString(context, 'Logs do serviço', 'Service logs'),
            value: '${AppConstants.windowsServiceLogPath}\\',
            description: appLocaleString(
              context,
              'Diretório padrão de logs do Windows Service.',
              'Default Windows Service log directory.',
            ),
            onCopy: () => unawaited(
              _copyPath('${AppConstants.windowsServiceLogPath}\\'),
            ),
            onOpen: () => unawaited(
              _openParentDirectory(
                '${AppConstants.windowsServiceLogPath}\\app.log',
              ),
            ),
            openTooltip: appLocaleString(context, 'Abrir pasta', 'Open folder'),
          ),
        ],
      ),
    );
  }

  String _getStatusText(WindowsServiceProvider provider) {
    if (provider.isLoading) {
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

  bool _shouldShowUacInfoBar(WindowsServiceProvider provider) {
    if (!provider.isLoading) {
      return false;
    }
    return provider.operation == WindowsServiceOperation.install ||
        provider.operation == WindowsServiceOperation.uninstall ||
        provider.operation == WindowsServiceOperation.start ||
        provider.operation == WindowsServiceOperation.stop ||
        provider.operation == WindowsServiceOperation.restart;
  }

  String _getUacInfoBarMessage(WindowsServiceProvider provider) {
    return switch (provider.operation) {
      WindowsServiceOperation.install => appLocaleString(
        context,
        'Confirme o prompt do Windows para instalar o serviço.',
        'Confirm the Windows prompt to install the service.',
      ),
      WindowsServiceOperation.uninstall => appLocaleString(
        context,
        'Confirme o prompt do Windows para remover o serviço.',
        'Confirm the Windows prompt to remove the service.',
      ),
      WindowsServiceOperation.start => appLocaleString(
        context,
        'Confirme o prompt do Windows para iniciar o serviço.',
        'Confirm the Windows prompt to start the service.',
      ),
      WindowsServiceOperation.stop => appLocaleString(
        context,
        'Confirme o prompt do Windows para parar o serviço.',
        'Confirm the Windows prompt to stop the service.',
      ),
      WindowsServiceOperation.restart => appLocaleString(
        context,
        'Confirme o prompt do Windows para reiniciar o serviço.',
        'Confirm the Windows prompt to restart the service.',
      ),
      _ => appLocaleString(
        context,
        'Confirme o prompt do Windows para continuar.',
        'Confirm the Windows prompt to continue.',
      ),
    };
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
        'Deseja instalar o Backup Database como serviço do Windows?\n\nO serviço será configurado para:\n- Iniciar automaticamente com o Windows\n- Executar sem usuário logado\n- Rodar com conta LocalSystem\n\nRequisitos:\n- Configure os backups antes de instalar\n- Certifique-se de ter permissões de administrador',
        'Do you want to install Backup Database as a Windows service?\n\nThe service will be configured to:\n- Start automatically with Windows\n- Run without logged-in user\n- Run under LocalSystem account\n\nRequirements:\n- Configure backups before installing\n- Ensure you have administrator permissions',
      ),
      confirmLabel: appLocaleString(context, 'Instalar', 'Install'),
      confirmIcon: FluentIcons.download,
    );
    if (!confirmed || !mounted) {
      return;
    }
    final successText = appLocaleString(
      this.context,
      'Serviço instalado com sucesso!\n\nO serviço foi configurado e iniciará automaticamente com o Windows.',
      'Service installed successfully!\n\nThe service was configured and will start automatically with Windows.',
    );
    final fallbackError = appLocaleString(
      this.context,
      'Erro desconhecido ao instalar serviço.',
      'Unknown error while installing service.',
    );
    final success = await provider.installService();
    if (!mounted) {
      return;
    }
    await _showOperationResult(
      success: success,
      successMessage: successText,
      errorMessage: provider.error ?? fallbackError,
    );
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
