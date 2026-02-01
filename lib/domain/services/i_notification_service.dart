import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:result_dart/result_dart.dart';

abstract class INotificationService {
  Future<Result<bool>> notifyBackupComplete(BackupHistory history);

  Future<Result<void>> sendTestEmail(String recipient, String subject);

  Future<Result<bool>> sendWarning({
    required String databaseName,
    required String message,
  });
}
