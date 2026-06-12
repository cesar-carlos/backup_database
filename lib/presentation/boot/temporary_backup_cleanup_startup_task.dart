import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';

class TemporaryBackupCleanupStartupTask {
  const TemporaryBackupCleanupStartupTask({
    required this.isSchedulerRegistered,
    required this.shouldSkipCleanup,
    required this.startScheduler,
    required this.logInfo,
    required this.logWarning,
  });

  final bool Function() isSchedulerRegistered;
  final Future<bool> Function(UiSchedulerFallbackMode fallbackMode)
  shouldSkipCleanup;
  final void Function() startScheduler;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;

  Future<void> start(BootstrapConfig config) async {
    if (!isSchedulerRegistered()) {
      return;
    }
    try {
      final shouldSkip = await shouldSkipCleanup(
        config.uiSchedulerFallbackMode,
      );
      if (shouldSkip) {
        logInfo(
          '[main] processRole=${ProcessRole.ui.name} '
          'temp_backup_cleanup_skipped=windows_service_installed_and_running',
        );
        return;
      }
      startScheduler();
    } on Object catch (e, stackTrace) {
      logWarning(
        'Erro ao iniciar limpeza periodica de temporarios locais: $e',
        e,
        stackTrace,
      );
    }
  }
}
