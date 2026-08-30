import 'package:backup_database/application/dtos/remote/queued_execution_view.dart';
import 'package:backup_database/application/dtos/remote/remote_db_kind.dart';
import 'package:backup_database/application/dtos/remote/remote_preflight_view.dart';
import 'package:backup_database/application/dtos/remote/run_diagnostics_view.dart';
import 'package:backup_database/infrastructure/protocol/database_config_messages.dart';
import 'package:backup_database/infrastructure/protocol/diagnostics_messages.dart';
import 'package:backup_database/infrastructure/protocol/execution_queue_messages.dart';
import 'package:backup_database/infrastructure/protocol/preflight_messages.dart';

RemoteDatabaseType remoteDbKindToProtocol(RemoteDbKind kind) {
  return RemoteDatabaseType.fromWire(kind.wireName) ??
      RemoteDatabaseType.sybase;
}

RemoteDbKind remoteDbKindFromProtocol(RemoteDatabaseType type) {
  return RemoteDbKind.fromWire(type.wireName) ?? RemoteDbKind.sybase;
}

QueuedExecutionView queuedExecutionViewFromProtocol(QueuedExecution item) {
  return QueuedExecutionView(
    runId: item.runId,
    scheduleId: item.scheduleId,
    queuedPosition: item.queuedPosition,
    queuedAt: item.queuedAt,
    requestedBy: item.requestedBy,
  );
}

RemotePreflightView remotePreflightViewFromProtocol(PreflightResult result) {
  return RemotePreflightView(
    status: switch (result.status) {
      PreflightStatus.passed => RemotePreflightStatus.passed,
      PreflightStatus.passedWithWarnings =>
        RemotePreflightStatus.passedWithWarnings,
      PreflightStatus.blocked => RemotePreflightStatus.blocked,
    },
    checks: result.checks
        .map(
          (check) => RemotePreflightCheckView(
            name: check.name,
            passed: check.passed,
            severity: switch (check.severity) {
              PreflightSeverity.blocking => RemotePreflightSeverity.blocking,
              PreflightSeverity.warning => RemotePreflightSeverity.warning,
              PreflightSeverity.info => RemotePreflightSeverity.info,
            },
            message: check.message,
          ),
        )
        .toList(),
    serverTimeUtc: result.serverTimeUtc,
    message: result.message,
  );
}

RunDiagnosticsLogsView runDiagnosticsLogsFromProtocol(RunLogsResult result) {
  return RunDiagnosticsLogsView(
    runId: result.runId,
    lines: List<String>.from(result.lines),
    truncated: result.truncated,
    totalLines: result.totalLines,
  );
}

RunDiagnosticsErrorView runDiagnosticsErrorFromProtocol(
  RunErrorDetailsResult result,
) {
  return RunDiagnosticsErrorView(
    runId: result.runId,
    found: result.found,
    errorMessage: result.errorMessage,
    errorCode: result.errorCode?.code,
    errorCodeMessage: result.errorCode?.defaultMessage,
    stackTrace: result.stackTrace,
    context: result.context == null
        ? null
        : Map<String, dynamic>.from(result.context!),
  );
}
