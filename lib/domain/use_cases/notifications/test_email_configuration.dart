import 'package:result_dart/result_dart.dart' as rd;

import '../../../domain/entities/email_config.dart';
import '../../../application/services/notification_service.dart';

class TestEmailConfiguration {
  final NotificationService _notificationService;

  TestEmailConfiguration(this._notificationService);

  Future<rd.Result<bool>> call(EmailConfig config) async {
    return await _notificationService.testEmailConfiguration(config);
  }
}

