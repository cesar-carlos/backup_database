import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DeleteEmailNotificationTarget {
  DeleteEmailNotificationTarget(this._repository);

  final IEmailNotificationTargetRepository _repository;

  Future<rd.Result<void>> call(String targetId) {
    return _repository.deleteById(targetId);
  }
}
