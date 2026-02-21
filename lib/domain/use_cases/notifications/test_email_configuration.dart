import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/services/i_notification_service.dart';
import 'package:result_dart/result_dart.dart' as rd;

class TestEmailConfiguration {
  TestEmailConfiguration(this._notificationService);
  final INotificationService _notificationService;

  Future<rd.Result<bool>> call(EmailConfig config) {
    return _notificationService.testEmailConfiguration(config);
  }
}
