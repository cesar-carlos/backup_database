import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:backup_database/infrastructure/external/system/single_instance_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:win32/win32.dart';

void main() {
  group('SingleInstanceService.checkAndLock', () {
    test(
      'should return false when mutex creation fails and fallback is fail_safe',
      () async {
        final service = SingleInstanceService.forTest(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => 5,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failSafe,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
      },
    );

    test(
      'should return true when mutex creation fails and fallback is fail_open',
      () async {
        final service = SingleInstanceService.forTest(
          createMutex: (_, _, _) => 0,
          setLastError: (_) {},
          getLastError: () => 5,
          isWindowsPlatform: () => true,
          lockFallbackModeProvider: () =>
              SingleInstanceLockFallbackMode.failOpen,
        );

        final result = await service.checkAndLock();

        expect(result, isTrue);
        expect(service.isFirstInstance, isTrue);
      },
    );

    test(
      'should return false and close handle when mutex already exists',
      () async {
        var closeHandleCallCount = 0;
        final service = SingleInstanceService.forTest(
          createMutex: (_, _, _) => 123,
          setLastError: (_) {},
          getLastError: () => ERROR_ALREADY_EXISTS,
          closeHandle: (_) {
            closeHandleCallCount++;
            return 1;
          },
          isWindowsPlatform: () => true,
        );

        final result = await service.checkAndLock();

        expect(result, isFalse);
        expect(service.isFirstInstance, isFalse);
        expect(closeHandleCallCount, equals(1));
      },
    );
  });
}
