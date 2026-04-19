import 'package:backup_database/infrastructure/protocol/error_codes.dart';

/// Resultado opaco de uma operacao de diagnostico.
class DiagnosticsOutcome<T> {
  const DiagnosticsOutcome({
    required this.success,
    this.data,
    this.error,
    this.errorCode,
  });

  factory DiagnosticsOutcome.found(T data) =>
      DiagnosticsOutcome(success: true, data: data);

  factory DiagnosticsOutcome.notFound() => const DiagnosticsOutcome(
        success: false,
        errorCode: ErrorCode.fileNotFound,
        error: 'Recurso nao encontrado',
      );

  factory DiagnosticsOutcome.failure({
    required String error,
    required ErrorCode errorCode,
  }) =>
      DiagnosticsOutcome(
        success: false,
        error: error,
        errorCode: errorCode,
      );

  final bool success;
  final T? data;
  final String? error;
  final ErrorCode? errorCode;
}

/// Dados de logs por runId.
class RunLogsData {
  const RunLogsData({
    required this.lines,
    this.truncated = false,
  });
  final List<String> lines;
  final bool truncated;
}

/// Dados de erro por runId.
class RunErrorData {
  const RunErrorData({
    this.errorMessage,
    this.errorCode,
    this.stackTrace,
    this.context,
  });
  final String? errorMessage;
  final ErrorCode? errorCode;
  final String? stackTrace;
  final Map<String, dynamic>? context;
}

/// Dados de metadata de artefato.
class ArtifactMetadataData {
  const ArtifactMetadataData({
    this.sizeBytes,
    this.hashAlgorithm,
    this.hashValue,
    this.stagingPath,
    this.expiresAt,
  });
  final int? sizeBytes;
  final String? hashAlgorithm;
  final String? hashValue;
  final String? stagingPath;
  final DateTime? expiresAt;
}

/// Resultado de cleanup de staging.
class CleanupStagingData {
  const CleanupStagingData({
    required this.cleaned,
    this.bytesFreed,
    this.message,
  });
  final bool cleaned;
  final int? bytesFreed;
  final String? message;
}

/// Provider de diagnostico operacional (PR-3 commit final).
///
/// Decoupla o handler de socket dos repositorios concretos de logs,
/// staging e metadata. Wiring concreto em PR de DI separado — handler
/// usa apenas a interface.
abstract class DiagnosticsProvider {
  Future<DiagnosticsOutcome<RunLogsData>> getRunLogs(
    String runId, {
    int? maxLines,
  });
  Future<DiagnosticsOutcome<RunErrorData>> getRunErrorDetails(String runId);
  Future<DiagnosticsOutcome<ArtifactMetadataData>> getArtifactMetadata(
    String runId,
  );
  Future<DiagnosticsOutcome<CleanupStagingData>> cleanupStaging(String runId);
}

/// Stub default — retorna `notFound` em tudo. Producao substitui via
/// DI por implementacao real que consulta `BackupLogRepository`,
/// `TransferStagingService` etc.
class NotConfiguredDiagnosticsProvider implements DiagnosticsProvider {
  const NotConfiguredDiagnosticsProvider();

  @override
  Future<DiagnosticsOutcome<RunLogsData>> getRunLogs(
    String runId, {
    int? maxLines,
  }) async =>
      DiagnosticsOutcome<RunLogsData>.notFound();

  @override
  Future<DiagnosticsOutcome<RunErrorData>> getRunErrorDetails(String runId) async =>
      DiagnosticsOutcome<RunErrorData>.notFound();

  @override
  Future<DiagnosticsOutcome<ArtifactMetadataData>> getArtifactMetadata(
    String runId,
  ) async =>
      DiagnosticsOutcome<ArtifactMetadataData>.notFound();

  @override
  Future<DiagnosticsOutcome<CleanupStagingData>> cleanupStaging(
    String runId,
  ) async =>
      DiagnosticsOutcome<CleanupStagingData>.notFound();
}
