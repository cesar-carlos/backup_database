import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/domain/services/i_single_instance_ipc_client.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/domain/services/i_windows_message_box.dart';
import 'package:backup_database/presentation/boot/launch_bootstrap_context.dart';
import 'package:backup_database/presentation/boot/single_instance_checker.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SingleInstanceChecker', () {
    test('should continue startup when first instance is acquired', () async {
      final singleInstanceService = _FakeSingleInstanceService(
        checkAndLockResult: true,
      );
      final checker = SingleInstanceChecker(
        singleInstanceService: singleInstanceService,
        ipcClient: _FakeSingleInstanceIpcClient(),
        messageBox: _FakeWindowsMessageBox(),
      );

      final canContinue = await checker.checkAndHandleSecondInstance();

      expect(canContinue, isTrue);
    });

    test('should show focus success message when notify succeeds', () async {
      final messageBox = _FakeWindowsMessageBox();
      final checker = SingleInstanceChecker(
        singleInstanceService: _FakeSingleInstanceService(
          checkAndLockResult: false,
        ),
        ipcClient: _FakeSingleInstanceIpcClient(
          existingUser: 'user_a',
          notifyResults: [true],
        ),
        messageBox: messageBox,
        getCurrentUsername: () => 'user_a',
        maxRetryAttempts: 1,
      );

      final canContinue = await checker.checkAndHandleSecondInstance();

      expect(canContinue, isFalse);
      expect(
        messageBox.warningTitle,
        equals(SingleInstanceChecker.dialogTitle),
      );
      expect(
        messageBox.warningMessage,
        contains('A janela existente foi trazida para frente.'),
      );
    });

    test('should show focus failure message when notify fails', () async {
      final messageBox = _FakeWindowsMessageBox();
      final ipcClient = _FakeSingleInstanceIpcClient(
        existingUser: 'user_a',
        notifyResults: [false, false, false],
      );
      final checker = SingleInstanceChecker(
        singleInstanceService: _FakeSingleInstanceService(
          checkAndLockResult: false,
        ),
        ipcClient: ipcClient,
        messageBox: messageBox,
        getCurrentUsername: () => 'user_a',
      );

      final canContinue = await checker.checkAndHandleSecondInstance();

      expect(canContinue, isFalse);
      expect(ipcClient.notifyAttemptCount, equals(3));
      expect(
        messageBox.warningMessage,
        contains('trazer a janela existente para frente'),
      );
    });

    test('should show different user message with existing username', () async {
      final messageBox = _FakeWindowsMessageBox();
      final checker = SingleInstanceChecker(
        singleInstanceService: _FakeSingleInstanceService(
          checkAndLockResult: false,
        ),
        ipcClient: _FakeSingleInstanceIpcClient(
          existingUser: 'admin_user',
          notifyResults: [true],
        ),
        messageBox: messageBox,
        getCurrentUsername: () => 'local_user',
        maxRetryAttempts: 1,
      );

      final canContinue = await checker.checkAndHandleSecondInstance();

      expect(canContinue, isFalse);
      expect(
        messageBox.warningMessage,
        contains('em outro usuário do Windows'),
      );
      expect(
        messageBox.warningMessage,
        contains('Usuario da instancia existente: admin_user.'),
      );
    });

    test(
      'should stay silent on windowsStartup when owner is the same user UI',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'local_user',
          existingRole: 'ui',
          notifyResults: [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'local_user',
          launchOrigin: LaunchOrigin.windowsStartup,
          maxRetryAttempts: 1,
          exitProcess: (_) {},
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.notifyAttemptCount, 0);
        expect(messageBox.warningMessage, isNull);
        expect(messageBox.errorMessage, isNull);
      },
    );

    test(
      'should explain windowsStartup when owner is not the same user UI',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'admin_user',
          existingRole: 'ui',
          notifyResults: [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'local_user',
          launchOrigin: LaunchOrigin.windowsStartup,
          maxRetryAttempts: 1,
          exitProcess: exitCodes.add,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.notifyAttemptCount, 0);
        expect(messageBox.warningMessage, contains('logon'));
        expect(
          messageBox.warningMessage,
          isNot(contains('trazida para frente')),
        );
        expect(exitCodes, [UiBootstrapExitCode.success]);
      },
    );

    test(
      'should explain windowsStartup when the lock owner is the service',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'local_user',
          existingRole: 'service',
          notifyResults: [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'local_user',
          launchOrigin: LaunchOrigin.windowsStartup,
          maxRetryAttempts: 1,
        );

        await checker.checkAndHandleSecondInstance();

        expect(ipcClient.notifyAttemptCount, 0);
        expect(messageBox.warningMessage, contains('serviço'));
        expect(
          messageBox.warningMessage,
          isNot(contains('trazida para frente')),
        );
      },
    );

    test(
      'should exit with success after showing manual duplicate dialog',
      () async {
        final exitCodes = <int>[];
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: _FakeSingleInstanceIpcClient(
            existingUser: 'user_a',
            notifyResults: [true],
          ),
          messageBox: _FakeWindowsMessageBox(),
          getCurrentUsername: () => 'user_a',
          maxRetryAttempts: 1,
          exitProcess: exitCodes.add,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(exitCodes, [UiBootstrapExitCode.success]);
      },
    );

    // F6: foreground notify deve ser pulado quando o dono é outro usuário,
    // evitando focar a janela na sessão de outra pessoa.
    test(
      'should not send SHOW_WINDOW when existing instance is a different user',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'user_a',
          notifyResults: [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'user_b',
          maxRetryAttempts: 1,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.notifyAttemptCount, 0);
        expect(
          messageBox.warningMessage,
          contains('em outro usuário do Windows'),
        );
      },
    );

    test(
      'should not send SHOW_WINDOW when existing instance user is unknown',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingRole: 'ui',
          notifyResults: [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'user_a',
          maxRetryAttempts: 1,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.notifyAttemptCount, 0);
        expect(messageBox.warningMessage, contains('identificar o usu'));
      },
    );

    // F4: race acquire→IPC. Tenta múltiplas vezes obter info quando a
    // primeira chamada retorna null (dono ainda subindo o IPC server).
    test(
      'should retry getExistingInstanceInfo when first attempt returns null',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          // existingRole = null para que o fallback de getExistingInstanceRole
          // também devolva null nas tentativas iniciais (caso contrário o
          // fallback resolveria o role na 1ª iteração e o retry nem
          // aconteceria).
          existingUser: 'user_a',
          notifyResults: [true],
          // Primeiras 2 tentativas retornam null (IPC ainda subindo),
          // 3ª finalmente responde com role.
          ownerInfoResults: [null, null, 'ui'],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'user_a',
          maxRetryAttempts: 1,
          ownerInfoRetryDelay: const Duration(milliseconds: 1),
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.getExistingInstanceInfoCallCount, 3);
        expect(ipcClient.notifyAttemptCount, 1);
      },
    );

    test('should not send SHOW_WINDOW when lock owner is service', () async {
      final messageBox = _FakeWindowsMessageBox();
      final ipcClient = _FakeSingleInstanceIpcClient(
        existingUser: 'user_a',
        existingRole: 'service',
        notifyResults: [true],
      );
      final checker = SingleInstanceChecker(
        singleInstanceService: _FakeSingleInstanceService(
          checkAndLockResult: false,
        ),
        ipcClient: ipcClient,
        messageBox: messageBox,
        getCurrentUsername: () => 'user_a',
        maxRetryAttempts: 1,
      );

      final canContinue = await checker.checkAndHandleSecondInstance();

      expect(canContinue, isFalse);
      expect(ipcClient.notifyAttemptCount, 0);
      expect(messageBox.warningMessage, contains('serviço do Windows'));
    });

    test(
      'should delegate scheduled duplicate and exit with result code',
      () async {
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingRole: 'service',
          canRunSchedule: true,
          delegationResult: const SingleInstanceScheduledDelegationResult(
            exitCode: 0,
          ),
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: _FakeWindowsMessageBox(),
          launchOrigin: LaunchOrigin.scheduledExecution,
          scheduledScheduleId: '00000000-0000-4000-8000-000000000001',
          exitProcess: exitCodes.add,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.delegatedScheduleIds, [
          '00000000-0000-4000-8000-000000000001',
        ]);
        expect(exitCodes, [0]);
      },
    );

    test(
      'should fail scheduled duplicate when lock owner cannot run schedule',
      () async {
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingRole: 'ui',
          delegationResult: const SingleInstanceScheduledDelegationResult(
            exitCode: 0,
          ),
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: _FakeWindowsMessageBox(),
          launchOrigin: LaunchOrigin.scheduledExecution,
          scheduledScheduleId: '00000000-0000-4000-8000-000000000001',
          exitProcess: exitCodes.add,
        );

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.delegatedScheduleIds, isEmpty);
        expect(ipcClient.getExistingInstanceRoleCallCount, 0);
        expect(exitCodes, [ScheduledBackupExitCode.genericFailure]);
      },
    );

    test(
      'should keep retrying a scheduled duplicate until PONG canRunSchedule',
      () async {
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingRole: 'ui',
          canRunSchedule: true,
          ownerInfoResults: const [null, null, 'service'],
          delegationResult: const SingleInstanceScheduledDelegationResult(
            exitCode: 0,
          ),
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: _FakeWindowsMessageBox(),
          launchOrigin: LaunchOrigin.scheduledExecution,
          scheduledScheduleId: '00000000-0000-4000-8000-000000000001',
          scheduledOwnerInfoMaxAttempts: 4,
          scheduledOwnerInfoRetryDelay: const Duration(milliseconds: 1),
          exitProcess: exitCodes.add,
        );

        await checker.checkAndHandleSecondInstance();

        expect(ipcClient.getExistingInstanceInfoCallCount, 3);
        expect(ipcClient.getExistingInstanceRoleCallCount, 0);
        expect(ipcClient.delegatedScheduleIds, [
          '00000000-0000-4000-8000-000000000001',
        ]);
        expect(exitCodes, [ScheduledBackupExitCode.success]);
      },
    );

    test(
      'should exit owner-not-on-pipe when the scheduled owner never answers',
      () async {
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingRole: 'ui',
          canRunSchedule: true,
          ownerInfoResults: const [null, null, null],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: ipcClient,
          messageBox: _FakeWindowsMessageBox(),
          launchOrigin: LaunchOrigin.scheduledExecution,
          scheduledScheduleId: '00000000-0000-4000-8000-000000000001',
          scheduledOwnerInfoMaxAttempts: 3,
          scheduledOwnerInfoRetryDelay: const Duration(milliseconds: 1),
          exitProcess: exitCodes.add,
        );

        await checker.checkAndHandleSecondInstance();

        expect(ipcClient.delegatedScheduleIds, isEmpty);
        expect(ipcClient.getExistingInstanceRoleCallCount, 0);
        expect(exitCodes, [ScheduledBackupExitCode.ownerNotOnPipe]);
        expect(exitCodes.single, isNot(ScheduledBackupExitCode.success));
        expect(
          exitCodes.single,
          isNot(ScheduledBackupExitCode.genericFailure),
        );
      },
    );

    test(
      'should stop scheduled owner retries when the mutex is gone',
      () async {
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          ownerInfoResults: const [null, 'ui'],
          canRunSchedule: true,
          delegationResult: const SingleInstanceScheduledDelegationResult(
            exitCode: 0,
          ),
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
            mutexHeld: false,
          ),
          ipcClient: ipcClient,
          messageBox: _FakeWindowsMessageBox(),
          launchOrigin: LaunchOrigin.scheduledExecution,
          scheduledScheduleId: '00000000-0000-4000-8000-000000000001',
          scheduledOwnerInfoMaxAttempts: 4,
          scheduledOwnerInfoRetryDelay: const Duration(milliseconds: 1),
          exitProcess: exitCodes.add,
        );

        await checker.checkAndHandleSecondInstance();

        expect(ipcClient.getExistingInstanceInfoCallCount, 1);
        expect(ipcClient.delegatedScheduleIds, isEmpty);
        expect(exitCodes, [ScheduledBackupExitCode.ownerNotOnPipe]);
      },
    );

    test(
      'should not claim the window was focused when show is unavailable',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
          ),
          ipcClient: _FakeSingleInstanceIpcClient(
            existingUser: 'user_a',
            existingRole: 'ui',
            notifyStatuses: const [
              SingleInstanceShowWindowStatus.unavailable,
            ],
          ),
          messageBox: messageBox,
          getCurrentUsername: () => 'user_a',
          maxRetryAttempts: 3,
        );

        await checker.checkAndHandleSecondInstance();

        expect(messageBox.warningMessage, contains('não tem uma janela'));
        expect(
          messageBox.warningMessage,
          isNot(contains('trazida para frente')),
        );
      },
    );

    test(
      'should describe a mutex API failure without claiming another copy',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final exitCodes = <int>[];
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'user_a',
          existingRole: 'ui',
          notifyResults: const [true],
        );
        final checker = SingleInstanceChecker(
          singleInstanceService: _FakeSingleInstanceService(
            checkAndLockResult: false,
            lockDenialReason: SingleInstanceLockDenialReason.creationFailed,
          ),
          ipcClient: ipcClient,
          messageBox: messageBox,
          getCurrentUsername: () => 'user_a',
          exitProcess: exitCodes.add,
        );

        await checker.checkAndHandleSecondInstance();

        expect(ipcClient.notifyAttemptCount, 0);
        expect(ipcClient.getExistingInstanceInfoCallCount, 0);
        expect(messageBox.warningMessage, isNull);
        expect(
          messageBox.errorMessage,
          contains('bloqueio de instância única'),
        );
        expect(messageBox.errorMessage, isNot(contains('já está aberto')));
        expect(exitCodes, [UiBootstrapExitCode.fatalBootstrapError]);
      },
    );
  });
}

