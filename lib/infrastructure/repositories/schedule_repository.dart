import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ScheduleRepository implements IScheduleRepository {
  ScheduleRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<Schedule>>> getAll() async {
    try {
      LoggerService.info('[ScheduleRepository] Loading schedules...');
      final schedules = await _database.scheduleDao.getAll();

      final entities = <Schedule>[];
      for (final schedule in schedules) {
        final entity = await _toEntity(schedule);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      LoggerService.error('[ScheduleRepository] Failed to load schedules', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar agendamentos: $e'),
      );
    }
  }

  @override
  Future<rd.Result<Schedule>> getById(String id) async {
    try {
      final schedule = await _database.scheduleDao.getById(id);
      if (schedule == null) {
        return const rd.Failure(
          NotFoundFailure(message: 'Agendamento nao encontrado'),
        );
      }

      final entity = await _toEntity(schedule);
      return rd.Success(entity);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<Schedule>> create(Schedule schedule) async {
    try {
      final companion = _toCompanion(schedule);

      await _database.transaction(() async {
        await _database.scheduleDao.insertSchedule(companion);
        await _replaceScheduleDestinations(schedule.id, schedule.destinationIds);
      });

      return rd.Success(schedule);
    } on Object catch (e, stackTrace) {
      LoggerService.error('[ScheduleRepository] Failed to create schedule', e, stackTrace);
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao criar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<Schedule>> update(Schedule schedule) async {
    try {
      final companion = _toCompanion(schedule);
      await _database.transaction(() async {
        await _database.scheduleDao.updateSchedule(companion);
        await _replaceScheduleDestinations(schedule.id, schedule.destinationIds);
      });

      return rd.Success(schedule);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.transaction(() async {
        await _database.scheduleDestinationDao.deleteByScheduleId(id);
        await _database.scheduleDao.deleteSchedule(id);
      });
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<Schedule>>> getEnabled() async {
    try {
      final schedules = await _database.scheduleDao.getEnabled();
      final entities = <Schedule>[];

      for (final schedule in schedules) {
        final entity = await _toEntity(schedule);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar agendamentos ativos: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<Schedule>>> getByDatabaseConfig(
    String databaseConfigId,
  ) async {
    try {
      final schedules = await _database.scheduleDao.getByDatabaseConfig(
        databaseConfigId,
      );
      final entities = <Schedule>[];

      for (final schedule in schedules) {
        final entity = await _toEntity(schedule);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar agendamentos por configuracao: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<List<Schedule>>> getByDestinationId(
    String destinationId,
  ) async {
    try {
      final relations = await _database.scheduleDestinationDao.getByDestinationId(
        destinationId,
      );
      final entities = <Schedule>[];

      for (final relation in relations) {
        final schedule = await _database.scheduleDao.getById(relation.scheduleId);
        if (schedule == null) {
          continue;
        }

        final entity = await _toEntity(schedule);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar agendamentos por destino: $e',
        ),
      );
    }
  }

  @override
  Future<rd.Result<void>> updateLastRun(
    String id,
    DateTime lastRunAt,
    DateTime? nextRunAt,
  ) async {
    try {
      await _database.scheduleDao.updateLastRun(id, lastRunAt, nextRunAt);
      return const rd.Success(unit);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar ultima execucao: $e'),
      );
    }
  }

  Future<Schedule> _toEntity(SchedulesTableData data) async {
    final destinationIds = await _loadDestinationIds(
      data.id,
      data.destinationIds,
    );

    return Schedule(
      id: data.id,
      name: data.name,
      databaseConfigId: data.databaseConfigId,
      databaseType: DatabaseType.values.firstWhere(
        (e) => e.name == data.databaseType,
      ),
      scheduleType: ScheduleType.values.firstWhere(
        (e) => e.name == data.scheduleType,
      ),
      scheduleConfig: data.scheduleConfig,
      destinationIds: destinationIds,
      backupFolder: data.backupFolder,
      backupType: BackupType.fromString(data.backupType),
      truncateLog: data.truncateLog,
      compressBackup: data.compressBackup,
      compressionFormat: CompressionFormat.fromString(data.compressionFormat),
      enabled: data.enabled,
      enableChecksum: data.enableChecksum,
      verifyAfterBackup: data.verifyAfterBackup,
      postBackupScript: data.postBackupScript,
      lastRunAt: data.lastRunAt,
      nextRunAt: data.nextRunAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  Future<List<String>> _loadDestinationIds(
    String scheduleId,
    String legacyDestinationIdsJson,
  ) async {
    try {
      final relations = await _database.scheduleDestinationDao.getByScheduleId(
        scheduleId,
      );
      if (relations.isNotEmpty) {
        return relations.map((r) => r.destinationId).toList();
      }
    } on Object catch (e) {
      LoggerService.warning(
        '[ScheduleRepository] Failed loading relational destinations for '
        '$scheduleId: $e',
      );
    }

    // Fallback while old DBs migrate.
    try {
      return (jsonDecode(legacyDestinationIdsJson) as List).cast<String>();
    } on Object {
      return [];
    }
  }

  Future<void> _replaceScheduleDestinations(
    String scheduleId,
    List<String> destinationIds,
  ) async {
    await _database.scheduleDestinationDao.deleteByScheduleId(scheduleId);

    for (final destinationId in destinationIds.toSet()) {
      await _database.scheduleDestinationDao.insertRelation(
        ScheduleDestinationsTableCompanion.insert(
          id: '$scheduleId:$destinationId',
          scheduleId: scheduleId,
          destinationId: destinationId,
          createdAt: DateTime.now(),
        ),
      );
    }
  }

  SchedulesTableCompanion _toCompanion(Schedule schedule) {
    return SchedulesTableCompanion(
      id: Value(schedule.id),
      name: Value(schedule.name),
      databaseConfigId: Value(schedule.databaseConfigId),
      databaseType: Value(schedule.databaseType.name),
      scheduleType: Value(schedule.scheduleType.name),
      scheduleConfig: Value(schedule.scheduleConfig),
      // Keep legacy JSON synced for backwards compatibility.
      destinationIds: Value(jsonEncode(schedule.destinationIds)),
      backupFolder: Value(schedule.backupFolder),
      backupType: Value(schedule.backupType.name),
      truncateLog: Value(schedule.truncateLog),
      compressBackup: Value(schedule.compressBackup),
      compressionFormat: Value(schedule.compressionFormat.name),
      enabled: Value(schedule.enabled),
      enableChecksum: Value(schedule.enableChecksum),
      verifyAfterBackup: Value(schedule.verifyAfterBackup),
      postBackupScript: Value(schedule.postBackupScript),
      lastRunAt: Value(schedule.lastRunAt),
      nextRunAt: Value(schedule.nextRunAt),
      createdAt: Value(schedule.createdAt),
      updatedAt: Value(schedule.updatedAt),
    );
  }
}
