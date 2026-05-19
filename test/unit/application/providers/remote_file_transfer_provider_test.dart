import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/providers/remote_file_transfer_provider.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/domain/services/i_send_file_to_destination_service.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/socket/client/connection_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../../helpers/stub_temp_directory_service.dart';

class MockConnectionManager extends Mock implements ConnectionManager {}

class MockBackupDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class MockSendFileToDestinationService extends Mock
    implements ISendFileToDestinationService {}

class MockMachineSettingsRepository extends Mock
    implements IMachineSettingsRepository {}

void main() {
  late MockConnectionManager connectionManager;
  late MockBackupDestinationRepository destinationRepository;
  late MockSendFileToDestinationService sendFileService;
  late MockMachineSettingsRepository machineSettings;
  late StubTempDirectoryService tempDirectory;
  late RemoteFileTransferProvider provider;

  const scheduleId = 'sch-transfer-1';
  const destId = 'dest-local-1';

  setUpAll(() {
    registerFallbackValue(
      BackupDestination(
        name: 'Local',
        type: DestinationType.local,
        config: '{}',
        id: destId,
      ),
    );
  });

  setUp(() {
    connectionManager = MockConnectionManager();
    destinationRepository = MockBackupDestinationRepository();
    sendFileService = MockSendFileToDestinationService();
    machineSettings = MockMachineSettingsRepository();
    tempDirectory = StubTempDirectoryService(
      machineSettings: machineSettings,
    );

    when(() => connectionManager.isConnected).thenReturn(true);
    when(
      () => connectionManager.cleanupRemoteStaging(
        runId: any(named: 'runId'),
      ),
    ).thenAnswer(
      (_) async => rd.Success(
        CleanupStagingResult(
          runId: 'run-1',
          cleaned: true,
          serverTimeUtc: DateTime.utc(2026, 5),
        ),
      ),
    );

    provider = RemoteFileTransferProvider(
      connectionManager,
      destinationRepository,
      sendFileService,
      tempDirectory,
      machineSettings,
    );
  });

  group('RemoteFileTransferProvider.transferCompletedBackupToClient', () {
    test(
      'should upload downloaded file to linked local destinations',
      () async {
        const serverRelativePath =
            'remote/sch-transfer-1_run-uuid-000000000000000000000001/backup.bak';

        when(
          () => machineSettings.getScheduleTransferDestinationsJson(),
        ).thenAnswer(
          (_) async => jsonEncode(<String, dynamic>{
            scheduleId: <String>[destId],
          }),
        );

        final destination = BackupDestination(
          id: destId,
          name: 'Pasta local',
          type: DestinationType.local,
          config: r'{"path":"C:\\backups"}',
        );
        when(() => destinationRepository.getById(destId)).thenAnswer(
          (_) async => rd.Success(destination),
        );

        when(
          () => sendFileService.sendFile(
            localFilePath: any(named: 'localFilePath'),
            destination: any(named: 'destination'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((_) async => const rd.Success(()));

        when(
          () => connectionManager.requestFile(
            filePath: any(named: 'filePath'),
            outputPath: any(named: 'outputPath'),
            scheduleId: any(named: 'scheduleId'),
            runId: any(named: 'runId'),
            onProgress: any(named: 'onProgress'),
          ),
        ).thenAnswer((invocation) async {
          final outputPath = invocation.namedArguments[#outputPath] as String;
          await File(outputPath).writeAsString('backup-bytes');
          return const rd.Success(());
        });

        final ok = await provider.transferCompletedBackupToClient(
          scheduleId,
          serverRelativePath,
          runId: 'sch-transfer-1_run-uuid-000000000000000000000001',
        );

        expect(ok, isTrue);
        verify(
          () => sendFileService.sendFile(
            localFilePath: any(named: 'localFilePath'),
            destination: destination,
            onProgress: any(named: 'onProgress'),
          ),
        ).called(1);
        verify(
          () => connectionManager.cleanupRemoteStaging(
            runId: 'sch-transfer-1_run-uuid-000000000000000000000001',
          ),
        ).called(1);
      },
    );

    test('should skip upload when no linked destinations', () async {
      when(
        () => machineSettings.getScheduleTransferDestinationsJson(),
      ).thenAnswer((_) async => null);

      when(
        () => connectionManager.requestFile(
          filePath: any(named: 'filePath'),
          outputPath: any(named: 'outputPath'),
          scheduleId: any(named: 'scheduleId'),
          runId: any(named: 'runId'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((invocation) async {
        final outputPath = invocation.namedArguments[#outputPath] as String;
        await File(outputPath).writeAsString('x');
        return const rd.Success(());
      });

      final ok = await provider.transferCompletedBackupToClient(
        scheduleId,
        r'C:\server\backup.bak',
      );

      expect(ok, isTrue);
      verifyNever(
        () => sendFileService.sendFile(
          localFilePath: any(named: 'localFilePath'),
          destination: any(named: 'destination'),
          onProgress: any(named: 'onProgress'),
        ),
      );
    });
  });
}
