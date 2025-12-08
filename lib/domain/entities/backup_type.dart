enum BackupType {
  full,
  differential,
  log;

  String get displayName {
    switch (this) {
      case BackupType.full:
        return 'Full';
      case BackupType.differential:
        return 'Diferencial';
      case BackupType.log:
        return 'Log de Transações';
    }
  }

  String get name {
    switch (this) {
      case BackupType.full:
        return 'full';
      case BackupType.differential:
        return 'differential';
      case BackupType.log:
        return 'log';
    }
  }

  static BackupType fromString(String value) {
    switch (value.toLowerCase()) {
      case 'full':
        return BackupType.full;
      case 'differential':
        return BackupType.differential;
      case 'log':
        return BackupType.log;
      default:
        return BackupType.full;
    }
  }
}

