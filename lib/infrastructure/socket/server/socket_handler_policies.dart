import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_error_sender.dart';

/// Políticas reaproveitadas por múltiplos handlers do socket server
/// (`ScheduleMessageHandler`, `ExecutionMessageHandler`,
/// `ScheduleCrudMessageHandler`, `DatabaseConfigMessageHandler`).
///
/// Antes desta classe, o pattern "rejeitar Firebird se o servidor não
/// suporta" estava duplicado inline em 4 handlers com pequenas
/// variações de mensagem.
abstract final class SocketHandlerPolicies {
  /// Retorna `true` quando enviou erro e o caller deve abortar.
  /// Retorna `false` quando suporta (ou tipo de banco diferente).
  ///
  /// Use ANTES de qualquer side-effect (registry, scheduler, repo)
  /// para evitar trabalho inútil.
  static Future<bool> rejectIfFirebirdUnsupported({
    required bool isFirebird,
    required bool supportsFirebird,
    required String clientId,
    required int requestId,
    required SendToClient sendToClient,
  }) async {
    if (supportsFirebird || !isFirebird) {
      return false;
    }
    await SocketErrorSender.sendProtocolError(
      clientId: clientId,
      requestId: requestId,
      errorMessage: ErrorCode.unsupportedDatabaseType.defaultMessage,
      sendToClient: sendToClient,
      errorCode: ErrorCode.unsupportedDatabaseType,
    );
    return true;
  }
}
