// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'idempotency_dao.dart';

// ignore_for_file: type=lint
mixin _$IdempotencyDaoMixin on DatabaseAccessor<AppDatabase> {
  $IdempotencyEntriesTableTable get idempotencyEntriesTable =>
      attachedDatabase.idempotencyEntriesTable;
  IdempotencyDaoManager get managers => IdempotencyDaoManager(this);
}

class IdempotencyDaoManager {
  final _$IdempotencyDaoMixin _db;
  IdempotencyDaoManager(this._db);
  $$IdempotencyEntriesTableTableTableManager get idempotencyEntriesTable =>
      $$IdempotencyEntriesTableTableTableManager(
        _db.attachedDatabase,
        _db.idempotencyEntriesTable,
      );
}
