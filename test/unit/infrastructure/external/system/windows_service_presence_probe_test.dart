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
  test(
    'native failure followed by SCM 1060 restores standalone mode',
    () async {
      final probe = WindowsServicePresenceProbe(
        query: () => throw StateError('FFI unavailable'),
      );
      final result = await probe.resolve(queryExitCode: () async => 1060);
      expect(result.presence, WindowsServicePresence.absent);
      expect(administrativeMode(result), isFalse);
      expect(probe.diagnostics, [
        contains('FFI unavailable'),
        contains('source=scm_cli presence=absent error=1060'),
      ]);
    },
  );

  test(
    'fallback confirms installed service without relying on localized output',
    () async {
      final probe = WindowsServicePresenceProbe(
        query: () => ServicePresenceResult.fromOpenServiceError(5),
      );
      final result = await probe.resolve(queryExitCode: () async => 0);
      expect(administrativeMode(result), isTrue);
      expect(result.presence, WindowsServicePresence.installed);
    },
  );

  for (final code in [5, 36, 1072, 1722]) {
    test('fallback error $code never authorizes a local executor', () async {
      final probe = WindowsServicePresenceProbe(
        query: () => ServicePresenceResult.fromOpenServiceError(5),
      );
      expect(
        administrativeMode(
          await probe.resolve(queryExitCode: () async => code),
        ),
        isTrue,
      );
    });
  }

  test('failed fallback retains unknown state', () async {
    final probe = WindowsServicePresenceProbe(
      query: () => ServicePresenceResult.fromOpenServiceError(5),
    );
    final result = await probe.resolve(
      queryExitCode: () async => throw const ProcessException('sc', []),
    );
    expect(result.presence, WindowsServicePresence.unknown);
    expect(result.errorCode, 5);
  });

  for (final presence in [
    WindowsServicePresence.absent,
    WindowsServicePresence.installed,
  ]) {
    test('confirmed $presence does not launch fallback', () async {
      final probe = WindowsServicePresenceProbe(
        query: () => ServicePresenceResult(presence),
      );
      final result = await probe.resolve(
        queryExitCode: () async => throw StateError('must not call'),
      );
      expect(result.presence, presence);
    });
  }

  test('confirmed absence allows local backups and automatic startup', () {
    final probe = WindowsServicePresenceProbe(
      query: () => ServicePresenceResult.fromOpenServiceError(1060),
    );
    final result = probe.read();
    expect(result.presence, WindowsServicePresence.absent);
    expect(administrativeMode(result), isFalse);
    expect(probe.diagnostics, ['source=native presence=absent error=1060']);
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
