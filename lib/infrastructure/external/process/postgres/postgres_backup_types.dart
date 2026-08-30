import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;

class PostgresBackupCommandResult {
  const PostgresBackupCommandResult({
    required this.processResult,
    required this.backupPath,
    this.measuredSizeBytes,
    this.executedBackupType,
    this.compressionApplied,
  });

  final ps.ProcessResult processResult;
  final String backupPath;
  final int? measuredSizeBytes;

  /// Quando preenchido, indica que o tipo realmente executado é diferente
  /// do tipo solicitado (ex.: incremental que caiu para FULL por falta de
  /// backup base). O orchestrator usa esse campo para evitar gravar um
  /// histórico inconsistente.
  final BackupType? executedBackupType;

  /// Modo de compressão efetivamente aplicado pelo `pg_receivewal` (ex.:
  /// `gzip`, `lz4`). `null` quando nenhum modo foi requisitado ou quando
  /// houve fallback automático para execução sem compressão. Usado por
  /// `_buildPostgresMetrics` para reportar `BackupFlags.compression`
  /// coerente com o T-SQL/CLI realmente executado.
  final String? compressionApplied;
}
