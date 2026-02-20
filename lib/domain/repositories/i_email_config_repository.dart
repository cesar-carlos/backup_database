import 'package:backup_database/domain/entities/email_config.dart';
import 'package:result_dart/result_dart.dart' as rd;

abstract class IEmailConfigRepository {
  Future<rd.Result<List<EmailConfig>>> getAll();
  Future<rd.Result<EmailConfig>> getById(String id);
  Future<rd.Result<EmailConfig>> create(EmailConfig config);
  Future<rd.Result<EmailConfig>> update(EmailConfig config);
  Future<rd.Result<void>> deleteById(String id);

  Future<rd.Result<EmailConfig>> get();
  Future<rd.Result<EmailConfig>> save(EmailConfig config);
  Future<rd.Result<void>> delete();
}
