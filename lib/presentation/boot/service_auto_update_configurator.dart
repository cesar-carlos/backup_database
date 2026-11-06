import 'dart:async';
import 'dart:io';

import 'package:backup_database/application/services/auto_update_service.dart';
import 'package:backup_database/core/compatibility/feature_availability_service.dart';
import 'package:backup_database/core/compatibility/feature_disable_reason.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';
import 'package:backup_database/presentation/boot/service_account_probe.dart';

typedef ServiceShutdownHook = Future<void> Function();

class ServiceAutoUpdateConfigurator {
  ServiceAutoUpdateConfigurator({
    required this.features,
    required this.autoUpdateService,
    required this.accountProbe,
    required this.beforeInstallHook,
    this.isBackupRunning,
  });

  final FeatureAvailabilityService features;
  final AutoUpdateService autoUpdateService;
  final ServiceAccountProbe accountProbe;
  final ServiceShutdownHook beforeInstallHook;
  final bool Function()? isBackupRunning;

  Future<void> configureAndStart() async {
    if (!features.isAutoUpdateEnabled) {
      LoggerService.info(
        'AutoUpdateService omitido no servico (compatibilidade): '
        '${features.autoUpdateDisabledReason?.diagnosticLabel ?? "unknown"}',
      );
      return;
    }

    autoUpdateService
      ..installContextProvider = _buildInstallContext
      ..installReadinessCheck = _checkInstallReadiness
      ..beforeInstallHook = beforeInstallHook;
    autoUpdateService.installFailureHook = AppCleanup.recoverFailedInstall;

    await autoUpdateService.initialize();
    if (!autoUpdateService.isInitialized) {
      LoggerService.info(
        'AutoUpdateService em modo servico ficou desabilitado/sem feed',
      );
      return;
    }
    autoUpdateService.startPeriodicChecks();
    unawaited(
      autoUpdateService.checkNow(source: AppUpdateSource.startup),
    );
  }

  Future<AppUpdateInstallContext> _buildInstallContext(
    AppcastRelease release,
  ) async {
    return AppUpdateInstallContext(
      origin: AppUpdateLaunchOrigin.service,
      appMode: currentAppMode,
      currentVersion: autoUpdateService.snapshot.currentVersion ?? '0.0.0',
      targetVersion: release.targetVersion,
      relaunchArguments: List<String>.of(Platform.executableArguments),
      executablePath: Platform.resolvedExecutable,
      createdAt: DateTime.now(),
    );
  }

  Future<AppUpdateBlockOutcome?> _checkInstallReadiness(
    AppcastRelease release,
    AppUpdateSource source,
  ) async {
    // WinSW preserves SCM credentials; silent updates still require an
    // administrative token without an interactive UAC prompt in session 0.
    if (isBackupRunning?.call() ?? false) {
      return const AppUpdateBlockOutcome(
        reason: AppUpdateBlockReason.localBackupRunning,
        message:
            'Atualização bloqueada: existe um backup em andamento no '
            'serviço. Aguarde a conclusão.',
      );
    }
    final serviceAccount = await accountProbe.probeInstalledAccount();
    final message = await accountProbe.silentUpdateBlockReason(
      serviceAccount,
    );
    if (message == null) return null;
    return AppUpdateBlockOutcome(
      message: message,
      reason: AppUpdateBlockReason.serviceAccountUnsupported,
    );
  }
}
