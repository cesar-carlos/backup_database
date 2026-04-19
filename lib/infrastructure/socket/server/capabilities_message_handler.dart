import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/capabilities_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/protocol_versions.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show SendToClient;

/// Responde `capabilitiesRequest` com o snapshot atual de features
/// suportadas pelo servidor.
///
/// Implementacao parcial de M1.3 (ADR-003) e M4.1 do plano remoto.
///
/// O snapshot reflete o estado **atual** do codigo neste commit:
///
/// - `protocolVersion` e `wireVersion` vem de
///   `lib/infrastructure/protocol/protocol_versions.dart`. Bumpar essas
///   constantes propaga automaticamente para a resposta sem precisar
///   editar o handler.
/// - As flags de feature refletem o que ja foi entregue ate agora:
///   - `supportsRunId = true` (M2.3 entregue: `runId` opcional ja
///     viaja em `backupProgress/Complete/Failed`).
///   - `supportsResume = true` (resume de download por chunk ja
///     existe em `requestFile`).
///   - `supportsArtifactRetention = false` (artefato sem TTL formal,
///     entrega prevista para PR-4 / M8.3).
///   - `supportsChunkAck = false` (decisao explicita ADR-002).
///   - `supportsExecutionQueue = false` (fila prevista para PR-3b).
/// - `chunkSize` e `compression` refletem `SocketConfig` atual.
/// - `serverTimeUtc` permite o cliente detectar drift de relogio.
class CapabilitiesMessageHandler {
  CapabilitiesMessageHandler({
    DateTime Function()? clock,
    int chunkSize = 65536,
    String compression = 'gzip',
  })  : _clock = clock ?? DateTime.now,
        _chunkSize = chunkSize,
        _compression = compression;

  final DateTime Function() _clock;
  final int _chunkSize;
  final String _compression;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isCapabilitiesRequestMessage(message)) {
      return;
    }

    final requestId = message.header.requestId;
    LoggerService.infoWithContext(
      'CapabilitiesMessageHandler: respondendo capabilities',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    await sendToClient(
      clientId,
      createCapabilitiesResponseMessage(
        requestId: requestId,
        protocolVersion: kCurrentProtocolVersion,
        wireVersion: kCurrentWireVersion,
        supportsRunId: true,
        supportsResume: true,
        supportsArtifactRetention: false,
        supportsChunkAck: false,
        supportsExecutionQueue: false,
        chunkSize: _chunkSize,
        compression: _compression,
        serverTimeUtc: _clock(),
      ),
    );
  }
}
