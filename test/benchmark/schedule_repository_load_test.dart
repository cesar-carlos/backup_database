import 'dart:convert';

import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/schedule_repository.dart';
import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:result_dart/result_dart.dart' as rd;

const scheduleCount = 50;
const destinationCount = 20;
const destinationsPerSchedule = 4;
const warmupRuns = 3;
const measureRuns = 10;

void main() {
  late AppDatabase database;
  late ScheduleRepository scheduleRepository;

  setUpAll(() async {
    database = AppDatabase.inMemory();
    scheduleRepository = ScheduleRepository(database);
    await _seedDatabase(database);
  });

  tearDownAll(() async {
    await database.close();
  });

  group('ScheduleRepository load benchmarks', () {
    test('getAll completes within threshold for $scheduleCount schedules',
        () async {
      final durations = await _measureOperation(
        () => scheduleRepository.getAll(),
        warmupRuns: warmupRuns,
        measureRuns: measureRuns,
      );
      final avgMs = _averageMs(durations);
      expect(avgMs, lessThan(500), reason: 'getAll should complete in < 500ms');
    });

    test('getEnabled completes within threshold for $scheduleCount schedules',
        () async {
      final durations = await _measureOperation(
        () => scheduleRepository.getEnabled(),
        warmupRuns: warmupRuns,
        measureRuns: measureRuns,
      );
      final avgMs = _averageMs(durations);
      expect(
        avgMs,
        lessThan(500),
        reason: 'getEnabled should complete in < 500ms',
      );
    });

    test('getEnabledDueForExecution completes within threshold', () async {
      final now = DateTime.now();
      final durations = await _measureOperation(
        () => scheduleRepository.getEnabledDueForExecution(now),
        warmupRuns: warmupRuns,
        measureRuns: measureRuns,
      );
      final avgMs = _averageMs(durations);
      expect(
        avgMs,
        lessThan(100),
        reason: 'getEnabledDueForExecution should complete in < 100ms',
      );
    });
  });
}

Future<void> _seedDatabase(AppDatabase db) async {
  final now = DateTime.now();

  await db.sqlServerConfigDao.insertConfig(
    SqlServerConfigsTableCompanion.insert(
      id: 'config-1',
      name: 'Test Config',
      server: 'localhost',
      database: 'test',
      username: 'sa',
      password: 'pwd',
      createdAt: now,
      updatedAt: now,
    ),
  );

  for (var i = 0; i < destinationCount; i++) {
    await db.backupDestinationDao.insertDestination(
      BackupDestinationsTableCompanion.insert(
        id: 'dest-$i',
        name: 'Destination $i',
        type: 'local',
        config: '{"path":"C:/backup/$i"}',
        createdAt: now,
        updatedAt: now,
      ),
    );
  }

  const dailyConfig = '{"hour":0,"minute":0}';
  for (var i = 0; i < scheduleCount; i++) {
    final destIds = List.generate(
      destinationsPerSchedule,
      (j) => 'dest-${(i + j) % destinationCount}',
    );
    await db.scheduleDao.insertSchedule(
      SchedulesTableCompanion.insert(
        id: 'schedule-$i',
        name: 'Schedule $i',
        databaseConfigId: 'config-1',
        databaseType: 'sqlServer',
        scheduleType: ScheduleType.daily.name,
        scheduleConfig: dailyConfig,
        destinationIds: jsonEncode(destIds),
        backupFolder: const Value('C:/backup'),
        backupType: const Value('full'),
        enabled: const Value(true),
        nextRunAt: Value(now.subtract(const Duration(minutes: 1))),
        createdAt: now,
        updatedAt: now,
      ),
    );

    for (final destId in destIds) {
      await db.scheduleDestinationDao.insertRelation(
        ScheduleDestinationsTableCompanion.insert(
          id: 'schedule-$i:$destId',
          scheduleId: 'schedule-$i',
          destinationId: destId,
          createdAt: now,
        ),
      );
    }
  }
}

Future<List<Duration>> _measureOperation(
  Future<rd.Result<List<Schedule>>> Function() operation, {
  required int warmupRuns,
  required int measureRuns,
}) async {
  for (var i = 0; i < warmupRuns; i++) {
    await operation();
  }

  final durations = <Duration>[];
  for (var i = 0; i < measureRuns; i++) {
    final stopwatch = Stopwatch()..start();
    await operation();
    stopwatch.stop();
    durations.add(stopwatch.elapsed);
  }
  return durations;
}

double _averageMs(List<Duration> durations) {
  if (durations.isEmpty) return 0;
  final totalMicros =
      durations.fold<int>(0, (sum, d) => sum + d.inMicroseconds);
  return totalMicros / durations.length / 1000;
}
