import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/machine_settings_table.dart';
import 'package:drift/drift.dart';

part 'machine_settings_dao.g.dart';

const int machineSettingsSingletonId = 1;

@DriftAccessor(tables: [MachineSettingsTable])
class MachineSettingsDao extends DatabaseAccessor<AppDatabase>
    with _$MachineSettingsDaoMixin {
  MachineSettingsDao(super.db);

  Future<MachineSettingsTableData?> getSingleton() => (select(
    machineSettingsTable,
  )..where((t) => t.id.equals(machineSettingsSingletonId))).getSingleOrNull();

  Future<int> insertSingleton(MachineSettingsTableCompanion row) =>
      into(machineSettingsTable).insert(row);

  Future<int> updateSingleton(MachineSettingsTableCompanion row) => (update(
    machineSettingsTable,
  )..where((t) => t.id.equals(machineSettingsSingletonId))).write(row);
}
