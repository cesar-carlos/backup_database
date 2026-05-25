import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/uuid_validator.dart';
import 'package:backup_database/core/utils/windows_user_service.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:backup_database/presentation/boot/scheduled_backup_executor.dart';

class SingleInstanceChecker {
  SingleInstanceChecker({
    required ISingleInstanceService singleInstanceService,
    required ISingleInstanceIpcClient ipcClient,
    required IWindowsMessageBox messageBox,
    String? Function()? getCurrentUsername,
    void Function(int code)? exitProcess,
    LaunchOrigin launchOrigin = LaunchOrigin.manual,
    String? scheduledScheduleId,
    int maxRetryAttempts = SingleInstanceConfig.maxRetryAttempts,
    Duration retryDelay = SingleInstanceConfig.retryDelay,
  }) : _singleInstanceService = singleInstanceService,
       _ipcClient = ipcClient,
       _messageBox = messageBox,
       _getCurrentUsername =
           getCurrentUsername ?? WindowsUserService.getCurrentUsername,
       _exitProcess = exitProcess,
       _launchOrigin = launchOrigin,
       _scheduledScheduleId = scheduledScheduleId,
       _maxRetryAttempts = maxRetryAttempts > 0 ? maxRetryAttempts : 1,
       _retryDelay = retryDelay;

  final ISingleInstanceService _singleInstanceService;
  final ISingleInstanceIpcClient _ipcClient;
  final IWindowsMessageBox _messageBox;
  final String? Function() _getCurrentUsername;
  final void Function(int code)? _exitProcess;
  final LaunchOrigin _launchOrigin;
  final String? _scheduledScheduleId;
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
  static const String _dialogMessageServiceOwner =
      'O Backup Database j\u00E1 est\u00E1 em execu\u00E7\u00E3o como servi\u00E7o '
      'do Windows neste computador.\n\n'
      'N\u00E3o \u00E9 poss\u00EDvel abrir outra inst\u00E2ncia enquanto o '
      'servi\u00E7o estiver ativo.';

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
      LoggerService.infoWithContext(
        'event=duplicate_launch_suppressed launchOrigin=windows-startup',
      );
      return;
    }

    if (_launchOrigin == LaunchOrigin.scheduledExecution) {
      await _handleScheduledSecondInstance();
      return;
    }

    final currentUser = _getCurrentUsername() ?? 'Desconhecido';
    final ownerInfo = await _getExistingInfo();
    final existingRole = ownerInfo?.role;

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
        'event=duplicate_manual_launch ownerRole=${existingRole ?? "unknown"} '
        'currentUser=$currentUser existingUser=${existingUser ?? "unknown"}',
      );
    } else {
      LoggerService.infoWithContext(
        'event=duplicate_manual_launch ownerRole=${existingRole ?? "unknown"} '
        'currentUser=$currentUser existingUser=$existingUser',
      );
    }

    final isServiceOwner =
        existingRole == SingleInstanceConfig.ipcInstanceRoleService;

    var wasExistingWindowNotified = false;
    if (!isServiceOwner) {
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
    } else {
      LoggerService.info(
        'Segunda instancia manual bloqueada porque o dono do lock e servico',
      );
    }

    final dialogMessage = _getDialogMessage(
      isServiceOwner: isServiceOwner,
      isDifferentUser: isDifferentUser,
      couldNotDetermineUser: couldNotDetermineUser,
      existingUser: existingUser,
      wasExistingWindowNotified: wasExistingWindowNotified,
    );
    _messageBox.showWarning(dialogTitle, dialogMessage);
  }

  Future<void> _handleScheduledSecondInstance() async {
    final scheduleId = _scheduledScheduleId;
    if (scheduleId == null || !UuidValidator.isValid(scheduleId)) {
      LoggerService.error(
        'event=scheduled_duplicate_invalid_schedule_id '
        'launchOrigin=scheduledExecution scheduleId=$scheduleId',
      );
      _exitProcess?.call(ScheduledBackupExitCode.invalidScheduleId);
      return;
    }

    final ownerInfo = await _getExistingInfo();
    if (ownerInfo?.canRunSchedule != true) {
      LoggerService.warning(
        'event=scheduled_duplicate_owner_cannot_run_schedule '
        'ownerRole=${ownerInfo?.role ?? "unknown"} '
        'canRunSchedule=${ownerInfo?.canRunSchedule ?? "unknown"}',
      );
      _exitProcess?.call(ScheduledBackupExitCode.genericFailure);
      return;
    }

    LoggerService.infoWithContext(
      'event=scheduled_duplicate_delegating ownerRole=${ownerInfo!.role} '
      'canRunSchedule=${ownerInfo.canRunSchedule}',
      scheduleId: scheduleId,
    );
    final result = await _ipcClient.delegateScheduledExecution(scheduleId);
    if (result == null) {
      LoggerService.error(
        'event=scheduled_duplicate_delegation_failed scheduleId=$scheduleId',
      );
      _exitProcess?.call(ScheduledBackupExitCode.genericFailure);
      return;
    }

    LoggerService.infoWithContext(
      'event=scheduled_duplicate_delegation_finished '
      'exitCode=${result.exitCode} message=${result.message ?? ""}',
      scheduleId: scheduleId,
    );
    _exitProcess?.call(result.exitCode);
  }

  Future<SingleInstanceOwnerInfo?> _getExistingInfo() async {
    try {
      final ownerInfo = await _ipcClient.getExistingInstanceInfo();
      if (ownerInfo != null) {
        return ownerInfo;
      }
      final role = await _ipcClient.getExistingInstanceRole();
      if (role == null) {
        return null;
      }
      return SingleInstanceOwnerInfo(role: role, canRunSchedule: false);
    } on Object catch (e) {
      LoggerService.debug(
        'Nao foi possivel obter info da instancia existente: $e',
      );
      return null;
    }
  }

  String _getDialogMessage({
    required bool isServiceOwner,
    required bool isDifferentUser,
    required bool couldNotDetermineUser,
    required bool wasExistingWindowNotified,
    String? existingUser,
  }) {
    if (isServiceOwner) {
      return _dialogMessageServiceOwner;
    }

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
