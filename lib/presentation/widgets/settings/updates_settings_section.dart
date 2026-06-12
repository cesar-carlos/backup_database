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
        // §audit-2026-05-28 wave 4 (UI banner): texto diferenciado por
        // motivo. Quando o reason é `uacPolicy`, o banner dedicado
        // abaixo (com botão "Atualizar agora") explica em detalhe e
        // dá ação — aqui só damos um resumo curto pro chip de status.
        switch (provider.blockReason) {
          case AppUpdateBlockReason.uacPolicy:
            return appLocaleString(
              context,
              'Auto-update pausado: aprovacao UAC necessaria.',
              'Auto-update paused: UAC approval required.',
            );
          case AppUpdateBlockReason.remoteBackupRunning:
            return appLocaleString(
              context,
              'Backup remoto em execucao. Aguarde a conclusao.',
              'Remote backup running. Wait for it to finish.',
            );
          case AppUpdateBlockReason.fileTransferActive:
            return appLocaleString(
              context,
              'Transferencia de arquivo em curso. Aguarde a conclusao.',
              'File transfer in progress. Wait for it to finish.',
            );
          case AppUpdateBlockReason.serviceAccountUnsupported:
            return appLocaleString(
              context,
              'Servico Windows precisa estar em LocalSystem.',
              'Windows Service must run as LocalSystem.',
            );
          case AppUpdateBlockReason.readinessCheckUnavailable:
            return appLocaleString(
              context,
              'Nao foi possivel verificar se o app esta pronto para atualizar. '
                  'Tente novamente em instantes.',
              'Could not verify install readiness. Try again shortly.',
            );
          case AppUpdateBlockReason.localBackupRunning:
          case null:
            return appLocaleString(
              context,
              'Ha um backup ativo. Aguarde a conclusao antes de atualizar.',
              'There is an active backup. Wait for it to finish before updating.',
            );
        }
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
        return _disabledReasonText(provider.disabledReason);
    }
  }

  /// Mensagem semântica por reason de disable — substitui a string
  /// genérica "indisponiveis neste ambiente" que escondia a causa real
  /// (audit 2026-05-28).
  String _disabledReasonText(AppUpdateDisabledReason? reason) {
    switch (reason) {
      case AppUpdateDisabledReason.nonWindowsPlatform:
        return appLocaleString(
          context,
          'Atualizacoes automaticas disponiveis apenas no Windows.',
          'Automatic updates only available on Windows.',
        );
      case AppUpdateDisabledReason.feedUrlMissing:
        return appLocaleString(
          context,
          'Configuracao ausente: AUTO_UPDATE_FEED_URL nao definida em '
              r'C:\ProgramData\BackupDatabase\config\.env.',
          'Configuration missing: AUTO_UPDATE_FEED_URL not set in '
              r'C:\ProgramData\BackupDatabase\config\.env.',
        );
      case AppUpdateDisabledReason.dotenvLoadFailed:
        return appLocaleString(
          context,
          'Falha ao carregar o arquivo de configuracao (.env). Verifique '
              'permissoes e formato do arquivo.',
          'Failed to load configuration file (.env). Check file '
              'permissions and format.',
        );
      case AppUpdateDisabledReason.feedReaderException:
        return appLocaleString(
          context,
          'Erro inesperado ao ler a configuracao do feed. Veja os logs '
              'para detalhes.',
          'Unexpected error reading feed configuration. See logs for '
              'details.',
        );
      case AppUpdateDisabledReason.osIncompatible:
        return appLocaleString(
          context,
          'Atualizacoes automaticas nao suportadas nesta versao do '
              'Windows.',
          'Automatic updates not supported on this Windows version.',
        );
      case AppUpdateDisabledReason.initializationException:
        return appLocaleString(
          context,
          'Falha na inicializacao do updater. Veja os logs e o item '
              '"Telemetria do updater" abaixo.',
          'Updater initialization failed. See logs and "Updater '
              'telemetry" item below.',
        );
      case null:
        return appLocaleString(
          context,
          'Atualizacoes automaticas indisponiveis neste ambiente.',
          'Automatic updates unavailable in this environment.',
        );
    }
  }

  /// Label curto do reason, usado em copy/diagnostics e no expander
  /// técnico.
  String _disabledReasonLabel(AppUpdateDisabledReason reason) {
    switch (reason) {
      case AppUpdateDisabledReason.nonWindowsPlatform:
        return 'non_windows_platform';
      case AppUpdateDisabledReason.feedUrlMissing:
        return 'feed_url_missing';
      case AppUpdateDisabledReason.dotenvLoadFailed:
        return 'dotenv_load_failed';
      case AppUpdateDisabledReason.feedReaderException:
        return 'feed_reader_exception';
      case AppUpdateDisabledReason.osIncompatible:
        return 'os_incompatible';
      case AppUpdateDisabledReason.initializationException:
        return 'initialization_exception';
    }
  }

  /// §audit-2026-05-28 wave 4 (UI banner): label snake_case do
  /// motivo de bloqueio, exibido no expander técnico para mapear
  /// contra logs (`[auto-update] silencioso bloqueado: ...`).
  String _blockReasonLabel(AppUpdateBlockReason reason) {
    switch (reason) {
      case AppUpdateBlockReason.localBackupRunning:
        return 'local_backup_running';
      case AppUpdateBlockReason.remoteBackupRunning:
        return 'remote_backup_running';
      case AppUpdateBlockReason.fileTransferActive:
        return 'file_transfer_active';
      case AppUpdateBlockReason.uacPolicy:
        return 'uac_policy';
      case AppUpdateBlockReason.serviceAccountUnsupported:
        return 'service_account_unsupported';
      case AppUpdateBlockReason.readinessCheckUnavailable:
        return 'readiness_check_unavailable';
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
              // P3#13: botão desabilitado quando o serviço está
              // disabled — checkNow no-op em disabled levava a UX
              // "clico e nada acontece, nem logs novos".
              Tooltip(
                message: autoUpdateProvider.isDisabled
                    ? appLocaleString(
                        context,
                        'Updater indisponivel. Resolva o motivo no '
                            'painel acima antes de tentar novamente.',
                        'Updater unavailable. Resolve the reason in the '
                            'panel above before retrying.',
                      )
                    : '',
                child: FilledButton(
                  onPressed:
                      autoUpdateProvider.isChecking ||
                          autoUpdateProvider.isDisabled
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
              ),
              // P3#14: ação corretiva inline quando faltam chaves de
              // config — abre a pasta do .env direto, sem o usuário
              // ter que decifrar o path no painel técnico.
              if (autoUpdateProvider.disabledReason ==
                      AppUpdateDisabledReason.feedUrlMissing ||
                  autoUpdateProvider.disabledReason ==
                      AppUpdateDisabledReason.dotenvLoadFailed ||
                  autoUpdateProvider.disabledReason ==
                      AppUpdateDisabledReason.feedReaderException)
                Button(
                  onPressed: () => unawaited(
                    _openParentDirectory(autoUpdateProvider.configFilePath),
                  ),
                  child: Text(
                    appLocaleString(
                      context,
                      'Abrir pasta de configuracao',
                      'Open config folder',
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
          // §audit-2026-05-28 wave 4 (UI banner): banner dedicado
          // quando o auto-update foi bloqueado pelo gate UAC. Inclui
          // botao "Atualizar agora" inline — `manual` ignora o gate
          // (operador esta ciente do prompt UAC).
          if (autoUpdateProvider.isBlockedByUacPolicy) ...[
            const SizedBox(height: AppSpacing.md),
            InfoBar(
              title: Text(
                appLocaleString(
                  context,
                  'Aprovacao UAC necessaria',
                  'UAC approval required',
                ),
              ),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    autoUpdateProvider.statusMessage ??
                        appLocaleString(
                          context,
                          'O Windows pediria aprovacao UAC para instalar a '
                              'nova versao. Auto-update silencioso esta '
                              'pausado para nao quebrar a sua tela do nada. '
                              'Clique abaixo para iniciar manualmente e '
                              'confirmar o prompt.',
                          'Windows would request UAC approval to install the '
                              'new version. Silent auto-update is paused so '
                              'it does not interrupt you. Click below to '
                              'start it manually and confirm the prompt.',
                        ),
                  ),
                  const SizedBox(height: AppSpacing.sm),
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
                                width: 16,
                                height: 16,
                                child: ProgressRing(strokeWidth: 2),
                              )
                            : Text(
                                appLocaleString(
                                  context,
                                  'Atualizar agora',
                                  'Update now',
                                ),
                              ),
                      ),
                    ],
                  ),
                ],
              ),
              severity: InfoBarSeverity.warning,
              isLong: true,
            ),
          ],
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
                // P3#15: estado do dotenv (sempre visível). Ajuda
                // diagnosticar misconfig em segundos vs. a sessão de
                // detective que motivou a auditoria.
                if (autoUpdateProvider.disabledReason != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SettingsTechnicalItem(
                    title: appLocaleString(
                      context,
                      'Motivo do disable',
                      'Disabled reason',
                    ),
                    value: _disabledReasonLabel(
                      autoUpdateProvider.disabledReason!,
                    ),
                    description: appLocaleString(
                      context,
                      'Causa raiz do estado "indisponivel". Use para '
                          'mapear contra logs.',
                      'Root cause of the "unavailable" state. Map against '
                          'logs.',
                    ),
                  ),
                ],
                // §audit-2026-05-28 wave 4 (UI banner): label técnico do
                // último motivo de bloqueio — útil para correlacionar
                // com logs `[auto-update] silencioso bloqueado: ...`.
                if (autoUpdateProvider.blockReason != null) ...[
                  const SizedBox(height: AppSpacing.lg),
                  SettingsTechnicalItem(
                    title: appLocaleString(
                      context,
                      'Motivo do bloqueio',
                      'Block reason',
                    ),
                    value: _blockReasonLabel(autoUpdateProvider.blockReason!),
                    description: appLocaleString(
                      context,
                      'Causa do ultimo ciclo bloqueado. Use para mapear '
                          'contra logs e decidir se o ciclo proximo vai '
                          'destravar sozinho.',
                      'Cause of the last blocked cycle. Use to map against '
                          'logs and decide whether the next cycle will '
                          'unblock on its own.',
                    ),
                  ),
                ],
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
