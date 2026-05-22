import 'dart:async';
import 'dart:io' show Platform;

import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/di/service_locator.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:backup_database/core/theme/theme.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/presentation/utils/compatibility_reason_localizer.dart';
import 'package:backup_database/presentation/widgets/common/common.dart';
import 'package:backup_database/presentation/widgets/settings/settings_ui.dart';
import 'package:fluent_ui/fluent_ui.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';

class UpdatesSettingsSection extends StatefulWidget {
  const UpdatesSettingsSection({super.key});

  @override
  State<UpdatesSettingsSection> createState() => _UpdatesSettingsSectionState();
}

class _UpdatesSettingsSectionState extends State<UpdatesSettingsSection> {
  late final ClipboardService _clipboardService;

  @override
  void initState() {
    super.initState();
    _clipboardService = getIt<ClipboardService>();
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
          'URL invalida para abertura externa.',
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
        'Nao foi possivel abrir o link.',
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
        'Nao foi possivel abrir a pasta.',
        'Could not open the folder.',
      ),
    );
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
          'Verificando feed e comparando versoes.',
          'Checking feed and comparing versions.',
        );
      case AppUpdateStatus.updateAvailable:
        return appLocaleString(
          context,
          'Nova versao encontrada para download silencioso.',
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
          'Handoff concluido para o instalador silencioso.',
          'Handoff completed to the silent installer.',
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
          'Atualizacoes automaticas indisponiveis neste ambiente.',
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
          'Preparando instalacao',
          'Preparing installation',
        );
      case AppUpdateStage.launchingInstaller:
        return appLocaleString(
          context,
          'Disparando instalador',
          'Launching installer',
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

  @override
  Widget build(BuildContext context) {
    final autoUpdateProvider = Provider.of<AutoUpdateProvider>(context);
    final features = getIt<FeatureAvailabilityService>();
    final lastCheckLabel = autoUpdateProvider.lastCheckDate != null
        ? appLocaleLastUpdateCheckSubtitle(
            context,
            autoUpdateProvider.lastCheckDate!,
          )
        : appLocaleString(context, 'Nunca verificado', 'Never checked');

    return AppSectionCard(
      title: appLocaleString(context, 'Atualizacoes', 'Updates'),
      description: appLocaleString(
        context,
        'Resumo do updater, acoes rapidas e diagnosticos tecnicos.',
        'Updater summary, quick actions and technical diagnostics.',
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
                  fallbackPt: 'Nao suportado nesta versao do Windows.',
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
                          'Verificar atualizacoes',
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
                        'Feed copiado para a area de transferencia.',
                        'Feed copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Nao foi possivel copiar o feed.',
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
                  'Atualizacao disponivel',
                  'Update available',
                ),
              ),
              content: Text(
                appLocaleString(
                  context,
                  'Uma nova versao esta pronta para o ciclo automatico.',
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
                'Updater technical details',
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
                      'Origem consultada para novas versoes.',
                      'Source consulted for new versions.',
                    ),
                    onCopy: () => unawaited(
                      _copyValue(
                        autoUpdateProvider.feedUrl!,
                        successMessage: appLocaleString(
                          context,
                          'Feed copiado para a area de transferencia.',
                          'Feed copied to the clipboard.',
                        ),
                        errorMessage: appLocaleString(
                          context,
                          'Nao foi possivel copiar o feed.',
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
                  title: appLocaleString(context, 'Ultimo ciclo', 'Last cycle'),
                  value: autoUpdateProvider.lastAttemptNumber != null
                      ? '#${autoUpdateProvider.lastAttemptNumber} • '
                            '${_buildAutoUpdateSourceText(autoUpdateProvider.lastSource)} • '
                            '${_buildAutoUpdateStageText(autoUpdateProvider.currentStage)}'
                      : appLocaleString(
                          context,
                          'Nenhuma execucao registrada.',
                          'No execution recorded.',
                        ),
                  description: appLocaleString(
                    context,
                    'Resumo do ultimo fluxo observado pelo provider.',
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
                      'Ultima falha: ${_buildAutoUpdateStageText(autoUpdateProvider.lastFailureStage)}',
                  description: appLocaleString(
                    context,
                    'Duracoes e ultima etapa de falha conhecida.',
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
                        'Caminho copiado para a area de transferencia.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Nao foi possivel copiar o caminho.',
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
                    'Historico operacional',
                    'Operational history',
                  ),
                  value: autoUpdateProvider.diagnosticsPath,
                  description: appLocaleString(
                    context,
                    'Historico persistido de tentativas e diagnosticos.',
                    'Persisted history of attempts and diagnostics.',
                  ),
                  onCopy: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.diagnosticsPath,
                      successMessage: appLocaleString(
                        context,
                        'Caminho copiado para a area de transferencia.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Nao foi possivel copiar o caminho.',
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
                    'Arquivo de coordenacao entre instancias.',
                    'Coordination file shared between instances.',
                  ),
                  onCopy: () => unawaited(
                    _copyValue(
                      autoUpdateProvider.lockFilePath,
                      successMessage: appLocaleString(
                        context,
                        'Caminho copiado para a area de transferencia.',
                        'Path copied to the clipboard.',
                      ),
                      errorMessage: appLocaleString(
                        context,
                        'Nao foi possivel copiar o caminho.',
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
            '${appLocaleString(context, 'Ultima verificacao', 'Last check')}: $lastCheckLabel',
            style: FluentTheme.of(context).typography.caption,
          ),
        ],
      ),
    );
  }
}
