class MachineStorageLayout {
  static const String data = 'data';
  static const String logs = 'logs';
  static const String locks = 'locks';
  static const String secrets = 'secrets';
  static const String staging = 'staging';
  static const String stagingBackups = 'backups';
  static const String config = 'config';

  static const String legacyAppdataMigrationMarker =
      'legacy_appdata_migration.done';

  static const String legacyAppdataLogsMigrationMarker =
      'legacy_appdata_logs_migration.done';

  static const String legacyImportedLogsSubdirectory = 'legacy_appdata';

  static const String migrationStateFile = 'migration_state.json';

  static const String resetV223Marker = 'reset_v2_2_3.done';
  static const String resetV224Marker = 'reset_v2_2_4.done';
}
