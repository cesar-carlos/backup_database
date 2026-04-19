import 'package:backup_database/core/core.dart';
import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/repositories/i_backup_destination_repository.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/repositories/repository_guard.dart';
import 'package:drift/drift.dart';
import 'package:result_dart/result_dart.dart' as rd;

class BackupDestinationRepository implements IBackupDestinationRepository {
  BackupDestinationRepository(this._database);
  final AppDatabase _database;

  @override
  Future<rd.Result<List<BackupDestination>>> getAll() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinos',
      action: () async {
        final destinations = await _database.backupDestinationDao.getAll();
        return destinations.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<BackupDestination>> getById(String id) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destino',
      action: () async {
        final destination = await _database.backupDestinationDao.getById(id);
        if (destination == null) {
          throw const NotFoundFailure(message: 'Destino não encontrado');
        }
        return _toEntity(destination);
      },
    );
  }

  @override
  Future<rd.Result<BackupDestination>> create(BackupDestination destination) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao criar destino',
      action: () async {
        final companion = _toCompanion(destination);
        await _database.backupDestinationDao.insertDestination(companion);
        return destination;
      },
    );
  }

  @override
  Future<rd.Result<BackupDestination>> update(BackupDestination destination) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao atualizar destino',
      action: () async {
        final companion = _toCompanion(destination);
        await _database.backupDestinationDao.updateDestination(companion);
        return destination;
      },
    );
  }

  @override
  Future<rd.Result<void>> delete(String id) {
    return RepositoryGuard.runVoid(
      errorMessage: 'Erro ao deletar destino',
      action: () => _database.backupDestinationDao.deleteDestination(id),
    );
  }

  @override
  Future<rd.Result<List<BackupDestination>>> getByType(DestinationType type) {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinos por tipo',
      action: () async {
        final destinations =
            await _database.backupDestinationDao.getByType(type.name);
        return destinations.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupDestination>>> getByIds(List<String> ids) {
    if (ids.isEmpty) {
      return Future.value(const rd.Success([]));
    }
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinos',
      action: () async {
        final destinations = await _database.backupDestinationDao.getByIds(ids);
        return destinations.map(_toEntity).toList();
      },
    );
  }

  @override
  Future<rd.Result<List<BackupDestination>>> getEnabled() {
    return RepositoryGuard.run(
      errorMessage: 'Erro ao buscar destinos ativos',
      action: () async {
        final destinations = await _database.backupDestinationDao.getEnabled();
        return destinations.map(_toEntity).toList();
      },
    );
  }

  BackupDestination _toEntity(BackupDestinationsTableData data) {
    DestinationType parsedType;
    try {
      parsedType = DestinationType.values.firstWhere(
        (e) => e.name == data.type,
      );
    } on Object catch (e, stackTrace) {
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
