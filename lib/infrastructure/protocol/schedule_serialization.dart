import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';

Map<String, dynamic> scheduleToMap(Schedule schedule) {
  return <String, dynamic>{
    'id': schedule.id,
    'name': schedule.name,
    'databaseConfigId': schedule.databaseConfigId,
    'databaseType': schedule.databaseType.name,
    'scheduleType': schedule.scheduleType.name,
    'scheduleConfig': schedule.scheduleConfig,
    'destinationIds': schedule.destinationIds,
    'backupFolder': schedule.backupFolder,
    'backupType': schedule.backupType.name,
    'truncateLog': schedule.truncateLog,
    'compressBackup': schedule.compressBackup,
    'compressionFormat': schedule.compressionFormat.name,
    'enabled': schedule.enabled,
    'enableChecksum': schedule.enableChecksum,
    'verifyAfterBackup': schedule.verifyAfterBackup,
    if (schedule.postBackupScript != null) 'postBackupScript': schedule.postBackupScript,
    if (schedule.lastRunAt != null) 'lastRunAt': schedule.lastRunAt!.toIso8601String(),
    if (schedule.nextRunAt != null) 'nextRunAt': schedule.nextRunAt!.toIso8601String(),
    'createdAt': schedule.createdAt.toIso8601String(),
    'updatedAt': schedule.updatedAt.toIso8601String(),
  };
}

Schedule scheduleFromMap(Map<String, dynamic> map) {
  return Schedule(
    id: map['id'] as String?,
    name: map['name'] as String,
    databaseConfigId: map['databaseConfigId'] as String,
    databaseType: DatabaseType.values.byName(map['databaseType'] as String),
    scheduleType: ScheduleType.values.byName(map['scheduleType'] as String),
    scheduleConfig: map['scheduleConfig'] as String,
    destinationIds: (map['destinationIds'] as List<dynamic>).cast<String>(),
    backupFolder: map['backupFolder'] as String,
    backupType: BackupType.values.byName(map['backupType'] as String),
    truncateLog: map['truncateLog'] as bool? ?? true,
    compressBackup: map['compressBackup'] as bool? ?? true,
    compressionFormat: map['compressionFormat'] != null
        ? CompressionFormat.values.byName(map['compressionFormat'] as String)
        : null,
    enabled: map['enabled'] as bool? ?? true,
    enableChecksum: map['enableChecksum'] as bool? ?? false,
    verifyAfterBackup: map['verifyAfterBackup'] as bool? ?? false,
    postBackupScript: map['postBackupScript'] as String?,
    lastRunAt: map['lastRunAt'] != null
        ? DateTime.parse(map['lastRunAt'] as String)
        : null,
    nextRunAt: map['nextRunAt'] != null
        ? DateTime.parse(map['nextRunAt'] as String)
        : null,
    createdAt: map['createdAt'] != null
        ? DateTime.parse(map['createdAt'] as String)
        : null,
    updatedAt: map['updatedAt'] != null
        ? DateTime.parse(map['updatedAt'] as String)
        : null,
  );
}
