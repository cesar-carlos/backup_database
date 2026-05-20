import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/tokens/tokens.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/presentation/providers/providers.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class SystemSettingsTab extends StatefulWidget {
  const SystemSettingsTab({super.key});

  @override
  State<SystemSettingsTab> createState() => _SystemSettingsTabState();
}

class _SystemSettingsTabState extends State<SystemSettingsTab> {
  PackageInfo? _packageInfo;
  bool _isLoadingVersion = true;
  late final ClipboardService _clipboardService;

  @override
  void initState() {
    super.initState();
    _clipboardService = getIt<ClipboardService>();
    unawaited(_loadPackageInfo());
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
    } on Object {
      if (mounted) {
        setState(() {
          _isLoadingVersion = false;
        });
      }
    }
  }

  Future<void> _copyValue(
    String value, {
    required String successMessage,
    required String errorMessage,
  }) async {
    final success = await _clipboardService.copyToClipboard(value);
    if (!mounted) {
      return;
    }
    if (success) {
      await FluentInfoBarFeedback.showSuccess(
        context,
        message: successMessage,
      );
      return;
    }
    await MessageModal.showError(context, message: errorMessage);
  }

  Future<void> _openUrl(String value) async {
    final uri = Uri.tryParse(value);
    if (uri == null) {
      await MessageModal.showError(
        context,
        message: appLocaleString(
          context,
          'URL inválida para abertura externa.',
          'Invalid URL for external launch.',
        ),
      );
      return;
    }
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
        'Não foi possível abrir o link.',
        'Could not open the link.',
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

  String _buildAutoUpdateStatusText(AutoUpdateProvider provider) {
    switch (provider.status) {
      case AppUpdateStatus.idle:
        return appLocaleString(
          context,
          'Pronto para verificar novas versões.',
          'Ready to check for new versions.',
        );
      case AppUpdateStatus.checking:
        return appLocaleString(
          context,
          'Verificando feed e comparando versões.',
          'Checking feed and comparing versions.',
        );
      case AppUpdateStatus.updateAvailable:
        return appLocaleString(
          context,
          'Nova versão encontrada para download silencioso.',
          'New version found for silent download.',
        );
      case AppUpdateStatus.downloading:
        return appLocaleString(
          context,
          'Baixando instalador para staging local.',
          'Downloading installer to local staging.',
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
          'Outra instância já está processando o auto update.',
          'Another instance is already processing the auto update.',
        );
      case AppUpdateStatus.blockedByActiveBackup:
        return appLocaleString(
          context,
          'Há um backup ativo. Aguarde a conclusão antes de atualizar.',
          'There is an active backup. Wait for it to finish before updating.',
        );
      case AppUpdateStatus.handoffCompleted:
        return appLocaleString(
          context,
          'Handoff concluído para o instalador silencioso.',
          'Handoff completed to the silent installer.',
        );
      case AppUpdateStatus.upToDate:
        return appLocaleString(
          context,
          'A aplicação já está na versão mais recente.',
          'The application is already up to date.',
        );
      case AppUpdateStatus.error:
        return appLocaleString(
          context,
          'A última tentativa falhou. Revise o erro abaixo.',
          'The last attempt failed. Review the error below.',
        );
      case AppUpdateStatus.disabled:
        return appLocaleString(
          context,
          'Atualizações automáticas indisponíveis neste ambiente.',
          'Automatic updates are unavailable in this environment.',
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
          'Bloqueado por outra instância',
          'Blocked by another instance',
        );
      case AppUpdateStage.blockedByActiveBackup:
        return appLocaleString(
          context,
          'Bloqueado por backup ativo',
          'Blocked by active backup',
        );
      case AppUpdateStage.fetchingFeed:
        return appLocaleString(context, 'Baixando feed', 'Downloading feed');
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
          'Preparando instalação',
          'Preparing installation',
        );
      case AppUpdateStage.launchingInstaller:
        return appLocaleString(
          context,
          'Disparando instalador',
          'Launching installer',
        );
      case AppUpdateStage.completed:
        return appLocaleString(context, 'Ciclo concluído', 'Cycle completed');
    }
  }

  String _buildAutoUpdateSourceText(AppUpdateSource? source) {
    switch (source) {
      case AppUpdateSource.startup:
        return appLocaleString(context, 'Startup', 'Startup');
      case AppUpdateSource.manual:
        return appLocaleString(context, 'Manual', 'Manual');
      case AppUpdateSource.periodic:
        return appLocaleString(context, 'Periódico', 'Periodic');
      case null:
        return appLocaleString(context, 'Desconhecida', 'Unknown');
    }
  }

  String _formatAutoUpdateDuration(Duration? duration) {
    if (duration == null) {
      return appLocaleString(context, 'Não disponível', 'Not available');
    }
    return '${duration.inMilliseconds} ms';
  }

  AppStatusChipTone _statusTone(AutoUpdateProvider provider) {
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

  String _modeLabel() {
    return switch (currentAppMode) {
      AppMode.client => appLocaleString(context, 'Cliente', 'Client'),
      AppMode.server => appLocaleString(context, 'Servidor', 'Server'),
      AppMode.unified => appLocaleString(context, 'Unificado', 'Unified'),
    };
  }

  String _versionLabel() {
    if (_isLoadingVersion) {
      return appLocaleString(context, 'Carregando...', 'Loading...');
    }
    if (_packageInfo == null) {
      return appLocaleString(context, 'Desconhecida', 'Unknown');
    }
    if (_packageInfo!.buildNumber.isNotEmpty) {
      return '${_packageInfo!.version}+${_packageInfo!.buildNumber}';
    }
    return _packageInfo!.version;
  }

  @override
  Widget build(BuildContext context) {
    final systemSettings = Provider.of<SystemSettingsProvider>(context);
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);
    final features = getIt<FeatureAvailabilityService>();

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildStartupSection(context, systemSettings, features),
          const SizedBox(height: 24),
          _buildTraySection(context, systemSettings, features),
          const SizedBox(height: 24),
          _buildUpdatesSection(context, autoUpdateProvider, features),
          const SizedBox(height: 24),
          _buildAboutSection(context),
        ],
      ),
    );
  }

  Widget _buildStartupSection(
    BuildContext context,
    SystemSettingsProvider systemSettings,
    FeatureAvailabilityService features,
  ) {
    final startupDisabledReason = !features.isStartupAtLogonTaskEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.startupAtLogonTaskDisabledReason,
            fallbackPt:
                'A tarefa de início no logon não está disponível nesta versão do Windows.',
            fallbackEn:
                'Logon startup task is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Inicialização', 'Startup'),
      description: appLocaleString(
        context,
        'Preferências de arranque da aplicação na máquina atual.',
        'Startup preferences for the current machine.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar com o Windows',
              'Start with Windows',
            ),
            description: currentAppMode == AppMode.server
                ? appLocaleString(
                    context,
                    'No modo servidor, o arranque automático real é controlado pela aba Serviço Windows.',
                    'In server mode, real automatic startup is controlled from the Windows Service tab.',
                  )
                : appLocaleString(
                    context,
                    'Cria ou remove a tarefa de arranque para esta instalação.',
                    'Creates or removes the startup task for this installation.',
                  ),
            value: systemSettings.startWithWindows,
            onChanged: features.isStartupAtLogonTaskEnabled
                ? systemSettings.setStartWithWindows
                : null,
            disabledReason: startupDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Iniciar minimizado',
              'Start minimized',
            ),
            description: appLocaleString(
              context,
              'Abre a aplicação já minimizada na próxima inicialização.',
              'Opens the application minimized on the next startup.',
            ),
            value: systemSettings.startMinimized,
            onChanged: systemSettings.setStartMinimized,
          ),
        ],
      ),
    );
  }

  Widget _buildTraySection(
    BuildContext context,
    SystemSettingsProvider systemSettings,
    FeatureAvailabilityService features,
  ) {
    final trayDisabledReason = !features.isTrayEnabled
        ? localizeCompatibilityReason(
            context,
            reason: features.trayDisabledReason,
            fallbackPt:
                'A bandeja do sistema não está disponível nesta versão do Windows.',
            fallbackEn: 'System tray is not available on this Windows version.',
          )
        : null;

    return AppSectionCard(
      title: appLocaleString(context, 'Bandeja', 'Tray'),
      description: appLocaleString(
        context,
        'Define como a janela se comporta ao minimizar ou fechar.',
        'Defines how the window behaves when minimizing or closing.',
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Minimizar para bandeja',
              'Minimize to tray',
            ),
            description: appLocaleString(
              context,
              'Mantém o app em segundo plano ao minimizar a janela.',
              'Keeps the app running in the background when the window is minimized.',
            ),
            value: systemSettings.minimizeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setMinimizeToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
          const SizedBox(height: AppSpacing.lg),
          SettingsToggleRow(
            title: appLocaleString(
              context,
              'Fechar para bandeja',
              'Close to tray',
            ),
            description: appLocaleString(
              context,
              'Fecha a janela principal, mas mantém o processo na bandeja.',
              'Closes the main window while keeping the process in the system tray.',
            ),
            value: systemSettings.closeToTray,
            onChanged: features.isTrayEnabled
                ? systemSettings.setCloseToTray
                : null,
            disabledReason: trayDisabledReason,
          ),
        ],
      ),
    );
  }

  Widget _buildUpdatesSection(
    BuildContext context,
    AutoUpdateProvider autoUpdateProvider,
    FeatureAvailabilityService features,
  ) {
    final lastCheckLabel = autoUpdateProvider.lastCheckDate != null
        ? appLocaleLastUpdateCheckSubtitle(
            context,
            autoUpdateProvider.lastCheckDate!,
          )
        : appLocaleString(context, 'Nunca verificado', 'Never checked');

    return AppSectionCard(
      title: appLocaleString(context, 'Atualizações', 'Updates'),
      description: appLocaleString(
        context,
        'Resumo do updater, ações rápidas e diagnósticos técnicos.',
        'Updater summary, quick actions and technical diagnostics.',
      ),
      banner: !features.isAutoUpdateEnabled
          ? InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Atualizações automáticas indisponíveis',
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
          _buildUpdateSummarySurface(
            context,
            autoUpdateProvider,
            lastCheckLabel,
          ),
          const SizedBox(height: AppSpacing.md),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              FilledButton(
                onPressed: autoUpdateProvider.isChecking
                    ? null
                    : autoUpdateProvider.checkForUpdates,
                child: autoUpdateProvider.isChecking
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: ProgressRing(strokeWidth: 2),
                      )
                    : Text(
                        appLocaleString(
                          context,
                          'Verificar atualizações',
                          'Check for updates',
                        ),
                      ),
              ),
              if (autoUpdateProvider.feedUrl != null)
                Button(
                  onPressed: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.feedUrl!,
                      successMessage: appLocaleString(
                        context,
                        'Feed copiado para a área de transferência.',
                        'Feed copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Não foi possível copiar o feed.',
                        'Could not copy the feed.',
                      ),
                    ),
                  ),
                  child: Text(
                    appLocaleString(context, 'Copiar feed', 'Copy feed'),
                  ),
                ),
              if (autoUpdateProvider.feedUrl != null)
                Button(
                  onPressed: () =>
                      unawaited(_openUrl(autoUpdateProvider.feedUrl!)),
                  child: Text(
                    appLocaleString(context, 'Abrir feed', 'Open feed'),
                  ),
                ),
            ],
          ),
          if (autoUpdateProvider.error != null) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(context, 'Falha recente', 'Recent failure'),
              ),
              content: Text(autoUpdateProvider.error!),
              severity: InfoBarSeverity.error,
              isLong: true,
            ),
          ],
          if (autoUpdateProvider.updateAvailable) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Atualização disponível',
                  'Update available',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'Uma nova versão está pronta para o ciclo automático.',
                  'A new version is ready for the automatic cycle.',
                ),
              ),
              severity: InfoBarSeverity.success,
              isLong: true,
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          Expander(
            header: Text(
              appLocaleString(
                context,
                'Detalhes técnicos do updater',
                'Updater technical details',
              ),
            ),
            content: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (autoUpdateProvider.feedUrl != null)
                  SettingsTechnicalItem(
                    title: appLocaleString(
                      context,
                      'Feed configurado',
                      'Configured feed',
                    ),
                    value: autoUpdateProvider.feedUrl!,
                    description: appLocaleString(
                      context,
                      'Origem consultada para novas versões.',
                      'Source consulted for new versions.',
                    ),
                    onCopy: () => unawaited(
                      _copyValue(
                        autoUpdateProvider.feedUrl!,
                        successMessage: appLocaleString(
                          context,
                          'Feed copiado para a área de transferência.',
                          'Feed copied to the clipboard.',
                        ),
                        errorMessage: appLocaleString(
                          context,
                          'Não foi possível copiar o feed.',
                          'Could not copy the feed.',
                        ),
                      ),
                    ),
                    onOpen: () =>
                        unawaited(_openUrl(autoUpdateProvider.feedUrl!)),
                    openTooltip: appLocaleString(
                      context,
                      'Abrir feed',
                      'Open feed',
                    ),
                  ),
                if (autoUpdateProvider.feedUrl != null)
                  const SizedBox(height: AppSpacing.lg),
                SettingsTechnicalItem(
                  title: appLocaleString(context, 'Último ciclo', 'Last cycle'),
                  value: autoUpdateProvider.lastAttemptNumber != null
                      ? '#${autoUpdateProvider.lastAttemptNumber} • '
                            '${_buildAutoUpdateSourceText(autoUpdateProvider.lastSource)} • '
                            '${_buildAutoUpdateStageText(autoUpdateProvider.currentStage)}'
                      : appLocaleString(
                          context,
                          'Nenhuma execução registrada.',
                          'No execution recorded.',
                        ),
                  description: appLocaleString(
                    context,
                    'Resumo do último fluxo observado pelo provider.',
                    'Summary of the latest flow observed by the provider.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingsTechnicalItem(
                  title: appLocaleString(
                    context,
                    'Telemetria do updater',
                    'Updater telemetry',
                  ),
                  value:
                      'Ciclo: ${_formatAutoUpdateDuration(autoUpdateProvider.lastCheckDuration)}\n'
                      'Download: ${_formatAutoUpdateDuration(autoUpdateProvider.lastDownloadDuration)}\n'
                      'Última falha: ${_buildAutoUpdateStageText(autoUpdateProvider.lastFailureStage)}',
                  description: appLocaleString(
                    context,
                    'Durações e última etapa de falha conhecida.',
                    'Durations and latest known failure stage.',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingsTechnicalItem(
                  title: appLocaleString(
                    context,
                    'Contexto do updater',
                    'Updater context',
                  ),
                  value: autoUpdateProvider.updateContextPath,
                  description: appLocaleString(
                    context,
                    'Arquivo de suporte com contexto operacional do updater.',
                    'Support file with updater operational context.',
                  ),
                  onCopy: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.updateContextPath,
                      successMessage: appLocaleString(
                        context,
                        'Caminho copiado para a área de transferência.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Não foi possível copiar o caminho.',
                        'Could not copy the path.',
                      ),
                    ),
                  ),
                  onOpen: () => unawaited(
                    _openParentDirectory(autoUpdateProvider.updateContextPath),
                  ),
                  openTooltip: appLocaleString(
                    context,
                    'Abrir pasta',
                    'Open folder',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingsTechnicalItem(
                  title: appLocaleString(
                    context,
                    'Histórico operacional',
                    'Operational history',
                  ),
                  value: autoUpdateProvider.diagnosticsPath,
                  description: appLocaleString(
                    context,
                    'Histórico persistido de tentativas e diagnósticos.',
                    'Persisted history of attempts and diagnostics.',
                  ),
                  onCopy: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.diagnosticsPath,
                      successMessage: appLocaleString(
                        context,
                        'Caminho copiado para a área de transferência.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Não foi possível copiar o caminho.',
                        'Could not copy the path.',
                      ),
                    ),
                  ),
                  onOpen: () => unawaited(
                    _openParentDirectory(autoUpdateProvider.diagnosticsPath),
                  ),
                  openTooltip: appLocaleString(
                    context,
                    'Abrir pasta',
                    'Open folder',
                  ),
                ),
                const SizedBox(height: AppSpacing.lg),
                SettingsTechnicalItem(
                  title: appLocaleString(
                    context,
                    'Lock global do updater',
                    'Updater global lock',
                  ),
                  value: autoUpdateProvider.lockFilePath,
                  description: appLocaleString(
                    context,
                    'Arquivo de coordenação entre instâncias.',
                    'Coordination file shared between instances.',
                  ),
                  onCopy: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.lockFilePath,
                      successMessage: appLocaleString(
                        context,
                        'Caminho copiado para a área de transferência.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Não foi possível copiar o caminho.',
                        'Could not copy the path.',
                      ),
                    ),
                  ),
                  onOpen: () => unawaited(
                    _openParentDirectory(autoUpdateProvider.lockFilePath),
                  ),
                  openTooltip: appLocaleString(
                    context,
                    'Abrir pasta',
                    'Open folder',
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildUpdateSummarySurface(
    BuildContext context,
    AutoUpdateProvider autoUpdateProvider,
    String lastCheckLabel,
  ) {
    return Container(
      width: double.infinity,
      padding: AppSpacing.paddingMd,
      decoration: BoxDecoration(
        color: const Color(0xFF8A8A8A).withValues(alpha: 0.08),
        borderRadius: AppRadius.circularMd,
        border: Border.all(
          color: const Color(0xFF8A8A8A).withValues(alpha: 0.22),
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
                label: _buildAutoUpdateStageText(
                  autoUpdateProvider.currentStage,
                ),
                tone: _statusTone(autoUpdateProvider),
                icon: FluentIcons.update_restore,
              ),
              if (autoUpdateProvider.targetVersion != null)
                AppStatusChip(
                  label: 'v${autoUpdateProvider.targetVersion}',
                  tone: AppStatusChipTone.info,
                ),
              if (autoUpdateProvider.currentVersion != null)
                AppStatusChip(
                  label:
                      '${appLocaleString(context, 'Atual', 'Current')}: v${autoUpdateProvider.currentVersion}',
                ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            _buildAutoUpdateStatusText(autoUpdateProvider),
            style: FluentTheme.of(context).typography.body,
          ),
          const SizedBox(height: AppSpacing.sm),
          Text(
            '${appLocaleString(context, 'Última verificação', 'Last check')}: $lastCheckLabel',
            style: FluentTheme.of(context).typography.caption,
          ),
        ],
      ),
    );
  }

  Widget _buildAboutSection(BuildContext context) {
    return AppSectionCard(
      title: appLocaleString(context, 'Sobre', 'About'),
      description: appLocaleString(
        context,
        'Metadados principais da instalação local.',
        'Main metadata for the local installation.',
      ),
      child: Wrap(
        spacing: AppSpacing.md,
        runSpacing: AppSpacing.md,
        children: [
          SettingsFactTile(
            label: appLocaleString(context, 'Versão', 'Version'),
            value: _versionLabel(),
            caption: appLocaleString(
              context,
              'Versão instalada nesta máquina.',
              'Version installed on this machine.',
            ),
          ),
          SettingsFactTile(
            label: appLocaleString(context, 'Modo atual', 'Current mode'),
            value: _modeLabel(),
            caption: appLocaleString(
              context,
              'Contexto de operação ativo na inicialização.',
              'Operation context active at startup.',
            ),
          ),
          SettingsFactTile(
            label: appLocaleString(context, 'Licença', 'License'),
            value: 'MIT License',
            caption: appLocaleString(
              context,
              'Termo de distribuição do aplicativo.',
              'Application distribution terms.',
            ),
          ),
        ],
      ),
    );
  }
}
