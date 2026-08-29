import 'package:backup_database/core/config/single_instance_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UI and Windows service instance contract', () {
    test('should use the same global mutex for UI and service', () {
      expect(
        SingleInstanceConfig.uiMutexName,
        equals(SingleInstanceConfig.instanceMutexName),
      );
      expect(
        SingleInstanceConfig.serviceMutexName,
        equals(SingleInstanceConfig.instanceMutexName),
      );
      expect(
        SingleInstanceConfig.instanceMutexName,
        contains('InstanceMutex'),
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

    test('should advertise that UI and service do not coexist', () {
      expect(SingleInstanceConfig.coexistsWithUi, isFalse);
      expect(
        SingleInstanceConfig.coexistenceLogToken,
        equals('coexists_with_ui=false'),
      );
      expect(
        SingleInstanceConfig.lockScopeLogToken,
        equals('lock_scope=machine_global'),
      );
    });
  });
}
