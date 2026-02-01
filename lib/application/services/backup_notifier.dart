import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart';

class BackupNotifier {
  BackupNotifier({
    required INotificationService notificationService,
  }) : _notificationService = notificationService;

  final INotificationService _notificationService;

  Future<Result<bool>> notifyBackupComplete(BackupHistory history) async {
    return _notificationService.notifyBackupComplete(history);
  }

  Future<Result<bool>> sendWarning({
    required String databaseName,
    required String message,
  }) async {
    return _notificationService.sendWarning(
      databaseName: databaseName,
      message: message,
    );
  }
}
