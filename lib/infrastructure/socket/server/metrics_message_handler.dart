import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_schedule_repository.dart';
import 'package:backup_database/domain/services/i_backup_running_state.dart';
import 'package:backup_database/domain/services/i_metrics_collector.dart';
import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:backup_database/infrastructure/protocol/metrics_messages.dart';
import 'package:backup_database/infrastructure/protocol/schedule_messages.dart';
import 'package:backup_database/infrastructure/socket/server/remote_execution_registry.dart'
    show RemoteExecutionRegistry, SendToClient;

class MetricsMessageHandler {
  MetricsMessageHandler({
    required IBackupHistoryRepository backupHistoryRepository,
    required IScheduleRepository scheduleRepository,
    required IBackupRunningState backupRunningState,
    IMetricsCollector? metricsCollector,
    RemoteExecutionRegistry? executionRegistry,
    Future<int> Function()? stagingUsageBytesProvider,
    DateTime Function()? clock,
  })  : _backupHistoryRepository = backupHistoryRepository,
        _scheduleRepository = scheduleRepository,
        _backupRunningState = backupRunningState,
        _metricsCollector = metricsCollector,
        _executionRegistry = executionRegistry,
        _stagingUsageBytesProvider = stagingUsageBytesProvider,
        _clock = clock ?? DateTime.now;

  final IBackupHistoryRepository _backupHistoryRepository;
  final IScheduleRepository _scheduleRepository;
  final IBackupRunningState _backupRunningState;
  final IMetricsCollector? _metricsCollector;

  /// Quando injetado, permite expor `activeRunId`/`activeRunCount` no
  /// payload de metricas — campos operacionais do M5.3/M7.1 do plano.
  /// Optional para preservar compat com testes/wiring antigos.
  final RemoteExecutionRegistry? _executionRegistry;

  /// Provider assincrono que retorna o uso atual em bytes do diretorio
  /// de staging. Quando ausente, o campo nao e publicado (null-safe).
  /// Use `StagingUsageMeasurer.measure` (em
  /// `lib/infrastructure/utils/staging_usage_measurer.dart`) como
  /// implementacao padrao.
  final Future<int> Function()? _stagingUsageBytesProvider;

  /// Relogio injetavel para `serverTimeUtc`. Em producao usa
  /// `DateTime.now`; testes podem cravar valor para validar wire format.
  final DateTime Function() _clock;

  Future<void> handle(
    String clientId,
    Message message,
    SendToClient sendToClient,
  ) async {
    if (!isMetricsRequestMessage(message)) return;

    final requestId = message.header.requestId;

    try {
      final payload = await _buildMetricsPayload();
      await sendToClient(
        clientId,
        createMetricsResponseMessage(
          requestId: requestId,
          payload: payload,
        ),
      );
    } on Object catch (e) {
      await sendToClient(
        clientId,
        createScheduleErrorMessage(
          requestId: requestId,
          error: e.toString(),
        ),
      );
    }
  }

  Future<Map<String, dynamic>> _buildMetricsPayload() async {
    final now = _clock();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    var totalBackups = 0;
    var backupsToday = 0;
    var failedToday = 0;
    var activeSchedules = 0;
    var recentBackups = <Map<String, dynamic>>[];

    final allResult = await _backupHistoryRepository.getAll(limit: 1000);
    allResult.fold(
      (list) => totalBackups = list.length,
      (_) {},
    );

    final todayResult = await _backupHistoryRepository.getByDateRange(
      startOfDay,
      endOfDay,
    );
    todayResult.fold(
      (list) {
        backupsToday = list.length;
        failedToday = list.where((b) => b.status == BackupStatus.error).length;
      },
      (_) {},
    );

    final schedulesResult = await _scheduleRepository.getEnabled();
    schedulesResult.fold(
      (list) => activeSchedules = list.length,
      (_) {},
    );

    final recentResult = await _backupHistoryRepository.getAll(limit: 10);
    recentResult.fold(
      (list) {
        recentBackups = list.map(_backupHistoryToMap).toList();
      },
      (_) {},
    );

    final payload = <String, dynamic>{
      'totalBackups': totalBackups,
      'backupsToday': backupsToday,
      'failedToday': failedToday,
      'activeSchedules': activeSchedules,
      'recentBackups': recentBackups,
      'backupInProgress': _backupRunningState.isRunning,
      // Sempre publicado: permite cliente detectar drift de relogio e
      // calcular `serverTimeUtc - clientTimeUtc` para timeouts (M7.1).
      'serverTimeUtc': now.toUtc().toIso8601String(),
    };

    final metricsSnapshot = _metricsCollector?.getSnapshot();
    if (metricsSnapshot != null && metricsSnapshot.isNotEmpty) {
      payload['observability'] = metricsSnapshot;
    }
    if (_backupRunningState.isRunning &&
        _backupRunningState.currentBackupName != null) {
      payload['backupScheduleName'] = _backupRunningState.currentBackupName;
    }

    // Campos operacionais do registry remoto (M2.1 + M5.3). Quando ha
    // execucao remota em curso, `activeRunId` carrega o identificador
    // atual — cliente pode fazer `getExecutionStatus(runId)` para
    // detalhes (PR-2). `activeRunCount` permite detectar discrepancia
    // entre `backupInProgress` (estado local) e o registry (estado
    // remoto), util em PR-3b com fila.
    if (_executionRegistry != null) {
      payload['activeRunCount'] = _executionRegistry.activeCount;
      // Hoje so existe 0 ou 1 runId ativo; futuramente com fila pode
      // virar lista. Mantemos o campo como string singleton para nao
      // quebrar contrato — fila aparece em endpoint dedicado
      // (`getExecutionQueue`, PR-3b).
      if (_executionRegistry.activeCount == 1) {
        payload['activeRunId'] = _executionRegistry.all.first.runId;
      }
    }

    // Uso de disco do staging remoto (M5.3 + M7.1). Apenas publicado
    // quando o provider e injetado para preservar compat com wiring
    // antigo. Erros do measurer ja sao convertidos em 0/parcial pelo
    // proprio helper, entao aqui nao ha try/catch extra necessario.
    if (_stagingUsageBytesProvider != null) {
      payload['stagingUsageBytes'] = await _stagingUsageBytesProvider();
    }

    return payload;
  }

  Map<String, dynamic> _backupHistoryToMap(BackupHistory h) {
    return <String, dynamic>{
      'id': h.id,
      'scheduleId': h.scheduleId,
      'databaseName': h.databaseName,
      'databaseType': h.databaseType,
      'backupPath': h.backupPath,
      'fileSize': h.fileSize,
      'status': h.status.name,
      'startedAt': h.startedAt.toIso8601String(),
      'finishedAt': h.finishedAt?.toIso8601String(),
      'errorMessage': h.errorMessage,
    };
  }
}
