import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_history.dart';
import 'package:backup_database/domain/entities/backup_log.dart';
import 'package:backup_database/domain/repositories/i_backup_history_repository.dart';
import 'package:backup_database/domain/repositories/i_backup_log_repository.dart';
import 'package:backup_database/infrastructure/protocol/error_codes.dart';
import 'package:backup_database/infrastructure/socket/server/diagnostics_provider.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;

/// Implementacao concreta de [DiagnosticsProvider] que reusa
/// `BackupHistoryRepository`, `BackupLogRepository` e o filesystem
/// de staging existente.
///
/// **Best-effort v1**: hoje BackupHistory ainda usa `scheduleId` (nao
/// tem coluna `runId` formal — pendente F2.18). O resolver extrai
/// `scheduleId` do formato `runId = <scheduleId>_<uuid>` e busca o
/// historico mais recente dessa schedule. Em PR-3 commit 5
/// (persistencia da fila + runId formal), substituir lookup por
/// query direta `getByRunId(runId)`.
///
/// Limitacoes documentadas:
/// - Se houver multiplas execucoes concorrentes do mesmo `scheduleId`
///   (cenario impossivel hoje pelo mutex global, mas planejado em
///   futuro), o lookup pode retornar a errada.
/// - `runId` que nao siga o formato `<scheduleId>_<uuid>` cai em
///   `notFound` mesmo se o backup existir.
class RealDiagnosticsProvider implements DiagnosticsProvider {
  RealDiagnosticsProvider({
    required this.historyRepository,
    required this.logRepository,
    required this.stagingBasePath,
    String hashAlgorithm = 'sha256',
  })  : _hashAlgorithm = hashAlgorithm,
        _stagingBase = p.normalize(p.absolute(stagingBasePath));

  final IBackupHistoryRepository historyRepository;
  final IBackupLogRepository logRepository;
  final String stagingBasePath;
  final String _stagingBase;
  final String _hashAlgorithm;

  /// Extrai `scheduleId` do `runId` no formato `<scheduleId>_<uuid>`.
  /// Retorna `null` para formatos nao reconhecidos. Defensivo: NAO
  /// confia no `runId` recebido sem validar.
  String? _scheduleIdFromRunId(String runId) {
    if (runId.isEmpty) return null;
    final lastUnderscore = runId.lastIndexOf('_');
    // UUID v4 tem 36 chars; aceita qualquer suffix com pelo menos
    // 32 chars (alguns geradores omitem hyphens) para flexibilidade.
    if (lastUnderscore < 1) return null;
    final suffix = runId.substring(lastUnderscore + 1);
    if (suffix.length < 32) return null;
    return runId.substring(0, lastUnderscore);
  }

