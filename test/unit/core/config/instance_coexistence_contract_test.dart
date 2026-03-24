import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI and Windows service instance contract', () {
    test('should use distinct mutex names for UI and service', () {
      expect(
        SingleInstanceConfig.uiMutexName,
        isNot(equals(SingleInstanceConfig.serviceMutexName)),
      );
      expect(
        SingleInstanceConfig.uiMutexName,
        contains('UIMutex'),
      );
      expect(
        SingleInstanceConfig.serviceMutexName,
        contains('ServiceMutex'),
      );
    });

    test(
      'should use fail_safe lock fallback for service process regardless of env',
      () {
        expect(
          SingleInstanceConfig.lockFallbackModeFor(isServiceMode: true),
          SingleInstanceLockFallbackMode.failSafe,
        );
      },
    );
  });
}
