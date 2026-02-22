import 'package:backup_database/application/providers/destination_provider.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:result_dart/result_dart.dart' as rd;

class _MockDestinationRepository extends Mock
    implements IBackupDestinationRepository {}

class _MockScheduleRepository extends Mock implements IScheduleRepository {}

void main() {
  late _MockDestinationRepository destinationRepository;
  late _MockScheduleRepository scheduleRepository;
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

  setUp(() {
    destinationRepository = _MockDestinationRepository();
    scheduleRepository = _MockScheduleRepository();

    when(
      () => destinationRepository.getAll(),
    ).thenAnswer((_) async => rd.Success(<BackupDestination>[destination]));

    provider = DestinationProvider(destinationRepository, scheduleRepository);
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
}
