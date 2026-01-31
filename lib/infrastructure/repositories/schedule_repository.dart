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
      LoggerService.info(
        '[ScheduleRepository] Carregando todos os agendamentos...',
      );
      final schedules = await _database.scheduleDao.getAll();
      LoggerService.info(
        '[ScheduleRepository] Encontrados ${schedules.length} agendamentos no banco',
      );
      final entities = schedules.map(_toEntity).toList();
      LoggerService.info(
        '[ScheduleRepository] Convertidos ${entities.length} agendamentos para entidades',
      );
      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        '[ScheduleRepository] Erro ao buscar agendamentos',
        e,
        stackTrace,
      );
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
          NotFoundFailure(message: 'Agendamento não encontrado'),
        );
      }
      return rd.Success(_toEntity(schedule));
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<Schedule>> create(Schedule schedule) async {
    try {
      LoggerService.info(
        '[ScheduleRepository] Criando agendamento: ${schedule.name}',
      );
      final companion = _toCompanion(schedule);
      final id = await _database.scheduleDao.insertSchedule(companion);
      LoggerService.info('[ScheduleRepository] Agendamento criado com ID: $id');

      // Verificar se foi salvo corretamente
      final saved = await _database.scheduleDao.getById(schedule.id);
      if (saved == null) {
        LoggerService.error(
          '[ScheduleRepository] Agendamento não foi encontrado após inserção!',
        );
        return const rd.Failure(
          DatabaseFailure(message: 'Agendamento não foi salvo corretamente'),
        );
      }

      LoggerService.info(
        '[ScheduleRepository] Agendamento verificado no banco: ${saved.name}',
      );
      return rd.Success(schedule);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        '[ScheduleRepository] Erro ao criar agendamento',
        e,
        stackTrace,
      );
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao criar agendamento: $e'),
      );
    }
  }

  @override
  Future<rd.Result<Schedule>> update(Schedule schedule) async {
    try {
      final companion = _toCompanion(schedule);
      await _database.scheduleDao.updateSchedule(companion);
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
      await _database.scheduleDao.deleteSchedule(id);
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
      final entities = schedules.map(_toEntity).toList();
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
      final entities = schedules.map(_toEntity).toList();
      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar agendamentos por configuração: $e',
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
        DatabaseFailure(message: 'Erro ao atualizar última execução: $e'),
      );
    }
  }

  Schedule _toEntity(SchedulesTableData data) {
    List<String> destinationIds;
    try {
      destinationIds = (jsonDecode(data.destinationIds) as List).cast<String>();
    } on Object catch (e) {
      LoggerService.warning(
        '[ScheduleRepository] Erro ao decodificar destinationIds para schedule ${data.id}: $e',
      );
      destinationIds = [];
    }

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

  SchedulesTableCompanion _toCompanion(Schedule schedule) {
    return SchedulesTableCompanion(
      id: Value(schedule.id),
      name: Value(schedule.name),
      databaseConfigId: Value(schedule.databaseConfigId),
      databaseType: Value(schedule.databaseType.name),
      scheduleType: Value(schedule.scheduleType.name),
      scheduleConfig: Value(schedule.scheduleConfig),
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
