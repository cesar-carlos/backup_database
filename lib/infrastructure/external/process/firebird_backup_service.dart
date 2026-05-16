import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdBackupService implements IFirebirdBackupService {
  FirebirdBackupService(this._processService);
  final ps.ProcessService _processService;

  static const Duration _defaultProbeTimeout = Duration(seconds: 30);
  static const Duration _defaultBackupTimeout = Duration(hours: 2);

  static final RegExp _pageSizePattern = RegExp(
    r'page\s+size\s+(\d+)',
    caseSensitive: false,
  );
  static final RegExp _dataPagesPattern = RegExp(
    r'data\s+pages:\s*(\d+)',
    caseSensitive: false,
  );

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required FirebirdConfig config,
    required BackupExecutionContext context,
  }) async {
    if (!_isSupportedBackupType(context.backupType)) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Firebird suporta apenas backup completo (Full ou Full Single). '
              'Tipos de log ou diferencial nao estao disponiveis.',
        ),
      );
    }

    final specResult = _connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    LoggerService.info(
      'Iniciando backup Firebird (gbak): ${config.primaryDatabase.value}',
    );

    final outputDir = Directory(context.outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final backupFileName =
        context.customFileName ??
        '${config.primaryDatabase.value}_full_$timestamp.fbk';
    final backupPath = p.join(context.outputDirectory, backupFileName);

    final stopwatch = Stopwatch()..start();
    final arguments = <String>[
      '-b',
      '-user',
      config.username,
      '-pas',
      config.password,
      '-y',
      if (config.cryptKey.trim().isNotEmpty) ...[
        '-key',
        config.cryptKey.trim(),
      ],
      dbSpec,
      backupPath,
    ];

    final runResult = await _processService.run(
      executable: 'gbak',
      arguments: arguments,
      environment: _clientLibEnvironment(config),
      timeout: context.backupTimeout ?? _defaultBackupTimeout,
      tag: context.cancelTag,
    );

    stopwatch.stop();

    return runResult.fold(
      (processResult) async {
        if (!processResult.isSuccess) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(
            _failureFromProcess(
              processResult: processResult,
              toolName: 'gbak',
              defaultMessage: 'Falha ao executar gbak',
              asBackupFailure: true,
            ),
          );
        }

        await BackupArtifactUtils.waitForStableFile(File(backupPath));
        final sizeResult = await BackupSizeCalculator.bytesOfFile(backupPath);
        return sizeResult.fold(
          (totalSize) {
            if (totalSize == 0) {
              return rd.Failure(
                BackupFailure(
                  message: 'Backup Firebird foi criado mas esta vazio',
                  originalError: Exception('Backup vazio'),
                ),
              );
            }
            final duration = stopwatch.elapsed;
            final metrics = BackupMetrics(
              totalDuration: duration,
              backupDuration: duration,
              verifyDuration: Duration.zero,
              backupSizeBytes: totalSize,
              backupSpeedMbPerSec: ByteFormat.speedMbPerSecFromDuration(
                totalSize,
                duration,
              ),
              backupType: context.backupType.name,
              flags: _defaultFlags,
            );
            LoggerService.info(
              'Backup Firebird concluido: $backupPath '
              '(${ByteFormat.format(totalSize)})',
            );
            return rd.Success(
              BackupExecutionResult(
                backupPath: backupPath,
                fileSize: totalSize,
                duration: duration,
                databaseName: config.primaryDatabase.value,
                metrics: metrics,
              ),
            );
          },
          rd.Failure.new,
        );
      },
      rd.Failure.new,
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(FirebirdConfig config) async {
    LoggerService.info(
      'Testando conexao Firebird (gstat): ${config.primaryDatabase.value}',
    );

    final specResult = _connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    final arguments = <String>[
      '-h',
      '-user',
      config.username,
      '-pas',
      config.password,
      dbSpec,
    ];

    final result = await _processService.run(
      executable: 'gstat',
      arguments: arguments,
      environment: _clientLibEnvironment(config),
      timeout: _defaultProbeTimeout,
    );

    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info('Conexao Firebird (gstat) bem-sucedida');
          return const rd.Success(true);
        }
        return rd.Failure(
          _failureFromProcess(
            processResult: processResult,
            toolName: 'gstat',
            defaultMessage: 'Falha ao validar conexao Firebird',
            asBackupFailure: false,
          ),
        );
      },
      (failure) {
        final msg = failure is Failure ? failure.message : failure.toString();
        final lower = msg.toLowerCase();
        if (ToolPathHelp.isToolNotFoundError(lower, 'gstat')) {
          return rd.Failure(
            ValidationFailure(
              message: ToolPathHelp.buildMessage('gstat'),
            ),
          );
        }
        return rd.Failure(
          ValidationFailure(
            message: 'Erro ao executar gstat: $msg',
            originalError: Exception(msg),
          ),
        );
      },
    );
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required FirebirdConfig config,
    Duration? timeout,
  }) async {
    final specResult = _connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    final arguments = <String>[
      '-h',
      '-user',
      config.username,
      '-pas',
      config.password,
      dbSpec,
    ];

    final result = await _processService.run(
      executable: 'gstat',
      arguments: arguments,
      environment: _clientLibEnvironment(config),
      timeout: timeout ?? _defaultProbeTimeout,
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          final combined = '${processResult.stderr}\n${processResult.stdout}'
              .trim();
          final lower = combined.toLowerCase();
          if (ToolPathHelp.isToolNotFoundError(lower, 'gstat')) {
            return rd.Failure(
              BackupFailure(message: ToolPathHelp.buildMessage('gstat')),
            );
          }
          return rd.Failure(
            BackupFailure(
              message:
                  'Nao foi possivel obter tamanho do banco Firebird: $combined',
            ),
          );
        }
        final text = '${processResult.stdout}\n${processResult.stderr}';
        final parsed = _parseGstatPageStats(text);
        final pageSize = parsed.$1;
        final dataPages = parsed.$2;
        if (pageSize == null ||
            dataPages == null ||
            pageSize <= 0 ||
            dataPages < 0) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Resposta invalida do gstat ao estimar tamanho '
                  '(pageSize=$pageSize, dataPages=$dataPages)',
            ),
          );
        }
        final estimate = pageSize * dataPages;
        return rd.Success(estimate);
      },
      rd.Failure.new,
    );
  }

  static const BackupFlags _defaultFlags = BackupFlags(
    compression: false,
    verifyPolicy: 'none',
    stripingCount: 1,
    withChecksum: false,
    stopOnError: true,
  );

  static bool _isSupportedBackupType(BackupType type) {
    switch (type) {
      case BackupType.full:
      case BackupType.fullSingle:
        return true;
      case BackupType.log:
      case BackupType.differential:
      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
      case BackupType.convertedLog:
        return false;
    }
  }

  rd.Result<String> _connectionSpec(FirebirdConfig config) {
    if (config.useEmbedded) {
      final path = config.databaseFile.trim();
      if (path.isEmpty) {
        return const rd.Failure(
          ValidationFailure(
            message: 'Caminho do arquivo do banco Firebird (embedded) vazio.',
          ),
        );
      }
      return rd.Success(path);
    }
    final alias = config.aliasName?.trim();
    if (alias != null && alias.isNotEmpty) {
      return rd.Success('${config.host}/${config.portValue}:$alias');
    }
    final db = config.databaseFile.trim();
    if (db.isEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Informe o caminho do banco no servidor ou um alias Firebird.',
        ),
      );
    }
    return rd.Success('${config.host}/${config.portValue}:$db');
  }

  Map<String, String>? _clientLibEnvironment(FirebirdConfig config) {
    final lib = config.clientLibraryPath?.trim();
    if (lib == null || lib.isEmpty) {
      return null;
    }
    final dir = p.dirname(lib);
    final key = Platform.isWindows ? 'Path' : 'PATH';
    final current = Platform.environment[key] ?? Platform.environment['PATH'];
    if (current == null || current.isEmpty) {
      return {key: dir};
    }
    final sep = Platform.isWindows ? ';' : ':';
    return {key: '$dir$sep$current'};
  }

  (int?, int?) _parseGstatPageStats(String text) {
    int? pageSize;
    int? dataPages;
    for (final raw in text.split(RegExp(r'[\r\n]+'))) {
      final line = raw.trim();
      if (line.isEmpty) {
        continue;
      }
      if (pageSize == null) {
        final m = _pageSizePattern.firstMatch(line);
        if (m != null) {
          pageSize = int.tryParse(m.group(1)!);
        }
      }
      if (dataPages == null) {
        final m = _dataPagesPattern.firstMatch(line);
        if (m != null) {
          dataPages = int.tryParse(m.group(1)!);
        }
      }
      if (pageSize != null && dataPages != null) {
        break;
      }
    }
    return (pageSize, dataPages);
  }

  Failure _failureFromProcess({
    required ps.ProcessResult processResult,
    required String toolName,
    required String defaultMessage,
    required bool asBackupFailure,
  }) {
    final errorOutput = '${processResult.stderr}\n${processResult.stdout}'
        .trim();
    final errorLower = errorOutput.toLowerCase();

    if (ToolPathHelp.isToolNotFoundError(errorLower, toolName)) {
      final msg = ToolPathHelp.buildMessage(toolName);
      return asBackupFailure
          ? BackupFailure(message: msg)
          : ValidationFailure(message: msg);
    }

    var errorMessage = defaultMessage;
    if (errorLower.contains('unable to complete') ||
        errorLower.contains('i/o error') ||
        errorLower.contains('connection')) {
      errorMessage =
          'Nao foi possivel conectar ao servidor Firebird. Verifique host, '
          'porta e caminho/alias no servidor.';
    } else if (errorLower.contains('password') ||
        errorLower.contains('authentication') ||
        errorLower.contains('login')) {
      errorMessage = 'Falha na autenticacao Firebird (usuario ou senha).';
    } else if (errorLower.contains('not found') ||
        errorLower.contains('no such file') ||
        errorLower.contains('nao encontrado')) {
      errorMessage =
          'Banco Firebird nao encontrado no servidor (caminho ou alias).';
    } else if (errorOutput.isNotEmpty) {
      errorMessage = errorOutput.split('\n').first.trim();
      if (errorMessage.length > 200) {
        errorMessage = '${errorMessage.substring(0, 200)}...';
      }
    }

    if (asBackupFailure) {
      return BackupFailure(
        message: errorMessage,
        originalError: Exception(errorOutput),
      );
    }
    return ValidationFailure(
      message: errorMessage,
      originalError: Exception(errorOutput),
    );
  }

  Failure _asFailure(Object failure) {
    if (failure is Failure) {
      return failure;
    }
    return BackupFailure(
      message: failure.toString(),
      originalError: failure,
    );
  }
}
