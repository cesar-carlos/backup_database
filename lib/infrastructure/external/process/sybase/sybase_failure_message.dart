import 'package:backup_database/core/errors/failure.dart';

String sybaseFailureMessage(Object failure) {
  if (failure is Failure) {
    return failure.message;
  }
  return failure.toString();
}
