import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/infrastructure/external/system/ipc_service.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_message_box.dart';

class SingleInstanceChecker {
  SingleInstanceChecker._();

  static final ISingleInstanceService _singleInstanceService =
      SingleInstanceService();
  static const IWindowsMessageBox _messageBox = WindowsMessageBox();

  static const String _dialogTitle =
      'Backup Database - J\u00E1 em Execu\u00E7\u00E3o';
  static const String _dialogMessageSameUser =
      'O aplicativo Backup Database j\u00E1 est\u00E1 aberto.\n\n'
      'A janela existente foi trazida para frente.\n\n'
      'N\u00E3o \u00E9 poss\u00EDvel executar mais de uma inst\u00E2ncia '
      'ao mesmo tempo.';
  static const String _dialogMessageDifferentUser =
      'O aplicativo Backup Database j\u00E1 est\u00E1 em execu\u00E7\u00E3o '
      'em outro usu\u00E1rio do Windows.\n\n'
      'N\u00E3o \u00E9 poss\u00EDvel executar mais de uma inst\u00E2ncia ao '
      'mesmo tempo neste computador.';
  static const String _dialogMessageUnknownUser =
      'O aplicativo Backup Database j\u00E1 est\u00E1 em execu\u00E7\u00E3o '
      'neste computador.\n\n'
      'N\u00E3o foi poss\u00EDvel identificar o usu\u00E1rio da inst\u00E2ncia '
      'existente.';

  static Future<bool> checkAndHandleSecondInstance() async {
    final isFirstInstance = await _singleInstanceService.checkAndLock();

    if (isFirstInstance) {
      return true;
    }

    await handleSecondInstance();
    return false;
  }

  static Future<bool> checkIpcServerAndHandle() async {
    final isServerRunning = await IpcService.checkServerRunning();

    if (!isServerRunning) {
      return true;
    }

    await handleSecondInstance();
    return false;
  }

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

    final dialogMessage = _getDialogMessage(
      isDifferentUser: isDifferentUser,
      couldNotDetermineUser: couldNotDetermineUser,
      existingUser: existingUser,
    );
    _messageBox.showWarning(_dialogTitle, dialogMessage);
  }

  static String _getDialogMessage({
    required bool isDifferentUser,
    required bool couldNotDetermineUser,
    String? existingUser,
  }) {
    if (isDifferentUser) {
      if (existingUser != null && existingUser.isNotEmpty) {
        return '$_dialogMessageDifferentUser\n\n'
            'Usuario da instancia existente: $existingUser.';
      }
      return _dialogMessageDifferentUser;
    }

    if (couldNotDetermineUser) {
      return _dialogMessageUnknownUser;
    }

    return _dialogMessageSameUser;
  }
}