class _FakeSingleInstanceService implements ISingleInstanceService {
  _FakeSingleInstanceService({
    required this.checkAndLockResult,
    this.lockDenialReason,
    this.mutexHeld = true,
  });

  final bool checkAndLockResult;
  final bool mutexHeld;

  @override
  final SingleInstanceLockDenialReason? lockDenialReason;

  @override
  Future<bool> checkAndLock({
    bool isServiceMode = false,
    SingleInstanceLockFallbackMode? fallbackMode,
  }) async {
    return checkAndLockResult;
  }

  @override
  bool isInstanceMutexHeld() => mutexHeld;

  @override
  bool get isFirstInstance => checkAndLockResult;

  @override
  bool get isIpcRunning => false;

  @override
  Future<void> releaseLock() async {}

  @override
  Future<bool> startIpcServer({
    required String role,
    Future<Object?> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    return true;
  }
}

class _FakeSingleInstanceIpcClient implements ISingleInstanceIpcClient {
  _FakeSingleInstanceIpcClient({
    this.existingUser,
    this.existingRole,
    this.canRunSchedule = false,
    this.delegationResult,
    List<bool>? notifyResults,
    List<SingleInstanceShowWindowStatus>? notifyStatuses,
    this._ownerInfoResults,
  }) : _notifyResults = notifyResults ?? <bool>[true],
       _notifyStatuses = notifyStatuses;

