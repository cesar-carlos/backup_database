import 'package:backup_database/core/errors/failure.dart';

Failure windowsServiceAsFailure(Object failure) {
  if (failure is Failure) return failure;
  return ServerFailure(
    message: failureUserMessage(failure),
    originalError: failure,
  );
}
