// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'license_dao.dart';

// ignore_for_file: type=lint
mixin _$LicenseDaoMixin on DatabaseAccessor<AppDatabase> {
  $LicensesTableTable get licensesTable => attachedDatabase.licensesTable;
  LicenseDaoManager get managers => LicenseDaoManager(this);
}

class LicenseDaoManager {
  final _$LicenseDaoMixin _db;
  LicenseDaoManager(this._db);
  $$LicensesTableTableTableManager get licensesTable =>
      $$LicensesTableTableTableManager(_db.attachedDatabase, _db.licensesTable);
}
