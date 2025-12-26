import 'failure.dart';

class DropboxFailure extends Failure {
  const DropboxFailure({
    super.message = 'Erro Dropbox.',
    super.code,
    super.originalError,
  });
}
