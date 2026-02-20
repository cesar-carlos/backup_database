import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ListEmailNotificationTargets {
  ListEmailNotificationTargets(this._repository);

  final IEmailNotificationTargetRepository _repository;

  Future<rd.Result<List<EmailNotificationTarget>>> call(String configId) {
    return _repository.getByConfigId(configId);
  }
}
