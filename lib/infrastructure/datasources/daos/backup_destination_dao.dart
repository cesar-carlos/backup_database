import 'package:drift/drift.dart';

import '../local/database.dart';
import '../local/tables/backup_destinations_table.dart';

part 'backup_destination_dao.g.dart';

@DriftAccessor(tables: [BackupDestinationsTable])
class BackupDestinationDao extends DatabaseAccessor<AppDatabase>
    with _$BackupDestinationDaoMixin {
  BackupDestinationDao(super.db);

  Future<List<BackupDestinationsTableData>> getAll() =>
      select(backupDestinationsTable).get();

  Future<BackupDestinationsTableData?> getById(String id) =>
      (select(backupDestinationsTable)..where((t) => t.id.equals(id)))
          .getSingleOrNull();

  Future<int> insertDestination(BackupDestinationsTableCompanion destination) =>
      into(backupDestinationsTable).insert(destination);

  Future<bool> updateDestination(
          BackupDestinationsTableCompanion destination) =>
      update(backupDestinationsTable).replace(destination);

  Future<int> deleteDestination(String id) =>
      (delete(backupDestinationsTable)..where((t) => t.id.equals(id))).go();

  Future<List<BackupDestinationsTableData>> getByType(String type) =>
      (select(backupDestinationsTable)..where((t) => t.type.equals(type)))
          .get();

  Future<List<BackupDestinationsTableData>> getEnabled() =>
      (select(backupDestinationsTable)..where((t) => t.enabled.equals(true)))
          .get();

  Stream<List<BackupDestinationsTableData>> watchAll() =>
      select(backupDestinationsTable).watch();
}

