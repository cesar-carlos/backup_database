import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/backup_type.dart';

abstract final class PostgresBackupToolErrors {
  static bool isExecutableNotFoundError(
    String errorLower,
    BackupType backupType,
  ) {
    return isToolNotFoundError(errorLower, toolNameForBackupType(backupType));
  }

  static String toolNameForBackupType(BackupType backupType) {
    return backupType == BackupType.fullSingle
        ? 'pg_dump'
        : backupType == BackupType.log
        ? 'pg_receivewal'
        : 'pg_basebackup';
  }

  static bool isToolNotFoundError(String errorLower, String toolName) =>
      ToolPathHelp.isToolNotFoundError(errorLower, toolName);

  static BackupFailure createExecutableNotFoundFailure(
    BackupType backupType,
  ) {
    return createToolNotFoundFailure(toolNameForBackupType(backupType));
  }

  static BackupFailure createToolNotFoundFailure(String toolName) {
    return BackupFailure(
      message: ToolPathHelp.buildMessage(toolName),
      originalError: Exception('$toolName não encontrado'),
    );
  }
}
