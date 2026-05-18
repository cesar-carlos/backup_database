import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/idempotency_registry.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Politica de idempotencia remota (F2.14 / M5 do plano).
class IdempotencyPolicy {
  IdempotencyPolicy._();

  static const Duration defaultTtl = Duration(hours: 1);

  static const Set<MessageType> keyRequiredTypes = <MessageType>{
    MessageType.startBackupRequest,
    MessageType.cancelBackupRequest,
    MessageType.createSchedule,
    MessageType.deleteSchedule,
    MessageType.createDatabaseConfigRequest,
    MessageType.deleteDatabaseConfigRequest,
  };

  static bool isKeyRequired(MessageType type) => keyRequiredTypes.contains(type);

  static bool hasValidKey(Message message) {
    final key = getIdempotencyKey(message);
    return key != null;
  }

  static Message? missingKeyErrorMessage({
    required Message message,
    required MessageType operationType,
  }) {
    if (!isKeyRequired(operationType) || hasValidKey(message)) {
      return null;
    }
    return createErrorMessage(
      requestId: message.header.requestId,
      errorMessage:
          'Campo `idempotencyKey` obrigatorio para ${operationType.name}',
      errorCode: ErrorCode.invalidRequest,
    );
  }
}
