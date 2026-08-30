import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/postgres_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_postgres_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_cli_runner.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_tool_errors.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_types.dart';
import 'package:backup_database/infrastructure/external/process/postgres/postgres_backup_verifier.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class PostgresBackupService implements IPostgresBackupService {
  PostgresBackupService(this._processService)
    : _cliRunner = PostgresBackupCliRunner(_processService),
      _verifier = PostgresBackupVerifier(_processService);

  final ps.ProcessService _processService;
  final PostgresBackupCliRunner _cliRunner;
  final PostgresBackupVerifier _verifier;
  static const Duration _defaultBackupTimeout = Duration(hours: 2);
  static const Duration _defaultVerifyTimeout = Duration(minutes: 30);

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required PostgresConfig config,
    required BackupExecutionContext context,
  }) {
    return _executeBackupCore(
      config: config,
      outputDirectory: context.outputDirectory,
      backupType: context.backupType,
      customFileName: context.customFileName,
      verifyAfterBackup: context.verifyAfterBackup,
      verifyPolicy: context.verifyPolicy,
      pgBasebackupPath: context.pgBasebackupPath,
      backupTimeout: context.backupTimeout,
      verifyTimeout: context.verifyTimeout,
      cancelTag: context.cancelTag,
    );
  }

  Future<rd.Result<BackupExecutionResult>> _executeBackupCore({
    required PostgresConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool verifyAfterBackup = false,
    VerifyPolicy verifyPolicy = VerifyPolicy.none,
    String? pgBasebackupPath,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
  }) async {
    LoggerService.info(
      'Iniciando backup PostgreSQL: ${config.databaseValue} (Tipo: ${backupType.displayName})',
    );

    final outputDir = Directory(outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final typeSlug = switch (backupType) {
      BackupType.log => 'log',
      BackupType.differential => 'incremental',
      BackupType.fullSingle => 'fullSingle',
      BackupType.full ||
      BackupType.convertedDifferential ||
      BackupType.convertedFullSingle ||
      BackupType.convertedLog => 'full',
    };

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
      backupTimeout: backupTimeout ?? _defaultBackupTimeout,
      cancelTag: cancelTag,
    );

    stopwatch.stop();

    return result.fold(
      (commandResult) async {
        final processResult = commandResult.processResult;
        final effectiveBackupPath = commandResult.backupPath;
        // Tipo de backup realmente executado (pode diferir do solicitado
        // quando há fallback automático, ex.: incremental → full).
        final effectiveBackupType =
            commandResult.executedBackupType ?? backupType;
        final stdout = processResult.stdout;
        final stderr = processResult.stderr;
        final outputLower = (stdout + stderr).toLowerCase();

        if (!processResult.isSuccess) {
          await BackupArtifactUtils.safeDeletePartial(effectiveBackupPath);
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
        } else if (effectiveBackupType == BackupType.fullSingle) {
          await BackupArtifactUtils.waitForStableFile(
            File(effectiveBackupPath),
          );
          sizeResult = await BackupSizeCalculator.bytesOfFile(
            effectiveBackupPath,
          );
        } else {
          sizeResult = await BackupSizeCalculator.bytesOfDirectoryTree(
            effectiveBackupPath,
          );
        }
        return sizeResult.fold((totalSize) async {
          if (totalSize == 0) {
            if (effectiveBackupType == BackupType.log) {
              LoggerService.info(
                'Backup WAL concluido sem novos segmentos para captura.',
              );
              final duration = stopwatch.elapsed;
              final metrics = _buildPostgresMetrics(
                backupDuration: duration,
                verifyDuration: Duration.zero,
                totalSize: 0,
                backupType: effectiveBackupType,
                verifyAfterBackup: false,
                verifyPolicy: verifyPolicy,
                compressionApplied: commandResult.compressionApplied,
              );
              return rd.Success(
                BackupExecutionResult(
                  backupPath: effectiveBackupPath,
                  fileSize: 0,
                  duration: duration,
                  databaseName: config.databaseValue,
                  metrics: metrics,
                  executedBackupType: commandResult.executedBackupType,
                ),
              );
            }

            await BackupArtifactUtils.safeDeletePartial(effectiveBackupPath);
            return rd.Failure(
              BackupFailure(
                message: 'Backup foi criado mas está vazio',
                originalError: Exception('Backup vazio'),
              ),
            );
          }

          LoggerService.info(
            'Backup PostgreSQL concluído: $effectiveBackupPath '
            '(${ByteFormat.format(totalSize)})',
          );

          final backupDuration = stopwatch.elapsed;
          var verifyDuration = Duration.zero;

          if (verifyAfterBackup && effectiveBackupType != BackupType.log) {
            final verifyStopwatch = Stopwatch()..start();
            final effectiveVerifyTimeout =
                verifyTimeout ?? _defaultVerifyTimeout;
            final verifyResult = effectiveBackupType == BackupType.fullSingle
                ? await _verifier.verifyFullSingleBackup(
                    effectiveBackupPath,
                    timeout: effectiveVerifyTimeout,
                    cancelTag: cancelTag,
                  )
                : await _verifier.verifyBackup(
                    effectiveBackupPath,
                    timeout: effectiveVerifyTimeout,
                    cancelTag: cancelTag,
                  );
            verifyStopwatch.stop();
            verifyDuration = verifyStopwatch.elapsed;

            String? verifyErrorMsg;
            var verifyFailed = false;
            verifyResult.fold(
              (_) {
                LoggerService.info(
                  'Verificação de integridade concluída com sucesso',
                );
              },
              (failure) {
                verifyFailed = true;
                verifyErrorMsg = failure is Failure
                    ? failure.message
                    : failure.toString();
                LoggerService.warning(
                  'Verificação de integridade falhou: $verifyErrorMsg',
                );
              },
            );

            // Antes este caminho **sempre** ignorava falhas de verify
            // (mesmo com `VerifyPolicy.strict` configurado no schedule),
            // porque a factory também não propagava `verifyPolicy` (ver
            // postgres_backup_strategy_factory.dart). Agora alinhado com
            // SQL Server / Sybase / Firebird.
            if (verifyFailed && verifyPolicy == VerifyPolicy.strict) {
              return rd.Failure(
                BackupFailure(
                  message:
                      'Verificação de integridade falhou: '
                      '${verifyErrorMsg ?? "erro desconhecido"}',
                ),
              );
            }
          }

          final totalDuration = backupDuration + verifyDuration;
          final metrics = _buildPostgresMetrics(
            backupDuration: backupDuration,
            verifyDuration: verifyDuration,
            totalSize: totalSize,
            backupType: effectiveBackupType,
            verifyAfterBackup: verifyAfterBackup,
            verifyPolicy: verifyPolicy,
            compressionApplied: commandResult.compressionApplied,
          );

          return rd.Success(
            BackupExecutionResult(
              backupPath: effectiveBackupPath,
              fileSize: totalSize,
              duration: totalDuration,
              databaseName: config.databaseValue,
              metrics: metrics,
              executedBackupType: commandResult.executedBackupType,
            ),
          );
        }, rd.Failure.new);
      },
      (failure) async {
        await BackupArtifactUtils.safeDeletePartial(backupPath);
        final errorMessage = failure is Failure
            ? failure.message
            : failure.toString();
        final errorLower = errorMessage.toLowerCase();

        if (PostgresBackupToolErrors.isExecutableNotFoundError(
          errorLower,
          backupType,
        )) {
          return rd.Failure(
            PostgresBackupToolErrors.createExecutableNotFoundFailure(
              backupType,
            ),
          );
        }

        return rd.Failure(failure);
      },
    );
  }

  Future<rd.Result<PostgresBackupCommandResult>> _executeBackupByType({
    required PostgresConfig config,
    required BackupType backupType,
    required String backupPath,
    required String outputDirectory,
    required Duration backupTimeout,
    String? pgBasebackupPath,
    String? cancelTag,
  }) async {
    switch (backupType) {
      case BackupType.full:
        final fullResult = await _cliRunner.executeFullBackup(
          config: config,
          backupPath: backupPath,
          pgBasebackupPath: pgBasebackupPath,
          timeout: backupTimeout,
          cancelTag: cancelTag,
        );
        return _withBackupPath(fullResult, backupPath);

      case BackupType.fullSingle:
        final fullSingleResult = await _cliRunner.executeFullSingleBackup(
          config: config,
          backupPath: backupPath,
          timeout: backupTimeout,
          cancelTag: cancelTag,
        );
        return _withBackupPath(fullSingleResult, backupPath);

      case BackupType.differential:
        final previousBackupResult = await _findPreviousFullBackup(
          outputDirectory: outputDirectory,
          databaseName: config.databaseValue,
        );

        return previousBackupResult.fold(
          (previousBackupPath) async {
            final incrementalResult = await _cliRunner.executeIncrementalBackup(
              config: config,
              backupPath: backupPath,
              previousBackupPath: previousBackupPath,
              pgBasebackupPath: pgBasebackupPath,
              timeout: backupTimeout,
              cancelTag: cancelTag,
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

            final fallbackResult = await _cliRunner.executeFullBackup(
              config: config,
              backupPath: fallbackBackupPath,
              pgBasebackupPath: pgBasebackupPath,
              timeout: backupTimeout,
              cancelTag: cancelTag,
            );
            if (fallbackResult.isError()) {
              await BackupArtifactUtils.safeDeletePartial(fallbackBackupPath);
            }
            // Indica explicitamente para o orchestrator que o tipo executado
            // foi FULL (e não differential como pedido). Evita registrar um
            // histórico inconsistente onde `backupType=differential` aponta
            // para um diretório FULL no disco.
            return fallbackResult.fold(
              (processResult) => rd.Success(
                PostgresBackupCommandResult(
                  processResult: processResult,
                  backupPath: fallbackBackupPath,
                  executedBackupType: BackupType.full,
                ),
              ),
              rd.Failure.new,
            );
          },
        );

      case BackupType.log:
        return _cliRunner.executeLogBackup(
          config: config,
          backupPath: backupPath,
          timeout: backupTimeout,
          cancelTag: cancelTag,
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

      final stamped = await Future.wait(
        fullBackups.map((d) async {
          final st = await d.stat();
          return (dir: d, modified: st.modified);
        }),
      );
      stamped.sort((a, b) => b.modified.compareTo(a.modified));

      return rd.Success(stamped.first.dir.path);
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

  rd.Result<PostgresBackupCommandResult> _withBackupPath(
    rd.Result<ps.ProcessResult> processResult,
    String backupPath,
  ) {
    return processResult.fold(
      (result) => rd.Success(
        PostgresBackupCommandResult(
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

  rd.Result<BackupExecutionResult> _handleBackupError({
    required String stdout,
    required String stderr,
    required String outputLower,
    required BackupType backupType,
  }) {
    if (PostgresBackupToolErrors.isExecutableNotFoundError(
      outputLower,
      backupType,
    )) {
      return rd.Failure(
        PostgresBackupToolErrors.createExecutableNotFoundFailure(backupType),
      );
    }

    if (backupType == BackupType.differential) {
      // `pg_basebackup --incremental=` foi introduzido no PostgreSQL 17.
      // Em PG ≤ 16, o cliente devolve "unrecognized option" com o nome do
      // flag. Mensagem específica orienta o usuário direto à causa em
      // vez do genérico "Backup PostgreSQL falhou: ...".
      if (_hasUnrecognizedIncrementalOption(outputLower)) {
        return rd.Failure(
          BackupFailure(
            message:
                'Backup incremental requer PostgreSQL 17+. O servidor atual '
                'não suporta `pg_basebackup --incremental`. Atualize o '
                'servidor PostgreSQL ou use backup `full` / `fullSingle`.',
            originalError: Exception(stderr.isNotEmpty ? stderr : stdout),
          ),
        );
      }

      // Em PG 17 com `summarize_wal = off` (default em alguns deploys), o
      // servidor recusa o incremental mencionando explicitamente o GUC.
      if (_hasSummarizeWalDisabledError(outputLower)) {
        return rd.Failure(
          BackupFailure(
            message:
                'Backup incremental requer `summarize_wal = on` no '
                'postgresql.conf do servidor. Habilite o parâmetro e '
                'reinicie o serviço PostgreSQL antes de tentar novamente.',
            originalError: Exception(stderr.isNotEmpty ? stderr : stdout),
          ),
        );
      }
    }

    if (backupType == BackupType.log &&
        outputLower.contains('replication') &&
        (outputLower.contains('permission denied') ||
            outputLower.contains('must be superuser') ||
            outputLower.contains('must be replication') ||
            outputLower.contains('not permitted'))) {
      return rd.Failure(
        BackupFailure(
          message: 'Backup WAL requer permissao REPLICATION no usuario PostgreSQL e liberacao no pg_hba.conf.',
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

  bool _hasUnrecognizedIncrementalOption(String outputLower) {
    final hasUnrecognized =
        outputLower.contains('unrecognized option') ||
        outputLower.contains('unknown option') ||
        outputLower.contains('invalid option');
    return hasUnrecognized && outputLower.contains('--incremental');
  }

  bool _hasSummarizeWalDisabledError(String outputLower) {
    return outputLower.contains('summarize_wal') ||
        outputLower.contains('wal summarization') ||
        outputLower.contains('pg_walsummarizer');
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

          if (PostgresBackupToolErrors.isToolNotFoundError(
            errorLower,
            'psql',
          )) {
            return rd.Failure(
              ValidationFailure(
                message: PostgresBackupToolErrors.createToolNotFoundFailure(
                  'psql',
                ).message,
              ),
            );
          }

          var errorMessage = 'Falha na conexão';

          if (errorLower.contains('password authentication failed') ||
              errorLower.contains('autenticação de senha falhou')) {
            errorMessage = 'Falha na autenticação: usuário ou senha incorretos';
          } else if (errorLower.contains('could not connect') ||
              errorLower.contains('não foi possível conectar')) {
            errorMessage = 'Não foi possível conectar ao servidor. Verifique host e porta.';
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

        if (PostgresBackupToolErrors.isToolNotFoundError(
          errorLower,
          'psql',
        )) {
          return rd.Failure(
            ValidationFailure(
              message: PostgresBackupToolErrors.createToolNotFoundFailure(
                'psql',
              ).message,
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
        if (PostgresBackupToolErrors.isToolNotFoundError(
          errorLower,
          'psql',
        )) {
          return rd.Failure(
            PostgresBackupToolErrors.createToolNotFoundFailure('psql'),
          );
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

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required PostgresConfig config,
    Duration? timeout,
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
      '-c',
      "SELECT pg_database_size('${config.databaseValue.replaceAll("'", "''")}')",
    ];
    final environment = <String, String>{'PGPASSWORD': config.password};

    final result = await _processService.run(
      executable: 'psql',
      arguments: arguments,
      environment: environment,
      timeout: timeout ?? const Duration(seconds: 30),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Não foi possível obter tamanho do banco PostgreSQL: '
                  '${processResult.stderr.isNotEmpty ? processResult.stderr : processResult.stdout}',
            ),
          );
        }
        final raw = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .firstWhere((l) => l.isNotEmpty, orElse: () => '');
        final size = int.tryParse(raw);
        if (size == null) {
          return rd.Failure(
            BackupFailure(
              message: 'Resposta inválida ao consultar tamanho do banco: $raw',
            ),
          );
        }
        return rd.Success(size);
      },
      rd.Failure.new,
    );
  }

  BackupMetrics _buildPostgresMetrics({
    required Duration backupDuration,
    required Duration verifyDuration,
    required int totalSize,
    required BackupType backupType,
    required bool verifyAfterBackup,
    required VerifyPolicy verifyPolicy,
    String? compressionApplied,
  }) {
    final totalDuration = backupDuration + verifyDuration;
    // `pg_basebackup` em modo full/differential gera sempre
    // `--manifest-checksums=sha256`; demais tipos (fullSingle via
    // pg_dump custom format, log via pg_receivewal) não emitem manifest
    // com checksum por padrão.
    final withChecksum =
        backupType == BackupType.full || backupType == BackupType.differential;
    // PostgreSQL não tem o conceito SQL Server-like de `STOP_ON_ERROR` no
    // pg_basebackup/pg_dump. Reportamos `false` para sinalizar "N/A" em
    // vez de copiar o default herdado por engano.
    return BackupMetrics(
      totalDuration: totalDuration,
      backupDuration: backupDuration,
      verifyDuration: verifyDuration,
      backupSizeBytes: totalSize,
      backupSpeedMbPerSec: ByteFormat.speedMbPerSec(
        totalSize,
        backupDuration.inSeconds,
      ),
      backupType: backupType.name,
      flags: BackupFlags(
        compression: compressionApplied != null,
        verifyPolicy: verifyAfterBackup ? verifyPolicy.name : 'none',
        stripingCount: 1,
        withChecksum: withChecksum,
        stopOnError: false,
      ),
    );
  }
}
