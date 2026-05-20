typedef BootstrapLog = void Function(String message);
typedef BootstrapLogWithError =
    void Function(
      String message, [
      Object? error,
      StackTrace? stackTrace,
    ]);

class BootstrapErrorPolicy {
  const BootstrapErrorPolicy({
    required this.logDebug,
    required this.logError,
    required this.cleanupApp,
    required this.exitProcess,
  });

  final BootstrapLog logDebug;
  final BootstrapLogWithError logError;
  final Future<void> Function() cleanupApp;
  final void Function(int code) exitProcess;

  void handleUnhandledUiError(Object error, StackTrace stack) {
    if (error.toString().contains('physicalKey is already pressed')) {
      logDebug(
        'Ignorando erro conhecido do Flutter (physicalKey already pressed): '
        '$error',
      );
      return;
    }

    logError('Erro nao tratado na UI', error, stack);
  }

  Future<void> handleFatalUiBootstrapFailure(
    Object error,
    StackTrace stackTrace,
  ) async {
    logError('Erro fatal na inicializacao', error, stackTrace);
    await cleanupApp();
    exitProcess(1);
  }
}
