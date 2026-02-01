import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class SendEmailNotification {
  SendEmailNotification(this._notificationService);
  final INotificationService _notificationService;

  Future<rd.Result<bool>> call(BackupHistory history) async {
    return _notificationService.notifyBackupComplete(history);
  }
}
