import 'package:backup_database/domain/entities/backup_validation_result.dart';
import 'package:backup_database/domain/services/i_file_validator.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ValidateBackupFile {
  ValidateBackupFile(this._fileValidator);
  final IFileValidator _fileValidator;

  Future<rd.Result<BackupValidationResult>> call(String filePath) async {
    return _fileValidator.validate(filePath);
  }
}
