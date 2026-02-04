import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:result_dart/result_dart.dart';

/// Service for orchestrating backup compression operations.
///
/// This service handles the compression of backup files, including
/// progress updates and error handling. It abstracts the complexity
/// of compression from the main backup orchestrator.
abstract class IBackupCompressionOrchestrator {
  /// Compresses a backup file with the specified format.
  ///
  /// Parameters:
  /// - [backupPath]: Path to the original backup file
  /// - [format]: Compression format to use
  /// - [databaseType]: Type of database (for naming conventions)
  /// - [backupType]: Type of backup (for naming conventions)
  /// - [progressNotifier]: Optional progress notifier for updates
  ///
  /// Returns [Success] with [CompressionResult] containing the compressed
  /// file path and size, or [Failure] if compression fails.
  Future<Result<CompressionResult>> compressBackup({
    required String backupPath,
    required CompressionFormat format,
    required DatabaseType databaseType,
    required BackupType backupType,
    IBackupProgressNotifier? progressNotifier,
  });
}
