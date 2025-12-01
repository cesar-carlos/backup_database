import 'package:result_dart/result_dart.dart' as rd;

import '../../../domain/entities/backup_history.dart';
import '../../../application/services/notification_service.dart';

class SendEmailNotification {
  final NotificationService _notificationService;

  SendEmailNotification(this._notificationService);

  Future<rd.Result<bool>> call(BackupHistory history) async {
    return await _notificationService.notifyBackupComplete(history);
  }
}

