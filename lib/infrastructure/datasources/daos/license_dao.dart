import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/tables/licenses_table.dart';
import 'package:drift/drift.dart';

part 'license_dao.g.dart';

@DriftAccessor(tables: [LicensesTable])
class LicenseDao extends DatabaseAccessor<AppDatabase> with _$LicenseDaoMixin {
  LicenseDao(super.db);

  Future<List<LicensesTableData>> getAll() => select(licensesTable).get();

  Future<LicensesTableData?> getById(String id) => (select(
    licensesTable,
  )..where((tbl) => tbl.id.equals(id))).getSingleOrNull();

  Future<LicensesTableData?> getByDeviceKey(String deviceKey) => (select(
    licensesTable,
  )..where((tbl) => tbl.deviceKey.equals(deviceKey))).getSingleOrNull();

  Future<int> insertLicense(LicensesTableCompanion license) =>
      into(licensesTable).insert(license);

  Future<bool> updateLicense(LicensesTableCompanion license) async {
    if (!license.id.present) {
      return false;
    }

    final updated = await (update(
      licensesTable,
    )..where((tbl) => tbl.id.equals(license.id.value))).write(license);
    return updated > 0;
  }

  Future<int> deleteLicense(String id) =>
      (delete(licensesTable)..where((tbl) => tbl.id.equals(id))).go();
}
