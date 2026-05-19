import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/idempotency_entries_table.dart';
import 'package:drift/drift.dart';

part 'idempotency_dao.g.dart';

@DriftAccessor(tables: [IdempotencyEntriesTable])
class IdempotencyDao extends DatabaseAccessor<AppDatabase>
    with _$IdempotencyDaoMixin {
  IdempotencyDao(super.db);

  Future<IdempotencyEntriesTableData?> getByKey(String key) {
    return (select(
      idempotencyEntriesTable,
    )..where((t) => t.idempotencyKey.equals(key))).getSingleOrNull();
  }

  Future<void> upsert({
    required String key,
    required String responseJson,
    required int createdAtMicros,
    required int expiresAtMicros,
  }) {
    return into(idempotencyEntriesTable).insertOnConflictUpdate(
      IdempotencyEntriesTableCompanion.insert(
        idempotencyKey: key,
        responseJson: responseJson,
        createdAtMicros: createdAtMicros,
        expiresAtMicros: expiresAtMicros,
      ),
    );
  }

  Future<int> deleteByKey(String key) {
    return (delete(
      idempotencyEntriesTable,
    )..where((t) => t.idempotencyKey.equals(key))).go();
  }

  Future<int> deleteExpiredBefore(int expiresBeforeMicros) {
    return (delete(idempotencyEntriesTable)..where(
          (t) => t.expiresAtMicros.isSmallerThanValue(expiresBeforeMicros),
        ))
        .go();
  }
}
