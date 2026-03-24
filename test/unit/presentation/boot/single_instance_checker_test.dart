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
        maxRetryAttempts: 3,
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
      'should not use ipc when duplicate launch is windowsStartup',
      () async {
        final messageBox = _FakeWindowsMessageBox();
        final ipcClient = _FakeSingleInstanceIpcClient(
          existingUser: 'admin_user',
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

        final canContinue = await checker.checkAndHandleSecondInstance();

        expect(canContinue, isFalse);
        expect(ipcClient.getExistingInstanceUserCallCount, 0);
        expect(ipcClient.notifyAttemptCount, 0);
        expect(messageBox.warningMessage, isNull);
      },
    );
  });
}

class _FakeSingleInstanceService implements ISingleInstanceService {
  _FakeSingleInstanceService({required this.checkAndLockResult});

  final bool checkAndLockResult;

  @override
  Future<bool> checkAndLock({bool isServiceMode = false}) async {
    return checkAndLockResult;
  }

  @override
  bool get isFirstInstance => checkAndLockResult;

  @override
  bool get isIpcRunning => false;

  @override
  Future<void> releaseLock() async {}

  @override
  Future<bool> startIpcServer({Function()? onShowWindow}) async {
    return true;
  }
}

class _FakeSingleInstanceIpcClient implements ISingleInstanceIpcClient {
  _FakeSingleInstanceIpcClient({
    this.isServerRunning = false,
    this.existingUser,
    List<bool>? notifyResults,
  }) : _notifyResults = notifyResults ?? <bool>[true];

  final bool isServerRunning;
  final String? existingUser;
  final List<bool> _notifyResults;

  int _notifyAttemptIndex = 0;

  int get notifyAttemptCount => _notifyAttemptIndex;

  int getExistingInstanceUserCallCount = 0;

  @override
  Future<bool> checkServerRunning() async {
    return isServerRunning;
  }

  @override
  Future<String?> getExistingInstanceUser() async {
    getExistingInstanceUserCallCount++;
    return existingUser;
  }

  @override
  Future<bool> notifyExistingInstance() async {
    if (_notifyAttemptIndex >= _notifyResults.length) {
      _notifyAttemptIndex++;
      return false;
    }
    final result = _notifyResults[_notifyAttemptIndex];
    _notifyAttemptIndex++;
    return result;
  }
}

class _FakeWindowsMessageBox implements IWindowsMessageBox {
  String? warningTitle;
  String? warningMessage;

  @override
  void showError(String title, String message) {}

  @override
  void showInfo(String title, String message) {}

  @override
  void showWarning(String title, String message) {
    warningTitle = title;
    warningMessage = message;
  }
}
