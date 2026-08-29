import 'package:backup_database/presentation/boot/bootstrap_config.dart';
import 'package:backup_database/presentation/boot/bootstrap_error_policy.dart';

typedef IpcRunScheduleHandler = Future<int> Function(String scheduleId);

typedef IpcServerStarter = Future<void> Function({
  required Future<void> Function() onShowWindow,
  required IpcRunScheduleHandler onRunSchedule,
});

class IpcServerStartupTask {
  IpcServerStartupTask({
    required this.isWindowManagementEnabled,
    required this.showWindow,
    required this.runSchedule,
    required this.startIpcServer,
    required this.logInfo,
    required this.logWarning,
    required this.logError,
    bool Function()? isWindowReady,
  }) : isWindowReady = isWindowReady ?? _windowAlwaysReady;

  static bool _windowAlwaysReady() => true;

  final bool Function() isWindowManagementEnabled;
  final bool Function() isWindowReady;
  final Future<void> Function() showWindow;
  final IpcRunScheduleHandler runSchedule;
  final IpcServerStarter startIpcServer;
  final BootstrapLog logInfo;
  final BootstrapLogWithError logWarning;
  final BootstrapLogWithError logError;

  bool _pendingShowWindow = false;

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

  /// After the window manager is initialized, raise the window if a
  /// SHOW_WINDOW arrived while the IPC server was already listening.
  Future<void> markWindowReadyAndFlush() async {
    if (!isWindowManagementEnabled() || !isWindowReady()) {
      return;
    }
    if (!_pendingShowWindow) {
      return;
    }
    _pendingShowWindow = false;
    logInfo('event=ipc_show_window_flushed');
    await _showNow();
  }

  Future<void> _handleShowWindow() async {
    logInfo('Recebido comando SHOW_WINDOW via IPC de outra instancia');
    if (!isWindowManagementEnabled()) {
      return;
    }
    if (!isWindowReady()) {
      _pendingShowWindow = true;
      logInfo('event=ipc_show_window_queued');
      return;
    }
    await _showNow();
  }

  Future<void> _showNow() async {
    try {
      await showWindow();
      logInfo('Janela trazida para frente apos comando IPC');
    } on Object catch (e, stackTrace) {
      logError('Erro ao mostrar janela via IPC', e, stackTrace);
    }
  }
}
