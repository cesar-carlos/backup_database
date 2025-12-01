import 'package:result_dart/result_dart.dart' as rd;

import '../../../domain/entities/email_config.dart';
import '../../../domain/repositories/i_email_config_repository.dart';

class ConfigureEmail {
  final IEmailConfigRepository _repository;

  ConfigureEmail(this._repository);

  Future<rd.Result<EmailConfig>> call(EmailConfig config) async {
    return await _repository.save(config);
  }
}

