import 'dart:io';

import 'package:backup_database/core/errors/failure.dart' as core_errors;
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

    // Verify write permissions
    final hasPermission = await _checkWritePermission(dir);
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

  /// Checks if the directory has write permissions.
  ///
  /// Creates a temporary test file and attempts to write to it.
  /// Returns true if successful, false otherwise.
  Future<bool> _checkWritePermission(Directory directory) async {
    try {
      final timestamp = DateTime.now().millisecondsSinceEpoch;
      final testFileName = '.backup_permission_test_$timestamp';
      final testFile = File(
        '${directory.path}${Platform.pathSeparator}$testFileName',
      );

      await testFile.writeAsString('test');

      if (await testFile.exists()) {
        await testFile.delete();
        return true;
      }

      return false;
    } on Object catch (e) {
      LoggerService.warning(
        'Error checking write permission for ${directory.path}: $e',
      );
      return false;
    }
  }
}
