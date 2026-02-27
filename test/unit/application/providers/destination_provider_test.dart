import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_license_policy_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

class _MockLicensePolicyService extends Mock implements ILicensePolicyService {}

void main() {
  late _MockDestinationRepository destinationRepository;
  late _MockScheduleRepository scheduleRepository;
  late _MockLicensePolicyService licensePolicyService;
  late DestinationProvider provider;

  const destinationId = 'dest-1';
  final destination = BackupDestination(
    id: destinationId,
    name: 'Local',
    type: DestinationType.local,
    config: '{"path":"C:/backup"}',
  );
  final linkedSchedule = Schedule(
    id: 'sch-1',
    name: 'Backup Diario',
    databaseConfigId: 'db-1',
    databaseType: DatabaseType.sqlServer,
    scheduleType: ScheduleType.daily.name,
    scheduleConfig: '{}',
    destinationIds: const [destinationId],
    backupFolder: r'C:\backup',
  );

  setUpAll(() {
    registerFallbackValue(destination);
  });

  setUp(() {
    destinationRepository = _MockDestinationRepository();
    scheduleRepository = _MockScheduleRepository();
    licensePolicyService = _MockLicensePolicyService();

    when(
      () => destinationRepository.getAll(),
    ).thenAnswer((_) async => rd.Success(<BackupDestination>[destination]));

    when(
      () => licensePolicyService.validateDestinationCapabilities(any()),
    ).thenAnswer((_) async => const rd.Success(rd.unit));

    provider = DestinationProvider(
      destinationRepository,
      scheduleRepository,
      licensePolicyService,
    );
  });

  group('DestinationProvider.deleteDestination', () {
    test('blocks delete when destination has linked schedules', () async {
      when(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).thenAnswer((_) async => rd.Success(<Schedule>[linkedSchedule]));

      final result = await provider.deleteDestination(destinationId);

      expect(result, isFalse);
      expect(provider.error, contains('agendamentos vinculados'));
      verify(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).called(1);
      verifyNever(() => destinationRepository.delete(any()));
    });

    test('returns false when dependency validation fails', () async {
      when(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).thenAnswer(
        (_) async => const rd.Failure(
          DatabaseFailure(message: 'erro ao buscar dependencias'),
        ),
      );

      final result = await provider.deleteDestination(destinationId);

      expect(result, isFalse);
      expect(provider.error, contains('Nao foi possivel validar dependencias'));
      verify(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).called(1);
      verifyNever(() => destinationRepository.delete(any()));
    });

    test('deletes destination when there is no linked schedule', () async {
      when(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).thenAnswer((_) async => const rd.Success(<Schedule>[]));
      when(
        () => destinationRepository.delete(destinationId),
      ).thenAnswer((_) async => const rd.Success(rd.unit));

      final result = await provider.deleteDestination(destinationId);

      expect(result, isTrue);
      expect(provider.error, isNull);
      expect(provider.destinations, isEmpty);
      verify(
        () => scheduleRepository.getByDestinationId(destinationId),
      ).called(1);
      verify(() => destinationRepository.delete(destinationId)).called(1);
    });
  });

  group('DestinationProvider.createDestination', () {
    test('rejects when license policy fails', () async {
      when(
        () => licensePolicyService.validateDestinationCapabilities(any()),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(
            message: 'Google Drive requer licença com permissão google_drive',
          ),
        ),
      );

      final googleDriveDest = BackupDestination(
        id: 'gd-1',
        name: 'Drive',
        type: DestinationType.googleDrive,
        config: '{"folderId":"x"}',
      );

      final result = await provider.createDestination(googleDriveDest);

      expect(result, isFalse);
      expect(provider.error, contains('google_drive'));
      verifyNever(() => destinationRepository.create(any()));
    });

    test('creates when license policy succeeds', () async {
      when(
        () => destinationRepository.create(any()),
      ).thenAnswer((_) async => rd.Success(destination));

      final result = await provider.createDestination(destination);

      expect(result, isTrue);
      verify(() => destinationRepository.create(destination)).called(1);
    });
  });

  group('DestinationProvider.updateDestination', () {
    test('rejects when license policy fails', () async {
      when(
        () => licensePolicyService.validateDestinationCapabilities(any()),
      ).thenAnswer(
        (_) async => const rd.Failure(
          ValidationFailure(
            message: 'Dropbox requer licença com permissão dropbox',
          ),
        ),
      );

      final dropboxDest = BackupDestination(
        id: 'db-1',
        name: 'Dropbox',
        type: DestinationType.dropbox,
        config: '{}',
      );

      final result = await provider.updateDestination(dropboxDest);

      expect(result, isFalse);
      expect(provider.error, contains('dropbox'));
      verifyNever(() => destinationRepository.update(any()));
    });
  });
}
