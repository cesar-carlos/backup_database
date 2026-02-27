enum SybaseCheckpointLog {
  copy,
  nocopy,
  auto,
  recover,
}

enum SybaseLogBackupMode {
  truncate,
  only,
  rename,
}

class SybaseBackupOptions {
  static const SybaseBackupOptions safeDefaults = SybaseBackupOptions();

  static const int blockSizeMin = 1;
  static const int blockSizeMax = 4096;

  const SybaseBackupOptions({
    this.checkpointLog,
    this.serverSide = false,
    this.autoTuneWriters = false,
    this.blockSize,
    this.logBackupMode,
  });

  final SybaseCheckpointLog? checkpointLog;
  final bool serverSide;
  final bool autoTuneWriters;
  final int? blockSize;
  final SybaseLogBackupMode? logBackupMode;

  ({bool isValid, String? errorMessage}) validate() {
    final errors = <String>[];

    if (checkpointLog == SybaseCheckpointLog.auto && !serverSide) {
      errors.add(
        'CHECKPOINT LOG AUTO requer modo Server-Side (dbbackup -s)',
      );
    }

    if (blockSize != null) {
      if (blockSize! < blockSizeMin) {
        errors.add('Block Size deve ser maior que $blockSizeMin');
      }
      if (blockSize! > blockSizeMax) {
        errors.add('Block Size não deve exceder $blockSizeMax páginas');
      }
    }

    if (errors.isEmpty) {
      return (isValid: true, errorMessage: null);
    }

    return (isValid: false, errorMessage: errors.join('; '));
  }

  Map<String, dynamic> toJson() => {
        if (checkpointLog != null) 'checkpointLog': checkpointLog!.name,
        'serverSide': serverSide,
        'autoTuneWriters': autoTuneWriters,
        if (blockSize != null) 'blockSize': blockSize,
        if (logBackupMode != null) 'logBackupMode': logBackupMode!.name,
      };

  static SybaseBackupOptions? fromJson(Map<String, dynamic>? map) {
    if (map == null || map.isEmpty) return null;
    final checkpointLog = checkpointLogFromString(
      map['checkpointLog'] as String?,
    );
    final logBackupMode = logBackupModeFromString(
      map['logBackupMode'] as String?,
    );
    return SybaseBackupOptions(
      checkpointLog: checkpointLog,
      serverSide: map['serverSide'] as bool? ?? false,
      autoTuneWriters: map['autoTuneWriters'] as bool? ?? false,
      blockSize: map['blockSize'] as int?,
      logBackupMode: logBackupMode,
    );
  }

  static SybaseLogBackupMode? logBackupModeFromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    for (final e in SybaseLogBackupMode.values) {
      if (e.name == lower) return e;
    }
    return null;
  }

  String buildCheckpointLogClause() {
    if (checkpointLog == null) return '';
    return ' WITH CHECKPOINT LOG ${checkpointLog!.name.toUpperCase()}';
  }

  String buildAutoTuneWritersClause() {
    return ' AUTO TUNE WRITERS ${autoTuneWriters ? 'ON' : 'OFF'}';
  }

  static SybaseCheckpointLog? checkpointLogFromString(String? value) {
    if (value == null || value.isEmpty) return null;
    final lower = value.toLowerCase();
    for (final e in SybaseCheckpointLog.values) {
      if (e.name == lower) return e;
    }
    return null;
  }

  @override
  bool operator ==(Object other) =>
      other is SybaseBackupOptions &&
      other.checkpointLog == checkpointLog &&
      other.serverSide == serverSide &&
      other.autoTuneWriters == autoTuneWriters &&
      other.blockSize == blockSize &&
      other.logBackupMode == logBackupMode;

  @override
  int get hashCode =>
      checkpointLog.hashCode ^
      serverSide.hashCode ^
      autoTuneWriters.hashCode ^
      blockSize.hashCode ^
      logBackupMode.hashCode;
}
