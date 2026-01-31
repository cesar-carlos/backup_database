import 'package:backup_database/core/errors/failure.dart';

class NextcloudFailure extends Failure {
  const NextcloudFailure({
    super.message = 'Erro Nextcloud.',
    super.code,
    super.originalError,
  });
}
