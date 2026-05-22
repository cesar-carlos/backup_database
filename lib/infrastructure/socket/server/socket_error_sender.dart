import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';

/// Shared helpers for sending protocol error envelopes to socket clients.
///
/// Consolidates the `_sendError` / `_sendErrorMsg` pattern duplicated across
/// schedule, execution, database-config, and schedule-CRUD handlers.
class SocketErrorSender {
  SocketErrorSender._();

  static Future<void> sendScheduleError({
    required String clientId,
    required int requestId,
    required String error,
    required SendToClient sendToClient,
    ErrorCode? errorCode,
  }) {
    return sendToClient(
      clientId,
      createScheduleErrorMessage(
        requestId: requestId,
        error: error,
        errorCode: errorCode,
      ),
    );
  }

  static Future<void> sendProtocolError({
    required String clientId,
    required int requestId,
    required String errorMessage,
    required SendToClient sendToClient,
    required ErrorCode errorCode,
    int? retryAfterSeconds,
  }) {
    return sendToClient(
      clientId,
      createErrorMessage(
        requestId: requestId,
        errorMessage: errorMessage,
        errorCode: errorCode,
        retryAfterSeconds: retryAfterSeconds,
      ),
    );
  }
}
