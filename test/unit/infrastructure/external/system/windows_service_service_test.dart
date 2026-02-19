import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart';
import 'package:backup_database/infrastructure/external/system/windows_service_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class MockProcessService extends Mock implements ProcessService {}

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
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: const Duration(seconds: 10),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 0,
              stdout: 'STATE              : 4  RUNNING',
              stderr: '',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            expect(status.isInstalled, isTrue);
            expect(status.isRunning, isTrue);
          },
          (failure) {
            fail('Expected success, got failure: $failure');
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return not installed when service is missing',
      () async {
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: const Duration(seconds: 10),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1060,
              stdout: '[SC] OpenService FAILED 1060',
              stderr: '',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            expect(status.isInstalled, isFalse);
            expect(status.isRunning, isFalse);
          },
          (failure) {
            fail('Expected success, got failure: $failure');
          },
        );
      },
      skip: !Platform.isWindows,
    );

    test(
      'should return failure when access is denied',
      () async {
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: const Duration(seconds: 10),
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

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            fail('Expected failure, got success: $status');
          },
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
        when(
          () => mockProcessService.run(
            executable: 'sc',
            arguments: ['query', 'BackupDatabaseService'],
            timeout: const Duration(seconds: 10),
          ),
        ).thenAnswer(
          (_) async => const rd.Success(
            ProcessResult(
              exitCode: 1,
              stdout: '',
              stderr: 'Some unexpected operational error',
              duration: Duration(milliseconds: 10),
            ),
          ),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            fail('Expected failure, got success: $status');
          },
          (failure) {
            expect(failure, isA<ServerFailure>());
            expect(
              (failure as ServerFailure).message,
              contains('Falha ao consultar status do serviço'),
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
            timeout: const Duration(seconds: 10),
          ),
        ).thenAnswer(
          (_) async => rd.Failure(Exception('process runner failed')),
        );

        final result = await windowsServiceService.getStatus();

        result.fold(
          (status) {
            fail('Expected failure, got success: $status');
          },
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
}
