import 'package:backup_database/application/services/send_file_to_destination_service.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/services/i_destination_orchestrator.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockDestinationOrchestrator extends Mock
    implements IDestinationOrchestrator {}

void main() {
  group('SendFileToDestinationService', () {
    late _MockDestinationOrchestrator orchestrator;
    late SendFileToDestinationService service;

    setUpAll(() {
      registerFallbackValue(
        BackupDestination(
          name: 'FTP',
          type: DestinationType.ftp,
          config: '{}',
          id: 'dest-1',
        ),
      );
    });

    setUp(() {
      orchestrator = _MockDestinationOrchestrator();
      service = SendFileToDestinationService(
        destinationOrchestrator: orchestrator,
      );
    });

    test('delegates upload to destination orchestrator', () async {
      final destination = BackupDestination(
        name: 'FTP',
        type: DestinationType.ftp,
        config: '{}',
        id: 'dest-1',
      );
      final progressEvents = <double>[];
      void onProgress(double progress, [String? stepOverride]) {
        progressEvents.add(progress);
      }

      when(
        () => orchestrator.uploadToDestination(
          sourceFilePath: any(named: 'sourceFilePath'),
          destination: any(named: 'destination'),
          onProgress: any(named: 'onProgress'),
        ),
      ).thenAnswer((_) async => const rd.Success(()));

      final result = await service.sendFile(
        localFilePath: r'C:\tmp\backup.bak',
        destination: destination,
        onProgress: onProgress,
      );

      expect(result.isSuccess(), isTrue);
      verify(
        () => orchestrator.uploadToDestination(
          sourceFilePath: r'C:\tmp\backup.bak',
          destination: destination,
          onProgress: onProgress,
        ),
      ).called(1);
      verifyNoMoreInteractions(orchestrator);
      expect(progressEvents, isEmpty);
    });
  });
}
