import 'dart:io';

import 'package:backup_database/core/errors/failure.dart' as core_errors;
import 'package:backup_database/core/utils/directory_permission_check.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:result_dart/result_dart.dart';

/// Use case for validating a backup directory.
///
/// Ensures that the directory path is valid and writable. Creates the
/// directory if it doesn't exist, and verifies write permissions.
class ValidateBackupDirectory {
  const ValidateBackupDirectory();

  /// Validates that [path] is a valid, writable directory.
  ///
  /// Returns [Success] if the directory is valid and writable.
  /// Returns [Failure] if:
  /// - The path is empty
  /// - The directory cannot be created
  /// - Write permissions are not available
  Future<Result<void>> call(String path) async {
    if (path.isEmpty) {
      return const Failure(
        core_errors.ValidationFailure(
          message: 'Directory path cannot be empty',
        ),
      );
    }

    final dir = Directory(path);

    // Create directory if it doesn't exist
    if (!await dir.exists()) {
      try {
        await dir.create(recursive: true);
        LoggerService.info('Directory created: $path');
      } on Object catch (e) {
        LoggerService.error('Failed to create directory: $path', e);
        return Failure(
          core_errors.DirectoryCreationFailure(
            message: 'Failed to create directory: $path',
            originalError: e,
          ),
        );
      }
    }

    // Verify write permissions via probe file. Centralized helper
    // (`DirectoryPermissionCheck`) substitui a implementação que era
    // duplicada em SchedulerService / ScheduleDialog / aqui.
    final hasPermission = await DirectoryPermissionCheck.hasWritePermission(
      dir,
    );
    if (!hasPermission) {
      LoggerService.warning('No write permission for directory: $path');
      return Failure(
        core_errors.ValidationFailure(
          message: 'No write permission for directory: $path',
        ),
      );
    }

    return const Success(unit);
  }
}
