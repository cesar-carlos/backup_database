import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:backup_database/domain/repositories/i_email_notification_target_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ConfigureEmailNotificationTarget {
  ConfigureEmailNotificationTarget(this._repository);

  final IEmailNotificationTargetRepository _repository;

  Future<rd.Result<EmailNotificationTarget>> call(
    EmailNotificationTarget target,
  ) async {
    final existingResult = await _repository.getById(target.id);

    return existingResult.fold(
      (_) => _repository.update(target),
      (_) => _repository.create(target),
    );
  }
}
