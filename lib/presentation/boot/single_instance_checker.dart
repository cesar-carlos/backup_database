import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';

class SingleInstanceChecker {
  SingleInstanceChecker({
    required ISingleInstanceService singleInstanceService,
    required ISingleInstanceIpcClient ipcClient,
    required IWindowsMessageBox messageBox,
    String? Function()? getCurrentUsername,
    LaunchOrigin launchOrigin = LaunchOrigin.manual,
    int maxRetryAttempts = SingleInstanceConfig.maxRetryAttempts,
    Duration retryDelay = SingleInstanceConfig.retryDelay,
  }) : _singleInstanceService = singleInstanceService,
       _ipcClient = ipcClient,
       _messageBox = messageBox,
       _getCurrentUsername =
           getCurrentUsername ?? WindowsUserService.getCurrentUsername,
       _launchOrigin = launchOrigin,
       _maxRetryAttempts = maxRetryAttempts > 0 ? maxRetryAttempts : 1,
       _retryDelay = retryDelay;

  final ISingleInstanceService _singleInstanceService;
  final ISingleInstanceIpcClient _ipcClient;
  final IWindowsMessageBox _messageBox;
  final String? Function() _getCurrentUsername;
  final LaunchOrigin _launchOrigin;
  final int _maxRetryAttempts;
  final Duration _retryDelay;

  static const String dialogTitle =
      'Backup Database - J\u00E1 em Execu\u00E7\u00E3o';
  static const String _dialogMessageSameUser =
      'O aplicativo Backup Database j\u00E1 est\u00E1 aberto.\n\n'
      'A janela existente foi trazida para frente.\n\n'
      'N\u00E3o \u00E9 poss\u00EDvel executar mais de uma inst\u00E2ncia '
      'ao mesmo tempo.';
  static const String _dialogMessageSameUserWindowFocusFailed =
      'O aplicativo Backup Database j\u00E1 est\u00E1 aberto.\n\n'
      'N\u00E3o foi poss\u00EDvel trazer a janela existente para frente '
      'automaticamente.\n\n'
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

  Future<bool> checkAndHandleSecondInstance() async {
    final isFirstInstance = await _singleInstanceService.checkAndLock();

    if (isFirstInstance) {
      return true;
    }

    await handleSecondInstance();
    return false;
  }

  Future<void> handleSecondInstance() async {
    if (_launchOrigin == LaunchOrigin.windowsStartup) {
      LoggerService.info(
        'duplicate_launch_suppressed_windows_startup: mutex negou UI; '
        'encerrando sem IPC nem popup.',
      );
      return;
    }

    final currentUser = _getCurrentUsername() ?? 'Desconhecido';

    String? existingUser;
    try {
      existingUser = await _ipcClient.getExistingInstanceUser();
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
        'Usuario: $currentUser. Mostrando aviso ao usuario.',
      );
    }

    var wasExistingWindowNotified = false;
    for (var i = 0; i < _maxRetryAttempts; i++) {
      final notified = await _ipcClient.notifyExistingInstance();
      if (notified) {
        LoggerService.info('Instancia existente notificada via IPC');
        wasExistingWindowNotified = true;
        break;
      }
      await Future.delayed(_retryDelay);
    }

    if (!wasExistingWindowNotified) {
      LoggerService.warning(
        'Nao foi possivel notificar instancia existente via IPC '
        'apos $_maxRetryAttempts tentativas',
      );
    }

    final dialogMessage = _getDialogMessage(
      isDifferentUser: isDifferentUser,
      couldNotDetermineUser: couldNotDetermineUser,
      existingUser: existingUser,
      wasExistingWindowNotified: wasExistingWindowNotified,
    );
    _messageBox.showWarning(dialogTitle, dialogMessage);
  }

  String _getDialogMessage({
    required bool isDifferentUser,
    required bool couldNotDetermineUser,
    required bool wasExistingWindowNotified,
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

    if (wasExistingWindowNotified) {
      return _dialogMessageSameUser;
    }

    return _dialogMessageSameUserWindowFocusFailed;
  }
}
