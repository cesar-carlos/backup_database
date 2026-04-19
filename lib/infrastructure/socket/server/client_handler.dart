import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/connection/connected_client.dart';
import 'package:backup_database/infrastructure/datasources/daos/connection_log_dao.dart';
import 'package:backup_database/infrastructure/protocol/auth_messages.dart';
import 'package:backup_database/infrastructure/protocol/binary_protocol.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/payload_limits.dart';
import 'package:backup_database/infrastructure/socket/heartbeat.dart';
import 'package:backup_database/infrastructure/socket/server/server_authentication.dart';
import 'package:uuid/uuid.dart';

const int _headerSize = 16;
const int _checksumSize = 4;

class ClientHandler {
  ClientHandler({
    required Socket socket,
    required BinaryProtocol protocol,
    required void Function(String clientId) onDisconnect,
    ServerAuthentication? authentication,
    ConnectionLogDao? connectionLogDao,
    SocketLoggerService? socketLogger,
  }) : _socket = socket,
       _protocol = protocol,
       _onDisconnect = onDisconnect,
       _authentication = authentication,
       _connectionLogDao = connectionLogDao,
       _socketLogger = socketLogger,
       _clientId = const Uuid().v4() {
    _remoteAddress = _socket.remoteAddress.address;
    _remotePort = _socket.remotePort;
  }

  final Socket _socket;
  final BinaryProtocol _protocol;
  final void Function(String clientId) _onDisconnect;
  final ServerAuthentication? _authentication;
  final ConnectionLogDao? _connectionLogDao;
  final SocketLoggerService? _socketLogger;
  final String _clientId;
  bool _authHandled = false;

  late final String _remoteAddress;
  late final int _remotePort;

  final StreamController<Message> _messageController =
      StreamController<Message>.broadcast();
  final List<int> _buffer = [];
  bool isAuthenticated = false;
  String clientName = '';

  /// `serverId` declarado pelo cliente no `authRequest` (preservado
  /// apos auth bem-sucedida). Usado por `SessionMessageHandler` para
  /// reportar a sessao corrente. `null` quando handler opera sem
  /// autenticacao ou antes do auth completar.
  String? authenticatedServerId;
  DateTime _lastHeartbeat = DateTime.now();
  HeartbeatManager? _heartbeatManager;
  StreamSubscription<List<int>>? _socketSubscription;

  /// Serializa as escritas no socket para evitar interleaving de bytes
  /// quando heartbeat e mensagens normais (ex.: progress) tentam emitir
  /// concorrentemente. Sem isso o protocolo binário pode receber bytes
  /// fora de ordem e o peer falha no parse.
  Future<void> _sendQueue = Future.value();

  Stream<Message> get messageStream => _messageController.stream;
  String get clientId => _clientId;
  String get host => _remoteAddress;
  int get port => _remotePort;
  DateTime get lastHeartbeat => _lastHeartbeat;

  void updateHeartbeat() => _lastHeartbeat = DateTime.now();

  ConnectedClient toConnectedClient(DateTime connectedAt) => ConnectedClient(
    id: _clientId,
    clientId: _clientId,
    clientName: clientName.isEmpty ? _remoteAddress : clientName,
    host: _remoteAddress,
    port: _remotePort,
    connectedAt: connectedAt,
    lastHeartbeat: _lastHeartbeat,
    isAuthenticated: isAuthenticated,
  );

  void start() {
    if (_authentication == null) {
      isAuthenticated = true;
    }
    _heartbeatManager = HeartbeatManager(
      sendHeartbeat: send,
      onTimeout: disconnect,
    );
    _heartbeatManager!.start();
    _socketSubscription = _socket.listen(
      _onData,
      onError: _onError,
      onDone: _onDone,
      cancelOnError: false,
    );
  }

  void _onData(List<int> data) {
    _buffer.addAll(data);

    // Proteção contra peer malicioso / dados malformados: se o buffer
    // crescer absurdamente sem produzir uma mensagem válida, derruba a
    // conexão para liberar memória do servidor.
    if (_buffer.length > SocketConfig.maxBufferOverhead) {
      LoggerService.warning(
        'ClientHandler $_clientId: buffer excedeu limite de '
        '${SocketConfig.maxBufferOverhead} bytes sem produzir mensagem '
        'válida — desconectando.',
      );
      disconnect();
      return;
    }

    _tryParseMessages();
  }

