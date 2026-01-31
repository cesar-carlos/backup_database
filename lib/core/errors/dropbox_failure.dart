import 'package:backup_database/core/errors/failure.dart';

class DropboxFailure extends Failure {
  const DropboxFailure({
    super.message = 'Erro Dropbox.',
    super.code,
    super.originalError,
  });
}
