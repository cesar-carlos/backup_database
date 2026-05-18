// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'email_notification_target_dao.dart';

// ignore_for_file: type=lint
mixin _$EmailNotificationTargetDaoMixin on DatabaseAccessor<AppDatabase> {
  $EmailConfigsTableTable get emailConfigsTable =>
      attachedDatabase.emailConfigsTable;
  $EmailNotificationTargetsTableTable get emailNotificationTargetsTable =>
      attachedDatabase.emailNotificationTargetsTable;
  EmailNotificationTargetDaoManager get managers =>
      EmailNotificationTargetDaoManager(this);
}

class EmailNotificationTargetDaoManager {
  final _$EmailNotificationTargetDaoMixin _db;
  EmailNotificationTargetDaoManager(this._db);
  $$EmailConfigsTableTableTableManager get emailConfigsTable =>
      $$EmailConfigsTableTableTableManager(
        _db.attachedDatabase,
        _db.emailConfigsTable,
      );
  $$EmailNotificationTargetsTableTableTableManager
  get emailNotificationTargetsTable =>
      $$EmailNotificationTargetsTableTableTableManager(
        _db.attachedDatabase,
        _db.emailNotificationTargetsTable,
      );
}
