import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';

class BackupExecutionResult {
  const BackupExecutionResult({
    required this.backupPath,
    required this.fileSize,
    required this.duration,
    required this.databaseName,
    this.metrics,
    this.executedBackupType,
  });
  final String backupPath;
  final int fileSize;
  final Duration duration;
  final String databaseName;
  final BackupMetrics? metrics;

  /// Quando definido, indica que o tipo de backup realmente executado pela
  /// camada de infraestrutura difere do tipo solicitado pelo schedule.
  ///
  /// Ex.: backup incremental do PostgreSQL que cai para FULL por falta de
  /// backup base anterior. O orchestrator deve usar este valor para gravar
  /// `BackupHistory.backupType` corretamente.
  final BackupType? executedBackupType;
}
