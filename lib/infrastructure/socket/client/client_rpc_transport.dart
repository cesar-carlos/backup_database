import 'dart:async';

import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/error_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:result_dart/result_dart.dart' as rd;

class ClientRpcTransport {
  int _nextRequestId = 0;
  final Map<int, Completer<Message>> _pendingRequests = {};

  bool get isEmpty => _pendingRequests.isEmpty;
  int get pendingCount => _pendingRequests.length;

  int allocateRequestId() => _nextRequestId++;

  Completer<Message> register(int requestId) {
    final completer = Completer<Message>();
    _pendingRequests[requestId] = completer;
    return completer;
  }

  void completeIfPending(int requestId, Message message) {
    final completer = _pendingRequests.remove(requestId);
    if (completer != null && !completer.isCompleted) {
      completer.complete(message);
    }
  }

  void abortAll(Object error) {
    for (final completer in _pendingRequests.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pendingRequests.clear();
  }

  void completeAllDisconnected() {
    final pending = Map<int, Completer<Message>>.from(_pendingRequests);
    _pendingRequests.clear();
    for (final entry in pending.entries) {
      if (!entry.value.isCompleted) {
        entry.value.complete(
          createErrorMessage(
            requestId: entry.key,
            errorMessage: 'Disconnected',
          ),
        );
      }
    }
  }

  Future<rd.Result<T>> request<T extends Object>({
    required bool isConnected,
    required Future<void> Function(Message message) send,
    required Message Function(int requestId) build,
    required bool Function(Message message) isExpected,
    required T Function(Message message) parse,
    required String operationName,
    Duration timeout = SocketConfig.scheduleRequestTimeout,
    bool logFailures = false,
    String? unexpectedLabel,
  }) async {
    if (!isConnected) {
      return rd.Failure(Exception('ConnectionManager not connected'));
    }
    final requestId = allocateRequestId();
    final completer = register(requestId);
    try {
      await send(build(requestId));
      final message = await completer.future.timeout(timeout);
      _pendingRequests.remove(requestId);
      if (message.header.type == MessageType.error) {
        final error = getErrorFromPayload(message) ?? 'Erro desconhecido';
        return rd.Failure(Exception(error));
      }
      if (!isExpected(message)) {
        final typeName = message.header.type.name;
        final unexpected = unexpectedLabel == null
            ? 'Resposta inesperada: $typeName'
            : 'Resposta inesperada para $unexpectedLabel: $typeName';
        return rd.Failure(Exception(unexpected));
      }
      return rd.Success(parse(message));
    } on TimeoutException {
      _pendingRequests.remove(requestId);
      return rd.Failure(TimeoutException('$operationName timeout'));
    } on Object catch (e, stackTrace) {
      _pendingRequests.remove(requestId);
      if (logFailures) {
        LoggerService.warning(
          '[ConnectionManager] $operationName falhou',
          e,
          stackTrace,
        );
      }
      return rd.Failure(e is Exception ? e : Exception(e.toString()));
    }
  }
}
