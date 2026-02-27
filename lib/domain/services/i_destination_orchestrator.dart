import 'package:backup_database/domain/entities/backup_destination.dart';
import 'package:result_dart/result_dart.dart';

/// Service for orchestrating backup uploads to multiple destinations.
///
/// This service handles the complexity of uploading backup files
/// to various destination types (Local, FTP, Google Drive, Dropbox, Nextcloud),
/// including license verification, configuration parsing, and error handling.
abstract class IDestinationOrchestrator {
  /// Uploads a backup file to a single destination.
  ///
  /// Parameters:
  /// - [sourceFilePath]: Path to the backup file to upload
  /// - [destination]: Destination configuration
  /// - [isCancelled]: Optional callback to check if operation was cancelled
  ///
  /// Returns [Success] if upload succeeded, [Failure] otherwise.
  Future<Result<void>> uploadToDestination({
    required String sourceFilePath,
    required BackupDestination destination,
    bool Function()? isCancelled,
  });

  /// Uploads a backup file to multiple destinations.
  ///
  /// Parameters:
  /// - [sourceFilePath]: Path to the backup file to upload
  /// - [destinations]: List of destination configurations
  /// - [isCancelled]: Optional callback to check if operation was cancelled
  ///
  /// Returns a list of results for each destination upload attempt.
  Future<List<Result<void>>> uploadToAllDestinations({
    required String sourceFilePath,
    required List<BackupDestination> destinations,
    bool Function()? isCancelled,
  });
}
