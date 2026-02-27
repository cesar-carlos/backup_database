import 'dart:convert';

import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_backup_schedule.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ScheduleRepository implements IScheduleRepository {
  ScheduleRepository(this._database);
  final AppDatabase _database;
  static const _verifyPolicyKey = '_verifyPolicy';
  static const _sqlServerBackupOptionsKey = '_sqlServerBackupOptions';

  @override
  Future<rd.Result<List<Schedule>>> getAll() async {
    try {
      LoggerService.info('[ScheduleRepository] Loading schedules...');
      final schedules = await _database.scheduleDao.getAll();
      final destinationIdsBySchedule =
          await _loadDestinationIdsBatch(schedules.map((s) => s.id).toList());

      final entities = <Schedule>[];
      for (final schedule in schedules) {
        final destinationIds = destinationIdsBySchedule[schedule.id] ??
            await _loadDestinationIdsFallback(
              schedule.id,
              schedule.destinationIds,
            );
        final entity = await _toEntity(schedule, destinationIds);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        '[ScheduleRepository] Failed to load schedules',
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
          NotFoundFailure(message: 'Agendamento nao encontrado'),
        );
      }

      final destinationIds =
          await _loadDestinationIds(schedule.id, schedule.destinationIds);
      final entity = await _toEntity(schedule, destinationIds);
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
        await _replaceScheduleDestinations(
          schedule.id,
          schedule.destinationIds,
        );
      });

      return rd.Success(schedule);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        '[ScheduleRepository] Failed to create schedule',
        e,
        stackTrace,
      );
      final errorStr = e.toString();
      if (errorStr.contains('foreign key constraint failed')) {
        return const rd.Failure(
          DatabaseFailure(
            message:
                'Erro ao criar agendamento: um ou mais destinos '
                'selecionados não existem. Por favor, selecione destinos válidos.',
          ),
        );
      }
      if (errorStr.contains('Configuracao SQL Server inexistente') ||
          errorStr.contains('Configuracao Sybase inexistente') ||
          errorStr.contains('Configuracao PostgreSQL inexistente')) {
        return const rd.Failure(
          DatabaseFailure(
            message:
                'A configuração de banco selecionada não existe mais. '
                'Recarregue a página de configurações e selecione uma configuração válida.',
          ),
        );
      }
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
        await _replaceScheduleDestinations(
          schedule.id,
          schedule.destinationIds,
        );
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
      final destinationIdsBySchedule =
          await _loadDestinationIdsBatch(schedules.map((s) => s.id).toList());

      final entities = <Schedule>[];
      for (final schedule in schedules) {
        final destinationIds = destinationIdsBySchedule[schedule.id] ??
            await _loadDestinationIdsFallback(
              schedule.id,
              schedule.destinationIds,
            );
        final entity = await _toEntity(schedule, destinationIds);
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
  Future<rd.Result<List<Schedule>>> getEnabledDueForExecution(
    DateTime beforeOrAt,
  ) async {
    try {
      final schedules =
          await _database.scheduleDao.getEnabledDueForExecution(beforeOrAt);
      if (schedules.isEmpty) {
        return const rd.Success([]);
      }
      final destinationIdsBySchedule =
          await _loadDestinationIdsBatch(schedules.map((s) => s.id).toList());

      final entities = <Schedule>[];
      for (final schedule in schedules) {
        final destinationIds = destinationIdsBySchedule[schedule.id] ??
            await _loadDestinationIdsFallback(
              schedule.id,
              schedule.destinationIds,
            );
        final entity = await _toEntity(schedule, destinationIds);
        entities.add(entity);
      }

      return rd.Success(entities);
    } on Object catch (e) {
      return rd.Failure(
        DatabaseFailure(
          message: 'Erro ao buscar agendamentos vencidos: $e',
        ),
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
      final destinationIdsBySchedule =
          await _loadDestinationIdsBatch(schedules.map((s) => s.id).toList());

      final entities = <Schedule>[];
      for (final schedule in schedules) {
        final destinationIds = destinationIdsBySchedule[schedule.id] ??
            await _loadDestinationIdsFallback(
              schedule.id,
              schedule.destinationIds,
            );
        final entity = await _toEntity(schedule, destinationIds);
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
      final relations = await _database.scheduleDestinationDao
          .getByDestinationId(
            destinationId,
          );
      final entities = <Schedule>[];

      for (final relation in relations) {
        final schedule = await _database.scheduleDao.getById(
          relation.scheduleId,
        );
        if (schedule == null) {
          continue;
        }

        final destinationIds =
            await _loadDestinationIds(schedule.id, schedule.destinationIds);
        final entity = await _toEntity(schedule, destinationIds);
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

  Future<Schedule> _toEntity(
    SchedulesTableData data,
    List<String> destinationIds,
  ) async {
    final scheduleConfigMap = _safeDecodeScheduleConfig(data.scheduleConfig);
    final verifyPolicy = _parseVerifyPolicy(scheduleConfigMap);
    final databaseType = DatabaseType.values.firstWhere(
      (e) => e.name == data.databaseType,
    );

    if (databaseType == DatabaseType.sqlServer) {
      final sqlOptions = _parseSqlServerBackupOptions(scheduleConfigMap);
      return SqlServerBackupSchedule(
        id: data.id,
        name: data.name,
        databaseConfigId: data.databaseConfigId,
        databaseType: databaseType,
        scheduleType: data.scheduleType,
        scheduleConfig: data.scheduleConfig,
        destinationIds: destinationIds,
        backupFolder: data.backupFolder,
        backupType: backupTypeFromString(data.backupType),
        truncateLog: data.truncateLog,
        compressBackup: data.compressBackup,
        compressionFormat: CompressionFormat.fromString(data.compressionFormat),
        enabled: data.enabled,
        enableChecksum: data.enableChecksum,
        verifyAfterBackup: data.verifyAfterBackup,
        verifyPolicy: verifyPolicy,
        postBackupScript: data.postBackupScript,
        backupTimeout: Duration(seconds: data.backupTimeoutSeconds),
        verifyTimeout: Duration(seconds: data.verifyTimeoutSeconds),
        lastRunAt: data.lastRunAt,
        nextRunAt: data.nextRunAt,
        createdAt: data.createdAt,
        updatedAt: data.updatedAt,
        sqlServerBackupOptions: sqlOptions,
      );
    }

    return Schedule(
      id: data.id,
      name: data.name,
      databaseConfigId: data.databaseConfigId,
      databaseType: databaseType,
      scheduleType: data.scheduleType,
      scheduleConfig: data.scheduleConfig,
      destinationIds: destinationIds,
      backupFolder: data.backupFolder,
      backupType: backupTypeFromString(data.backupType),
      truncateLog: data.truncateLog,
      compressBackup: data.compressBackup,
      compressionFormat: CompressionFormat.fromString(data.compressionFormat),
      enabled: data.enabled,
      enableChecksum: data.enableChecksum,
      verifyAfterBackup: data.verifyAfterBackup,
      verifyPolicy: verifyPolicy,
      postBackupScript: data.postBackupScript,
      backupTimeout: Duration(seconds: data.backupTimeoutSeconds),
      verifyTimeout: Duration(seconds: data.verifyTimeoutSeconds),
      lastRunAt: data.lastRunAt,
      nextRunAt: data.nextRunAt,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  Future<Map<String, List<String>>> _loadDestinationIdsBatch(
    List<String> scheduleIds,
  ) async {
    if (scheduleIds.isEmpty) return {};
    try {
      final relations = await _database.scheduleDestinationDao.getByScheduleIds(
        scheduleIds,
      );
      final map = <String, List<String>>{};
      for (final r in relations) {
        map[r.scheduleId] ??= [];
        map[r.scheduleId]!.add(r.destinationId);
      }
      return map;
    } on Object catch (e) {
      LoggerService.warning(
        '[ScheduleRepository] Failed batch loading destinations: $e',
      );
      return {};
    }
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

    return _loadDestinationIdsFallback(scheduleId, legacyDestinationIdsJson);
  }

  Future<List<String>> _loadDestinationIdsFallback(
    String scheduleId,
    String legacyDestinationIdsJson,
  ) async {
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

    final uniqueDestinationIds = destinationIds.toSet();

    for (final destinationId in uniqueDestinationIds) {
      final destinationExists = await _database.backupDestinationDao.getById(
        destinationId,
      );
      if (destinationExists == null) {
        LoggerService.warning(
          '[ScheduleRepository] Skipping non-existent destination: $destinationId',
        );
        continue;
      }

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
    final scheduleConfigMap = _safeDecodeScheduleConfig(
      schedule.scheduleConfig,
    );
    scheduleConfigMap[_verifyPolicyKey] = schedule.verifyPolicy.name;

    if (schedule.databaseType == DatabaseType.sqlServer &&
        schedule is SqlServerBackupSchedule) {
      scheduleConfigMap[_sqlServerBackupOptionsKey] = {
        'compression': schedule.sqlServerBackupOptions.compression,
        'maxTransferSize': schedule.sqlServerBackupOptions.maxTransferSize,
        'bufferCount': schedule.sqlServerBackupOptions.bufferCount,
        'blockSize': schedule.sqlServerBackupOptions.blockSize,
        'stripingCount': schedule.sqlServerBackupOptions.stripingCount,
        'statsPercent': schedule.sqlServerBackupOptions.statsPercent,
      };
    }

    return SchedulesTableCompanion(
      id: Value(schedule.id),
      name: Value(schedule.name),
      databaseConfigId: Value(schedule.databaseConfigId),
      databaseType: Value(schedule.databaseType.name),
      scheduleType: Value(schedule.scheduleType),
      scheduleConfig: Value(jsonEncode(scheduleConfigMap)),
      // Keep legacy JSON synced for backwards compatibility.
      destinationIds: Value(jsonEncode(schedule.destinationIds)),
      backupFolder: Value(schedule.backupFolder),
      backupType: Value(schedule.backupType.name),
      truncateLog: Value(schedule.truncateLog),
      compressBackup: Value(schedule.compressBackup),
      compressionFormat: Value(schedule.compressionFormat?.name ?? 'zip'),
      enabled: Value(schedule.enabled),
      enableChecksum: Value(schedule.enableChecksum),
      verifyAfterBackup: Value(schedule.verifyAfterBackup),
      postBackupScript: Value(schedule.postBackupScript),
      backupTimeoutSeconds: Value(schedule.backupTimeout.inSeconds),
      verifyTimeoutSeconds: Value(schedule.verifyTimeout.inSeconds),
      lastRunAt: Value(schedule.lastRunAt),
      nextRunAt: Value(schedule.nextRunAt),
      createdAt: Value(schedule.createdAt ?? DateTime.now()),
      updatedAt: Value(schedule.updatedAt ?? DateTime.now()),
    );
  }

  Map<String, dynamic> _safeDecodeScheduleConfig(String rawConfig) {
    try {
      final decoded = jsonDecode(rawConfig);
      if (decoded is Map<String, dynamic>) {
        return Map<String, dynamic>.from(decoded);
      }
      if (decoded is Map) {
        return decoded.map(
          (key, value) => MapEntry(key.toString(), value),
        );
      }
    } on Object catch (_) {}
    return {};
  }

  VerifyPolicy _parseVerifyPolicy(Map<String, dynamic> configMap) {
    final rawValue = configMap[_verifyPolicyKey];
    if (rawValue == null || rawValue is! String) {
      return VerifyPolicy.bestEffort;
    }

    return VerifyPolicy.values.firstWhere(
      (value) => value.name == rawValue,
      orElse: () => VerifyPolicy.bestEffort,
    );
  }

  SqlServerBackupOptions _parseSqlServerBackupOptions(
    Map<String, dynamic> configMap,
  ) {
    final optionsRaw = configMap[_sqlServerBackupOptionsKey];
    if (optionsRaw == null || optionsRaw is! Map) {
      return const SqlServerBackupOptions();
    }

    final options = optionsRaw.map(
      (key, value) => MapEntry(key.toString(), value),
    );

    final parsed = SqlServerBackupOptions(
      compression: options['compression'] as bool? ?? false,
      maxTransferSize: options['maxTransferSize'] as int?,
      bufferCount: options['bufferCount'] as int?,
      blockSize: options['blockSize'] as int?,
      stripingCount: options['stripingCount'] as int? ?? 1,
      statsPercent: options['statsPercent'] as int? ?? 10,
    );

    final validation = parsed.validate();
    if (validation.isValid) {
      return parsed;
    }

    LoggerService.warning(
      '[ScheduleRepository] SQL Server backup options invalid in schedule config. '
      'Using defaults. Details: ${validation.errorMessage}',
    );
    return const SqlServerBackupOptions();
  }
}
