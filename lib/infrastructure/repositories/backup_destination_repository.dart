import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

import '../../core/core.dart';
import '../../domain/entities/backup_destination.dart';
import '../../domain/repositories/i_backup_destination_repository.dart';
import '../datasources/local/database.dart';

class BackupDestinationRepository implements IBackupDestinationRepository {
  final AppDatabase _database;

  BackupDestinationRepository(this._database);

  @override
  Future<rd.Result<List<BackupDestination>>> getAll() async {
    try {
      final destinations = await _database.backupDestinationDao.getAll();
      final entities = destinations.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar destinos: $e'),
      );
    }
  }

  @override
  Future<rd.Result<BackupDestination>> getById(String id) async {
    try {
      final destination = await _database.backupDestinationDao.getById(id);
      if (destination == null) {
        return rd.Failure(NotFoundFailure(message: 'Destino não encontrado'));
      }
      return rd.Success(_toEntity(destination));
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao buscar destino: $e'));
    }
  }

  @override
  Future<rd.Result<BackupDestination>> create(
    BackupDestination destination,
  ) async {
    try {
      final companion = _toCompanion(destination);
      await _database.backupDestinationDao.insertDestination(companion);
      return rd.Success(destination);
    } catch (e) {
      return rd.Failure(DatabaseFailure(message: 'Erro ao criar destino: $e'));
    }
  }

  @override
  Future<rd.Result<BackupDestination>> update(
    BackupDestination destination,
  ) async {
    try {
      final companion = _toCompanion(destination);
      await _database.backupDestinationDao.updateDestination(companion);
      return rd.Success(destination);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao atualizar destino: $e'),
      );
    }
  }

  @override
  Future<rd.Result<void>> delete(String id) async {
    try {
      await _database.backupDestinationDao.deleteDestination(id);
      return const rd.Success(unit);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao deletar destino: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupDestination>>> getByType(
    DestinationType type,
  ) async {
    try {
      final typeStr = type.name;
      final destinations = await _database.backupDestinationDao.getByType(
        typeStr,
      );
      final entities = destinations.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar destinos por tipo: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<BackupDestination>>> getEnabled() async {
    try {
      final destinations = await _database.backupDestinationDao.getEnabled();
      final entities = destinations.map((data) => _toEntity(data)).toList();
      return rd.Success(entities);
    } catch (e) {
      return rd.Failure(
        DatabaseFailure(message: 'Erro ao buscar destinos ativos: $e'),
      );
    }
  }

  BackupDestination _toEntity(BackupDestinationsTableData data) {
    DestinationType parsedType;
    try {
      parsedType = DestinationType.values.firstWhere(
        (e) => e.name == data.type,
      );
    } catch (e, stackTrace) {
      LoggerService.warning(
        'Tipo de destino desconhecido no banco: ${data.type} '
        '(id: ${data.id}, name: ${data.name}). '
        'Fazendo fallback para local.',
        e,
        stackTrace,
      );
      parsedType = DestinationType.local;
    }

    return BackupDestination(
      id: data.id,
      name: data.name,
      type: parsedType,
      config: data.config,
      enabled: data.enabled,
      createdAt: data.createdAt,
      updatedAt: data.updatedAt,
    );
  }

  BackupDestinationsTableCompanion _toCompanion(BackupDestination destination) {
    return BackupDestinationsTableCompanion(
      id: Value(destination.id),
      name: Value(destination.name),
      type: Value(destination.type.name),
      config: Value(destination.config),
      enabled: Value(destination.enabled),
      createdAt: Value(destination.createdAt),
      updatedAt: Value(destination.updatedAt),
    );
  }
}
