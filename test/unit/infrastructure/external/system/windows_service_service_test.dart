import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockProcessService extends Mock implements ProcessService {}

const _shortTimeout = Duration(seconds: 10);
const _longTimeout = Duration(seconds: 30);

const _runningQueryResult = ProcessResult(
  exitCode: 0,
  stdout: 'STATE              : 4  RUNNING',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _stoppedQueryResult = ProcessResult(
  exitCode: 0,
  stdout: 'STATE              : 1  STOPPED',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _runningQueryResultPt = ProcessResult(
  exitCode: 0,
  stdout: 'ESTADO             : 4  EM EXECUÇÃO',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _pausedQueryResult = ProcessResult(
  exitCode: 0,
  stdout: 'STATE              : 7  PAUSED',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _notInstalledQueryResult = ProcessResult(
  exitCode: 1060,
  stdout: '[SC] OpenService FAILED 1060',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _startPendingQueryResult = ProcessResult(
  exitCode: 0,
  stdout: 'STATE              : 2  START_PENDING',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

const _stopPendingQueryResult = ProcessResult(
  exitCode: 0,
  stdout: 'STATE              : 3  STOP_PENDING',
  stderr: '',
  duration: Duration(milliseconds: 10),
);

void _stubQuery(
  MockProcessService mock,
  ProcessResult result,
) {
  when(
    () => mock.run(
      executable: 'sc',
      arguments: ['query', 'BackupDatabaseService'],
      timeout: _shortTimeout,
    ),
  ).thenAnswer((_) async => rd.Success(result));
}

void _stubStart(
  MockProcessService mock,
  ProcessResult result,
) {
  when(
    () => mock.run(
      executable: 'sc',
      arguments: ['start', 'BackupDatabaseService'],
      timeout: _longTimeout,
    ),
  ).thenAnswer((_) async => rd.Success(result));
}

void _stubStop(
  MockProcessService mock,
  ProcessResult result,
) {
  when(
    () => mock.run(
      executable: 'sc',
      arguments: ['stop', 'BackupDatabaseService'],
      timeout: _longTimeout,
    ),
  ).thenAnswer((_) async => rd.Success(result));
}

void main() {
  group('WindowsServiceService.getStatus', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return installed and running when sc query succeeds',
      () async {
        _stubQuery(mockProcessService, _runningQueryResult);

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            expect(status.isInstalled, isTrue);
            expect(status.isRunning, isTrue);
          },
          (failure) => fail('Expected success, got failure: $failure'),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return installed and running when sc query returns PT-BR (EM EXECUÇÃO)',
      () async {
        _stubQuery(mockProcessService, _runningQueryResultPt);

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            expect(status.isInstalled, isTrue);
            expect(status.isRunning, isTrue);
          },
          (failure) => fail('Expected success, got failure: $failure'),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return not installed when service is missing',
      () async {
        _stubQuery(mockProcessService, _notInstalledQueryResult);

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            expect(status.isInstalled, isFalse);
            expect(status.isRunning, isFalse);
          },
          (failure) => fail('Expected success, got failure: $failure'),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when access is denied',
      () async {
        _stubQuery(
          mockProcessService,
          const ProcessResult(
            exitCode: 5,
            stdout: '',
            stderr: 'Access is denied.',
            duration: Duration(milliseconds: 10),
          ),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) => fail('Expected failure, got success: $status'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('Acesso negado'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when sc query returns unknown operational error',
      () async {
        _stubQuery(
          mockProcessService,
          const ProcessResult(
            exitCode: 1,
            stdout: '',
            stderr: 'Some unexpected operational error',
            duration: Duration(milliseconds: 10),
          ),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) => fail('Expected failure, got success: $status'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('Falha ao consultar status do servi'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when process runner returns failure',
      () async {
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer(
          (_) async => rd.Failure(Exception('process runner failed')),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) => fail('Expected failure, got success: $status'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('Erro ao executar comando para consultar status'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  // ---------------------------------------------------------------------------
  // startService
  // ---------------------------------------------------------------------------
  group('WindowsServiceService.startService', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return success when service transitions to RUNNING after start',
      () async {
        // First getStatus call (before start): stopped
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          // 1st call: STOPPED; subsequent calls (polling): RUNNING
          return queryCallCount == 1
              ? const rd.Success(_stoppedQueryResult)
              : const rd.Success(_runningQueryResult);
        });

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout:
                'SERVICE_NAME: BackupDatabaseService\n  STATE: 2  START_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(seconds: 5),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        expect(result.isSuccess(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return success when service is PAUSED and recovery stop/start reaches RUNNING',
      () async {
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          if (queryCallCount == 1) {
            return const rd.Success(_pausedQueryResult);
          }
          if (queryCallCount == 2) {
            return const rd.Success(_pausedQueryResult);
          }
          if (queryCallCount == 3) {
            return const rd.Success(_stoppedQueryResult);
          }
          return const rd.Success(_runningQueryResult);
        });

        _stubStop(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout: 'STATE: 3  STOP_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout:
                'SERVICE_NAME: BackupDatabaseService\n  STATE: 2  START_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(seconds: 5),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        expect(result.isSuccess(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return success when error 1056 and service is already RUNNING',
      () async {
        // Pre-check: service is not running yet (or pre-check comes as STOPPED)
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          return queryCallCount == 1
              ? const rd.Success(_stoppedQueryResult)
              : const rd.Success(_runningQueryResult);
        });

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 1056,
            stdout:
                '[SC] StartService FAILED 1056:\nUma cópia deste serviço já está em execução.',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );

        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(seconds: 5),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        expect(result.isSuccess(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when error 1056 and service never reaches RUNNING',
      () async {
        // All query calls return STOPPED
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async => const rd.Success(_stoppedQueryResult));

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 1056,
            stdout:
                '[SC] StartService FAILED 1056:\nUma cópia deste serviço já está em execução.',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );

        // Use a tiny polling timeout so the test finishes quickly
        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(milliseconds: 50),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        result.fold(
          (success) => fail('Expected failure, got success'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('1056'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when service never reaches RUNNING within timeout',
      () async {
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async => const rd.Success(_stoppedQueryResult));

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout: 'STATE: 2  START_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 10),
          ),
        );

        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(milliseconds: 50),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        result.fold(
          (success) => fail('Expected failure, got success'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('RUNNING'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return success immediately when service is already running',
      () async {
        _stubQuery(mockProcessService, _runningQueryResult);

        final result = await windowsServiceService.startService();

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['start', 'BackupDatabaseService'],
            timeout: any(named: 'timeout'),
          ),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when access is denied',
      () async {
        _stubQuery(mockProcessService, _stoppedQueryResult);

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 5,
            stdout: '',
            stderr: 'Access is denied.',
            duration: Duration(milliseconds: 10),
          ),
        );
        when(
          () => mockProcessService.run(
            executable: 'powershell',
            arguments: any(named: 'arguments'),
            timeout: _longTimeout,
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 5,
              stdout: '',
              stderr: 'Access is denied.',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.startService();

        result.fold(
          (success) => fail('Expected failure, got success'),
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message.toLowerCase(),
              contains('uac'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('WindowsServiceService.stopService', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return success when service was running and stops',
      () async {
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          return queryCallCount == 1
              ? const rd.Success(_runningQueryResult)
              : const rd.Success(_stoppedQueryResult);
        });

        _stubStop(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout: 'STATE: 3  STOP_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        final result = await windowsServiceService.stopService();

        expect(result.isSuccess(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return success when service already stopped',
      () async {
        _stubQuery(mockProcessService, _stoppedQueryResult);

        final result = await windowsServiceService.stopService();

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['stop', 'BackupDatabaseService'],
            timeout: any(named: 'timeout'),
          ),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should attempt UAC elevation when access is denied (S13)',
      () async {
        // S13 da auditoria: "Access is denied" agora aciona elevação UAC
        // (consolidado no `_textContainsAccessDenied`). Antes apenas o
        // start path tratava essa variante; agora todos os comandos
        // (stop/install/uninstall) tentam elevar quando matchear.
        _stubQuery(mockProcessService, _runningQueryResult);
        _stubStop(
          mockProcessService,
          const ProcessResult(
            exitCode: 5,
            stdout: '',
            stderr: 'Access is denied.',
            duration: Duration(milliseconds: 10),
          ),
        );
        // Stubs powershell elevation (UAC negado pelo usuário). A
        // mensagem precisa bater no detector `_wasUacCancelled` (busca
        // 'cancelada pelo usuário' com acento).
        when(
          () => mockProcessService.run(
            executable: 'powershell',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'A operacao foi cancelada pelo usuário',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.stopService();

        result.fold(
          (success) => fail('Expected failure, got success'),
          (failure) {
            // Após elevation cancelada, retorna ValidationFailure com
            // mensagem sobre UAC.
            expect(failure, isA<ValidationFailure>());
            final msg = (failure as ValidationFailure).message.toLowerCase();
            expect(msg, contains('administrador'));
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('WindowsServiceService.restartService', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return success when stop then start both succeed',
      () async {
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          if (queryCallCount <= 2) {
            return queryCallCount == 1
                ? const rd.Success(_runningQueryResult)
                : const rd.Success(_stoppedQueryResult);
          }
          return queryCallCount == 3
              ? const rd.Success(_stoppedQueryResult)
              : const rd.Success(_runningQueryResult);
        });

        _stubStop(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout: 'STATE: 3  STOP_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        _stubStart(
          mockProcessService,
          const ProcessResult(
            exitCode: 0,
            stdout: 'STATE: 2  START_PENDING',
            stderr: '',
            duration: Duration(milliseconds: 50),
          ),
        );

        final result = await windowsServiceService.restartService();

        expect(result.isSuccess(), isTrue);
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when stop fails after UAC cancel',
      () async {
        // S13 da auditoria: "Access is denied" agora aciona elevação UAC
        // mesmo no path de stop (consumido pelo restart). Quando o UAC
        // é cancelado pelo usuário, retornamos ValidationFailure.
        _stubQuery(mockProcessService, _runningQueryResult);
        _stubStop(
          mockProcessService,
          const ProcessResult(
            exitCode: 5,
            stdout: '',
            stderr: 'Access is denied.',
            duration: Duration(milliseconds: 10),
          ),
        );
        when(
          () => mockProcessService.run(
            executable: 'powershell',
            arguments: any(named: 'arguments'),
            timeout: any(named: 'timeout'),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'A operacao foi cancelada pelo usuário',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.restartService();

        result.fold(
          (success) => fail('Expected failure, got success'),
          (failure) {
            // O ValidationFailure do UAC cancel propaga pelo restart.
            expect(failure, isA<ValidationFailure>());
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('WindowsServiceService.installService', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return failure when NSSM is not found in tools directory',
      () async {
        final result = await windowsServiceService.installService();

        result.fold(
          (_) => fail('Expected failure when NSSM not found'),
          (failure) {
            expect(failure, isA<ValidationFailure>());
            expect(
              (failure as ValidationFailure).message.toLowerCase(),
              contains('nssm'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('WindowsServiceService.uninstallService', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'should return failure when NSSM is not found in tools directory',
      () async {
        final result = await windowsServiceService.uninstallService();

        result.fold(
          (_) => fail('Expected failure when NSSM not found'),
          (failure) {
            expect(failure, isA<ValidationFailure>());
            expect(
              (failure as ValidationFailure).message.toLowerCase(),
              contains('nssm'),
            );
          },
        );
      },
      skip: !Platform.isWindows,
    );
  });

  group('WindowsServiceService idempotência', () {
    late MockProcessService mockProcessService;
    late WindowsServiceService windowsServiceService;

    setUp(() {
      mockProcessService = MockProcessService();
      windowsServiceService = WindowsServiceService(mockProcessService);
    });

    test(
      'startService when START_PENDING should only poll until RUNNING without calling sc start',
      () async {
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          return queryCallCount == 1
              ? const rd.Success(_startPendingQueryResult)
              : const rd.Success(_runningQueryResult);
        });

        final result = await windowsServiceService.startServiceWithTimeout(
          pollingTimeout: const Duration(seconds: 5),
          pollingInterval: const Duration(milliseconds: 10),
          initialDelay: Duration.zero,
        );

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['start', 'BackupDatabaseService'],
            timeout: any(named: 'timeout'),
          ),
        );
        verifyNever(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['continue', 'BackupDatabaseService'],
            timeout: any(named: 'timeout'),
          ),
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'stopService when STOP_PENDING should only poll until stopped without calling sc stop',
      () async {
        var queryCallCount = 0;
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: _shortTimeout,
          ),
        ).thenAnswer((_) async {
          queryCallCount++;
          return queryCallCount == 1
              ? const rd.Success(_stopPendingQueryResult)
              : const rd.Success(_stoppedQueryResult);
        });

        final result = await windowsServiceService.stopService();

        expect(result.isSuccess(), isTrue);
        verifyNever(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['stop', 'BackupDatabaseService'],
            timeout: any(named: 'timeout'),
          ),
        );
      },
      skip: !Platform.isWindows,
    );
  });
}
