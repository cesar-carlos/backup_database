import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_message_box.dart';

/// Utility class for checking and handling single instance enforcement.
///
/// NOTE: This class directly instantiates services instead of using DI because
/// it runs BEFORE the dependency injection container is initialized. This is
/// intentional - we want to check for existing instances before setting up
/// databases, services, and other resources that could conflict with or
/// duplicate another running instance.
class SingleInstanceChecker {
  SingleInstanceChecker._();

  // Direct instantiation required because this runs before DI setup
  static final ISingleInstanceService _singleInstanceService =
      SingleInstanceService();
  static const IWindowsMessageBox _messageBox = WindowsMessageBox();

  // User-facing messages with Unicode escapes to guarantee correct encoding
  // \u00E1=á \u00E3=ã \u00E7=ç \u00E9=é \u00ED=í \u00F3=ó \u00FA=ú \u00E2=â
  static const String _dialogTitle =
      'Backup Database - J\u00E1 em Execu\u00E7\u00E3o';
  static const String _dialogMessage =
      'O aplicativo Backup Database j\u00E1 est\u00E1 aberto.\n\n'
      'A janela existente foi trazida para frente.\n\n'
      'N\u00E3o \u00E9 poss\u00EDvel executar mais de uma inst\u00E2ncia ao mesmo tempo.';

  /// Checks if this is the first instance using mutex.
  ///
  /// Returns `true` if the application can continue (first instance),
  /// `false` if another instance is already running.
  static Future<bool> checkAndHandleSecondInstance() async {
    final isFirstInstance = await _singleInstanceService.checkAndLock();

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
        'Nao foi possivel obter usuario da instancia existente: $e',
      );
    }

    final isDifferentUser = existingUser != null && existingUser != currentUser;
    final couldNotDetermineUser = existingUser == null;

    if (isDifferentUser || couldNotDetermineUser) {
      LoggerService.warning(
        'SEGUNDA INSTANCIA DETECTADA. '
        'Usuario atual: $currentUser. '
        '${existingUser != null ? "Instancia existente em: $existingUser" : "Nao foi possivel determinar usuario da instancia existente"}',
      );
    } else {
      LoggerService.info(
        'SEGUNDA INSTANCIA DETECTADA (mesmo usuario). '
        'Usuario: $currentUser. Encerrando silenciosamente.',
      );
    }

    for (var i = 0; i < SingleInstanceConfig.maxRetryAttempts; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instancia existente notificada via IPC');
        break;
      }
      await Future.delayed(SingleInstanceConfig.retryDelay);
    }

    _messageBox.showWarning(_dialogTitle, _dialogMessage);
  }
}
