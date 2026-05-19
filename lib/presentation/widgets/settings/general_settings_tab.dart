import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/theme/app_colors.dart';
import 'package:backup_database/core/theme/tokens/app_density.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/i_user_preferences_repository.dart';
import 'package:backup_database/presentation/boot/windows_native_chrome_bootstrap.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/machine_storage_settings_section.dart';
import 'package:file_picker/file_picker.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:provider/provider.dart';

class GeneralSettingsTab extends StatefulWidget {
  const GeneralSettingsTab({super.key});

  @override
  State<GeneralSettingsTab> createState() => _GeneralSettingsTabState();
}

class _GeneralSettingsTabState extends State<GeneralSettingsTab> {
  PackageInfo? _packageInfo;
  bool _isLoadingVersion = true;
  String? _tempDownloadsPath;
  bool _isLoadingTempPath = false;
  bool _useWindowsMicaBackdrop = true;

  final TempDirectoryService _tempService = getIt<TempDirectoryService>();

  @override
  void initState() {
    super.initState();
    unawaited(_loadPackageInfo());
    unawaited(_loadTempPath());
    unawaited(_loadWindowsChromePrefs());
  }

  Future<void> _loadWindowsChromePrefs() async {
    if (!Platform.isWindows) {
      return;
    }
    try {
      final repo = getIt<IUserPreferencesRepository>();
      final v = await repo.getUseWindowsMicaBackdrop();
      if (mounted) {
        setState(() => _useWindowsMicaBackdrop = v);
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar preferência Mica', e, s);
    }
  }

  Future<void> _loadPackageInfo() async {
    try {
      final packageInfo = await PackageInfo.fromPlatform();
      if (mounted) {
        setState(() {
          _packageInfo = packageInfo;
          _isLoadingVersion = false;
        });
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar informações do pacote', e, s);
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  Future<void> _loadTempPath() async {
    if (!mounted) return;
    setState(() => _isLoadingTempPath = true);
    try {
      final dir = await _tempService.getDownloadsDirectory();
      if (mounted) {
        setState(() {
          _tempDownloadsPath = dir.path;
          _isLoadingTempPath = false;
        });
      }
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao carregar pasta temporária', e, s);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
      }
    }
  }

  Future<void> _changeTempPath() async {
    final result = await FilePicker.platform.getDirectoryPath(
      dialogTitle: appLocaleString(
        context,
        'Selecionar pasta temporária de downloads',
        'Select temporary downloads folder',
      ),
    );
    if (result != null && mounted) {
      setState(() => _isLoadingTempPath = true);
      final success = await _tempService.setCustomTempPath(result);
      if (mounted) {
        setState(() => _isLoadingTempPath = false);
        if (!success) {
          unawaited(
            MessageModal.showError(
              context,
              message: appLocaleString(
                context,
                'Não foi possível definir a pasta temporária. Verifique se tem permissão de escrita.',
                'Could not set temporary folder. Check write permissions.',
              ),
            ),
          );
          return;
        }
        await _loadTempPath();
        if (!mounted) {
          return;
        }
        unawaited(
          FluentInfoBarFeedback.showSuccess(
            context,
            message: appLocaleString(
              context,
              'Pasta temporária alterada com sucesso!',
              'Temporary folder changed successfully!',
            ),
          ),
        );
      }
    }
  }

  Future<void> _resetTempPath() async {
    final confirmed = await MessageModal.showConfirm(
      context,
      title: appLocaleString(context, 'Confirmar', 'Confirm'),
      message: appLocaleString(
        context,
        'Deseja voltar a usar a pasta temporária padrão do sistema?',
        'Do you want to use the system default temporary folder again?',
      ),
      confirmLabel: appLocaleString(context, 'Confirmar', 'Confirm'),
      confirmIcon: FluentIcons.refresh,
    );
    if (confirmed && mounted) {
      await _tempService.clearCustomTempPath();
      await _loadTempPath();
    }
  }

  String _buildAutoUpdateStatusText(AutoUpdateProvider provider) {
    switch (provider.status) {
      case AppUpdateStatus.idle:
        return appLocaleString(
          context,
          'Pronto para verificar novas versoes.',
          'Ready to check for new versions.',
        );
      case AppUpdateStatus.checking:
        return appLocaleString(
          context,
          'Verificando appcast e comparando versoes...',
          'Checking appcast and comparing versions...',
        );
      case AppUpdateStatus.updateAvailable:
        return appLocaleString(
          context,
          'Nova versao encontrada. O download silencioso sera iniciado.',
          'New version found. Silent download will start.',
        );
      case AppUpdateStatus.downloading:
        return appLocaleString(
          context,
          'Baixando instalador para staging local...',
          'Downloading installer to local staging...',
        );
      case AppUpdateStatus.installing:
        return appLocaleString(
          context,
          'Instalador silencioso em andamento.',
          'Silent installer is running.',
        );
      case AppUpdateStatus.blockedByOtherInstance:
        return appLocaleString(
          context,
          'Outra instancia ja esta processando o auto update.',
          'Another instance is already processing the auto update.',
        );
      case AppUpdateStatus.blockedByActiveBackup:
        return appLocaleString(
          context,
          'Ha um backup ativo. Aguarde a conclusao antes de atualizar.',
          'There is an active backup. Wait for it to finish before updating.',
        );
      case AppUpdateStatus.handoffCompleted:
        return appLocaleString(
          context,
          'Handoff concluido. O instalador silencioso assumiu a troca.',
          'Handoff completed. The silent installer took over the update.',
        );
      case AppUpdateStatus.upToDate:
        return appLocaleString(
          context,
          'A aplicacao ja esta na versao mais recente.',
          'The application is already up to date.',
        );
      case AppUpdateStatus.error:
        return appLocaleString(
          context,
          'A ultima tentativa falhou. Revise o erro abaixo.',
          'The last attempt failed. Review the error below.',
        );
      case AppUpdateStatus.disabled:
        return appLocaleString(
          context,
          r'Configure AUTO_UPDATE_FEED_URL em C:\ProgramData\BackupDatabase\config\.env.',
          r'Configure AUTO_UPDATE_FEED_URL in C:\ProgramData\BackupDatabase\config\.env.',
        );
    }
  }

  String _buildAutoUpdateStageText(AppUpdateStage? stage) {
    if (stage == null) {
      return appLocaleString(
        context,
        'Sem etapa registrada',
        'No stage recorded',
      );
    }

    switch (stage) {
      case AppUpdateStage.blockedByOtherInstance:
        return appLocaleString(
          context,
          'Bloqueado por outra instancia',
          'Blocked by another instance',
        );
      case AppUpdateStage.blockedByActiveBackup:
        return appLocaleString(
          context,
          'Bloqueado por backup ativo',
          'Blocked by active backup',
        );
      case AppUpdateStage.fetchingFeed:
        return appLocaleString(
          context,
          'Baixando appcast',
          'Downloading appcast',
        );
      case AppUpdateStage.evaluatingRelease:
        return appLocaleString(
          context,
          'Avaliando release',
          'Evaluating release',
        );
      case AppUpdateStage.downloadingInstaller:
        return appLocaleString(
          context,
          'Baixando instalador',
          'Downloading installer',
        );
      case AppUpdateStage.validatingInstaller:
        return appLocaleString(
          context,
          'Validando instalador',
          'Validating installer',
        );
      case AppUpdateStage.preparingInstall:
        return appLocaleString(
          context,
          'Preparando instalacao',
          'Preparing installation',
        );
      case AppUpdateStage.launchingInstaller:
        return appLocaleString(
          context,
          'Disparando instalador silencioso',
          'Launching silent installer',
        );
      case AppUpdateStage.completed:
        return appLocaleString(context, 'Ciclo concluido', 'Cycle completed');
    }
  }

  String _buildAutoUpdateSourceText(AppUpdateSource? source) {
    switch (source) {
      case AppUpdateSource.startup:
        return appLocaleString(context, 'Startup', 'Startup');
      case AppUpdateSource.manual:
        return appLocaleString(context, 'Manual', 'Manual');
      case AppUpdateSource.periodic:
        return appLocaleString(context, 'Periodico', 'Periodic');
      case null:
        return appLocaleString(context, 'Desconhecida', 'Unknown');
    }
  }

  String _formatAutoUpdateDuration(Duration? duration) {
    if (duration == null) {
      return appLocaleString(context, 'Nao disponivel', 'Not available');
    }
    return '${duration.inMilliseconds} ms';
  }

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);
    final systemSettings = Provider.of<SystemSettingsProvider>(context);
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);
    final features = getIt<FeatureAvailabilityService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildAppearanceSection(context, themeProvider),
          const SizedBox(height: 24),
          _buildSystemSection(context, systemSettings, features),
          if (currentAppMode == AppMode.client) ...[
            const SizedBox(height: 24),
            _buildClientDownloadsSection(context),
          ],
          const SizedBox(height: 24),
          const MachineStorageSettingsSection(),
          const SizedBox(height: 24),
          _buildUpdatesSection(context, autoUpdateProvider, features),
          const SizedBox(height: 24),
          _buildAboutSection(context),
        ],
      ),
    );
  }

  Widget _buildAppearanceSection(
    BuildContext context,
    ThemeProvider themeProvider,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Aparencia', 'Appearance'),
      description: appLocaleString(
        context,
        'Preferencias visuais e de densidade da interface.',
        'Visual and density preferences for the interface.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: appLocaleString(context, 'Tema escuro', 'Dark theme'),
            child: ToggleSwitch(
              checked: themeProvider.isDarkMode,
              onChanged: themeProvider.setDarkMode,
            ),
          ),
          if (Platform.isWindows) ...[
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Backdrop Mica (Windows 11)',
                'Mica backdrop (Windows 11)',
              ),
              child: ToggleSwitch(
                checked: _useWindowsMicaBackdrop,
                onChanged: (bool enabled) async {
                  setState(() => _useWindowsMicaBackdrop = enabled);
                  await getIt<IUserPreferencesRepository>()
                      .setUseWindowsMicaBackdrop(enabled);
                  await WindowsNativeChromeBootstrap.setBackdrop(
                    micaEnabled: enabled,
                    isDark: themeProvider.isDarkMode,
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocaleString(
                context,
                'No Windows 10 o efeito pode não estar disponível; o sistema ignora silenciosamente.',
                'On Windows 10 the effect may be unavailable; the system may ignore it silently.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
            const SizedBox(height: 16),
            InfoLabel(
              label: appLocaleString(
                context,
                'Cor de destaque do sistema',
                'System accent color',
              ),
              child: ToggleSwitch(
                checked: themeProvider.useSystemAccentColor,
                onChanged: themeProvider.setUseSystemAccentColor,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              appLocaleString(
                context,
                'Quando ativo, botões e realces seguem o accent do Windows em vez da cor da marca.',
                'When on, buttons and highlights follow the Windows accent instead of the brand color.',
              ),
              style: FluentTheme.of(context).typography.caption,
            ),
          ],
          const SizedBox(height: 16),
          Consumer<AppDensityProvider>(
            builder: (context, densityProvider, _) {
              return InfoLabel(
                label: appLocaleString(
                  context,
                  'Densidade das tabelas',
                  'Table density',
                ),
                child: ComboBox<AppDensity>(
                  value: densityProvider.density,
                  items: [
                    ComboBoxItem(
                      value: AppDensity.compact,
                      child: Text(
                        appLocaleString(context, 'Compacta', 'Compact'),
                      ),
                    ),
                    ComboBoxItem(
                      value: AppDensity.comfortable,
                      child: Text(
                        appLocaleString(context, 'Confortavel', 'Comfortable'),
                      ),
                    ),
                    ComboBoxItem(
                      value: AppDensity.spacious,
                      child: Text(
                        appLocaleString(context, 'Espacosa', 'Spacious'),
                      ),
                    ),
                  ],
                  onChanged: (AppDensity? value) {
                    if (value != null) {
                      unawaited(densityProvider.setDensity(value));
                    }
                  },
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          Consumer<SkeletonLoadingPreferenceProvider>(
            builder: (context, skeletonPrefs, _) {
              return InfoLabel(
                label: appLocaleString(
                  context,
                  'Animacoes de carregamento',
                  'Loading animations',
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    ToggleSwitch(
                      checked: skeletonPrefs.shimmerLoadingEffectsEnabled,
                      onChanged: (bool enabled) {
                        unawaited(
                          skeletonPrefs.setShimmerLoadingEffectsEnabled(
                            enabled,
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 4),
                    Text(
                      appLocaleString(
                        context,
                        'Desative para reduzir movimento na tela (acessibilidade).',
                        'Turn off to reduce on-screen motion (accessibility).',
                      ),
                      style: FluentTheme.of(context).typography.caption,
                    ),
                  ],
                ),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _buildSystemSection(
    BuildContext context,
    SystemSettingsProvider systemSettings,
    FeatureAvailabilityService features,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Sistema', 'System'),
      description: appLocaleString(
        context,
        'Comportamento de inicializacao, bandeja e integracao com o Windows.',
        'Startup, tray and Windows integration behavior.',
      ),
      banner: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!features.isTrayEnabled) ...[
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Bandeja do sistema',
                  'System tray',
                ),
              ),
              content: Text(
                localizeCompatibilityReason(
                  context,
                  reason: features.trayDisabledReason,
                  fallbackPt:
                      'Minimizar ou fechar para a bandeja não está disponível nesta versão do Windows.',
                  fallbackEn:
                      'Minimize or close to tray is not available on this Windows version.',
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
            const SizedBox(height: 12),
          ],
          if (!features.isStartupAtLogonTaskEnabled)
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Inicio com o Windows',
                  'Start with Windows',
                ),
              ),
              content: Text(
                localizeCompatibilityReason(
                  context,
                  reason: features.startupAtLogonTaskDisabledReason,
                  fallbackPt:
                      'A tarefa de início no logon não está disponível nesta versão do Windows.',
                  fallbackEn:
                      'Logon startup task is not available on this Windows version.',
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InfoLabel(
            label: appLocaleString(
              context,
              'Iniciar com o Windows',
              'Start with Windows',
            ),
            child: ToggleSwitch(
              checked: systemSettings.startWithWindows,
              onChanged: features.isStartupAtLogonTaskEnabled
                  ? systemSettings.setStartWithWindows
                  : null,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            currentAppMode == AppMode.server
                ? appLocaleString(
                    context,
                    'No modo servidor o arranque automático é feito pelo Windows Service (aba Serviço). Esta opção apenas guarda a preferência na máquina.',
                    'In server mode, automatic startup is handled by the Windows Service (Service tab). This option only stores the preference for this machine.',
                  )
                : appLocaleString(
                    context,
                    'A tarefa de início aplica-se a todos os utilizadores deste PC. Pode ser necessário executar a aplicação como administrador para criar ou remover a tarefa.',
                    'The startup task applies to all users on this PC. You may need to run the app as administrator to create or remove the task.',
                  ),
            style: FluentTheme.of(context).typography.caption,
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: appLocaleString(
              context,
              'Iniciar minimizado',
              'Start minimized',
            ),
            child: ToggleSwitch(
              checked: systemSettings.startMinimized,
              onChanged: systemSettings.setStartMinimized,
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: appLocaleString(
              context,
              'Minimizar para bandeja',
              'Minimize to tray',
            ),
            child: ToggleSwitch(
              checked: systemSettings.minimizeToTray,
              onChanged: features.isTrayEnabled
                  ? systemSettings.setMinimizeToTray
                  : null,
            ),
          ),
          const SizedBox(height: 16),
          InfoLabel(
            label: appLocaleString(
              context,
              'Fechar para bandeja',
              'Close to tray',
            ),
            child: ToggleSwitch(
              checked: systemSettings.closeToTray,
              onChanged: features.isTrayEnabled
                  ? systemSettings.setCloseToTray
                  : null,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildClientDownloadsSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(
        context,
        'Pasta temporaria de downloads (cliente)',
        'Temporary downloads folder (client)',
      ),
      description: appLocaleString(
        context,
        'Arquivos baixados do servidor são salvos temporariamente aqui antes de serem enviados para os destinos finais.',
        'Files downloaded from the server are stored here temporarily before being sent to final destinations.',
      ),
      footer: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          AppButton.icon(
            icon: FluentIcons.folder_open,
            label: appLocaleString(context, 'Alterar pasta', 'Change folder'),
            onPressed: () => unawaited(_changeTempPath()),
          ),
          AppButton.icon(
            icon: FluentIcons.refresh,
            label: appLocaleString(
              context,
              'Usar padrao do sistema',
              'Use system default',
            ),
            onPressed: () => unawaited(_resetTempPath()),
          ),
        ],
      ),
      child: ListTile(
        title: Text(appLocaleString(context, 'Pasta atual', 'Current folder')),
        subtitle: _isLoadingTempPath
            ? Text(appLocaleString(context, 'Carregando...', 'Loading...'))
            : SelectableText(
                _tempDownloadsPath ??
                    appLocaleString(context, 'Desconhecida', 'Unknown'),
              ),
        trailing: _isLoadingTempPath
            ? const SizedBox(
                width: 20,
                height: 20,
                child: ProgressRing(strokeWidth: 2),
              )
            : Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(FluentIcons.folder_open),
                    onPressed: () => unawaited(_changeTempPath()),
                  ),
                  IconButton(
                    icon: const Icon(FluentIcons.refresh),
                    onPressed: () => unawaited(_loadTempPath()),
                  ),
                ],
              ),
      ),
    );
  }

  Widget _buildUpdatesSection(
    BuildContext context,
    AutoUpdateProvider autoUpdateProvider,
    FeatureAvailabilityService features,
  ) {
    return AppSectionCard(
      title: appLocaleString(context, 'Atualizacoes', 'Updates'),
      description: appLocaleString(
        context,
        'Monitoramento do ciclo de auto update, feed configurado e arquivos de suporte operacional.',
        'Auto-update lifecycle monitoring, configured feed and operational support files.',
      ),
      banner: !features.isAutoUpdateEnabled
          ? InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Atualizacoes automaticas indisponiveis',
                  'Automatic updates unavailable',
                ),
              ),
              content: Text(
                localizeCompatibilityReason(
                  context,
                  reason: features.autoUpdateDisabledReason,
                  fallbackPt: 'Não suportado nesta versão do Windows.',
                  fallbackEn: 'Not supported on this Windows version.',
                ),
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            )
          : null,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (!features.isAutoUpdateEnabled)
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Atualizacoes automaticas',
                  'Automatic updates',
                ),
              ),
              subtitle: Text(_buildAutoUpdateStatusText(autoUpdateProvider)),
              trailing: const Icon(FluentIcons.info),
            )
          else if (!autoUpdateProvider.isInitialized)
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Atualizacoes automaticas',
                  'Automatic updates',
                ),
              ),
              subtitle: Text(
                autoUpdateProvider.statusMessage ??
                    _buildAutoUpdateStatusText(autoUpdateProvider),
              ),
              trailing: const Icon(FluentIcons.info),
            )
          else ...[
            ListTile(
              title: Text(
                appLocaleString(context, 'Status do updater', 'Updater status'),
              ),
              subtitle: Text(
                autoUpdateProvider.statusMessage ??
                    _buildAutoUpdateStatusText(autoUpdateProvider),
              ),
              trailing: autoUpdateProvider.targetVersion != null
                  ? Text(
                      'v${autoUpdateProvider.targetVersion}',
                      style: FluentTheme.of(context).typography.caption,
                    )
                  : const Icon(FluentIcons.info),
            ),
            if (autoUpdateProvider.feedUrl != null)
              ListTile(
                title: Text(
                  appLocaleString(
                    context,
                    'Feed configurado',
                    'Configured feed',
                  ),
                ),
                subtitle: SelectableText(autoUpdateProvider.feedUrl!),
                trailing: const Icon(FluentIcons.link),
              ),
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Verificar atualizacoes',
                  'Check for updates',
                ),
              ),
              subtitle: Text(
                autoUpdateProvider.lastCheckDate != null
                    ? appLocaleLastUpdateCheckSubtitle(
                        context,
                        autoUpdateProvider.lastCheckDate!,
                      )
                    : appLocaleString(
                        context,
                        'Nunca verificado',
                        'Never checked',
                      ),
              ),
              trailing: autoUpdateProvider.isChecking
                  ? const SizedBox(
                      width: 20,
                      height: 20,
                      child: ProgressRing(strokeWidth: 2),
                    )
                  : IconButton(
                      icon: const Icon(FluentIcons.refresh),
                      onPressed: autoUpdateProvider.isChecking
                          ? null
                          : autoUpdateProvider.checkForUpdates,
                    ),
            ),
            if (autoUpdateProvider.lastErrorDate != null)
              ListTile(
                title: Text(
                  appLocaleString(context, 'Ultima falha', 'Last failure'),
                ),
                subtitle: Text(
                  autoUpdateProvider.lastErrorDate!.toLocal().toString(),
                ),
                trailing: const Icon(FluentIcons.warning),
              ),
            if (autoUpdateProvider.lastAttemptNumber != null)
              ListTile(
                title: Text(
                  appLocaleString(context, 'Ultimo ciclo', 'Last cycle'),
                ),
                subtitle: Text(
                  '#${autoUpdateProvider.lastAttemptNumber} â€¢ '
                  '${_buildAutoUpdateSourceText(autoUpdateProvider.lastSource)} â€¢ '
                  '${_buildAutoUpdateStageText(autoUpdateProvider.currentStage)}',
                ),
                trailing: const Icon(FluentIcons.timeline),
              ),
            if (autoUpdateProvider.lastCheckDuration != null ||
                autoUpdateProvider.lastDownloadDuration != null)
              ListTile(
                title: Text(
                  appLocaleString(
                    context,
                    'Telemetria do updater',
                    'Updater telemetry',
                  ),
                ),
                subtitle: Text(
                  appLocaleString(
                    context,
                    'Ciclo: ${_formatAutoUpdateDuration(autoUpdateProvider.lastCheckDuration)} â€¢ '
                        'Download: ${_formatAutoUpdateDuration(autoUpdateProvider.lastDownloadDuration)}',
                    'Cycle: ${_formatAutoUpdateDuration(autoUpdateProvider.lastCheckDuration)} â€¢ '
                        'Download: ${_formatAutoUpdateDuration(autoUpdateProvider.lastDownloadDuration)}',
                  ),
                ),
                trailing: const Icon(FluentIcons.speed_high),
              ),
            if (autoUpdateProvider.lastFailureStage != null)
              ListTile(
                title: Text(
                  appLocaleString(
                    context,
                    'Etapa da ultima falha',
                    'Last failure stage',
                  ),
                ),
                subtitle: Text(
                  _buildAutoUpdateStageText(
                    autoUpdateProvider.lastFailureStage,
                  ),
                ),
                trailing: const Icon(FluentIcons.warning),
              ),
            if (autoUpdateProvider.error != null)
              ListTile(
                title: Text(appLocaleString(context, 'Erro', 'Error')),
                subtitle: Text(
                  autoUpdateProvider.error!,
                  style: FluentTheme.of(context).typography.body?.copyWith(
                    color: const Color(0xFFF44336),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(FluentIcons.cancel),
                  onPressed: autoUpdateProvider.clearError,
                ),
              ),
            if (autoUpdateProvider.updateAvailable)
              ListTile(
                title: Text(
                  appLocaleString(
                    context,
                    'Atualizacao disponivel',
                    'Update available',
                  ),
                ),
                subtitle: Text(
                  appLocaleString(
                    context,
                    'Uma nova versao esta disponivel para download',
                    'A new version is available for download',
                  ),
                ),
                leading: const Icon(
                  FluentIcons.update_restore,
                  color: AppColors.primary,
                ),
              ),
          ],
          if (features.isAutoUpdateEnabled) ...[
            const SizedBox(height: 8),
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Arquivos de suporte do updater',
                  'Updater support files',
                ),
              ),
              subtitle: SelectableText(autoUpdateProvider.updateContextPath),
              trailing: const Icon(FluentIcons.document_management),
            ),
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Historico operacional',
                  'Operational history',
                ),
              ),
              subtitle: SelectableText(autoUpdateProvider.diagnosticsPath),
              trailing: const Icon(FluentIcons.history),
            ),
            ListTile(
              title: Text(
                appLocaleString(
                  context,
                  'Lock global do updater',
                  'Updater global lock',
                ),
              ),
              subtitle: SelectableText(autoUpdateProvider.lockFilePath),
              trailing: const Icon(FluentIcons.lock),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Sobre', 'About'),
      description: appLocaleString(
        context,
        'Metadados da instalação local da aplicação.',
        'Metadata for the local app installation.',
      ),
      child: Column(
        children: [
          ListTile(
            title: Text(appLocaleString(context, 'Versao', 'Version')),
            subtitle: _isLoadingVersion
                ? Text(appLocaleString(context, 'Carregando...', 'Loading...'))
                : Text(
                    _packageInfo != null
                        ? (_packageInfo!.buildNumber.isNotEmpty
                              ? '${_packageInfo!.version}+${_packageInfo!.buildNumber}'
                              : _packageInfo!.version)
                        : appLocaleString(context, 'Desconhecida', 'Unknown'),
                  ),
          ),
          ListTile(
            title: Text(appLocaleString(context, 'Licenca', 'License')),
            subtitle: const Text('MIT License'),
          ),
        ],
      ),
    );
  }
}
