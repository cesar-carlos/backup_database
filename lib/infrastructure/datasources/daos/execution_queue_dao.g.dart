// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'execution_queue_dao.dart';

// ignore_for_file: type=lint
mixin _$ExecutionQueueDaoMixin on DatabaseAccessor<AppDatabase> {
  $ExecutionQueueItemsTableTable get executionQueueItemsTable =>
      attachedDatabase.executionQueueItemsTable;
  ExecutionQueueDaoManager get managers => ExecutionQueueDaoManager(this);
}

class ExecutionQueueDaoManager {
  final _$ExecutionQueueDaoMixin _db;
  ExecutionQueueDaoManager(this._db);
  $$ExecutionQueueItemsTableTableTableManager get executionQueueItemsTable =>
      $$ExecutionQueueItemsTableTableTableManager(
        _db.attachedDatabase,
        _db.executionQueueItemsTable,
      );
}
