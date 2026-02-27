import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/backup_destinations_table.dart';
import 'package:drift/drift.dart';

part 'backup_destination_dao.g.dart';

@DriftAccessor(tables: [BackupDestinationsTable])
class BackupDestinationDao extends DatabaseAccessor<AppDatabase> with _$BackupDestinationDaoMixin {
  BackupDestinationDao(super.db);

  Future<List<BackupDestinationsTableData>> getAll() => select(backupDestinationsTable).get();

  Future<BackupDestinationsTableData?> getById(String id) => (select(
    backupDestinationsTable,
  )..where((t) => t.id.equals(id))).getSingleOrNull();

  Future<List<BackupDestinationsTableData>> getByIds(List<String> ids) {
    if (ids.isEmpty) return Future.value([]);
    return (select(backupDestinationsTable)..where((t) => t.id.isIn(ids))).get();
  }

  Future<int> insertDestination(BackupDestinationsTableCompanion destination) =>
      into(backupDestinationsTable).insert(destination);

  Future<bool> updateDestination(
    BackupDestinationsTableCompanion destination,
  ) => update(backupDestinationsTable).replace(destination);

  Future<int> deleteDestination(String id) => (delete(backupDestinationsTable)..where((t) => t.id.equals(id))).go();

  Future<List<BackupDestinationsTableData>> getByType(String type) => (select(
    backupDestinationsTable,
  )..where((t) => t.type.equals(type))).get();

  Future<List<BackupDestinationsTableData>> getEnabled() => (select(
    backupDestinationsTable,
  )..where((t) => t.enabled.equals(true))).get();

  Stream<List<BackupDestinationsTableData>> watchAll() => select(backupDestinationsTable).watch();
}
