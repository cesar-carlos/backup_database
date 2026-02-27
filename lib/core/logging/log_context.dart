/// Contexto de execução para correlação de logs estruturados.
///
/// Permite associar runId e scheduleId a todas as mensagens de log
/// durante uma execução de backup.
class LogContext {
  LogContext._();

  static String? _runId;
  static String? _scheduleId;

  static String? get runId => _runId;
  static String? get scheduleId => _scheduleId;

  static bool get hasContext => _runId != null || _scheduleId != null;

  static void setContext({String? runId, String? scheduleId}) {
    _runId = runId;
    _scheduleId = scheduleId;
  }

  static void clearContext() {
    _runId = null;
    _scheduleId = null;
  }

  static String buildStructuredPrefix() {
    final parts = <String>[];
    if (_runId != null) parts.add('runId=$_runId');
    if (_scheduleId != null) parts.add('scheduleId=$_scheduleId');
    if (parts.isEmpty) return '';
    return '${parts.map((p) => '[$p]').join()} ';
  }
}
