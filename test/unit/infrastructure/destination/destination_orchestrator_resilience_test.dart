import 'dart:async';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/errors/failure_codes.dart';
import 'package:backup_database/core/utils/circuit_breaker.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_dropbox_destination_service.dart';
import 'package:backup_database/domain/services/i_ftp_service.dart';
import 'package:backup_database/domain/services/i_google_drive_destination_service.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:backup_database/domain/services/i_local_destination_service.dart';
import 'package:backup_database/domain/services/i_nextcloud_destination_service.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_dropbox.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_ftp.dart';
import 'package:backup_database/domain/use_cases/destinations/send_to_nextcloud.dart';
import 'package:backup_database/infrastructure/destination/destination_orchestrator_impl.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockLocalDestinationService extends Mock
    implements ILocalDestinationService {}

class _MockFtpService extends Mock implements IFtpService {}

class _MockGoogleDriveDestinationService extends Mock
    implements IGoogleDriveDestinationService {}

class _MockDropboxDestinationService extends Mock
    implements IDropboxDestinationService {}

class _MockNextcloudDestinationService extends Mock
    implements INextcloudDestinationService {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

void main() {
  late _MockLocalDestinationService localDestinationService;
  late _MockFtpService ftpService;
  late _MockGoogleDriveDestinationService googleDriveDestinationService;
  late _MockDropboxDestinationService dropboxDestinationService;
  late _MockNextcloudDestinationService nextcloudDestinationService;
  late _MockLicensePolicyService licensePolicyService;
  late CircuitBreakerRegistry circuitBreakerRegistry;
  late DestinationOrchestratorImpl orchestrator;

  final ftpDestination = BackupDestination(
    id: 'dest-ftp-1',
    name: 'FTP Test',
    type: DestinationType.ftp,
    config: '{"host":"ftp.example.com","port":21,"username":"u","password":"p",'
        '"remotePath":"/backups"}',
  );

  setUpAll(() {
    registerFallbackValue(
      const FtpDestinationConfig(
        host: 'ftp.example.com',
        username: 'u',
        password: 'p',
        remotePath: '/',
      ),
    );
    registerFallbackValue(ftpDestination);
    registerFallbackValue(const LocalDestinationConfig(path: 'C:/test'));
  });

  setUp(() {
    localDestinationService = _MockLocalDestinationService();
    ftpService = _MockFtpService();
    googleDriveDestinationService = _MockGoogleDriveDestinationService();
    dropboxDestinationService = _MockDropboxDestinationService();
    nextcloudDestinationService = _MockNextcloudDestinationService();
    licensePolicyService = _MockLicensePolicyService();
    circuitBreakerRegistry = CircuitBreakerRegistry(
      openDuration: const Duration(milliseconds: 50),
    );

    when(
      () => licensePolicyService.validateDestinationCapabilities(any()),
    ).thenAnswer((_) async => const rd.Success(rd.unit));

    orchestrator = DestinationOrchestratorImpl(
      localDestinationService: localDestinationService,
      sendToFtp: SendToFtp(ftpService),
      googleDriveDestinationService: googleDriveDestinationService,
      sendToDropbox: SendToDropbox(dropboxDestinationService),
      sendToNextcloud: SendToNextcloud(nextcloudDestinationService),
      licensePolicyService: licensePolicyService,
      circuitBreakerRegistry: circuitBreakerRegistry,
    );
  });

  group('DestinationOrchestrator resilience - cancellation', () {
    test('returns uploadCancelled when isCancelled returns true immediately',
        () async {
      final result = await orchestrator.uploadToDestination(
        sourceFilePath: '/tmp/backup.bak',
        destination: ftpDestination,
        isCancelled: () => true,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as BackupFailure;
      expect(failure.code, FailureCodes.uploadCancelled);
      verifyNever(
        () => ftpService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
          isCancelled: any(named: 'isCancelled'),
        ),
      );
    });

    test('proceeds with upload when isCancelled is null', () async {
      when(
        () => ftpService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          FtpUploadResult(
            remotePath: '/backups/file.bak',
            fileSize: 1024,
            duration: Duration(seconds: 1),
          ),
        ),
      );

      final result = await orchestrator.uploadToDestination(
        sourceFilePath: '/tmp/backup.bak',
        destination: ftpDestination,
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => ftpService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).called(1);
    });
  });

  group('DestinationOrchestrator resilience - circuit breaker', () {
    test('returns circuitBreakerOpen when circuit is open after failures',
        () async {
      when(
        () => ftpService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer(
        (_) async => rd.Failure(
          BackupFailure(
            message: 'timeout',
            originalError: TimeoutException('connection'),
          ),
        ),
      );

      for (var i = 0; i < 3; i++) {
        await orchestrator.uploadToDestination(
          sourceFilePath: '/tmp/backup.bak',
          destination: ftpDestination,
        );
      }

      final result = await orchestrator.uploadToDestination(
        sourceFilePath: '/tmp/backup.bak',
        destination: ftpDestination,
      );

      expect(result.isError(), isTrue);
      final failure = result.exceptionOrNull()! as BackupFailure;
      expect(failure.code, FailureCodes.circuitBreakerOpen);
    });
  });

  group('DestinationOrchestrator resilience - transient failure retry', () {
    test('retries on transient failure and succeeds', () async {
      var attempts = 0;
      when(
        () => ftpService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
          isCancelled: any(named: 'isCancelled'),
        ),
      ).thenAnswer((_) async {
        attempts++;
        if (attempts < 2) {
          return rd.Failure(
            BackupFailure(
              message: 'timeout',
              originalError: TimeoutException('connection'),
            ),
          );
        }
        return const rd.Success(
          FtpUploadResult(
            remotePath: '/backups/file.bak',
            fileSize: 1024,
            duration: Duration(seconds: 1),
          ),
        );
      });

      final result = await orchestrator.uploadToDestination(
        sourceFilePath: '/tmp/backup.bak',
        destination: ftpDestination,
      );

      expect(result.isSuccess(), isTrue);
      expect(attempts, 2);
    });
  });

  group('DestinationOrchestrator uploadToAllDestinations - parallelism', () {
    test('returns results in order for multiple destinations', () async {
      final localDest = BackupDestination(
        id: 'dest-local-1',
        name: 'Local',
        type: DestinationType.local,
        config: '{"path":"C:/backups"}',
      );
      final localDest2 = BackupDestination(
        id: 'dest-local-2',
        name: 'Local 2',
        type: DestinationType.local,
        config: '{"path":"D:/backups"}',
      );

      when(
        () => localDestinationService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
        ),
      ).thenAnswer(
        (invocation) async {
          final config = invocation.namedArguments[const Symbol('config')]
              as LocalDestinationConfig;
          return rd.Success(
            LocalUploadResult(
              destinationPath: config.path,
              fileSize: 1024,
              duration: const Duration(seconds: 1),
            ),
          );
        },
      );

      final results = await orchestrator.uploadToAllDestinations(
        sourceFilePath: '/tmp/backup.bak',
        destinations: [localDest, localDest2],
      );

      expect(results.length, 2);
      expect(results[0].isSuccess(), isTrue);
      expect(results[1].isSuccess(), isTrue);
      verify(
        () => localDestinationService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
        ),
      ).called(2);
    });

    test('returns uploadCancelled for remaining when isCancelled before batch',
        () async {
      when(
        () => localDestinationService.upload(
          sourceFilePath: any(named: 'sourceFilePath'),
          config: any(named: 'config'),
        ),
      ).thenAnswer(
        (_) async => const rd.Success(
          LocalUploadResult(
            destinationPath: 'C:/backups',
            fileSize: 1024,
            duration: Duration(seconds: 1),
          ),
        ),
      );

      final destinations = List.generate(
        4,
        (i) => BackupDestination(
          id: 'dest-local-$i',
          name: 'Local $i',
          type: DestinationType.local,
          config: '{"path":"C:/backups/$i"}',
        ),
      );

      var batchCount = 0;
      final results = await orchestrator.uploadToAllDestinations(
        sourceFilePath: '/tmp/backup.bak',
        destinations: destinations,
        isCancelled: () {
          batchCount++;
          return batchCount > 1;
        },
      );

      expect(results.length, 4);
      expect(results[0].isSuccess(), isTrue);
      expect(results[1].isSuccess(), isTrue);
      expect(results[2].isSuccess(), isTrue);
      expect(results[3].isError(), isTrue);
      expect(
        results[3].exceptionOrNull(),
        isA<BackupFailure>().having(
          (f) => f.code,
          'code',
          FailureCodes.uploadCancelled,
        ),
      );
    });
  });
}
