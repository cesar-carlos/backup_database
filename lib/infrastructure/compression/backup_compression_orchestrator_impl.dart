import 'package:backup_database/core/errors/failure.dart' as core_errors;
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/compression_format.dart';
import 'package:backup_database/domain/entities/schedule.dart';
import 'package:backup_database/domain/services/compression_result.dart';
import 'package:backup_database/domain/services/i_backup_compression_orchestrator.dart';
import 'package:backup_database/domain/services/i_backup_progress_notifier.dart';
import 'package:backup_database/domain/services/i_compression_service.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart';

/// Implementation of [IBackupCompressionOrchestrator].
class BackupCompressionOrchestratorImpl
    implements IBackupCompressionOrchestrator {
  const BackupCompressionOrchestratorImpl({
    required ICompressionService compressionService,
  }) : _compressionService = compressionService;

  final ICompressionService _compressionService;

  @override
  Future<Result<CompressionResult>> compressBackup({
    required String backupPath,
    required CompressionFormat format,
    required DatabaseType databaseType,
    required BackupType backupType,
    IBackupProgressNotifier? progressNotifier,
  }) async {
    LoggerService.info('Iniciando compressão: $backupPath');

    try {
      progressNotifier?.updateProgress(
        step: 'Compactando',
        message: 'Comprimindo arquivo de backup...',
        progress: 0.6,
      );
    } on Object catch (e, s) {
      LoggerService.warning('Erro ao atualizar progresso', e, s);
    }

    try {
      String? compressionOutputPath;

      // Special naming for Sybase full backups
      if (databaseType == DatabaseType.sybase &&
          backupType == BackupType.full) {
        final ts = DateTime.now().toIso8601String().replaceAll(':', '-');
        final baseName = p.basename(backupPath);
        final extension = format == CompressionFormat.rar ? '.rar' : '.zip';
        compressionOutputPath = p.join(
          p.dirname(backupPath),
          '${baseName}_${backupType.name}_$ts$extension',
        );
      }

      final compressionResult = await _compressionService.compress(
        path: backupPath,
        outputPath: compressionOutputPath,
        deleteOriginal: true,
        format: format,
      );

      if (compressionResult.isSuccess()) {
        final result = compressionResult.getOrNull()!;
        LoggerService.info('Compressão concluída: ${result.compressedPath}');

        try {
          progressNotifier?.updateProgress(
            step: 'Compactando',
            message: 'Compressão concluída',
            progress: 0.8,
          );
        } on Object catch (e, s) {
          LoggerService.warning('Erro ao atualizar progresso', e, s);
        }

        return Success(result);
      } else {
        final failure = compressionResult.exceptionOrNull()!;
        final failureMessage = failure.toString();

        LoggerService.error('Falha na compressão: $failureMessage', failure);

        return Failure(
          core_errors.BackupCompressionFailure(
            message:
                'Erro ao comprimir backup. Verifique permissões da pasta de destino.',
            originalError: failure,
          ),
        );
      }
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro inesperado durante compressão', e, stackTrace);

      return Failure(
        core_errors.BackupCompressionFailure(
          message:
              'Erro ao comprimir backup: $e. Verifique permissões da pasta de destino.',
          originalError: e,
        ),
      );
    }
  }
}
