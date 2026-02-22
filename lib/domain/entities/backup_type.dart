enum BackupType {
  full,
  fullSingle,
  log,
  differential,
  convertedDifferential,
  convertedFullSingle,
  convertedLog,
}

extension BackupTypeExtension on BackupType {
  String get displayName {
    switch (this) {
      case BackupType.full:
        return 'Full';
      case BackupType.fullSingle:
        return 'Full Single';
      case BackupType.differential:
        return 'Diferencial';
      case BackupType.log:
        return 'Log de Transações';
      case BackupType.convertedDifferential:
        return 'Diferencial (convertido)';
      case BackupType.convertedFullSingle:
        return 'Full Single (convertido)';
      case BackupType.convertedLog:
        return 'Log de Transações (convertido)';
    }
  }

  String get name {
    switch (this) {
      case BackupType.full:
        return 'full';
      case BackupType.fullSingle:
        return 'fullSingle';
      case BackupType.differential:
        return 'differential';
      case BackupType.log:
        return 'log';
      case BackupType.convertedDifferential:
        return 'differential';
      case BackupType.convertedFullSingle:
        return 'fullSingle';
      case BackupType.convertedLog:
        return 'log';
    }
  }

  bool get isConvertedFromDifferential {
    return this == BackupType.convertedDifferential ||
        this == BackupType.convertedFullSingle ||
        this == BackupType.convertedLog;
  }
}

BackupType backupTypeFromString(String value) {
  switch (value.toLowerCase()) {
    case 'full':
      return BackupType.full;
    case 'fullsingle':
      return BackupType.fullSingle;
    case 'differential':
      return BackupType.differential;
    case 'log':
      return BackupType.log;
    case 'diferencial (convertido)':
      return BackupType.convertedDifferential;
    case 'fullsingle (convertido)':
      return BackupType.convertedFullSingle;
    case 'log (convertido)':
      return BackupType.convertedLog;
    default:
      return BackupType.full;
  }
}

String getBackupTypeDisplayName(BackupType type) {
  switch (type) {
    case BackupType.full:
      return 'Full';
    case BackupType.fullSingle:
      return 'Full Single';
    case BackupType.differential:
      return 'Diferencial';
    case BackupType.log:
      return 'Log de Transações';
    case BackupType.convertedDifferential:
      return 'Diferencial (convertido)';
    case BackupType.convertedFullSingle:
      return 'Full Single (convertido)';
    case BackupType.convertedLog:
      return 'Log de Transações (convertido)';
  }
}

String getBackupTypeName(BackupType type) {
  switch (type) {
    case BackupType.full:
      return 'full';
    case BackupType.fullSingle:
      return 'fullSingle';
    case BackupType.differential:
      return 'differential';
    case BackupType.log:
      return 'log';
    case BackupType.convertedDifferential:
      return 'differential';
    case BackupType.convertedFullSingle:
      return 'fullSingle';
    case BackupType.convertedLog:
      return 'log';
  }
}
