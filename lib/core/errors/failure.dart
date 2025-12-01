abstract class Failure implements Exception {
  final String message;
  final String? code;
  final dynamic originalError;

  const Failure({
    required this.message,
    this.code,
    this.originalError,
  });

  @override
  String toString() => 'Failure(message: $message, code: $code)';
}

class ServerFailure extends Failure {
  const ServerFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class DatabaseFailure extends Failure {
  const DatabaseFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class NetworkFailure extends Failure {
  const NetworkFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class ValidationFailure extends Failure {
  const ValidationFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class BackupFailure extends Failure {
  const BackupFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class FileSystemFailure extends Failure {
  const FileSystemFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class FtpFailure extends Failure {
  const FtpFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class GoogleDriveFailure extends Failure {
  const GoogleDriveFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

class NotFoundFailure extends Failure {
  const NotFoundFailure({
    required super.message,
    super.code,
    super.originalError,
  });
}

