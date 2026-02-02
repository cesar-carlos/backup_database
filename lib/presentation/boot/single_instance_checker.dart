import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_message_box.dart';

/// Utility class for checking and handling single instance enforcement.
class SingleInstanceChecker {
  SingleInstanceChecker._();

  /// Checks if this is the first instance using mutex.
  ///
  /// Returns `true` if the application can continue (first instance),
  /// `false` if another instance is already running.
  static Future<bool> checkAndHandleSecondInstance() async {
    final singleInstanceService = SingleInstanceService();
    final isFirstInstance = await singleInstanceService.checkAndLock();

    if (isFirstInstance) {
      return true;
    }

    await handleSecondInstance();
    return false;
  }

  /// Checks if an IPC server is already running.
  ///
  /// Returns `true` if no server is running (can continue),
  /// `false` if another instance is already running.
  static Future<bool> checkIpcServerAndHandle() async {
    final isServerRunning = await IpcService.checkServerRunning();

    if (!isServerRunning) {
      return true;
    }

    await handleSecondInstance();
    return false;
  }

  /// Handles the case when a second instance is detected.
  ///
  /// Notifies the existing instance and shows a warning dialog.
  static Future<void> handleSecondInstance() async {
    final currentUser =
        WindowsUserService.getCurrentUsername() ?? 'Desconhecido';

    String? existingUser;
    try {
      existingUser = await IpcService.getExistingInstanceUser();
    } on Object catch (e) {
      LoggerService.debug(
        'Não foi possível obter usuário da instância existente: $e',
      );
    }

    final isDifferentUser = existingUser != null && existingUser != currentUser;
    final couldNotDetermineUser = existingUser == null;

    if (isDifferentUser || couldNotDetermineUser) {
      LoggerService.warning(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA. '
        'Usuário atual: $currentUser. '
        '${existingUser != null ? "Instância existente em: $existingUser" : "Não foi possível determinar usuário da instância existente"}',
      );
    } else {
      LoggerService.info(
        '⚠️ SEGUNDA INSTÂNCIA DETECTADA (mesmo usuário). '
        'Usuário: $currentUser. Encerrando silenciosamente.',
      );
    }

    for (var i = 0; i < SingleInstanceConfig.maxRetryAttempts; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(SingleInstanceConfig.retryDelay);
    }

    WindowsMessageBox.showWarning(
      'Backup Database - Já em Execução',
      'O aplicativo Backup Database já está aberto.\n\n'
          'A janela existente foi trazida para frente.\n\n'
          'Não é possível executar mais de uma instância ao mesmo tempo.',
    );
  }
}
