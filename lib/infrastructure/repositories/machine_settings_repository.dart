import 'package:backup_database/core/constants/app_constants.dart';
import 'package:backup_database/domain/repositories/i_machine_settings_repository.dart';
import 'package:backup_database/infrastructure/datasources/daos/machine_settings_dao.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:drift/drift.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MachineSettingsRepository implements IMachineSettingsRepository {
  MachineSettingsRepository(this._db);

  final AppDatabase _db;

  MachineSettingsDao get _dao => _db.machineSettingsDao;

  Future<void>? _seedFuture;

  Future<void> _ensureSeeded() async {
    final future = _seedFuture ??= _seedFromLegacyPrefsIfNeeded();
    try {
      await future;
    } on Object {
      if (identical(_seedFuture, future)) {
        _seedFuture = null;
      }
      rethrow;
    }
  }

  Future<void> _seedFromLegacyPrefsIfNeeded() async {
    final existing = await _dao.getSingleton();
    if (existing != null) {
      return;
    }

    final prefs = await SharedPreferences.getInstance();
    final startWithWindows = prefs.getBool('start_with_windows') ?? false;
    final startMinimized = prefs.getBool('start_minimized') ?? false;
    final customTemp = prefs.getString('custom_temp_downloads_path');
    final receivedPath = prefs.getString(
      AppConstants.receivedBackupsDefaultPathKey,
    );
    final scheduleJson = prefs.getString(
      AppConstants.scheduleTransferDestinationsKey,
    );

    await _dao.insertSingleton(
      MachineSettingsTableCompanion.insert(
        id: const Value(machineSettingsSingletonId),
        startWithWindows: Value(startWithWindows),
        startMinimized: Value(startMinimized),
        customTempDownloadsPath: Value(customTemp),
        receivedBackupsDefaultPath: Value(receivedPath),
        scheduleTransferDestinationsJson: Value(scheduleJson),
      ),
    );

    await prefs.remove('start_with_windows');
    await prefs.remove('start_minimized');
    await prefs.remove('custom_temp_downloads_path');
    await prefs.remove(AppConstants.receivedBackupsDefaultPathKey);
    await prefs.remove(AppConstants.scheduleTransferDestinationsKey);
  }

  Future<MachineSettingsTableData> _row() async {
    await _ensureSeeded();
    final row = await _dao.getSingleton();
    if (row == null) {
      await _dao.insertSingleton(
        MachineSettingsTableCompanion.insert(
          id: const Value(machineSettingsSingletonId),
        ),
      );
      return (await _dao.getSingleton())!;
    }
    return row;
  }

  @override
  Future<bool> getStartWithWindows() async => (await _row()).startWithWindows;

  @override
  Future<void> setStartWithWindows(bool value) async {
    await _ensureSeeded();
    await _dao.updateSingleton(
      MachineSettingsTableCompanion(startWithWindows: Value(value)),
    );
  }

  @override
  Future<bool> getStartMinimized() async => (await _row()).startMinimized;

  @override
  Future<void> setStartMinimized(bool value) async {
    await _ensureSeeded();
    await _dao.updateSingleton(
      MachineSettingsTableCompanion(startMinimized: Value(value)),
    );
  }

  @override
  Future<String?> getCustomTempDownloadsPath() async =>
      (await _row()).customTempDownloadsPath;

  @override
  Future<void> setCustomTempDownloadsPath(String? path) async {
    await _ensureSeeded();
    await _dao.updateSingleton(
      MachineSettingsTableCompanion(
        customTempDownloadsPath: Value(path),
      ),
    );
  }

  @override
  Future<String?> getReceivedBackupsDefaultPath() async =>
      (await _row()).receivedBackupsDefaultPath;

  @override
  Future<void> setReceivedBackupsDefaultPath(String? path) async {
    await _ensureSeeded();
    await _dao.updateSingleton(
      MachineSettingsTableCompanion(
        receivedBackupsDefaultPath: Value(path),
      ),
    );
  }

  @override
  Future<String?> getScheduleTransferDestinationsJson() async =>
      (await _row()).scheduleTransferDestinationsJson;

  @override
  Future<void> setScheduleTransferDestinationsJson(String? json) async {
    await _ensureSeeded();
    await _dao.updateSingleton(
      MachineSettingsTableCompanion(
        scheduleTransferDestinationsJson: Value(json),
      ),
    );
  }
}
