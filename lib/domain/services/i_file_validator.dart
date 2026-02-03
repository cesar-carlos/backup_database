import 'package:backup_database/domain/entities/backup_validation_result.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IFileValidator {
  Future<rd.Result<BackupValidationResult>> validate(String filePath);
}
