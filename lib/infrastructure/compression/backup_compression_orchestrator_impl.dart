import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:backup_database/core/errors/failure.dart' as core_errors;
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
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

      // **Importante**: `deleteOriginal: false` aqui. Antes era `true`
      // e o backup bruto era removido antes de qualquer validação do
      // arquivo comprimido. Se o ZIP/RAR ficasse corrompido mas passasse
      // checagens mínimas dentro do `CompressionService`, o backup
      // original era perdido sem cópia de recuperação. Agora validamos
      // o artefato comprimido (tamanho > 0 + parse de ZIP quando
      // aplicável) e só então removemos o original.
      final compressionResult = await _compressionService.compress(
        path: backupPath,
        outputPath: compressionOutputPath,
        deleteOriginal: false,
        format: format,
      );

      if (compressionResult.isError()) {
        final failure = compressionResult.exceptionOrNull()!;
        final failureMessage = core_errors.failureUserMessage(failure);

        LoggerService.error('Falha na compressão: $failureMessage', failure);

        return Failure(
          core_errors.BackupCompressionFailure(
            message: 'Erro ao comprimir backup: $failureMessage',
            originalError: failure,
          ),
        );
      }

      final result = compressionResult.getOrNull()!;

      // Validação pós-compressão: garante que o artefato existe e está
      // íntegro antes de comprometer o backup bruto.
      final validation = await _validateCompressedArtifact(
        result.compressedPath,
        format,
      );
      if (validation != null) {
        // ZIP corrompido — apaga o lixo, preserva o original.
        await BackupArtifactUtils.safeDeletePartial(result.compressedPath);
        LoggerService.error(
          'Validação pós-compressão falhou: $validation. '
          'Arquivo comprimido removido; original preservado em $backupPath',
        );
        return Failure(
          core_errors.BackupCompressionFailure(
            message:
                'Validação do arquivo comprimido falhou: $validation. '
                'O backup original foi preservado em "$backupPath".',
          ),
        );
      }

      // Agora sim é seguro remover o original.
      await BackupArtifactUtils.safeDeletePartial(backupPath);

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
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro inesperado durante compressão', e, stackTrace);

      final friendly = e is core_errors.Failure ? e.message : e.toString();
      return Failure(
        core_errors.BackupCompressionFailure(
          message:
              'Erro ao comprimir backup: $friendly. '
              'Verifique permissões da pasta de destino.',
          originalError: e,
        ),
      );
    }
  }

  /// Valida o artefato comprimido. Retorna `null` se OK ou uma mensagem
  /// de erro caso o arquivo esteja corrompido / faltando / vazio.
  ///
  /// Para `.zip`: tenta abrir e contar entradas com `ZipDecoder`.
  /// Para `.rar`: apenas valida existência + tamanho mínimo (não há
  /// decoder RAR puro em Dart; validação completa exigiria invocar o
  /// próprio WinRAR de novo).
  Future<String?> _validateCompressedArtifact(
    String compressedPath,
    CompressionFormat format,
  ) async {
    final file = File(compressedPath);
    if (!await file.exists()) {
      return 'arquivo comprimido não encontrado em $compressedPath';
    }
    final size = await file.length();
    if (size <= 0) {
      return 'arquivo comprimido com 0 bytes';
    }

    if (format == CompressionFormat.zip) {
      try {
        final bytes = await file.readAsBytes();
        final archive = ZipDecoder().decodeBytes(bytes, verify: true);
        if (archive.files.isEmpty) {
          return 'ZIP válido mas sem entradas (vazio)';
        }
        return null;
      } on Object catch (e) {
        return 'ZIP corrompido: $e';
      }
    }
    // RAR: validação best-effort de tamanho. Sem decoder RAR em Dart,
    // dependemos do exit code do WinRAR já checado pelo service.
    return null;
  }
}
