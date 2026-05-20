import 'package:backup_database/core/config/process_role.dart';
import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';
import 'package:backup_database/presentation/boot/ui_scheduler_policy.dart';

class UiSchedulerStartupTask {
  const UiSchedulerStartupTask({
    required this.isTaskSchedulerEnabled,
    required this.shouldSkipScheduler,
    required this.startScheduler,
    required this.logInfo,
    required this.logWarning,
    required this.logError,
  });

  final bool Function() isTaskSchedulerEnabled;
  final Future<bool> Function(UiSchedulerFallbackMode fallbackMode)
  shouldSkipScheduler;
  final Future<void> Function() startScheduler;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;
  final BootstrapLogWithError logError;

  Future<void> start(BootstrapConfig config) async {
    try {
      if (!isTaskSchedulerEnabled()) {
        logWarning(
          'Agendamento local nao iniciado: Task Scheduler indisponivel para '
          'esta versao do Windows.',
        );
        return;
      }

      final shouldSkip = await shouldSkipScheduler(
        config.uiSchedulerFallbackMode,
      );
      if (shouldSkip) {
        logInfo(
          '[main] processRole=${ProcessRole.ui.name} '
          'scheduler_local_skipped=windows_service_installed_and_running',
        );
        return;
      }

      await startScheduler();
      logInfo('Servico de agendamento iniciado');
    } on Object catch (e, stackTrace) {
      logError('Erro ao iniciar scheduler', e, stackTrace);
    }
  }
}
