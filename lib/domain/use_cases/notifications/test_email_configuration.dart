import 'package:backup_database/application/services/notification_service.dart';
import 'package:backup_database/domain/entities/email_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

class TestEmailConfiguration {
  TestEmailConfiguration(this._notificationService);
  final NotificationService _notificationService;

  Future<rd.Result<bool>> call(EmailConfig config) async {
    return _notificationService.testEmailConfiguration(config);
  }
}