  @override
  Future<DiagnosticsOutcome<RunLogsData>> getRunLogs(
    String runId, {
    int? maxLines,
  }) async {
    try {
      final history = await _findHistory(runId);
      if (history == null) {
        return DiagnosticsOutcome<RunLogsData>.notFound();
      }
      final logsResult = await logRepository.getByBackupHistory(history.id);
      if (logsResult.isError()) {
        return DiagnosticsOutcome<RunLogsData>.failure(
          error:
              'Falha ao buscar logs: ${logsResult.exceptionOrNull() ?? "desconhecido"}',
          errorCode: ErrorCode.unknown,
        );
      }
      final logs = logsResult.getOrNull() ?? const [];
      final lines = logs
          .map(
            (l) => '[${l.createdAt.toUtc().toIso8601String()}] '
                '[${l.level.name.toUpperCase()}] '
                '[${l.category.name}] ${l.message}'
                '${l.details != null ? " | ${l.details}" : ""}',
          )
          .toList(growable: false);
      final truncated = maxLines != null && lines.length > maxLines;
      final clipped = truncated ? lines.sublist(lines.length - maxLines) : lines;
      return DiagnosticsOutcome<RunLogsData>.found(
        RunLogsData(lines: clipped, truncated: truncated),
      );
    } on Object catch (e, st) {
      LoggerService.warning('RealDiagnosticsProvider.getRunLogs: $e', e, st);
      return DiagnosticsOutcome<RunLogsData>.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DiagnosticsOutcome<RunErrorData>> getRunErrorDetails(String runId) async {
    try {
      final history = await _findHistory(runId);
      if (history == null) {
        return DiagnosticsOutcome<RunErrorData>.notFound();
      }
      // Sem erro registrado: history existe mas backup terminou OK.
      // Convencao: retornamos notFound para sinalizar "nada a reportar".
      if (history.status == BackupStatus.success ||
          history.errorMessage == null ||
          history.errorMessage!.isEmpty) {
        return DiagnosticsOutcome<RunErrorData>.notFound();
      }
      // Buscamos o ultimo log de error/warning para capturar context
      // adicional (stack trace pode estar em `details`).
      final logsResult = await logRepository.getByBackupHistory(history.id);
      String? stackTrace;
      Map<String, dynamic>? context;
      if (!logsResult.isError()) {
        final logs = logsResult.getOrNull() ?? const [];
        for (final log in logs.reversed) {
          if (log.level == LogLevel.error || log.level == LogLevel.warning) {
            stackTrace = log.details;
            context = <String, dynamic>{
              'logCategory': log.category.name,
              'logMessage': log.message,
              'logTimestamp': log.createdAt.toUtc().toIso8601String(),
            };
            break;
          }
        }
      }
      return DiagnosticsOutcome<RunErrorData>.found(
        RunErrorData(
          errorMessage: history.errorMessage,
          // Sem mapping confiavel BackupHistory -> ErrorCode em v1;
          // protocolo aceita null e cliente trata como "unknown".
          stackTrace: stackTrace,
          context: context,
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning('RealDiagnosticsProvider.getRunErrorDetails: $e', e, st);
      return DiagnosticsOutcome<RunErrorData>.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DiagnosticsOutcome<ArtifactMetadataData>> getArtifactMetadata(
    String runId,
  ) async {
    try {
      final scheduleId = _scheduleIdFromRunId(runId);
      if (scheduleId == null) {
        return DiagnosticsOutcome<ArtifactMetadataData>.notFound();
      }
      final scheduleDir = Directory(p.join(_stagingBase, 'remote', scheduleId));
      if (!await scheduleDir.exists()) {
        return DiagnosticsOutcome<ArtifactMetadataData>.notFound();
      }

      // Pega o arquivo regular mais recente. Em v2 (staging por runId),
      // sera lookup direto por path conhecido.
      File? newest;
      DateTime? newestModified;
      await for (final entity in scheduleDir.list(followLinks: false)) {
        if (entity is File) {
          final modified = await entity.lastModified();
          if (newestModified == null || modified.isAfter(newestModified)) {
            newest = entity;
            newestModified = modified;
          }
        }
      }
      if (newest == null) {
        return DiagnosticsOutcome<ArtifactMetadataData>.notFound();
      }

      final size = await newest.length();
      final hashValue = await _hashFile(newest);
      // Path retornado e RELATIVO ao staging base (sem expor caminho
      // absoluto do servidor — pequena defesa de seguranca).
      final relativePath = p
          .relative(newest.path, from: _stagingBase)
          .replaceAll(r'\', '/');

      return DiagnosticsOutcome<ArtifactMetadataData>.found(
        ArtifactMetadataData(
          sizeBytes: size,
          hashAlgorithm: _hashAlgorithm,
          hashValue: hashValue,
          stagingPath: relativePath,
          // TTL ainda nao implementado (PR-4). Por enquanto omitimos.
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning('RealDiagnosticsProvider.getArtifactMetadata: $e', e, st);
      return DiagnosticsOutcome<ArtifactMetadataData>.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.unknown,
      );
    }
  }

  @override
  Future<DiagnosticsOutcome<CleanupStagingData>> cleanupStaging(String runId) async {
    try {
      final scheduleId = _scheduleIdFromRunId(runId);
      if (scheduleId == null) {
        return DiagnosticsOutcome<CleanupStagingData>.found(
          const CleanupStagingData(cleaned: false, message: 'runId invalido'),
        );
      }
      final scheduleDir = Directory(p.join(_stagingBase, 'remote', scheduleId));
      if (!await scheduleDir.exists()) {
        // Nada a limpar nao e erro — cliente recebe cleaned=false +
        // message claro. Idempotency natural.
        return DiagnosticsOutcome<CleanupStagingData>.found(
          const CleanupStagingData(
            cleaned: false,
            bytesFreed: 0,
            message: 'Diretorio de staging ja inexistente',
          ),
        );
      }

      // Calcula tamanho ANTES de deletar para reportar bytesFreed.
      var totalBytes = 0;
      await for (final entity in scheduleDir.list(
        recursive: true,
        followLinks: false,
      )) {
        if (entity is File) {
          totalBytes += await entity.length();
        }
      }

      await scheduleDir.delete(recursive: true);

      return DiagnosticsOutcome<CleanupStagingData>.found(
        CleanupStagingData(
          cleaned: true,
          bytesFreed: totalBytes,
          message: 'Limpeza concluida ($totalBytes bytes liberados)',
        ),
      );
    } on Object catch (e, st) {
      LoggerService.warning('RealDiagnosticsProvider.cleanupStaging: $e', e, st);
      return DiagnosticsOutcome<CleanupStagingData>.failure(
        error: 'Erro inesperado: $e',
        errorCode: ErrorCode.ioError,
      );
    }
  }

  /// Resolve o `BackupHistory` correspondente ao `runId`. Em v1 faz
  /// match por `scheduleId` extraido do formato `<scheduleId>_<uuid>`
  /// e pega o historico mais recente. Em v2 substituir por query
  /// direta quando coluna `runId` for adicionada.
  Future<BackupHistory?> _findHistory(String runId) async {
    final scheduleId = _scheduleIdFromRunId(runId);
    if (scheduleId == null) return null;
    final result = await historyRepository.getLastBySchedule(scheduleId);
    if (result.isError()) return null;
    return result.getOrNull();
  }

  /// Calcula hash do arquivo de forma incremental (streaming via
  /// `bind` no conversor) para nao carregar todos os bytes em memoria.
  /// Suporta arquivos de qualquer tamanho.
  Future<String> _hashFile(File file) async {
    final digest = await sha256.bind(file.openRead()).first;
    return digest.toString();
  }
}
