import 'package:backup_database/domain/repositories/i_email_config_repository.dart';
import 'package:result_dart/result_dart.dart' as rd;

class DeleteEmailConfiguration {
  DeleteEmailConfiguration(this._repository);

  final IEmailConfigRepository _repository;

  Future<rd.Result<void>> call(String configId) {
    return _repository.deleteById(configId);
  }
}
