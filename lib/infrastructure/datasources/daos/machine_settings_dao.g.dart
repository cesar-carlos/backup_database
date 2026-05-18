// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'machine_settings_dao.dart';

// ignore_for_file: type=lint
mixin _$MachineSettingsDaoMixin on DatabaseAccessor<AppDatabase> {
  $MachineSettingsTableTable get machineSettingsTable =>
      attachedDatabase.machineSettingsTable;
  MachineSettingsDaoManager get managers => MachineSettingsDaoManager(this);
}

class MachineSettingsDaoManager {
  final _$MachineSettingsDaoMixin _db;
  MachineSettingsDaoManager(this._db);
  $$MachineSettingsTableTableTableManager get machineSettingsTable =>
      $$MachineSettingsTableTableTableManager(
        _db.attachedDatabase,
        _db.machineSettingsTable,
      );
}
