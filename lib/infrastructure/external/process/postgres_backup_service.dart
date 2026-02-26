import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/postgres_wal_slot_utils.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class PostgresBackupService implements IPostgresBackupService {
  PostgresBackupService(this._processService);
  final ps.ProcessService _processService;
  static const String _logCompressionEnv = 'BACKUP_DATABASE_PG_LOG_COMPRESSION';
  static const String _logTimeoutSecondsEnv =
      'BACKUP_DATABASE_PG_LOG_TIMEOUT_SECONDS';

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required PostgresConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool verifyAfterBackup = false,
    String? pgBasebackupPath,
    Duration? backupTimeout,
    Duration? verifyTimeout,
  }) async {
    LoggerService.info(
      'Iniciando backup PostgreSQL: ${config.databaseValue} (Tipo: ${backupType.displayName})',
    );

    final outputDir = Directory(outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final typeSlug = backupType == BackupType.log
        ? 'log'
        : backupType == BackupType.differential
        ? 'incremental'
        : backupType == BackupType.fullSingle
        ? 'fullSingle'
        : 'full';

    final String backupPath;
    if (backupType == BackupType.fullSingle) {
      final backupFileName =
          customFileName ??
          '${config.databaseValue}_${typeSlug}_$timestamp.backup';
      backupPath = p.join(outputDirectory, backupFileName);
    } else {
      final backupDirName =
          customFileName ?? '${config.databaseValue}_${typeSlug}_$timestamp';
      backupPath = p.join(outputDirectory, backupDirName);
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }
    }

    final stopwatch = Stopwatch()..start();

    final result = await _executeBackupByType(
      config: config,
      backupType: backupType,
      backupPath: backupPath,
      outputDirectory: outputDirectory,
      pgBasebackupPath: pgBasebackupPath,
    );

    stopwatch.stop();

    return result.fold(
      (commandResult) async {
        final processResult = commandResult.processResult;
        final effectiveBackupPath = commandResult.backupPath;
        final stdout = processResult.stdout;
        final stderr = processResult.stderr;
        final outputLower = (stdout + stderr).toLowerCase();

        if (!processResult.isSuccess) {
          return _handleBackupError(
            stdout: stdout,
            stderr: stderr,
            outputLower: outputLower,
            backupType: backupType,
          );
        }

        final rd.Result<int> sizeResult;
        if (commandResult.measuredSizeBytes != null) {
          sizeResult = rd.Success(commandResult.measuredSizeBytes!);
        } else {
          sizeResult = backupType == BackupType.fullSingle
              ? await _calculateFileSize(effectiveBackupPath)
              : await _calculateBackupSize(effectiveBackupPath);
        }
        return sizeResult.fold((totalSize) async {
          if (totalSize == 0) {
            if (backupType == BackupType.log) {
              LoggerService.info(
                'Backup WAL concluido sem novos segmentos para captura.',
              );
              final duration = stopwatch.elapsed;
              final metrics = _buildPostgresMetrics(
                backupDuration: duration,
                verifyDuration: Duration.zero,
                totalSize: 0,
                backupType: backupType,
                verifyAfterBackup: false,
              );
              return rd.Success(
                BackupExecutionResult(
                  backupPath: effectiveBackupPath,
                  fileSize: 0,
                  duration: duration,
                  databaseName: config.databaseValue,
                  metrics: metrics,
                ),
              );
            }

            return rd.Failure(
              BackupFailure(
                message: 'Backup foi criado mas está vazio',
                originalError: Exception('Backup vazio'),
              ),
            );
          }

          LoggerService.info(
            'Backup PostgreSQL concluído: $effectiveBackupPath (${_formatBytes(totalSize)})',
          );

          final backupDuration = stopwatch.elapsed;
          var verifyDuration = Duration.zero;

          if (verifyAfterBackup && backupType != BackupType.log) {
            final verifyStopwatch = Stopwatch()..start();
            final verifyResult = backupType == BackupType.fullSingle
                ? await _verifyFullSingleBackup(effectiveBackupPath)
                : await _verifyBackup(effectiveBackupPath);
            verifyStopwatch.stop();
            verifyDuration = verifyStopwatch.elapsed;

            verifyResult.fold(
              (_) {
                LoggerService.info(
                  'Verificação de integridade concluída com sucesso',
                );
              },
              (failure) {
                final errorMessage = failure is Failure
                    ? failure.message
                    : failure.toString();
                LoggerService.warning(
                  'Verificação de integridade falhou: $errorMessage',
                );
              },
            );
          }

          final totalDuration = backupDuration + verifyDuration;
          final metrics = _buildPostgresMetrics(
            backupDuration: backupDuration,
            verifyDuration: verifyDuration,
            totalSize: totalSize,
            backupType: backupType,
            verifyAfterBackup: verifyAfterBackup,
          );

          return rd.Success(
            BackupExecutionResult(
              backupPath: effectiveBackupPath,
              fileSize: totalSize,
              duration: totalDuration,
              databaseName: config.databaseValue,
              metrics: metrics,
            ),
          );
        }, rd.Failure.new);
      },
      (failure) async {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        final errorLower = errorMessage.toLowerCase();

        if (_isExecutableNotFoundError(errorLower, backupType)) {
          return rd.Failure(_createExecutableNotFoundFailure(backupType));
        }

        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<_BackupCommandResult>> _executeBackupByType({
    required PostgresConfig config,
    required BackupType backupType,
    required String backupPath,
    required String outputDirectory,
    String? pgBasebackupPath,
  }) async {
    switch (backupType) {
      case BackupType.full:
        final fullResult = await _executeFullBackup(
          config: config,
          backupPath: backupPath,
          pgBasebackupPath: pgBasebackupPath,
        );
        return _withBackupPath(fullResult, backupPath);

      case BackupType.fullSingle:
        final fullSingleResult = await _executeFullSingleBackup(
          config: config,
          backupPath: backupPath,
        );
        return _withBackupPath(fullSingleResult, backupPath);

      case BackupType.differential:
        final previousBackupResult = await _findPreviousFullBackup(
          outputDirectory: outputDirectory,
          databaseName: config.databaseValue,
        );

        return previousBackupResult.fold(
          (previousBackupPath) async {
            final incrementalResult = await _executeIncrementalBackup(
              config: config,
              backupPath: backupPath,
              previousBackupPath: previousBackupPath,
              pgBasebackupPath: pgBasebackupPath,
            );
            return _withBackupPath(incrementalResult, backupPath);
          },
          (failure) async {
            final errorMessage = failure is Failure
                ? failure.message
                : failure.toString();
            LoggerService.warning(
              'Backup incremental requer backup FULL anterior. Executando FULL: $errorMessage',
            );
            final fallbackBackupPath = await _prepareFallbackFullBackupPath(
              incrementalBackupPath: backupPath,
              databaseName: config.databaseValue,
            );

            final fallbackResult = await _executeFullBackup(
              config: config,
              backupPath: fallbackBackupPath,
              pgBasebackupPath: pgBasebackupPath,
            );
            return _withBackupPath(fallbackResult, fallbackBackupPath);
          },
        );

      case BackupType.log:
        return _executeLogBackup(
          config: config,
          backupPath: backupPath,
        );

      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
      case BackupType.convertedLog:
        return const rd.Failure(
          BackupFailure(
            message:
                'PostgreSQL não suporta tipos convertidos de backup do Sybase. '
                'Use um tipo de backup nativo do PostgreSQL.',
          ),
        );
    }
  }

  Future<rd.Result<ps.ProcessResult>> _executeFullBackup({
    required PostgresConfig config,
    required String backupPath,
    String? pgBasebackupPath,
  }) async {
    final executable = pgBasebackupPath ?? 'pg_basebackup';

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-D',
      backupPath,
      '-P',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeFullSingleBackup({
    required PostgresConfig config,
    required String backupPath,
  }) async {
    const executable = 'pg_dump';

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-F',
      'c',
      '-f',
      backupPath,
      '-v',
      '--no-owner',
      '--no-privileges',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<ps.ProcessResult>> _executeIncrementalBackup({
    required PostgresConfig config,
    required String backupPath,
    required String previousBackupPath,
    String? pgBasebackupPath,
  }) async {
    final executable = pgBasebackupPath ?? 'pg_basebackup';

    final manifestPath = p.join(previousBackupPath, 'backup_manifest');
    final manifestFile = File(manifestPath);

    if (!await manifestFile.exists()) {
      return rd.Failure(
        BackupFailure(
          message:
              'Backup anterior não possui backup_manifest. '
              'Backups incrementais requerem backup FULL com manifest.',
          originalError: Exception('backup_manifest não encontrado'),
        ),
      );
    }

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '--incremental=$manifestPath',
      '-D',
      backupPath,
      '-P',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: const Duration(hours: 2),
    );
  }

  Future<rd.Result<_BackupCommandResult>> _executeLogBackup({
    required PostgresConfig config,
    required String backupPath,
  }) async {
    const executable = 'pg_receivewal';
    final useSlot = _isWalSlotEnabled();
    final existingWalFiles = await _snapshotWalFileNames(backupPath);

    final preflightResult = await _validateWalStreamingPreconditions(
      config: config,
      useSlot: useSlot,
    );
    if (preflightResult.isError()) {
      return rd.Failure(preflightResult.exceptionOrNull()!);
    }

    final endLsnResult = await _getCurrentWalLsn(config);
    if (endLsnResult.isError()) {
      return rd.Failure(endLsnResult.exceptionOrNull()!);
    }

    final endLsn = endLsnResult.getOrNull()!;
    String? replicationSlot;
    if (useSlot) {
      replicationSlot = _resolveWalSlotName(config);
      final ensureSlotResult = await _ensureWalReplicationSlot(
        config: config,
        backupPath: backupPath,
        slotName: replicationSlot,
      );
      if (ensureSlotResult.isError()) {
        return rd.Failure(ensureSlotResult.exceptionOrNull()!);
      }
    }

    final baseArguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '--directory=$backupPath',
      if (replicationSlot != null) '--slot=$replicationSlot',
      '--endpos=$endLsn',
      '--no-loop',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};
    final compressionMode = _resolveWalCompressionMode();
    final timeout = _resolveLogBackupTimeout();

    final processResult = await _runPgReceiveWalWithCompressionFallback(
      executable: executable,
      baseArguments: baseArguments,
      compressionMode: compressionMode,
      environment: environment,
      timeout: timeout,
    );

    if (processResult.isError()) {
      return rd.Failure(processResult.exceptionOrNull()!);
    }

    final result = processResult.getOrNull()!;
    if (!result.isSuccess) {
      return rd.Success(
        _BackupCommandResult(
          processResult: result,
          backupPath: backupPath,
        ),
      );
    }

    final walDeltaResult = await _calculateWalCaptureDelta(
      backupPath: backupPath,
      previousFileNames: existingWalFiles,
    );
    if (walDeltaResult.isError()) {
      return rd.Failure(walDeltaResult.exceptionOrNull()!);
    }

    final walDelta = walDeltaResult.getOrNull()!;
    final metadataResult = await _writeWalCaptureMetadata(
      backupPath: backupPath,
      endLsn: endLsn,
      capturedSegments: walDelta.capturedSegments,
      capturedBytes: walDelta.capturedBytes,
    );
    if (metadataResult.isError()) {
      return rd.Failure(metadataResult.exceptionOrNull()!);
    }

    return rd.Success(
      _BackupCommandResult(
        processResult: result,
        backupPath: backupPath,
        measuredSizeBytes: walDelta.capturedBytes,
      ),
    );
  }

  bool _isWalSlotEnabled() {
    return PostgresWalSlotUtils.isWalSlotEnabled(
      environment: Platform.environment,
    );
  }

  String _resolveWalSlotName(PostgresConfig config) {
    return PostgresWalSlotUtils.resolveWalSlotName(
      config: config,
      environment: Platform.environment,
    );
  }

  Future<rd.Result<void>> _ensureWalReplicationSlot({
    required PostgresConfig config,
    required String backupPath,
    required String slotName,
  }) async {
    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '--directory=$backupPath',
      '--slot=$slotName',
      '--create-slot',
      '--if-not-exists',
      '--no-loop',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'pg_receivewal',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(minutes: 1),
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('Replication slot WAL pronto para uso: $slotName');
          return const rd.Success(unit);
        }

        final output = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        final lower = output.toLowerCase();

        var message =
            'Nao foi possivel criar/validar replication slot "$slotName": $output';

        if (lower.contains('max_replication_slots')) {
          message =
              'Nao foi possivel criar o replication slot "$slotName": '
              'limite max_replication_slots atingido no servidor PostgreSQL.';
        } else if (lower.contains('permission denied') ||
            lower.contains('must be superuser') ||
            lower.contains('must be replication') ||
            lower.contains('not permitted')) {
          message =
              'Nao foi possivel criar o replication slot "$slotName": '
              'usuario sem permissao REPLICATION/superuser ou pg_hba.conf sem acesso de replicacao.';
        }

        return rd.Failure(
          BackupFailure(
            message: message,
            originalError: Exception(output),
          ),
        );
      },
      (failure) {
        final error = failure is Failure ? failure.message : failure.toString();
        return rd.Failure(
          BackupFailure(
            message:
                'Erro ao criar/validar replication slot para backup WAL: $error',
            originalError: failure,
          ),
        );
      },
    );
  }

  Future<rd.Result<String>> _getCurrentWalLsn(PostgresConfig config) async {
    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-t',
      '-A',
      '-c',
      'SELECT pg_current_wal_lsn();',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(seconds: 30),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          final output = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;
          final outputLower = output.toLowerCase();
          if (_isToolNotFoundError(outputLower, 'psql')) {
            return rd.Failure(_createToolNotFoundFailure('psql'));
          }
          return rd.Failure(
            BackupFailure(
              message:
                  'Nao foi possivel obter o LSN atual para backup WAL: $output',
              originalError: Exception(output),
            ),
          );
        }

        final lsn = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((line) => line.trim())
            .firstWhere((line) => line.isNotEmpty, orElse: () => '');

        final lsnPattern = RegExp(
          r'^[0-9A-F]+/[0-9A-F]+$',
          caseSensitive: false,
        );
        if (!lsnPattern.hasMatch(lsn)) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Nao foi possivel interpretar o LSN atual para backup WAL: ${processResult.stdout}',
              originalError: Exception('LSN invalido: $lsn'),
            ),
          );
        }

        return rd.Success(lsn.toUpperCase());
      },
      (failure) {
        final message = failure is Failure
            ? failure.message
            : failure.toString();
        final messageLower = message.toLowerCase();
        if (_isToolNotFoundError(messageLower, 'psql')) {
          return rd.Failure(_createToolNotFoundFailure('psql'));
        }
        return rd.Failure(
          BackupFailure(
            message: 'Erro ao consultar LSN atual do PostgreSQL: $message',
            originalError: failure,
          ),
        );
      },
    );
  }

  Future<rd.Result<void>> _writeWalCaptureMetadata({
    required String backupPath,
    required String endLsn,
    required int capturedSegments,
    required int capturedBytes,
  }) async {
    try {
      final metadataFile = File(p.join(backupPath, 'wal_capture_info.txt'));
      final content =
          'captured_at=${DateTime.now().toIso8601String()}\n'
          'end_lsn=$endLsn\n'
          'captured_segments=$capturedSegments\n'
          'captured_bytes=$capturedBytes\n'
          'had_new_wal=${capturedSegments > 0}\n'
          'tool=pg_receivewal\n'
          'mode=one_shot_endpos\n';
      await metadataFile.writeAsString(content, flush: true);
      return const rd.Success(unit);
    } on Object catch (e, stackTrace) {
      LoggerService.error(
        'Erro ao gravar metadados do backup WAL',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao gravar metadados do backup WAL: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<Set<String>> _snapshotWalFileNames(String backupPath) async {
    try {
      final directory = Directory(backupPath);
      if (!await directory.exists()) {
        return <String>{};
      }

      final names = <String>{};
      await for (final entity in directory.list()) {
        if (entity is! File) {
          continue;
        }
        final name = p.basename(entity.path).toLowerCase();
        if (!_isWalPayloadFile(name)) {
          continue;
        }
        names.add(name);
      }
      return names;
    } on Object {
      return <String>{};
    }
  }

  bool _isWalPayloadFile(String lowerName) {
    if (lowerName == 'wal_capture_info.txt') {
      return false;
    }

    if (lowerName == 'archive_status') {
      return false;
    }

    return true;
  }

  Future<rd.Result<_WalCaptureDelta>> _calculateWalCaptureDelta({
    required String backupPath,
    required Set<String> previousFileNames,
  }) async {
    try {
      final directory = Directory(backupPath);
      if (!await directory.exists()) {
        return const rd.Success(
          _WalCaptureDelta(capturedSegments: 0, capturedBytes: 0),
        );
      }

      var segments = 0;
      var bytes = 0;
      await for (final entity in directory.list()) {
        if (entity is! File) {
          continue;
        }

        final name = p.basename(entity.path).toLowerCase();
        if (!_isWalPayloadFile(name) || previousFileNames.contains(name)) {
          continue;
        }

        segments++;
        bytes += await entity.length();
      }

      return rd.Success(
        _WalCaptureDelta(capturedSegments: segments, capturedBytes: bytes),
      );
    } on Object catch (e) {
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho incremental de WAL: $e',
          originalError: e,
        ),
      );
    }
  }

  String? _resolveWalCompressionMode() {
    final raw = Platform.environment[_logCompressionEnv]?.trim();
    if (raw == null || raw.isEmpty) {
      return null;
    }

    final normalized = raw.toLowerCase();
    if (normalized == 'none' || normalized == 'off' || normalized == 'false') {
      return null;
    }

    return normalized;
  }

  Duration _resolveLogBackupTimeout() {
    final raw = Platform.environment[_logTimeoutSecondsEnv];
    final parsedSeconds = int.tryParse(raw ?? '');
    if (parsedSeconds == null || parsedSeconds <= 0) {
      return const Duration(hours: 1);
    }

    return Duration(seconds: parsedSeconds);
  }

  Future<rd.Result<ps.ProcessResult>> _runPgReceiveWalWithCompressionFallback({
    required String executable,
    required List<String> baseArguments,
    required String? compressionMode,
    required Map<String, String> environment,
    required Duration timeout,
  }) async {
    final initialArguments = <String>[
      ...baseArguments,
      if (compressionMode != null) '--compress=$compressionMode',
    ];

    final firstAttempt = await _processService.run(
      executable: executable,
      arguments: initialArguments,
      environment: environment,
      timeout: timeout,
    );

    if (compressionMode == null || firstAttempt.isError()) {
      return firstAttempt;
    }

    final firstResult = firstAttempt.getOrNull()!;
    if (firstResult.isSuccess) {
      return firstAttempt;
    }

    final combinedOutput = '${firstResult.stdout}\n${firstResult.stderr}'
        .toLowerCase();
    if (!_isUnsupportedCompressionError(combinedOutput)) {
      return firstAttempt;
    }

    LoggerService.warning(
      'pg_receivewal nao suporta --compress=$compressionMode. Reexecutando sem compressao.',
    );
    return _processService.run(
      executable: executable,
      arguments: baseArguments,
      environment: environment,
      timeout: timeout,
    );
  }

  bool _isUnsupportedCompressionError(String outputLower) {
    return (outputLower.contains('unrecognized option') ||
            outputLower.contains('unknown option') ||
            outputLower.contains('invalid option')) &&
        outputLower.contains('compress');
  }

  Future<rd.Result<void>> _validateWalStreamingPreconditions({
    required PostgresConfig config,
    required bool useSlot,
  }) async {
    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-t',
      '-A',
      '-F',
      '|',
      '-c',
      "SELECT current_setting('wal_level'), current_setting('max_wal_senders'), current_setting('max_replication_slots', true), (SELECT CASE WHEN rolsuper OR rolreplication THEN 'true' ELSE 'false' END FROM pg_roles WHERE rolname = current_user);",
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(seconds: 30),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          final output = processResult.stderr.isNotEmpty
              ? processResult.stderr
              : processResult.stdout;
          final outputLower = output.toLowerCase();
          if (_isToolNotFoundError(outputLower, 'psql')) {
            return rd.Failure(_createToolNotFoundFailure('psql'));
          }
          return rd.Failure(
            BackupFailure(
              message: 'Falha no preflight de WAL streaming: $output',
              originalError: Exception(output),
            ),
          );
        }

        final line = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((value) => value.trim())
            .firstWhere((value) => value.isNotEmpty, orElse: () => '');

        if (line.isEmpty) {
          return rd.Failure(
            BackupFailure(
              message: 'Preflight de WAL streaming retornou vazio.',
              originalError: Exception('resultado vazio'),
            ),
          );
        }

        final parts = line.split('|');
        if (parts.length < 4) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Preflight de WAL streaming retornou formato inválido: $line',
              originalError: Exception('formato invalido'),
            ),
          );
        }

        final walLevel = parts[0].trim().toLowerCase();
        final maxWalSenders = int.tryParse(parts[1].trim()) ?? 0;
        final maxReplicationSlots = int.tryParse(parts[2].trim()) ?? 0;
        final hasReplicationPrivilege = parts[3].trim().toLowerCase() == 'true';

        if (walLevel != 'replica' && walLevel != 'logical') {
          return rd.Failure(
            BackupFailure(
              message:
                  "Backup WAL requer wal_level='replica' ou 'logical'. Valor atual: '$walLevel'.",
              originalError: Exception('wal_level invalido'),
            ),
          );
        }

        if (maxWalSenders <= 0) {
          return rd.Failure(
            BackupFailure(
              message:
                  "Backup WAL requer max_wal_senders > 0. Valor atual: '$maxWalSenders'.",
              originalError: Exception('max_wal_senders invalido'),
            ),
          );
        }

        if (!hasReplicationPrivilege) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Backup WAL requer usuario com permissao REPLICATION (ou superuser).',
              originalError: Exception('usuario sem privilegio de replicacao'),
            ),
          );
        }

        if (useSlot && maxReplicationSlots <= 0) {
          return rd.Failure(
            BackupFailure(
              message:
                  "Slot WAL habilitado, mas max_replication_slots <= 0. Valor atual: '$maxReplicationSlots'.",
              originalError: Exception('max_replication_slots invalido'),
            ),
          );
        }

        return const rd.Success(unit);
      },
      (failure) {
        final message = failure is Failure
            ? failure.message
            : failure.toString();
        final lower = message.toLowerCase();
        if (_isToolNotFoundError(lower, 'psql')) {
          return rd.Failure(_createToolNotFoundFailure('psql'));
        }
        return rd.Failure(
          BackupFailure(
            message: 'Erro ao executar preflight de WAL streaming: $message',
            originalError: failure,
          ),
        );
      },
    );
  }

  Future<rd.Result<String>> _findPreviousFullBackup({
    required String outputDirectory,
    required String databaseName,
  }) async {
    try {
      final fullBackups = <Directory>[];
      final candidateDirectories = _resolveFullBackupSearchDirectories(
        outputDirectory,
      );

      for (final candidatePath in candidateDirectories) {
        final candidateDir = Directory(candidatePath);
        if (!await candidateDir.exists()) {
          continue;
        }

        await for (final entity in candidateDir.list()) {
          if (entity is Directory) {
            final dirName = p.basename(entity.path);
            if (dirName.startsWith('${databaseName}_full_')) {
              final manifestPath = p.join(entity.path, 'backup_manifest');
              final manifestFile = File(manifestPath);
              if (await manifestFile.exists()) {
                fullBackups.add(entity);
              }
            }
          }
        }
      }

      if (fullBackups.isEmpty) {
        return rd.Failure(
          BackupFailure(
            message:
                'Nenhum backup FULL anterior encontrado para backup incremental. '
                'Execute um backup FULL primeiro.',
            originalError: Exception('Backup anterior não encontrado'),
          ),
        );
      }

      fullBackups.sort((a, b) {
        final aStat = a.statSync();
        final bStat = b.statSync();
        return bStat.modified.compareTo(aStat.modified);
      });

      return rd.Success(fullBackups.first.path);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao buscar backup anterior', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao buscar backup anterior: $e',
          originalError: e,
        ),
      );
    }
  }

  List<String> _resolveFullBackupSearchDirectories(String outputDirectory) {
    final directories = <String>{outputDirectory};
    final parentDirectory = p.dirname(outputDirectory);

    if (parentDirectory != outputDirectory) {
      directories.add(p.join(parentDirectory, BackupType.full.displayName));
    }

    return directories.toList();
  }

  rd.Result<_BackupCommandResult> _withBackupPath(
    rd.Result<ps.ProcessResult> processResult,
    String backupPath,
  ) {
    return processResult.fold(
      (result) => rd.Success(
        _BackupCommandResult(
          processResult: result,
          backupPath: backupPath,
        ),
      ),
      rd.Failure.new,
    );
  }

  Future<String> _prepareFallbackFullBackupPath({
    required String incrementalBackupPath,
    required String databaseName,
  }) async {
    final parentDirectory = p.dirname(incrementalBackupPath);
    final incrementalName = p.basename(incrementalBackupPath);

    final fallbackName = incrementalName.contains('_incremental_')
        ? incrementalName.replaceFirst('_incremental_', '_full_')
        : '${databaseName}_full_${DateTime.now().toIso8601String().replaceAll(':', '-')}';

    final fallbackPath = p.join(parentDirectory, fallbackName);
    final fallbackDirectory = Directory(fallbackPath);
    if (!await fallbackDirectory.exists()) {
      await fallbackDirectory.create(recursive: true);
    }

    if (fallbackPath != incrementalBackupPath) {
      final incrementalDirectory = Directory(incrementalBackupPath);
      if (await incrementalDirectory.exists()) {
        final isEmpty = await _isDirectoryEmpty(incrementalDirectory);
        if (isEmpty) {
          await incrementalDirectory.delete();
        }
      }
    }

    return fallbackPath;
  }

  Future<bool> _isDirectoryEmpty(Directory directory) async {
    await for (final _ in directory.list()) {
      return false;
    }
    return true;
  }

  Future<rd.Result<int>> _calculateBackupSize(String backupPath) async {
    try {
      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Diretório de backup não existe: $backupPath',
            originalError: Exception('Diretório não encontrado'),
          ),
        );
      }

      var totalSize = 0;
      await for (final entity in backupDir.list(recursive: true)) {
        if (entity is File) {
          totalSize += await entity.length();
        }
      }

      return rd.Success(totalSize);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do backup', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do backup: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<int>> _calculateFileSize(String backupPath) async {
    try {
      final backupFile = File(backupPath);
      if (!await backupFile.exists()) {
        return rd.Failure(
          BackupFailure(
            message: 'Arquivo de backup não existe: $backupPath',
            originalError: Exception('Arquivo não encontrado'),
          ),
        );
      }

      final fileSize = await backupFile.length();
      return rd.Success(fileSize);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao calcular tamanho do arquivo', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao calcular tamanho do arquivo: $e',
          originalError: e,
        ),
      );
    }
  }

  Future<rd.Result<void>> _verifyBackup(String backupPath) async {
    final verifyArgs = ['-D', backupPath];

    final verifyResult = await _processService.run(
      executable: 'pg_verifybackup',
      arguments: verifyArgs,
      timeout: const Duration(minutes: 30),
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, rd.Failure.new);
  }

  Future<rd.Result<void>> _verifyFullSingleBackup(String backupPath) async {
    final verifyArgs = ['-l', backupPath];

    final verifyResult = await _processService.run(
      executable: 'pg_restore',
      arguments: verifyArgs,
      timeout: const Duration(minutes: 30),
    );

    return verifyResult.fold((processResult) {
      if (processResult.isSuccess) {
        final objectCount = processResult.stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty && !line.startsWith(';'))
            .length;
        LoggerService.info(
          'Verificação de integridade concluída. Objetos no backup: $objectCount',
        );
        return const rd.Success(unit);
      } else {
        return rd.Failure(
          BackupFailure(
            message:
                'Verificação de integridade falhou: ${processResult.stderr}',
            originalError: Exception(processResult.stderr),
          ),
        );
      }
    }, rd.Failure.new);
  }

  rd.Result<BackupExecutionResult> _handleBackupError({
    required String stdout,
    required String stderr,
    required String outputLower,
    required BackupType backupType,
  }) {
    if (_isExecutableNotFoundError(outputLower, backupType)) {
      return rd.Failure(_createExecutableNotFoundFailure(backupType));
    }

    if (backupType == BackupType.log &&
        outputLower.contains('replication') &&
        (outputLower.contains('permission denied') ||
            outputLower.contains('must be superuser') ||
            outputLower.contains('must be replication') ||
            outputLower.contains('not permitted'))) {
      return rd.Failure(
        BackupFailure(
          message:
              'Backup WAL requer permissao REPLICATION no usuario PostgreSQL e liberacao no pg_hba.conf.',
          originalError: Exception(stderr.isNotEmpty ? stderr : stdout),
        ),
      );
    }

    final errorMessage = stderr.isNotEmpty ? stderr : stdout;
    return rd.Failure(
      BackupFailure(
        message: 'Backup PostgreSQL falhou: $errorMessage',
        originalError: Exception(errorMessage),
      ),
    );
  }

  bool _isExecutableNotFoundError(String errorLower, BackupType backupType) {
    return _isToolNotFoundError(errorLower, _toolNameForBackupType(backupType));
  }

  String _toolNameForBackupType(BackupType backupType) {
    return backupType == BackupType.fullSingle
        ? 'pg_dump'
        : backupType == BackupType.log
        ? 'pg_receivewal'
        : 'pg_basebackup';
  }

  bool _isToolNotFoundError(String errorLower, String toolName) {
    final normalized = errorLower.toLowerCase();
    final tool = toolName.toLowerCase();

    final hasToolReference =
        normalized.contains("'$tool'") || normalized.contains(tool);
    final hasNotFoundMarker =
        normalized.contains('command not found') ||
        normalized.contains('not recognized') ||
        normalized.contains('nao e reconhecido') ||
        normalized.contains('nao reconhecido') ||
        normalized.contains('nao encontrado') ||
        normalized.contains('nao foi encontrado') ||
        normalized.contains('cmdlet') ||
        normalized.contains('operable program') ||
        normalized.contains('script file') ||
        normalized.contains('programa operavel') ||
        normalized.contains('arquivo de script');

    return hasNotFoundMarker && hasToolReference;
  }

  BackupFailure _createExecutableNotFoundFailure(BackupType backupType) {
    return _createToolNotFoundFailure(_toolNameForBackupType(backupType));
  }

  BackupFailure _createToolNotFoundFailure(String toolName) {
    return BackupFailure(
      message:
          '$toolName nao encontrado no PATH do sistema.\n\n'
          'INSTRUCOES PARA ADICIONAR AO PATH:\n\n'
          '1. Localize a pasta bin do PostgreSQL instalado\n'
          '   (geralmente: C:\\Program Files\\PostgreSQL\\16\\bin)\n\n'
          '2. Adicione ao PATH do Windows:\n'
          '   - Pressione Win + X e selecione "Sistema"\n'
          '   - Clique em "Configuracoes avancadas do sistema"\n'
          '   - Na aba "Avancado", clique em "Variaveis de Ambiente"\n'
          '   - Em "Variaveis do sistema", encontre "Path" e clique em "Editar"\n'
          '   - Clique em "Novo" e adicione o caminho completo da pasta bin\n'
          '   - Clique em "OK" em todas as janelas\n\n'
          '3. Reinicie o aplicativo de backup\n\n'
          r'Consulte: docs\path_setup.md para mais detalhes.',
      originalError: Exception('$toolName nao encontrado'),
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(PostgresConfig config) async {
    LoggerService.info(
      'Testando conexão PostgreSQL: ${config.host}:${config.port}/${config.database}',
    );

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      config.databaseValue,
      '-c',
      'SELECT 1',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: const Duration(seconds: 30),
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('Conexão PostgreSQL bem-sucedida');
          return const rd.Success(true);
        } else {
          final errorOutput = '${processResult.stderr}\n${processResult.stdout}'
              .trim();
          final errorLower = errorOutput.toLowerCase();

          if (_isToolNotFoundError(errorLower, 'psql')) {
            return rd.Failure(
              ValidationFailure(
                message: _createToolNotFoundFailure('psql').message,
              ),
            );
          }

          var errorMessage = 'Falha na conexão';

          if (errorLower.contains('password authentication failed') ||
              errorLower.contains('autenticação de senha falhou')) {
            errorMessage = 'Falha na autenticação: usuário ou senha incorretos';
          } else if (errorLower.contains('could not connect') ||
              errorLower.contains('não foi possível conectar')) {
            errorMessage =
                'Não foi possível conectar ao servidor. Verifique host e porta.';
          } else if (errorLower.contains('does not exist') ||
              errorLower.contains('não existe')) {
            errorMessage = 'Banco de dados não existe';
          } else if (errorOutput.isNotEmpty) {
            errorMessage = errorOutput.split('\n').first.trim();
            if (errorMessage.length > 200) {
              errorMessage = '${errorMessage.substring(0, 200)}...';
            }
          }

          return rd.Failure(
            ValidationFailure(
              message: errorMessage,
              originalError: Exception(errorOutput),
            ),
          );
        }
      },
      (failure) {
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        final errorLower = errorMessage.toLowerCase();

        if (_isToolNotFoundError(errorLower, 'psql')) {
          return rd.Failure(
            ValidationFailure(
              message: _createToolNotFoundFailure('psql').message,
            ),
          );
        }

        return rd.Failure(
          ValidationFailure(
            message: 'Erro ao executar psql: $errorMessage',
            originalError: Exception(errorMessage),
          ),
        );
      },
    );
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required PostgresConfig config,
    Duration? timeout,
  }) async {
    LoggerService.info('Listando bancos de dados PostgreSQL');

    final arguments = <String>[
      '-h',
      config.host,
      '-p',
      config.portValue.toString(),
      '-U',
      config.username,
      '-d',
      'postgres',
      '-t',
      '-A',
      '-c',
      "SELECT datname FROM pg_database WHERE datistemplate = false AND datname != 'postgres'",
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: timeout ?? const Duration(seconds: 30),
    );

    return result.fold((processResult) {
      if (processResult.isSuccess) {
        final databases = processResult.stdout
            .split('\n')
            .where((line) => line.trim().isNotEmpty)
            .map((line) => line.trim())
            .toList();
        LoggerService.info('Bancos encontrados: ${databases.length}');
        return rd.Success(databases);
      } else {
        final errorOutput = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        final errorLower = errorOutput.toLowerCase();
        if (_isToolNotFoundError(errorLower, 'psql')) {
          return rd.Failure(_createToolNotFoundFailure('psql'));
        }
        return rd.Failure(
          BackupFailure(
            message: 'Erro ao listar bancos: $errorOutput',
            originalError: Exception(errorOutput),
          ),
        );
      }
    }, rd.Failure.new);
  }

  BackupMetrics _buildPostgresMetrics({
    required Duration backupDuration,
    required Duration verifyDuration,
    required int totalSize,
    required BackupType backupType,
    required bool verifyAfterBackup,
  }) {
    final totalDuration = backupDuration + verifyDuration;
    return BackupMetrics(
      totalDuration: totalDuration,
      backupDuration: backupDuration,
      verifyDuration: verifyDuration,
      backupSizeBytes: totalSize,
      backupSpeedMbPerSec: _calculateSpeedMbPerSec(
        totalSize,
        backupDuration.inSeconds,
      ),
      backupType: backupType.name,
      flags: BackupFlags(
        compression: false,
        verifyPolicy: verifyAfterBackup ? 'verify' : 'none',
        stripingCount: 1,
        withChecksum: false,
        stopOnError: true,
      ),
    );
  }

  double _calculateSpeedMbPerSec(int sizeInBytes, int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    final sizeInMb = sizeInBytes / 1024 / 1024;
    return sizeInMb / durationSeconds;
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(2)} KB';
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }
}

class _BackupCommandResult {
  const _BackupCommandResult({
    required this.processResult,
    required this.backupPath,
    this.measuredSizeBytes,
  });

  final ps.ProcessResult processResult;
  final String backupPath;
  final int? measuredSizeBytes;
}

class _WalCaptureDelta {
  const _WalCaptureDelta({
    required this.capturedSegments,
    required this.capturedBytes,
  });

  final int capturedSegments;
  final int capturedBytes;
}
