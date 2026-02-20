import 'package:backup_database/domain/entities/email_config.dart';
import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ListEmailConfigurations {
  ListEmailConfigurations(this._repository);

  final IEmailConfigRepository _repository;

  Future<rd.Result<List<EmailConfig>>> call() {
    return _repository.getAll();
  }
}