  void _tryParseMessages() {
    while (_buffer.length >= _headerSize) {
      final length = _readUint32Be(_buffer, 5);

      // Validação de range no length declarado pelo header. Antes era
      // confiado cegamente — peer malicioso podia declarar 4 GB e
      // alocar tudo. Agora rejeitamos qualquer payload acima do limite.
      if (length < 0 || length > SocketConfig.maxMessagePayloadBytes) {
        LoggerService.warning(
          'ClientHandler $_clientId: length declarado inválido ($length '
          'bytes; máximo ${SocketConfig.maxMessagePayloadBytes}). '
          'Encerrando conexão.',
        );
        unawaited(
          send(
            createErrorMessage(
              requestId: 0,
              errorMessage:
                  'Message length out of range: $length (max '
                  '${SocketConfig.maxMessagePayloadBytes})',
              errorCode: ErrorCode.parseError,
            ),
          ),
        );
        disconnect();
        return;
      }

      // Validacao de limite por tipo de mensagem (M5.4). Le o `type`
      // direto do header (offset 9) ANTES de gastar memoria com o
      // sublist + deserializacao. Tipos desconhecidos (cliente futuro
      // enviando MessageType novo que ainda nao existe no enum) caem
      // no limite global por fallback — comportamento conservador.
      // Encadeia `disconnect` ao final do flush via `whenComplete` para
      // garantir que o cliente receba o erro antes da desconexao
      // (mesmo padrao usado em wire version invalida — ADR-003).
      final typeIndex = _buffer[9];
      final type = typeIndex < MessageType.values.length
          ? MessageType.values[typeIndex]
          : null;
      if (type != null) {
        final maxForType = PayloadLimits.maxPayloadBytesFor(type);
        if (length > maxForType) {
          LoggerService.warning(
            'ClientHandler $_clientId: payload de ${type.name} excede '
            'limite ($length bytes; max $maxForType). Encerrando conexão.',
          );
          unawaited(
            send(
              createErrorMessage(
                requestId: 0,
                errorMessage:
                    'Payload too large for ${type.name}: $length bytes '
                    '(max $maxForType)',
                errorCode: ErrorCode.payloadTooLarge,
              ),
            ).whenComplete(disconnect),
          );
          return;
        }
      }

      final totalNeeded = _headerSize + length + _checksumSize;
      if (_buffer.length < totalNeeded) break;

      final messageBytes = Uint8List.fromList(_buffer.sublist(0, totalNeeded));
      _buffer.removeRange(0, totalNeeded);

      try {
        final message = _protocol.deserializeMessage(messageBytes);

        // Log received message
        _socketLogger?.logReceived(message);

        if (isAuthRequestMessage(message) && !_authHandled) {
          _authHandled = true;
          if (_authentication != null) {
            // Pausa o subscription enquanto a validação async roda; sem
            // isso, mensagens subsequentes do peer chegavam e caíam no
            // ramo `else` PRÉ-AUTH (eram entregues ao
            // `_messageController` SEM `isAuthenticated=true`),
            // permitindo executar comandos antes de validar credencial.
            _socketSubscription?.pause();
            _authentication.validateAuthRequest(message).then((
              AuthValidationResult validationResult,
            ) async {
              try {
                final valid = validationResult.isValid;
                isAuthenticated = valid;
                final serverId = message.payload['serverId'] as String?;
                if (valid && serverId != null && serverId.isNotEmpty) {
                  // Persiste para que SessionMessageHandler possa
                  // reportar a sessao corrente sem depender do payload
                  // original do auth.
                  authenticatedServerId = serverId;
                }
                try {
                  await _connectionLogDao?.insertConnectionAttempt(
                    clientHost: _remoteAddress,
                    serverId: serverId,
                    success: valid,
                    errorMessage: valid ? null : validationResult.errorMessage,
                    clientId: _clientId,
                  );
                } on Object catch (e) {
                  LoggerService.warning(
                    'ClientHandler: failed to log auth: $e',
                  );
                }
                await send(
                  createAuthResponse(
                    success: valid,
                    error: validationResult.errorMessage,
                    errorCode: validationResult.errorCode,
                  ),
                );
                if (!valid) {
                  disconnect();
                  return;
                }
                _safeAddMessage(message);
              } finally {
                // Retoma o stream para processar mensagens pós-auth.
                if (_socketSubscription?.isPaused ?? false) {
                  _socketSubscription?.resume();
                  // Mensagens que já estão no buffer precisam ser
                  // reprocessadas — `_tryParseMessages` é idempotente.
                  _tryParseMessages();
                }
              }
            });
            return;
          }
          isAuthenticated = true;
        } else if (isHeartbeatMessage(message)) {
          _heartbeatManager?.onHeartbeatReceived();
          _lastHeartbeat = DateTime.now();
        } else if (!isAuthenticated) {
          // F0.1 — guard explicito de defesa em profundidade.
          //
          // Cenario: peer envia mensagem operacional (executeSchedule,
          // listSchedules, etc.) antes de completar o handshake. O
          // pause/resume do `_authHandled` ja cobre o caso comum (msg
          // chegou no buffer durante a validacao async), mas peers que
          // ignoram o protocolo (cliente terceiro buggy, peer hostil)
          // poderiam enviar mensagem operacional ANTES do `authRequest`.
          // Aqui rejeitamos com erro padronizado em vez de deixar a
          // mensagem cair no `_messageController` para ser processada
          // por handlers downstream sem credencial.
          //
          // Tipos liberados pre-auth: `authRequest` (tratado acima),
          // `heartbeat` (tratado acima), `disconnect` (cliente desistiu
          // — silencioso), `error` (servidor nao processa erro do peer).
          // Demais tipos -> rejeitados com `notAuthenticated` (401).
          if (message.header.type == MessageType.disconnect ||
              message.header.type == MessageType.error) {
            // Liberados pre-auth sem efeito colateral
          } else {
            LoggerService.warning(
              'ClientHandler $_clientId: rejecting pre-auth message '
              '${message.header.type.name} from $_remoteAddress',
            );
            unawaited(
              send(
                createErrorMessage(
                  requestId: message.header.requestId,
                  errorMessage:
                      'Mensagem ${message.header.type.name} rejeitada: '
                      'autenticacao nao concluida',
                  errorCode: ErrorCode.notAuthenticated,
                ),
              ),
            );
            // Nao desconecta: cliente ainda pode enviar `authRequest`
            // valido na sequencia. Apenas nao roteamos a mensagem
            // operacional para downstream handlers.
            continue;
          }
        }
        _safeAddMessage(message);
      } on UnsupportedProtocolVersionException catch (e) {
        // Wire version desconhecida: peer com protocolo binario
        // incompativel. Responde com errorCode dedicado para que o
        // cliente saiba que precisa atualizar (ver ADR-003 + M1.3).
        // Encadeia `disconnect` ao final do `send` (via `whenComplete`)
        // para garantir que a mensagem de erro chegue antes do socket
        // ser destruido — `unawaited(send(...))` sozinho com
        // `disconnect` em seguida derrubaria a conexao antes do flush.
        LoggerService.warning(
          'ClientHandler unsupported wire version for $_remoteAddress: '
          'received=${e.receivedVersion}, '
          'supported=${e.supportedVersions.join(',')}',
        );
        unawaited(
          send(
            createErrorMessage(
              requestId: 0,
              errorMessage: e.message,
              errorCode: ErrorCode.unsupportedProtocolVersion,
            ),
          ).whenComplete(disconnect),
        );
        return;
      } on ProtocolException catch (e) {
        LoggerService.warning(
          'ClientHandler parse error for $_remoteAddress: ${e.message}',
        );
        unawaited(
          send(
            createErrorMessage(
              requestId: 0,
              errorMessage: 'Failed to parse message: ${e.message}',
              errorCode: ErrorCode.parseError,
            ),
          ),
        );
      }
    }
  }

