import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/session_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show SendToClient;

/// Snapshot imutavel da sessao de um cliente conectado, do ponto de
/// vista do servidor.
class SessionInfo {
  const SessionInfo({
    required this.clientId,
    required this.isAuthenticated,
    required this.host,
    required this.port,
    required this.connectedAt,
    this.serverId,
  });

  final String clientId;
  final bool isAuthenticated;
  final String host;
  final int port;
  final DateTime connectedAt;
  final String? serverId;
}

/// Lookup assincrono que dado um `clientId` retorna o snapshot de
/// sessao correspondente, ou `null` quando o cliente nao esta mais
/// conectado (ja foi removido do `_handlers`).
typedef SessionInfoLookup = Future<SessionInfo?> Function(String clientId);

/// Responde `sessionRequest` com snapshot da sessao do cliente que
/// originou a requisicao. Implementa o terceiro endpoint do trio do
/// handshake do PR-1 (capabilities, health, session).
///
/// O lookup e injetado para que o handler nao tenha dependencia direta
/// de `_handlers`/`_clientManager` do `TcpSocketServer` (ISP). Em
/// producao, o wiring no server passa um lookup que consulta o
/// `ClientManager`/handlers map. Em testes, basta mockar.
class SessionMessageHandler {
  SessionMessageHandler({
    required SessionInfoLookup sessionLookup,
    DateTime Function()? clock,
  })  : _sessionLookup = sessionLookup,
        _clock = clock ?? DateTime.now;

  final SessionInfoLookup _sessionLookup;
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isSessionRequestMessage(message)) return;

    final requestId = message.header.requestId;
    LoggerService.infoWithContext(
      'SessionMessageHandler: respondendo session',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    try {
      final info = await _sessionLookup(clientId);
      if (info == null) {
        // Cliente nao mais conectado (race condition rara: handler
        // recebe a request e o cliente desconecta antes do lookup).
        // Retorna erro padronizado em vez de inventar dados.
        await sendToClient(
          clientId,
          createErrorMessage(
            requestId: requestId,
            errorMessage: 'Sessao nao encontrada para clientId: $clientId',
            errorCode: ErrorCode.unknown,
          ),
        );
        return;
      }

      await sendToClient(
        clientId,
        createSessionResponseMessage(
          requestId: requestId,
          clientId: info.clientId,
          isAuthenticated: info.isAuthenticated,
          host: info.host,
          port: info.port,
          connectedAt: info.connectedAt,
          serverTimeUtc: _clock(),
          serverId: info.serverId,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'SessionMessageHandler: falha ao responder session: $e',
        e,
        st,
      );
      await sendToClient(
        clientId,
        createErrorMessage(
          requestId: requestId,
          errorMessage: 'Falha ao consultar sessao: $e',
          errorCode: ErrorCode.unknown,
        ),
      );
    }
  }
}