  final String? existingUser;
  final String? existingRole;
  final bool canRunSchedule;
  final SingleInstanceScheduledDelegationResult? delegationResult;
  final List<bool> _notifyResults;
  final List<SingleInstanceShowWindowStatus>? _notifyStatuses;
  final List<String?>? _ownerInfoResults;
  final delegatedScheduleIds = <String>[];

  int _notifyAttemptIndex = 0;
  int _ownerInfoCallIndex = 0;

  int get notifyAttemptCount => _notifyAttemptIndex;
  int get getExistingInstanceInfoCallCount => _ownerInfoCallIndex;

  int getExistingInstanceUserCallCount = 0;

  @override
  Future<bool> checkServerRunning() async {
    return false;
  }

  @override
  Future<String?> getExistingInstanceUser() async {
    getExistingInstanceUserCallCount++;
    return existingUser;
  }

  int getExistingInstanceRoleCallCount = 0;

  @override
  Future<String?> getExistingInstanceRole() async {
    getExistingInstanceRoleCallCount++;
    return existingRole;
  }

  @override
  Future<SingleInstanceOwnerInfo?> getExistingInstanceInfo() async {
    final index = _ownerInfoCallIndex;
    _ownerInfoCallIndex++;
    final scriptedResults = _ownerInfoResults;
    if (scriptedResults != null) {
      if (index >= scriptedResults.length) {
        return null;
      }
      final role = scriptedResults[index];
      if (role == null) {
        return null;
      }
      return SingleInstanceOwnerInfo(
        role: role,
        canRunSchedule: canRunSchedule,
      );
    }
    final role = existingRole;
    if (role == null) {
      return null;
    }
    return SingleInstanceOwnerInfo(
      role: role,
      canRunSchedule: canRunSchedule,
    );
  }

