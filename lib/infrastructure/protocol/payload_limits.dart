import 'package:backup_database/core/constants/socket_config.dart';
import 'package:backup_database/infrastructure/protocol/message_types.dart';

/// Limite maximo de payload por tipo de mensagem (M5.4 do plano).
///
/// Defesa em profundidade: alem do limite global
/// `SocketConfig.maxMessagePayloadBytes` (64 MB), cada tipo de mensagem
/// tem um teto especifico que reflete o uso real esperado. Mensagens
/// pequenas como `executeSchedule` (so um `scheduleId`) nao devem
/// chegar perto de megabytes — quando isso acontece, e indicio forte
/// de payload malformado ou peer hostil.
///
/// Os limites foram escolhidos **generosos o suficiente** para o uso
/// real atual (com folga para evolucao), mas **restritivos o suficiente**
/// para detectar abuso. Tipos nao mapeados explicitamente caem no
/// limite global (zero regressao para casos legados).
///
/// Ancora no plano: M5.4 (limite por tipo) + ADR-003 (defesa em
/// profundidade do parser).
class PayloadLimits {
  PayloadLimits._();

  /// Mapa publico imutavel para inspecao/teste. Use [maxPayloadBytesFor]
  /// para obter o limite efetivo (com fallback global).
  static const Map<MessageType, int> perType = <MessageType, int>{
    // ---- Auth e sessao (payloads minimos) ----
    MessageType.authRequest: 8 * 1024, // 8 KB
    MessageType.authResponse: 8 * 1024,
    MessageType.authChallenge: 8 * 1024,

    // ---- Sistema ----
    MessageType.heartbeat: 1 * 1024, // 1 KB
    MessageType.disconnect: 1 * 1024,
    MessageType.error: 64 * 1024, // 64 KB (pode ter detalhes)

    // ---- Capabilities (M1.3 / M4.1) ----
    MessageType.capabilitiesRequest: 1 * 1024,
    MessageType.capabilitiesResponse: 16 * 1024, // 16 KB

    // ---- Health (M1.10 / PR-1) ----
    MessageType.healthRequest: 1 * 1024,
    MessageType.healthResponse: 16 * 1024, // suporta lista de checks com mensagens

    // ---- Session (M1.10 / PR-1) ----
    MessageType.sessionRequest: 1 * 1024,
    MessageType.sessionResponse: 8 * 1024,

    // ---- Preflight (F1.8 / PR-1) ----
    // Response pode crescer com lista de checks + details estruturados;
    // 64KB cobre dezenas de checks com detalhes diagnosticos.
    MessageType.preflightRequest: 1 * 1024,
    MessageType.preflightResponse: 64 * 1024,

    // ---- Execution status (PR-2 base / M2.3 complement) ----
    // Request carrega so o runId; response e snapshot pequeno.
    MessageType.executionStatusRequest: 1 * 1024,
    MessageType.executionStatusResponse: 4 * 1024,

    // ---- Execution queue (PR-3b base) ----
    // Request vazio; response cresce com lista de itens enfileirados
    // mas e limitada por `maxQueueSize` (default 50 conforme M8).
    // ~200 bytes por item -> 50 * 200 = ~10KB; 32KB cobre folgado.
    MessageType.executionQueueRequest: 1 * 1024,
    MessageType.executionQueueResponse: 32 * 1024,

    // ---- Schedule commands ----
    // Lista pode ser grande se tiver muitos schedules; update/scheduleUpdated
    // carregam um schedule completo com config JSON.
    MessageType.listSchedules: 1 * 1024, // request vazio
    MessageType.scheduleList: 512 * 1024, // 512 KB
    MessageType.updateSchedule: 256 * 1024,
    MessageType.scheduleUpdated: 256 * 1024,
    MessageType.executeSchedule: 4 * 1024, // so scheduleId
    MessageType.cancelSchedule: 4 * 1024,
    MessageType.scheduleCancelled: 4 * 1024,

    // ---- Backup events ----
    // Carregam scheduleId, runId opcional, mensagem, path opcional.
    MessageType.backupProgress: 64 * 1024,
    MessageType.backupStep: 16 * 1024,
    MessageType.backupComplete: 64 * 1024,
    MessageType.backupFailed: 64 * 1024,

    // ---- File transfer ----
    // fileChunk e o unico que pode ter MB; mantem proximo do global.
    MessageType.listFiles: 1 * 1024,
    MessageType.fileList: 512 * 1024,
    MessageType.fileTransferStart: 16 * 1024,
    MessageType.fileChunk: SocketConfig.maxMessagePayloadBytes, // ~64 MB
    MessageType.fileTransferProgress: 4 * 1024,
    MessageType.fileTransferComplete: 4 * 1024,
    MessageType.fileTransferError: 16 * 1024,
    MessageType.fileAck: 4 * 1024, // reservado v1; ver ADR-002

    // ---- Metricas ----
    MessageType.metricsRequest: 1 * 1024,
    MessageType.metricsResponse: 256 * 1024,

    // ---- Database connection test (PR-2) ----
    // Request pode levar config ad-hoc inteira (host/port/credenciais)
    // ou apenas `databaseConfigId`; 16KB cobre o caso ad-hoc com folga.
    // Response e snapshot pequeno (connected, latencyMs, error).
    MessageType.testDatabaseConnectionRequest: 16 * 1024,
    MessageType.testDatabaseConnectionResponse: 8 * 1024,

    // ---- Execution (start/cancel backup nao-bloqueante, PR-2) ----
    // Request carrega scheduleId + idempotencyKey opcional (~100 bytes).
    // Response carrega runId + state + scheduleId + queuePosition? + msg.
    MessageType.startBackupRequest: 4 * 1024,
    MessageType.startBackupResponse: 4 * 1024,
    MessageType.cancelBackupRequest: 4 * 1024,
    MessageType.cancelBackupResponse: 4 * 1024,
  };

  /// Retorna o limite maximo de payload (em bytes) para o tipo de
  /// mensagem informado. Tipos nao mapeados retornam o limite global
  /// (`SocketConfig.maxMessagePayloadBytes`) — fallback conservador
  /// para evitar regressao em tipos legados ou tipos novos ainda nao
  /// catalogados aqui.
  ///
  /// Sempre garante que o retorno NAO excede o teto global, mesmo que
  /// alguma entrada do mapa seja maior por engano.
  static int maxPayloadBytesFor(MessageType type) {
    final perTypeLimit = perType[type];
    final effective = perTypeLimit ?? SocketConfig.maxMessagePayloadBytes;
    if (effective > SocketConfig.maxMessagePayloadBytes) {
      return SocketConfig.maxMessagePayloadBytes;
    }
    if (effective < 0) {
      return SocketConfig.maxMessagePayloadBytes;
    }
    return effective;
  }
}
