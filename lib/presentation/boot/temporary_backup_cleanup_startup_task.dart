import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

class TemporaryBackupCleanupStartupTask {
  const TemporaryBackupCleanupStartupTask({
    required this.isSchedulerRegistered,
    required this.startScheduler,
    required this.logWarning,
  });

  final bool Function() isSchedulerRegistered;
  final void Function() startScheduler;
  final BootstrapLogWithError logWarning;

  void start() {
    if (!isSchedulerRegistered()) {
      return;
    }
    try {
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
