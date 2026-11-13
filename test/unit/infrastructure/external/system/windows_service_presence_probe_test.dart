import 'dart:io';

import 'package:backup_database/core/config/execution_ownership.dart';
import 'package:backup_database/infrastructure/external/system/windows_service/windows_service_presence_probe.dart';
import 'package:flutter_test/flutter_test.dart';

bool administrativeMode(ServicePresenceResult result) =>
    ExecutionOwnership.useAdministrativeUi(
      scheduledLaunch: false,
      serviceInstalled: result.presence == WindowsServicePresence.installed,
      statusUnknown: result.presence == WindowsServicePresence.unknown,
    );

void main() {
  test('confirmed absence allows local backups and automatic startup', () {
    final probe = WindowsServicePresenceProbe(
      query: () => ServicePresenceResult.fromOpenServiceError(1060),
    );
    final result = probe.read();
    expect(result.presence, WindowsServicePresence.absent);
    expect(administrativeMode(result), isFalse);
    final previous = ExecutionOwnership.administrativeUi;
    addTearDown(() => ExecutionOwnership.administrativeUi = previous);
    ExecutionOwnership.administrativeUi = administrativeMode(result);
    expect(
      ExecutionOwnership.suppressAutomaticUi(automaticLaunch: true),
      isFalse,
    );
  });

  test('installed service owns execution regardless of running state', () {
    final probe = WindowsServicePresenceProbe(
      query: () =>
          const ServicePresenceResult(WindowsServicePresence.installed),
    );
    expect(administrativeMode(probe.read()), isTrue);
  });

  for (final error in [5, 36, 1072, 1722, 0]) {
    test('OpenService error $error does not authorize local execution', () {
      final probe = WindowsServicePresenceProbe(
        query: () => ServicePresenceResult.fromOpenServiceError(error),
      );
      final result = probe.read();
      expect(result.presence, WindowsServicePresence.unknown);
      expect(result.errorCode, error);
      expect(administrativeMode(result), isTrue);
    });
  }

  test('native query exception never authorizes a second executor', () {
    final result = WindowsServicePresenceProbe(
      query: () => throw StateError('native API unavailable'),
    ).read();
    expect(result.presence, WindowsServicePresence.unknown);
    expect(administrativeMode(result), isTrue);
  });

  test('scheduled launches still use the global executor lock', () {
    expect(
      ExecutionOwnership.useAdministrativeUi(
        scheduledLaunch: true,
        serviceInstalled: true,
        statusUnknown: false,
      ),
      isFalse,
    );
  });

  test(
    'real SCM identifies missing service without launching sc.exe',
    () {
      // Read-only: no service is created, started, stopped or removed.
      final result = WindowsServicePresenceProbe.queryNative(
        serviceName:
            'BackupDatabaseMissingTest_${pid}_'
            '${DateTime.now().microsecondsSinceEpoch}',
      );
      expect(result.presence, WindowsServicePresence.absent);
      expect(result.errorCode, 1060);
      expect(administrativeMode(result), isFalse);
    },
    skip: !Platform.isWindows,
  );
}
