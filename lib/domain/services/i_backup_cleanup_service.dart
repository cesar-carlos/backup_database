import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:result_dart/result_dart.dart';

/// Service for cleaning up old backups from multiple destinations.
///
/// This service handles the complexity of cleaning old backup files
/// from various destination types (Local, FTP, Google Drive, Dropbox, Nextcloud),
/// including license verification, configuration parsing, and error handling.
abstract class IBackupCleanupService {
  /// Cleans up old backups from all destinations.
  ///
  /// Parameters:
  /// - [destinations]: List of destination configurations
  /// - [backupHistoryId]: ID of the backup history entry for logging purposes
  /// - [schedule]: When present and Sybase, applies chain-aware retention
  ///   (protects full+log chains from deletion)
  ///
  /// Returns [Success] if cleanup completed (with partial failures logged),
  /// [Failure] only for critical errors.
  Future<Result<void>> cleanOldBackups({
    required List<BackupDestination> destinations,
    required String backupHistoryId,
    Schedule? schedule,
  });
}
