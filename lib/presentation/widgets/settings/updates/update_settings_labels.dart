import 'package:backup_database/application/providers/auto_update_provider.dart';
import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/l10n/app_locale_string.dart';
import 'package:fluent_ui/fluent_ui.dart';

String autoUpdateStatusText(
  BuildContext context,
  AutoUpdateProvider provider,
) {
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
      return autoUpdateDisabledReasonText(context, provider.disabledReason);
  }
}

/// Mensagem semântica por reason de disable — substitui a string
/// genérica "indisponiveis neste ambiente" que escondia a causa real
/// (audit 2026-05-28).
String autoUpdateDisabledReasonText(
  BuildContext context,
  AppUpdateDisabledReason? reason,
) {
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
String autoUpdateDisabledReasonLabel(AppUpdateDisabledReason reason) {
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
String autoUpdateBlockReasonLabel(AppUpdateBlockReason reason) {
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

String autoUpdateStageText(BuildContext context, AppUpdateStage? stage) {
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

String autoUpdateSourceText(BuildContext context, AppUpdateSource? source) {
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

String autoUpdateDurationLabel(BuildContext context, Duration? duration) {
  if (duration == null) {
    return appLocaleString(context, 'Nao disponivel', 'Not available');
  }
  return '${duration.inMilliseconds} ms';
}
