import 'package:backup_database/core/errors/failure.dart';

class GoogleDriveFailure extends Failure {
  const GoogleDriveFailure({
    super.message = 'Erro Google Drive.',
    super.code,
    super.originalError,
  });
}
