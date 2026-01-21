import '../../core/utils/logger_service.dart';
import '../../core/utils/windows_user_service.dart';
import '../managers/managers.dart';

class SingleInstanceChecker {
  static Future<bool> checkAndHandleSecondInstance() async {
    final singleInstanceService = SingleInstanceService();
    final isFirstInstance = await singleInstanceService.checkAndLock();

    if (isFirstInstance) {
      return true;
    }

    await _handleSecondInstance();
    return false;
  }

  static Future<bool> checkIpcServerAndHandle() async {
    final isServerRunning = await IpcService.checkServerRunning();

    if (!isServerRunning) {
      return true;
    }

    await _handleSecondInstance();
    return false;
  }

  static Future<void> _handleSecondInstance() async {
    final currentUser = WindowsUserService.getCurrentUsername() ?? 'Desconhecido';

    String? existingUser;
    try {
      existingUser = await IpcService.getExistingInstanceUser();
    } catch (e) {
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

    for (int i = 0; i < 5; i++) {
      final notified = await SingleInstanceService.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instância existente notificada via IPC');
        break;
      }
      await Future.delayed(const Duration(milliseconds: 200));
    }

    WindowsMessageBox.showWarning(
      'Backup Database - Já está em execução',
      'O aplicativo Backup Database já está aberto.\n\n'
      'A janela existente foi trazida para frente.\n\n'
      'Não é possível executar mais de uma instância do aplicativo ao mesmo tempo.',
    );
  }
}
