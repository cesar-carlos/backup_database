import 'package:backup_database/domain/entities/email_test_audit.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IEmailTestAuditRepository {
  Future<rd.Result<EmailTestAudit>> create(EmailTestAudit audit);

  Future<rd.Result<List<EmailTestAudit>>> getRecent({
    String? configId,
    DateTime? startAt,
    DateTime? endAt,
    int limit = 100,
  });
}
