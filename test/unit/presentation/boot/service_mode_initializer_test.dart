import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/core/exit_codes.dart';
import 'package:backup_database/domain/services/i_single_instance_service.dart';
import 'package:backup_database/presentation/boot/service_mode_initializer.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('ServiceModeInitializer service account policy', () {
    test('accepts LocalSystem aliases', () {
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount(
          'LocalSystem',
        ),
        isTrue,
      );
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount('System'),
        isTrue,
      );
      expect(
        ServiceModeInitializer.isSupportedSilentUpdateServiceAccount(
          r'NT AUTHORITY\System',
        ),
        isTrue,
      );
    });

    test('blocks custom or unknown accounts with actionable message', () {
      expect(
        ServiceModeInitializer.buildUnsupportedServiceAccountMessage(
          r'.\BackupUser',
        ),
        contains('LocalSystem'),
      );
      expect(
        ServiceModeInitializer.buildUnsupportedServiceAccountMessage(null),
        contains('não foi possível validar'),
      );
    });
  });

  group('ServiceModeInitializer.completeGracefulShutdown', () {
    test('releases the lock and then exits', () async {
      final service = _FakeSingleInstanceService();
      final logs = <String>[];
      final exits = <int>[];

      await ServiceModeInitializer.completeGracefulShutdown(
        singleInstanceService: service,
        appendLog: (String message) async {
          logs.add(message);
        },
        exitProcess: exits.add,
      );

      expect(service.releaseCount, 1);
      expect(exits, [ServiceModeExitCode.gracefulShutdown]);
      expect(logs, [
        'initialize: shutdown signal received',
        'initialize: lock released, exiting',
      ]);
      expect(service.events, ['release']);
    });

    test('still exits when releasing the lock throws', () async {
      final service = _FakeSingleInstanceService(
        releaseError: StateError('mutex busy'),
      );
      final exits = <int>[];

      await ServiceModeInitializer.completeGracefulShutdown(
        singleInstanceService: service,
        appendLog: (String _) async {},
        exitProcess: exits.add,
      );

      expect(service.releaseCount, 1);
      expect(exits, [ServiceModeExitCode.gracefulShutdown]);
    });

    test('exits when no single instance service was acquired', () async {
      final exits = <int>[];

      await ServiceModeInitializer.completeGracefulShutdown(
        singleInstanceService: null,
        appendLog: (String _) async {},
        exitProcess: exits.add,
      );

      expect(exits, [ServiceModeExitCode.gracefulShutdown]);
    });
  });
}

final class _FakeSingleInstanceService implements ISingleInstanceService {
  _FakeSingleInstanceService({this.releaseError});

  final StateError? releaseError;
  final List<String> events = <String>[];
  int releaseCount = 0;

  @override
  Future<bool> checkAndLock({
    bool isServiceMode = false,
    SingleInstanceLockFallbackMode? fallbackMode,
  }) async {
    return true;
  }

  @override
  SingleInstanceLockDenialReason? get lockDenialReason => null;

  @override
  bool isInstanceMutexHeld() => false;

  @override
  bool get isFirstInstance => true;

  @override
  bool get isIpcRunning => false;

  @override
  Future<void> releaseLock() async {
    events.add('release');
    releaseCount++;
    final error = releaseError;
    if (error != null) {
      throw error;
    }
  }

  @override
  Future<bool> startIpcServer({
    required String role,
    Future<Object?> Function()? onShowWindow,
    RunScheduleIpcHandler? onRunSchedule,
  }) async {
    return true;
  }
}
