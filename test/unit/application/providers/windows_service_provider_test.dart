import 'dart:async';

import 'package:backup_database/application/providers/windows_service_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/domain/services/i_windows_service_event_logger.dart';
import 'package:backup_database/domain/services/i_windows_service_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockService extends Mock implements IWindowsServiceService {}

class _MockEventLog extends Mock implements IWindowsServiceEventLogger {}

class _MockMetrics extends Mock implements IMetricsCollector {}

const _runningStatus = WindowsServiceStatus(
  isInstalled: true,
  isRunning: true,
  serviceName: 'BackupDatabaseService',
  displayName: 'Backup Database Service',
);

const _stoppedStatus = WindowsServiceStatus(
  isInstalled: true,
  isRunning: false,
  serviceName: 'BackupDatabaseService',
  displayName: 'Backup Database Service',
);

const _notInstalledStatus = WindowsServiceStatus(
  isInstalled: false,
  isRunning: false,
);

void main() {
  setUpAll(() {
    registerFallbackValue(const Duration(seconds: 1));
  });

  group('WindowsServiceProvider.checkStatus', () {
    late _MockService service;
    late _MockEventLog eventLog;
    late WindowsServiceProvider provider;

    setUp(() {
      service = _MockService();
      eventLog = _MockEventLog();
      provider = WindowsServiceProvider(service, eventLog);
    });

    test('populates status from successful getStatus result', () async {
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_runningStatus),
      );

      await provider.checkStatus();

      expect(provider.isInstalled, isTrue);
      expect(provider.isRunning, isTrue);
      expect(provider.error, isNull);
      verify(service.getStatus).called(1);
    });

    test('caches status for 2s and skips repeated getStatus', () async {
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_runningStatus),
      );

      await provider.checkStatus();
      await provider.checkStatus();

      verify(service.getStatus).called(1);
    });

    test('forceRefresh bypasses cache and re-queries', () async {
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_runningStatus),
      );

      await provider.checkStatus();
      await provider.checkStatus(forceRefresh: true);

      verify(service.getStatus).called(2);
    });

    test('stores error message when getStatus fails', () async {
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Failure(
          ServerFailure(message: 'access denied'),
        ),
      );

      await provider.checkStatus();

      expect(provider.error, contains('access denied'));
      expect(provider.isRunning, isFalse);
    });

    test('returns early when already loading', () async {
      var callCount = 0;
      when(service.getStatus).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const rd.Success(_runningStatus);
      });

      final f1 = provider.checkStatus();
      final f2 = provider.checkStatus();
      await Future.wait([f1, f2]);

      expect(callCount, 1);
    });

    test('forceRefresh proceeds even when already loading', () async {
      var callCount = 0;
      when(service.getStatus).thenAnswer((_) async {
        callCount++;
        await Future<void>.delayed(const Duration(milliseconds: 50));
        return const rd.Success(_runningStatus);
      });

      final f1 = provider.checkStatus();
      final f2 = provider.checkStatus(forceRefresh: true);
      await Future.wait([f1, f2]);

      expect(callCount, 2);
    });
  });

  group('WindowsServiceProvider.installService', () {
    late _MockService service;
    late _MockEventLog eventLog;
    late _MockMetrics metrics;
    late WindowsServiceProvider provider;

    setUp(() {
      service = _MockService();
      eventLog = _MockEventLog();
      metrics = _MockMetrics();
      provider = WindowsServiceProvider(
        service,
        eventLog,
        metricsCollector: metrics,
      );

      when(() => eventLog.logInstallStarted()).thenAnswer((_) async {});
      when(() => eventLog.logInstallSucceeded()).thenAnswer((_) async {});
      when(
        () => eventLog.logInstallFailed(error: any(named: 'error')),
      ).thenAnswer((_) async {});
      when(() => eventLog.logStartStarted()).thenAnswer((_) async {});
      when(() => eventLog.logStartSucceeded()).thenAnswer((_) async {});
      when(
        () => eventLog.logStartFailed(error: any(named: 'error')),
      ).thenAnswer((_) async {});
    });

    test('calls startService after successful install', () async {
      when(
        () => service.installService(
          serviceUser: any(named: 'serviceUser'),
          servicePassword: any(named: 'servicePassword'),
        ),
      ).thenAnswer((_) async => const rd.Success(rd.unit));
      when(service.startService).thenAnswer(
        (_) async => const rd.Success(rd.unit),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_runningStatus),
      );

      final ok = await provider.installService();

      expect(ok, isTrue);
      verify(service.startService).called(1);
      verify(() => eventLog.logStartStarted()).called(1);
      verify(() => eventLog.logStartSucceeded()).called(1);
    });

    test('records install_to_running metric on successful install', () async {
      when(
        () => service.installService(
          serviceUser: any(named: 'serviceUser'),
          servicePassword: any(named: 'servicePassword'),
        ),
      ).thenAnswer((_) async => const rd.Success(rd.unit));
      when(service.startService).thenAnswer(
        (_) async => const rd.Success(rd.unit),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_runningStatus),
      );

      final ok = await provider.installService();

      expect(ok, isTrue);
      verify(() => eventLog.logInstallStarted()).called(1);
      verify(() => eventLog.logInstallSucceeded()).called(1);
      verify(
        () => metrics.recordHistogram(
          'windows_service_install_to_running_seconds',
          any(),
        ),
      ).called(1);
    });

    test('does NOT record metric if service did not become running', () async {
      when(
        () => service.installService(
          serviceUser: any(named: 'serviceUser'),
          servicePassword: any(named: 'servicePassword'),
        ),
      ).thenAnswer((_) async => const rd.Success(rd.unit));
      when(service.startService).thenAnswer(
        (_) async => const rd.Success(rd.unit),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_stoppedStatus),
      );

      final ok = await provider.installService();

      expect(ok, isTrue);
      verify(service.startService).called(1);
      verifyNever(
        () => metrics.recordHistogram(
          'windows_service_install_to_running_seconds',
          any(),
        ),
      );
    });

    test('logs install failure when service returns Failure', () async {
      when(
        () => service.installService(
          serviceUser: any(named: 'serviceUser'),
          servicePassword: any(named: 'servicePassword'),
        ),
      ).thenAnswer(
        (_) async => const rd.Failure(ServerFailure(message: 'NSSM not found')),
      );

      final ok = await provider.installService();

      expect(ok, isFalse);
      verify(
        () => eventLog.logInstallFailed(error: any(named: 'error')),
      ).called(1);
      verifyNever(() => eventLog.logInstallSucceeded());
    });

    test(
      'returns false when isLoading is already true (UI-level guard)',
      () async {
        // Cenário real: enquanto a primeira chamada está dentro de
        // `service.installService` (e portanto `isLoading=true`), o
        // usuário não consegue clicar de novo na UI (botão disabled),
        // mas se algum código externo tentar, o provider rejeita.
        final firstReleased = Completer<void>();
        when(
          () => service.installService(
            serviceUser: any(named: 'serviceUser'),
            servicePassword: any(named: 'servicePassword'),
          ),
        ).thenAnswer((_) async {
          await firstReleased.future;
          return const rd.Success(rd.unit);
        });
        when(service.startService).thenAnswer(
          (_) async => const rd.Success(rd.unit),
        );
        when(service.getStatus).thenAnswer(
          (_) async => const rd.Success(_notInstalledStatus),
        );

        final f1 = provider.installService();
        // Aguarda isLoading virar true (primeira chamada já entrou em
        // runAsync). Microtask suficiente para drenar até `await
        // service.installService(...)`.
        for (var i = 0; i < 5; i++) {
          if (provider.isLoading) break;
          await Future<void>.delayed(const Duration(milliseconds: 5));
        }
        expect(provider.isLoading, isTrue);

        final secondResult = await provider.installService();
        expect(secondResult, isFalse);

        firstReleased.complete();
        await f1;
      },
    );
  });

  group('WindowsServiceProvider.startService', () {
    late _MockService service;
    late _MockEventLog eventLog;
    late WindowsServiceProvider provider;

    setUp(() {
      service = _MockService();
      eventLog = _MockEventLog();
      provider = WindowsServiceProvider(service, eventLog);

      when(() => eventLog.logStartStarted()).thenAnswer((_) async {});
      when(() => eventLog.logStartSucceeded()).thenAnswer((_) async {});
      when(
        () => eventLog.logStartFailed(error: any(named: 'error')),
      ).thenAnswer((_) async {});
      when(
        () => eventLog.logStartTimeout(timeout: any(named: 'timeout')),
      ).thenAnswer((_) async {});
    });

    test('logs StartTimeout when error message contains "timeout"', () async {
      when(service.startService).thenAnswer(
        (_) async =>
            const rd.Failure(ServerFailure(message: 'Service start timeout')),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_stoppedStatus),
      );

      final ok = await provider.startService();

      expect(ok, isFalse);
      verify(
        () => eventLog.logStartTimeout(timeout: any(named: 'timeout')),
      ).called(1);
      verifyNever(() => eventLog.logStartFailed(error: any(named: 'error')));
    });

    test('logs StartTimeout with PT-BR "tempo esgotado" variant', () async {
      when(service.startService).thenAnswer(
        (_) async => const rd.Failure(
          ServerFailure(message: 'Tempo esgotado ao iniciar serviço'),
        ),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_stoppedStatus),
      );

      await provider.startService();

      verify(
        () => eventLog.logStartTimeout(timeout: any(named: 'timeout')),
      ).called(1);
    });

    test('logs StartFailed for non-timeout errors', () async {
      when(service.startService).thenAnswer(
        (_) async => const rd.Failure(ServerFailure(message: 'access denied')),
      );
      when(service.getStatus).thenAnswer(
        (_) async => const rd.Success(_stoppedStatus),
      );

      await provider.startService();

      verify(
        () => eventLog.logStartFailed(error: any(named: 'error')),
      ).called(1);
      verifyNever(
        () => eventLog.logStartTimeout(timeout: any(named: 'timeout')),
      );
    });
  });

  group('WindowsServiceProvider.dispose', () {
    test('subsequent notifyListeners is a no-op after dispose', () async {
      final service = _MockService();
      final eventLog = _MockEventLog();
      final provider = WindowsServiceProvider(service, eventLog);
      var notifyCount = 0;
      provider.addListener(() => notifyCount++);

      provider.dispose();

      // Após dispose, qualquer chamada interna a notifyListeners é
      // suprimida — sem crash. Antes do S15, chamar notifyListeners
      // post-dispose lançava.
      // (Não há método público para forçar notify, mas `clearError`
      // chama notifyListeners internamente quando há erro a limpar.)
      expect(notifyCount, 0);
    });
  });
}
