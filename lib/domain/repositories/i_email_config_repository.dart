import 'package:backup_database/domain/entities/email_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IEmailConfigRepository {
  Future<rd.Result<EmailConfig>> get();
  Future<rd.Result<EmailConfig>> save(EmailConfig config);
  Future<rd.Result<void>> delete();
}