  /// Emite no `_messageController` apenas se ele ainda está aberto.
  /// Antes, `disconnect()` fechava o controller mas `_tryParseMessages`
  /// poderia continuar rodando e disparar `StateError: Cannot add to
  /// closed controller`.
  void _safeAddMessage(Message message) {
    if (!_messageController.isClosed) {
      _messageController.add(message);
    }
  }

  int _readUint32Be(List<int> data, int offset) {
    if (data.length < offset + 4) return 0;
    return (data[offset] << 24) |
        (data[offset + 1] << 16) |
        (data[offset + 2] << 8) |
        data[offset + 3];
  }

  void _onError(Object error, [StackTrace? stackTrace]) {
    LoggerService.warning(
      'ClientHandler error for $clientId: $error',
      error,
      stackTrace,
    );
  }

  void _onDone() {
    disconnect();
  }

  Future<void> send(Message message) {
    // Encadeia as escritas em uma fila implícita (`_sendQueue`) — cada
    // novo `send` aguarda o anterior antes de tocar no socket. Mantém
    // o protocolo binário consistente quando heartbeat e progress
    // tentam emitir simultaneamente.
    final next = _sendQueue.then((_) async {
      try {
        final data = _protocol.serializeMessage(message);
        _socketLogger?.logSent(message);
        _socket.add(data);
        await _socket.flush();
      } on Object catch (e) {
        LoggerService.warning('ClientHandler send error: $e');
        rethrow;
      }
    });
    // Mantém a cadeia mesmo se `next` falhar (catchError silencia para
    // não estourar erro futuro não-aguardado em outras chamadas).
    _sendQueue = next.catchError((Object _) {});
    return next;
  }

  void disconnect() {
    _heartbeatManager?.stop();
    _heartbeatManager = null;
    _socketSubscription?.cancel();
    _socketSubscription = null;
    if (!_messageController.isClosed) {
      _messageController.close();
    }
    _socket.destroy();
    _onDisconnect(_clientId);
  }
}
