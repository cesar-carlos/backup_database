import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IEmailService {
  Future<rd.Result<bool>> sendEmail({
    required EmailConfig config,
    required String subject,
    required String body,
    List<String>? attachmentPaths,
    bool isHtml = false,
  });

  Future<rd.Result<bool>> sendBackupSuccessNotification({
    required EmailConfig config,
    required BackupHistory history,
    String? logPath,
  });

  Future<rd.Result<bool>> sendBackupErrorNotification({
    required EmailConfig config,
    required BackupHistory history,
    String? logPath,
  });

  Future<rd.Result<bool>> sendBackupWarningNotification({
    required EmailConfig config,
    required String databaseName,
    required String warningMessage,
    String? logPath,
  });
}
