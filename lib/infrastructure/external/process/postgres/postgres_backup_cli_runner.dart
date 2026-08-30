import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_tool_errors.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_types.dart';
import 'package:backup_database/infrastructure/external/process/postgres_wal_slot_utils.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class PostgresBackupCliRunner {
  PostgresBackupCliRunner(this._processService);

  final ps.ProcessService _processService;
  static const String _logCompressionEnv = 'BACKUP_DATABASE_PG_LOG_COMPRESSION';
  static const String _logTimeoutSecondsEnv =
      'BACKUP_DATABASE_PG_LOG_TIMEOUT_SECONDS';

  Future<rd.Result<ps.ProcessResult>> executeFullBackup({
    required PostgresConfig config,
    required String backupPath,
    required Duration timeout,
    String? pgBasebackupPath,
    String? cancelTag,
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
      // Acelera a fase de checkpoint do servidor para iniciar o stream
      // mais rápido (evita esperar checkpoint natural).
      '--checkpoint=fast',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: timeout,
      tag: cancelTag,
    );
  }

  Future<rd.Result<ps.ProcessResult>> executeFullSingleBackup({
    required PostgresConfig config,
    required String backupPath,
    required Duration timeout,
    String? cancelTag,
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
      timeout: timeout,
      tag: cancelTag,
    );
  }

  Future<rd.Result<ps.ProcessResult>> executeIncrementalBackup({
    required PostgresConfig config,
    required String backupPath,
    required String previousBackupPath,
    required Duration timeout,
    String? pgBasebackupPath,
    String? cancelTag,
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
      '--checkpoint=fast',
      '--manifest-checksums=sha256',
      '--wal-method=stream',
    ];

    final environment = <String, String>{'PGPASSWORD': config.password};

    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: environment,
      timeout: timeout,
      tag: cancelTag,
    );
  }

  Future<rd.Result<PostgresBackupCommandResult>> executeLogBackup({
    required PostgresConfig config,
    required String backupPath,
    required Duration timeout,
    String? cancelTag,
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
    // Para backup WAL preferimos o timeout específico vindo do schedule
    // (`timeout` parâmetro). A variável de ambiente continua sendo um
    // fallback histórico para deploys onde não há schedule configurado.
    final effectiveTimeout = _resolveLogBackupTimeout(fallback: timeout);

    final outcomeResult = await _runPgReceiveWalWithCompressionFallback(
      executable: executable,
      baseArguments: baseArguments,
      compressionMode: compressionMode,
      environment: environment,
      timeout: effectiveTimeout,
      cancelTag: cancelTag,
    );

    if (outcomeResult.isError()) {
      return rd.Failure(outcomeResult.exceptionOrNull()!);
    }

    final outcome = outcomeResult.getOrNull()!;
    final result = outcome.processResult;
    if (!result.isSuccess) {
      return rd.Success(
        PostgresBackupCommandResult(
          processResult: result,
          backupPath: backupPath,
          compressionApplied: outcome.compressionApplied,
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
      PostgresBackupCommandResult(
        processResult: result,
        backupPath: backupPath,
        measuredSizeBytes: walDelta.capturedBytes,
        compressionApplied: outcome.compressionApplied,
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
          if (PostgresBackupToolErrors.isToolNotFoundError(
            outputLower,
            'psql',
          )) {
            return rd.Failure(
              PostgresBackupToolErrors.createToolNotFoundFailure('psql'),
            );
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
        if (PostgresBackupToolErrors.isToolNotFoundError(
          messageLower,
          'psql',
        )) {
          return rd.Failure(
            PostgresBackupToolErrors.createToolNotFoundFailure('psql'),
          );
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

  Duration _resolveLogBackupTimeout({required Duration fallback}) {
    final raw = Platform.environment[_logTimeoutSecondsEnv];
    final parsedSeconds = int.tryParse(raw ?? '');
    if (parsedSeconds == null || parsedSeconds <= 0) {
      return fallback;
    }

    return Duration(seconds: parsedSeconds);
  }

  Future<rd.Result<_PgReceiveWalOutcome>>
  _runPgReceiveWalWithCompressionFallback({
    required String executable,
    required List<String> baseArguments,
    required String? compressionMode,
    required Map<String, String> environment,
    required Duration timeout,
    String? cancelTag,
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
      tag: cancelTag,
    );

    if (firstAttempt.isError()) {
      return rd.Failure(firstAttempt.exceptionOrNull()!);
    }

    final firstResult = firstAttempt.getOrNull()!;
    if (compressionMode == null || firstResult.isSuccess) {
      return rd.Success(
        _PgReceiveWalOutcome(
          processResult: firstResult,
          compressionApplied: firstResult.isSuccess ? compressionMode : null,
        ),
      );
    }

    final combinedOutput = '${firstResult.stdout}\n${firstResult.stderr}'
        .toLowerCase();
    if (!_isUnsupportedCompressionError(combinedOutput)) {
      return rd.Success(
        _PgReceiveWalOutcome(
          processResult: firstResult,
          compressionApplied: null,
        ),
      );
    }

    LoggerService.warning(
      'pg_receivewal nao suporta --compress=$compressionMode. Reexecutando sem compressao.',
    );
    final fallback = await _processService.run(
      executable: executable,
      arguments: baseArguments,
      environment: environment,
      timeout: timeout,
      tag: cancelTag,
    );
    if (fallback.isError()) {
      return rd.Failure(fallback.exceptionOrNull()!);
    }
    return rd.Success(
      _PgReceiveWalOutcome(
        processResult: fallback.getOrNull()!,
        compressionApplied: null,
      ),
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
          if (PostgresBackupToolErrors.isToolNotFoundError(
            outputLower,
            'psql',
          )) {
            return rd.Failure(
              PostgresBackupToolErrors.createToolNotFoundFailure('psql'),
            );
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
              message: 'Backup WAL requer usuario com permissao REPLICATION (ou superuser).',
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
        if (PostgresBackupToolErrors.isToolNotFoundError(lower, 'psql')) {
          return rd.Failure(
            PostgresBackupToolErrors.createToolNotFoundFailure('psql'),
          );
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
}

class _PgReceiveWalOutcome {
  const _PgReceiveWalOutcome({
    required this.processResult,
    required this.compressionApplied,
  });

  final ps.ProcessResult processResult;
  final String? compressionApplied;
}

class _WalCaptureDelta {
  const _WalCaptureDelta({
    required this.capturedSegments,
    required this.capturedBytes,
  });

  final int capturedSegments;
  final int capturedBytes;
}
