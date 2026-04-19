import 'package:backup_database/infrastructure/protocol/message.dart';
import 'package:uuid/uuid.dart';

/// Funcao de envio de mensagem ao cliente que originou a execucao.
/// Mantida no contexto para que listeners de progresso encaminhem eventos
/// para o cliente correto sem depender de estado global no handler.
typedef SendToClient = Future<void> Function(String clientId, Message message);

/// Contexto imutavel de uma execucao remota em curso.
///
/// Substitui os campos singleton `_currentClientId/_currentRequestId/
/// _currentScheduleId/_sendToClient` que existiam em `ScheduleMessageHandler`
/// e que corrompiam estado quando dois clientes disparavam schedules
/// diferentes ao mesmo tempo (mesmo com `tryStartBackup` rejeitando o
/// segundo, havia janela TOCTOU em que os campos eram sobrescritos
/// antes da rejeicao).
class RemoteExecutionContext {
  RemoteExecutionContext({
    required this.runId,
    required this.scheduleId,
    required this.clientId,
    required this.requestId,
    required this.sendToClient,
    DateTime? startedAt,
  }) : startedAt = startedAt ?? DateTime.now();

  /// Identificador unico desta execucao remota (`<scheduleId>_<uuid>`).
  /// Mantem o mesmo formato gerado em `SchedulerService._executeScheduledBackup`
  /// para que logs e telemetria continuem correlacionados.
  final String runId;

  /// Schedule alvo desta execucao. Usado para indexacao secundaria no
  /// registry (suporta `cancelSchedule` por `scheduleId` enquanto o
  /// contrato remoto nao expor `runId` diretamente).
  final String scheduleId;

  /// Cliente que disparou a execucao. Eventos de progresso/erro/conclusao
  /// devem ser enviados apenas para este `clientId`.
  final String clientId;

  /// `requestId` do envelope de transporte que iniciou a execucao.
  /// Usado para correlacionar respostas no cliente.
  final int requestId;

  /// Callback para envio de mensagens ao cliente correto. Capturado no
  /// momento do registro para evitar que mudancas no estado do handler
  /// afetem entregas em curso.
  final SendToClient sendToClient;

  final DateTime startedAt;
}

/// Registry de execucoes remotas em curso, indexado por `runId`.
///
/// Hoje, com `maxConcurrentBackups = 1` aplicado pelo `SchedulerService`,
/// existira no maximo 1 contexto ativo por vez. A estrutura e desenhada
/// pensando na fila futura (PR-3b) para suportar multiplos `runId` em
/// `queued` + 1 em `running` sem reescrita.
///
/// Indexacao secundaria por `scheduleId` existe apenas como ponte para
/// o contrato remoto atual, que cancela por `scheduleId`. Quando o
/// contrato passar a expor `runId` (PR-2 / M2.3), `getActiveByScheduleId`
/// pode ser deprecado.
class RemoteExecutionRegistry {
  RemoteExecutionRegistry({Uuid? uuid}) : _uuid = uuid ?? const Uuid();

  final Uuid _uuid;
  final Map<String, RemoteExecutionContext> _byRunId = {};
  final Map<String, String> _scheduleToRunId = {};

  /// Gera um novo `runId` no mesmo formato usado pelo `SchedulerService`
  /// para manter correlacao end-to-end com logs e telemetria existentes.
  String generateRunId(String scheduleId) =>
      '${scheduleId}_${_uuid.v4()}';

  /// Numero de execucoes ativas. Hoje sempre 0 ou 1; preparado para
  /// fila futura (PR-3b).
  int get activeCount => _byRunId.length;

  /// Lista todos os contextos ativos. Util para `_onProgressChanged`
  /// iterar e entregar eventos a todos os clientes interessados (hoje
  /// no maximo 1; preparado para multiplos quando houver fila + multi-execucao).
  Iterable<RemoteExecutionContext> get all => _byRunId.values;

  bool get hasAny => _byRunId.isNotEmpty;

  /// Registra uma nova execucao em curso.
  ///
  /// Lanca [StateError] se ja existir execucao com o mesmo `runId` (bug
  /// de geracao) ou se ja existir execucao em curso para o mesmo
  /// `scheduleId` (deveria ter sido bloqueada antes pelo mutex global
  /// do scheduler — chegar aqui e bug logico).
  RemoteExecutionContext register({
    required String runId,
    required String scheduleId,
    required String clientId,
    required int requestId,
    required SendToClient sendToClient,
  }) {
    if (_byRunId.containsKey(runId)) {
      throw StateError(
        'RemoteExecutionRegistry: runId ja registrado: $runId',
      );
    }
    if (_scheduleToRunId.containsKey(scheduleId)) {
      throw StateError(
        'RemoteExecutionRegistry: scheduleId ja em execucao: $scheduleId '
        '(runId atual: ${_scheduleToRunId[scheduleId]})',
      );
    }
    final context = RemoteExecutionContext(
      runId: runId,
      scheduleId: scheduleId,
      clientId: clientId,
      requestId: requestId,
      sendToClient: sendToClient,
    );
    _byRunId[runId] = context;
    _scheduleToRunId[scheduleId] = runId;
    return context;
  }

  RemoteExecutionContext? getByRunId(String runId) => _byRunId[runId];

  /// Retorna o contexto ativo associado a `scheduleId`, se houver.
  /// Ponte para o contrato remoto atual que cancela por `scheduleId`.
  RemoteExecutionContext? getActiveByScheduleId(String scheduleId) {
    final runId = _scheduleToRunId[scheduleId];
    if (runId == null) return null;
    return _byRunId[runId];
  }

  bool hasActiveForSchedule(String scheduleId) =>
      _scheduleToRunId.containsKey(scheduleId);

  /// Remove a execucao identificada por `runId` (e seu indice secundario).
  /// Idempotente: nao falha se ja foi removido.
  void unregister(String runId) {
    final context = _byRunId.remove(runId);
    if (context != null) {
      _scheduleToRunId.remove(context.scheduleId);
    }
  }

  /// Remove todas as execucoes (usado em `dispose` / shutdown).
  void clear() {
    _byRunId.clear();
    _scheduleToRunId.clear();
  }
}
