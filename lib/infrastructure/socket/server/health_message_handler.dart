import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/infrastructure/protocol/health_messages.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show SendToClient;
import 'package:backup_database/infrastructure/utils/staging_usage_policy.dart';

/// Funcao opcional injetavel que executa um check assincrono e retorna
/// `true` quando o subsistema esta saudavel. Tudo que dispara excepcao
/// e tratado como `false` (fail-closed) — defesa em profundidade contra
/// checker que crashe.
typedef HealthCheck = Future<bool> Function();

/// Responde `healthRequest` com snapshot agregado de saude do servidor.
///
/// Implementacao parcial de M1.10 do plano (API de saude minima do
/// servidor) + parte de PR-1.
///
/// Os checks sao **injetados** para que o handler nao tenha
/// dependencias diretas de subsistemas (ISP). Implementacao default e
/// minimalista: apenas reporta que o socket esta funcionando (se a
/// request chegou aqui, o socket OK e `socket: true`). Wirings em
/// producao podem injetar checks adicionais (database, license,
/// staging) sem mudar o handler.
///
/// Politica de agregacao:
/// - Se algum check obrigatorio retornar `false` -> `unhealthy`.
/// - Se algum check NAO obrigatorio retornar `false` -> `degraded`.
/// - Caso contrario -> `ok`.
class HealthMessageHandler {
  HealthMessageHandler({
    Map<String, HealthCheck>? requiredChecks,
    Map<String, HealthCheck>? optionalChecks,
    DateTime Function()? clock,
    DateTime? startTime,
    Future<int> Function()? stagingUsageBytesProvider,
  })  : _requiredChecks = requiredChecks ?? const <String, HealthCheck>{},
        _optionalChecks = optionalChecks ?? const <String, HealthCheck>{},
        _clock = clock ?? DateTime.now,
        _startTime = startTime ?? DateTime.now(),
        _stagingUsageBytesProvider = stagingUsageBytesProvider;

  final Map<String, HealthCheck> _requiredChecks;
  final Map<String, HealthCheck> _optionalChecks;
  final DateTime Function() _clock;
  final DateTime _startTime;

  /// Quando injetado, publica `stagingUsage*` no health e, se o nivel
  /// for `warn` ou `block`, contribui para `degraded` (M5.3 / PR-4).
  final Future<int> Function()? _stagingUsageBytesProvider;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isHealthRequestMessage(message)) return;

    final requestId = message.header.requestId;
    LoggerService.infoWithContext(
      'HealthMessageHandler: respondendo health',
      clientId: clientId,
      requestId: requestId.toString(),
    );

    try {
      final snapshot = await _buildHealthSnapshot();
      await sendToClient(
        clientId,
        createHealthResponseMessage(
          requestId: requestId,
          status: snapshot.status,
          checks: snapshot.checks,
          serverTimeUtc: _clock(),
          uptimeSeconds: _uptimeSeconds(),
          message: snapshot.message,
          stagingUsageBytes: snapshot.stagingUsageBytes,
          stagingUsageWarnThresholdBytes: snapshot.stagingUsageWarnThresholdBytes,
          stagingUsageBlockThresholdBytes:
              snapshot.stagingUsageBlockThresholdBytes,
          stagingUsageLevel: snapshot.stagingUsageLevel,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning(
        'HealthMessageHandler: falha ao montar snapshot: $e',
        e,
        st,
      );
      // Mesmo em falha, responde algo — `unhealthy` com mensagem
      // diagnostica. Cliente nunca fica esperando indefinidamente.
      await sendToClient(
        clientId,
        createHealthResponseMessage(
          requestId: requestId,
          status: ServerHealthStatus.unhealthy,
          checks: const {'socket': true},
          serverTimeUtc: _clock(),
          uptimeSeconds: _uptimeSeconds(),
          message: 'Health check falhou: $e',
        ),
      );
    }
  }

  int _uptimeSeconds() => _clock().difference(_startTime).inSeconds;

  Future<_HealthSnapshot> _buildHealthSnapshot() async {
    // socket=true sempre que chegamos aqui (handler so e invocado quando
    // a mensagem foi parseada e roteada com sucesso).
    final checks = <String, bool>{'socket': true};

    var hasUnhealthyRequired = false;
    var hasDegradedOptional = false;
    final messages = <String>[];

    for (final entry in _requiredChecks.entries) {
      final ok = await _runCheck(entry.key, entry.value);
      checks[entry.key] = ok;
      if (!ok) {
        hasUnhealthyRequired = true;
        messages.add('${entry.key} required check failed');
      }
    }
    for (final entry in _optionalChecks.entries) {
      final ok = await _runCheck(entry.key, entry.value);
      checks[entry.key] = ok;
      if (!ok) {
        hasDegradedOptional = true;
        messages.add('${entry.key} optional check failed');
      }
    }

    int? stagingBytes;
    int? stagingWarn;
    int? stagingBlock;
    String? stagingLevelName;
    var hasStagingPressure = false;
    final measure = _stagingUsageBytesProvider;
    if (measure != null) {
      try {
        final usage = await measure();
        stagingBytes = usage;
        stagingWarn = StagingUsagePolicy.warnThresholdBytes;
        stagingBlock = StagingUsagePolicy.blockThresholdBytes;
        final level = StagingUsagePolicy.levelFor(usage);
        stagingLevelName = level.name;
        if (level == StagingUsageLevel.warn ||
            level == StagingUsageLevel.block) {
          hasStagingPressure = true;
        }
      } on Object catch (e, st) {
        LoggerService.warning(
          'HealthMessageHandler: staging medido falhou: $e',
          e,
          st,
        );
      }
    }

    final ServerHealthStatus status;
    if (hasUnhealthyRequired) {
      status = ServerHealthStatus.unhealthy;
    } else if (hasDegradedOptional || hasStagingPressure) {
      status = ServerHealthStatus.degraded;
    } else {
      status = ServerHealthStatus.ok;
    }

    if (hasStagingPressure) {
      messages.add('staging disk pressure ($stagingLevelName)');
    }

    return _HealthSnapshot(
      status: status,
      checks: checks,
      message: messages.isEmpty ? null : messages.join('; '),
      stagingUsageBytes: stagingBytes,
      stagingUsageWarnThresholdBytes: stagingWarn,
      stagingUsageBlockThresholdBytes: stagingBlock,
      stagingUsageLevel: stagingLevelName,
    );
  }

  Future<bool> _runCheck(String name, HealthCheck check) async {
    try {
      return await check();
    } on Object catch (e, st) {
      LoggerService.warning(
        'HealthMessageHandler: check "$name" lancou excecao: $e',
        e,
        st,
      );
      return false; // fail-closed
    }
  }
}

class _HealthSnapshot {
  _HealthSnapshot({
    required this.status,
    required this.checks,
    this.message,
    this.stagingUsageBytes,
    this.stagingUsageWarnThresholdBytes,
    this.stagingUsageBlockThresholdBytes,
    this.stagingUsageLevel,
  });

  final ServerHealthStatus status;
  final Map<String, bool> checks;
  final String? message;
  final int? stagingUsageBytes;
  final int? stagingUsageWarnThresholdBytes;
  final int? stagingUsageBlockThresholdBytes;
  final String? stagingUsageLevel;
}
