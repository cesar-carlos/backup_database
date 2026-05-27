import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

typedef IpcRunScheduleHandler = Future<int> Function(String scheduleId);

typedef IpcServerStarter =
    Future<void> Function({
      required Future<void> Function() onShowWindow,
      required IpcRunScheduleHandler onRunSchedule,
    });

class IpcServerStartupTask {
  const IpcServerStartupTask({
    required this.isWindowManagementEnabled,
    required this.showWindow,
    required this.runSchedule,
    required this.startIpcServer,
    required this.logInfo,
    required this.logWarning,
    required this.logError,
  });

  final bool Function() isWindowManagementEnabled;
  final Future<void> Function() showWindow;
  final IpcRunScheduleHandler runSchedule;
  final IpcServerStarter startIpcServer;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;
  final BootstrapLogWithError logError;

  Future<void> start(BootstrapConfig config) async {
    if (!config.singleInstanceEnabled) {
      logInfo(
        'IPC Server nao iniciado: single instance desabilitado via configuracao',
      );
      return;
    }

    try {
      await startIpcServer(
        onShowWindow: _handleShowWindow,
        onRunSchedule: runSchedule,
      );
      logInfo('IPC Server inicializado e pronto');
    } on Object catch (e, stackTrace) {
      logWarning('Erro ao inicializar IPC Server: $e', e, stackTrace);
    }
  }

  Future<void> _handleShowWindow() async {
    logInfo('Recebido comando SHOW_WINDOW via IPC de outra instancia');
    if (!isWindowManagementEnabled()) {
      return;
    }
    try {
      await showWindow();
      logInfo('Janela trazida para frente apos comando IPC');
    } on Object catch (e, stackTrace) {
      logError('Erro ao mostrar janela via IPC', e, stackTrace);
    }
  }
}
