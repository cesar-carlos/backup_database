import 'dart:io';

import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/presentation/boot/app_cleanup.dart';

typedef BootstrapLog = void Function(String message);
typedef BootstrapLogWithError =
    void Function(
      String message, [
      Object? error,
      StackTrace? stackTrace,
    ]);

/// Identificadores de erros conhecidos do Flutter que não devem poluir
/// o log de erros (são reportados pelo próprio Flutter como `physicalKey
/// already pressed` quando o handler de teclado nativo se descasa do
/// estado lógico). Centralizar aqui evita que cada caller tenha que
/// duplicar o filtro.
const String _physicalKeyAlreadyPressedSignature =
    'physicalKey is already pressed';

class BootstrapErrorPolicy {
  const BootstrapErrorPolicy({
    required this.logDebug,
    required this.logError,
    required this.cleanupApp,
    required this.exitProcess,
  });

  /// Instância default reutilizada por `runZonedGuarded` no `main`.
  /// Construída uma única vez para evitar reinstanciar o grafo de
  /// dependências do bootstrap a cada erro não tratado.
  static const BootstrapErrorPolicy defaults = BootstrapErrorPolicy(
    logDebug: LoggerService.debug,
    logError: LoggerService.error,
    cleanupApp: AppCleanup.cleanup,
    exitProcess: exit,
  );

  final BootstrapLog logDebug;
  final BootstrapLogWithError logError;
  final Future<void> Function() cleanupApp;
  final void Function(int code) exitProcess;

  void handleUnhandledUiError(Object error, StackTrace stack) {
    if (error.toString().contains(_physicalKeyAlreadyPressedSignature)) {
      logDebug(
        'Ignorando erro conhecido do Flutter '
        '($_physicalKeyAlreadyPressedSignature): $error',
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
    exitProcess(UiBootstrapExitCode.fatalBootstrapError);
  }
}
