import 'failure.dart';

class FtpFailure extends Failure {
  const FtpFailure({
    super.message = 'Erro FTP.',
    super.code,
    super.originalError,
  });
}

