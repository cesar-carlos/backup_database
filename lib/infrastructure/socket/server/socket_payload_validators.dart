import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart';
import 'package:backup_database/infrastructure/socket/server/socket_error_sender.dart';

/// Helpers de validação de payload de mensagens socket.
///
/// Centraliza o pattern repetido em ~7 handlers:
/// ```dart
/// final id = payload['scheduleId'] is String
///     ? payload['scheduleId'] as String
///     : '';
/// if (id.isEmpty) {
///   await SocketErrorSender.sendProtocolError(...);
///   return;
/// }
/// ```
/// Vira:
/// ```dart
/// final id = await SocketPayloadValidators.requireStringField(
///   payload, 'scheduleId',
///   clientId: clientId, requestId: requestId,
///   sendToClient: sendToClient,
/// );
/// if (id == null) return;
/// ```
abstract final class SocketPayloadValidators {
  /// Lê `payload[key]` como String não-vazia. Quando ausente ou vazio,
  /// dispara `invalidRequest` para o cliente e retorna `null` — o caller
  /// deve sair imediatamente com `return`.
  ///
  /// `customErrorMessage`: sobrescreve a mensagem default
  /// (``"`{key}` ausente ou vazio"``) para casos como
  /// `"scheduleId vazio ou inválido"`.
  static Future<String?> requireStringField(
    Map<String, dynamic> payload,
    String key, {
    required String clientId,
    required int requestId,
    required SendToClient sendToClient,
    String? customErrorMessage,
  }) async {
    final raw = payload[key];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    await SocketErrorSender.sendProtocolError(
      clientId: clientId,
      requestId: requestId,
      errorMessage: customErrorMessage ?? '`$key` ausente ou vazio',
      sendToClient: sendToClient,
      errorCode: ErrorCode.invalidRequest,
    );
    return null;
  }

  /// Variante síncrona para casos onde o caller já vai jogar uma
  /// exceção (ex.: `_doStart` que joga `_StartFailure` em vez de
  /// enviar resposta direto). Retorna `null` quando o campo está
  /// ausente/vazio — caller decide como sinalizar.
  static String? readStringField(Map<String, dynamic> payload, String key) {
    final raw = payload[key];
    if (raw is String && raw.isNotEmpty) {
      return raw;
    }
    return null;
  }

  /// Extrator de `runId` para handlers de diagnostics/cancel
  /// (helper de conveniência por ser usado em vários lugares).
  static String? readRunId(Message message) =>
      readStringField(message.payload, 'runId');

  /// Extrator de `scheduleId`.
  static String? readScheduleId(Message message) =>
      readStringField(message.payload, 'scheduleId');
}
