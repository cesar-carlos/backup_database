import 'package:drift/drift.dart';

/// Respostas idempotentes cacheadas (F2.16 / PR-5).
class IdempotencyEntriesTable extends Table {
  TextColumn get idempotencyKey => text()();

  TextColumn get responseJson => text()();

  IntColumn get createdAtMicros => integer()();

  IntColumn get expiresAtMicros => integer()();

  @override
  Set<Column<Object>> get primaryKey => {idempotencyKey};
}