  @override
  Future<SingleInstanceShowWindowStatus> notifyExistingInstance() async {
    final statuses = _notifyStatuses;
    if (statuses != null) {
      if (_notifyAttemptIndex >= statuses.length) {
        _notifyAttemptIndex++;
        return SingleInstanceShowWindowStatus.notDelivered;
      }
      final status = statuses[_notifyAttemptIndex];
      _notifyAttemptIndex++;
      return status;
    }
    if (_notifyAttemptIndex >= _notifyResults.length) {
      _notifyAttemptIndex++;
      return SingleInstanceShowWindowStatus.notDelivered;
    }
    final result = _notifyResults[_notifyAttemptIndex];
    _notifyAttemptIndex++;
    return result
        ? SingleInstanceShowWindowStatus.shown
        : SingleInstanceShowWindowStatus.notDelivered;
  }

  @override
  Future<SingleInstanceScheduledDelegationResult?> delegateScheduledExecution(
    String scheduleId,
  ) async {
    delegatedScheduleIds.add(scheduleId);
    return delegationResult;
  }
}

class _FakeWindowsMessageBox implements IWindowsMessageBox {
  String? warningTitle;
  String? warningMessage;
  String? errorTitle;
  String? errorMessage;

  @override
  void showError(String title, String message) {
    errorTitle = title;
    errorMessage = message;
  }

  @override
  void showInfo(String title, String message) {}

  @override
  void showWarning(String title, String message) {
    warningTitle = title;
    warningMessage = message;
  }
}
