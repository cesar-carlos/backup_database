import 'package:backup_database/domain/entities/email_notification_target.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IEmailNotificationTargetRepository {
  Future<rd.Result<List<EmailNotificationTarget>>> getByConfigId(
    String emailConfigId,
  );

  Future<rd.Result<EmailNotificationTarget>> getById(String id);

  Future<rd.Result<EmailNotificationTarget>> create(
    EmailNotificationTarget target,
  );

  Future<rd.Result<EmailNotificationTarget>> update(
    EmailNotificationTarget target,
  );

  Future<rd.Result<void>> deleteById(String id);

  Future<rd.Result<void>> deleteByConfigId(String emailConfigId);
}
