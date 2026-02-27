import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:backup_database/infrastructure/external/process/sybase_connection_strategy_cache.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class SybaseBackupService implements ISybaseBackupService {
  SybaseBackupService(
    this._processService, {
    SybaseConnectionStrategyCache? strategyCache,
  }) : _strategyCache = strategyCache ?? SybaseConnectionStrategyCache();

  final ps.ProcessService _processService;
  final SybaseConnectionStrategyCache _strategyCache;

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required String outputDirectory,
    BackupType backupType = BackupType.full,
    String? customFileName,
    String? dbbackupPath,
    bool truncateLog = true,
    bool verifyAfterBackup = false,
    VerifyPolicy verifyPolicy = VerifyPolicy.bestEffort,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    SybaseBackupOptions? sybaseBackupOptions,
  }) async {
    final options = sybaseBackupOptions ?? SybaseBackupOptions.safeDefaults;
    final effectiveLogMode = _resolveLogBackupMode(options, truncateLog);
    try {
      LoggerService.info(
        'Iniciando backup Sybase: ${config.serverName} (Tipo: ${backupType.displayName})',
      );

      if (backupType == BackupType.log) {
        LoggerService.debug(
          'Modo de log: ${effectiveLogMode.name}',
        );
      }

      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      final effectiveType = backupType == BackupType.fullSingle
          ? BackupType.full
          : backupType == BackupType.differential
          ? BackupType.log
          : backupType;

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final typeSlug = effectiveType.name;

      String backupPath;
      if (effectiveType == BackupType.full) {
        backupPath = p.join(outputDirectory, config.databaseNameValue);
      } else {
        final folderName =
            customFileName ??
            '${config.databaseNameValue}_${typeSlug}_$timestamp';
        backupPath = p.join(outputDirectory, folderName);
      }

      final executable = dbbackupPath ?? 'dbbackup';

      final databaseName = config.databaseNameValue;

      final backupStopwatch = Stopwatch()..start();
      rd.Result<ps.ProcessResult>? result;
      var lastError = '';

      LoggerService.info('Tentando backup via comando SQL BACKUP DATABASE...');

      final backupDir = Directory(backupPath);
      if (!await backupDir.exists()) {
        await backupDir.create(recursive: true);
      }

      final escapedBackupPath = backupPath.replaceAll(r'\', r'\\');

      final dbisqlConnections = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',

        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
      ];

      final cacheKey = effectiveType.name;
      final cached = _strategyCache.get(config.id, cacheKey);

      var sqlBackupSuccess = false;
      var dbisqlStrategyIndex = 0;
      var dbbackupStrategyIndex = -1;

      final connectionStrategies = <Map<String, String>>[
        {
          'name': 'ENG+DBN (serverName + databaseName)',
          'conn':
              'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        },
        {
          'name': 'ENG+DBN (databaseName como ambos)',
          'conn':
              'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',
        },
        {
          'name': 'Apenas ENG por serverName',
          'conn':
              'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
        },
        {
          'name': 'Conexão via TCPIP',
          'conn':
              'HOST=localhost:${config.port};DBN=$databaseName;UID=${config.username};PWD=${config.password};LINKS=TCPIP',
        },
      ];

      if (cached != null &&
          cached.method == SybaseConnectionMethod.dbbackup &&
          cached.strategyIndex < connectionStrategies.length) {
        final strategy = connectionStrategies[cached.strategyIndex];
        LoggerService.debug(
          'Tentando estratégia cacheada dbbackup ${cached.strategyIndex + 1}',
        );

        final arguments = <String>[];
        if (options.serverSide) {
          arguments.add('-s');
        }
        if (options.blockSize != null) {
          arguments.addAll(['-b', options.blockSize.toString()]);
        }
        if (effectiveType == BackupType.log) {
          arguments.addAll(
            _buildDbbackupLogArgs(effectiveLogMode),
          );
        }
        arguments.addAll(['-c', strategy['conn']!, '-y', backupPath]);

        result = await _processService.run(
          executable: executable,
          arguments: arguments,
          timeout: backupTimeout ?? const Duration(hours: 2),
        );

        result.fold(
          (processResult) {
            if (processResult.isSuccess) {
              sqlBackupSuccess = true;
              dbbackupStrategyIndex = cached.strategyIndex;
              LoggerService.info(
                'Backup bem-sucedido com estratégia cacheada dbbackup '
                '${cached.strategyIndex + 1}',
              );
            } else {
              lastError = processResult.stderr;
              _strategyCache.invalidate(config.id, cacheKey);
            }
          },
          (_) => _strategyCache.invalidate(config.id, cacheKey),
        );
      }

      if (cached != null &&
          cached.method == SybaseConnectionMethod.dbisql &&
          cached.strategyIndex < dbisqlConnections.length) {
        final connStr = dbisqlConnections[cached.strategyIndex];
        LoggerService.debug(
          'Tentando estratégia cacheada dbisql ${cached.strategyIndex + 1}',
        );

        final backupSql = _buildBackupSql(
          effectiveType,
          escapedBackupPath,
          effectiveLogMode,
          options,
        );
        if (backupSql != null) {
          result = await _processService.run(
            executable: 'dbisql',
            arguments: ['-c', connStr, '-nogui', backupSql],
            timeout: backupTimeout ?? const Duration(hours: 2),
          );

          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                sqlBackupSuccess = true;
                dbisqlStrategyIndex = cached.strategyIndex + 1;
                LoggerService.info(
                  'Backup SQL bem-sucedido com estratégia cacheada '
                  '${cached.strategyIndex + 1}',
                );
              } else {
                lastError = processResult.stderr;
                _strategyCache.invalidate(config.id, cacheKey);
              }
            },
            (_) => _strategyCache.invalidate(config.id, cacheKey),
          );
        }
      }

      if (!sqlBackupSuccess) {
        for (var i = 0; i < dbisqlConnections.length; i++) {
          final connStr = dbisqlConnections[i];
          dbisqlStrategyIndex = i + 1;
          LoggerService.debug(
            'Tentando dbisql com estratégia '
            '$dbisqlStrategyIndex/${dbisqlConnections.length}',
          );

        final backupSql = _buildBackupSql(
          effectiveType,
          escapedBackupPath,
          effectiveLogMode,
          options,
        );
        if (backupSql == null) {
          return const rd.Failure(
            BackupFailure(
              message:
                  'Sybase SQL Anywhere não suporta tipos convertidos. '
                  'Use o tipo de backup nativo correspondente.',
            ),
          );
        }

        final dbisqlArgs = ['-c', connStr, '-nogui', backupSql];

          result = await _processService.run(
            executable: 'dbisql',
            arguments: dbisqlArgs,
            timeout: backupTimeout ?? const Duration(hours: 2),
          );

          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                sqlBackupSuccess = true;
                LoggerService.info(
                  'Backup SQL bem-sucedido com estratégia $dbisqlStrategyIndex',
                );
              } else {
                lastError = processResult.stderr;
                LoggerService.debug('dbisql falhou: ${processResult.stderr}');
              }
            },
            (failure) {
              if (failure is Failure) {
                lastError = failure.message;
              } else {
                lastError = failure.toString();
              }
            },
          );

          if (sqlBackupSuccess) break;
        }
      }

      if (!sqlBackupSuccess) {
        LoggerService.info('Backup SQL falhou, tentando dbbackup...');

        for (var i = 0; i < connectionStrategies.length; i++) {
          final strategy = connectionStrategies[i];
          LoggerService.debug('Tentando dbbackup: ${strategy['name']}');

          final arguments = <String>[];

          if (options.serverSide) {
            arguments.add('-s');
          }
          if (options.blockSize != null) {
            arguments.addAll(['-b', options.blockSize.toString()]);
          }
          if (effectiveType == BackupType.log) {
            arguments.addAll(_buildDbbackupLogArgs(effectiveLogMode));
          }

          arguments.addAll(['-c', strategy['conn']!, '-y', backupPath]);

          result = await _processService.run(
            executable: executable,
            arguments: arguments,
            timeout: backupTimeout ?? const Duration(hours: 2),
          );

          var success = false;
          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                success = true;
                dbbackupStrategyIndex = i;
                LoggerService.info(
                  'Backup bem-sucedido com: ${strategy['name']}',
                );
              } else {
                lastError = processResult.stderr;
                LoggerService.debug(
                  'Estratégia "${strategy['name']}" falhou: ${processResult.stderr}',
                );
              }
            },
            (failure) {
              if (failure is Failure) {
                lastError = failure.message;
              } else {
                lastError = failure.toString();
              }
            },
          );

          if (success) break;
        }
      }

      backupStopwatch.stop();

      if (result == null) {
        final message = _buildNoStrategyWorkedMessage(lastError, config);
        return rd.Failure(BackupFailure(message: message));
      }

      return result.fold((processResult) async {
        if (processResult.isSuccess) {
          if (sqlBackupSuccess) {
            _strategyCache.put(
              config.id,
              cacheKey,
              SybaseConnectionMethod.dbisql,
              dbisqlStrategyIndex - 1,
            );
          } else if (dbbackupStrategyIndex >= 0) {
            _strategyCache.put(
              config.id,
              cacheKey,
              SybaseConnectionMethod.dbbackup,
              dbbackupStrategyIndex,
            );
          }
        }

        if (!processResult.isSuccess) {
          LoggerService.error(
            'Backup Sybase falhou após todas as tentativas',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: ${processResult.stdout}\n'
              'STDERR: ${processResult.stderr}',
            ),
          );

          final errorMessage = _buildProcessResultErrorMessage(
            processResult,
            config,
            databaseName,
          );

          return rd.Failure(BackupFailure(message: errorMessage));
        }

        var totalSize = 0;
        var actualBackupPath = backupPath;

        final backupDir = Directory(backupPath);
        final backupFile = File(backupPath);

        var backupFound = false;
        for (var i = 0; i < 10; i++) {
          if (await backupDir.exists()) {
            final files = await backupDir.list().toList();
            if (files.isNotEmpty) {
              for (final entity in files) {
                if (entity is File) {
                  totalSize += await entity.length();
                }
              }
              if (totalSize > 0) {
                backupFound = true;
                break;
              }
            }
          }

          if (!backupFound && await backupFile.exists()) {
            totalSize = await backupFile.length();
            if (totalSize > 0) {
              backupFound = true;
              break;
            }
          }

          if (!backupFound && i < 9) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        if (!backupFound) {
          return rd.Failure(
            BackupFailure(
              message: _buildBackupNotCreatedMessage(backupPath),
            ),
          );
        }

        if (totalSize == 0) {
          return rd.Failure(
            BackupFailure(
              message: _buildBackupEmptyMessage(backupPath),
            ),
          );
        }

        if (effectiveType == BackupType.log && await backupDir.exists()) {
          final resolvedLogFile = await _tryFindLogFile(backupDir);
          if (resolvedLogFile != null) {
            actualBackupPath = resolvedLogFile.path;
            totalSize = await resolvedLogFile.length();
          }
        }

        final resolvedBackupFile = File(actualBackupPath);
        if (effectiveType == BackupType.log &&
            await resolvedBackupFile.exists()) {
          LoggerService.debug(
            'Aguardando arquivo de log ser liberado pelo Sybase...',
          );

          var fileAccessible = false;
          for (var attempt = 0; attempt < 5; attempt++) {
            try {
              final randomAccessFile = await resolvedBackupFile.open();
              await randomAccessFile.close();
              fileAccessible = true;
              LoggerService.debug('Arquivo de log está acessível');
              break;
            } on Object catch (e) {
              if (attempt < 4) {
                LoggerService.debug(
                  'Arquivo de log ainda em uso, aguardando... (tentativa ${attempt + 1}/5)',
                );
                await Future.delayed(const Duration(seconds: 1));
              } else {
                LoggerService.warning(
                  'Arquivo de log pode ainda estar em uso, mas continuando...',
                );
              }
            }
          }

          if (fileAccessible) {
            await Future.delayed(const Duration(milliseconds: 500));
          }
        }

        LoggerService.info(
          'Backup Sybase concluído: $actualBackupPath (${_formatBytes(totalSize)})',
        );

        final verifyStopwatch = Stopwatch();
        var verifySuccess = false;
        var verificationMethodUsed = 'dbvalid';
        if (verifyAfterBackup) {
          LoggerService.info('Verificando integridade do backup Sybase...');
          verifyStopwatch.start();

          var lastVerifyError = '';

          if (effectiveType == BackupType.full) {
            final dir = Directory(actualBackupPath);
            if (await dir.exists()) {
              final backupDbFile = await _tryFindBackupDbFile(dir);
              if (backupDbFile != null) {
                final connStr =
                    'UID=${config.username};PWD=${config.password};DBF=${backupDbFile.path}';
                LoggerService.debug(
                  'Tentando dbvalid no arquivo: ${backupDbFile.path}',
                );

                final verifyResult = await _processService.run(
                  executable: 'dbvalid',
                  arguments: ['-c', connStr],
                  timeout: verifyTimeout ?? const Duration(minutes: 30),
                );

                verifyResult.fold(
                  (processResult) {
                    if (processResult.isSuccess) {
                      verifySuccess = true;
                      LoggerService.info(
                        'Verificação de integridade concluída com sucesso (dbvalid)',
                      );
                    } else {
                      lastVerifyError = processResult.stderr.isNotEmpty
                          ? processResult.stderr
                          : processResult.stdout;
                      LoggerService.debug(
                        'dbvalid falhou: $lastVerifyError',
                      );
                    }
                  },
                  (failure) {
                    lastVerifyError = failure is Failure
                        ? failure.message
                        : failure.toString();
                  },
                );

                if (!verifySuccess) {
                  LoggerService.debug(
                    'Tentando fallback dbverify no arquivo: ${backupDbFile.path}',
                  );
                  final dbverifyResult = await _processService.run(
                    executable: 'dbverify',
                    arguments: ['-c', connStr],
                    timeout: verifyTimeout ?? const Duration(minutes: 30),
                  );
                  dbverifyResult.fold(
                    (processResult) {
                      if (processResult.isSuccess) {
                        verifySuccess = true;
                        verificationMethodUsed = 'dbverify';
                        LoggerService.info(
                          'Verificação de integridade concluída com sucesso (dbverify fallback)',
                        );
                      } else {
                        lastVerifyError = processResult.stderr.isNotEmpty
                            ? processResult.stderr
                            : processResult.stdout;
                      }
                    },
                    (failure) {
                      lastVerifyError = failure is Failure
                          ? failure.message
                          : failure.toString();
                    },
                  );
                }
              } else {
                lastVerifyError =
                    'Não foi possível localizar um arquivo .db no diretório do backup';
              }
            }
          }

          if (effectiveType == BackupType.log) {
            LoggerService.info(
              'Verificação não disponível para backup de log; '
              'resultado registrado como indisponível',
            );
            lastVerifyError = 'Verificação não disponível para backup de log';
          } else if (!verifySuccess) {
            LoggerService.warning(
              'Verificação de integridade falhou (dbvalid e dbverify): $lastVerifyError',
            );
            if (verifyPolicy == VerifyPolicy.strict) {
              verifyStopwatch.stop();
              return rd.Failure(
                BackupFailure(
                  message:
                      'Verificação de integridade falhou (modo estrito). '
                      '$lastVerifyError',
                ),
              );
            }
          }
          verifyStopwatch.stop();
        }

        final backupDuration = backupStopwatch.elapsed;
        final verifyDuration = verifyAfterBackup
            ? verifyStopwatch.elapsed
            : Duration.zero;
        final totalDuration = backupDuration + verifyDuration;

        final verifyPolicyLabel = !verifyAfterBackup
            ? 'none'
            : effectiveType == BackupType.log
            ? 'log_unavailable'
            : verifySuccess
            ? verificationMethodUsed
            : 'dbvalid_falhou';

        final sybaseOptionsJson = Map<String, dynamic>.from(options.toJson());
        sybaseOptionsJson['verificationMethod'] = verifyPolicyLabel;
        if (dbbackupStrategyIndex >= 0) {
          sybaseOptionsJson['backupMethod'] = 'dbbackup';
          sybaseOptionsJson['connectionStrategy'] =
              connectionStrategies[dbbackupStrategyIndex]['name'] ??
                  'dbbackup #${dbbackupStrategyIndex + 1}';
        } else {
          sybaseOptionsJson['backupMethod'] = 'dbisql';
          sybaseOptionsJson['connectionStrategy'] =
              _dbisqlStrategyName(dbisqlStrategyIndex);
        }

        final metrics = BackupMetrics(
          totalDuration: totalDuration,
          backupDuration: backupDuration,
          verifyDuration: verifyDuration,
          backupSizeBytes: totalSize,
          backupSpeedMbPerSec: _calculateSpeedMbPerSec(
            totalSize,
            backupDuration.inSeconds,
          ),
          backupType: effectiveType.name,
          flags: BackupFlags(
            compression: false,
            verifyPolicy: verifyPolicyLabel,
            stripingCount: 1,
            withChecksum: false,
            stopOnError: true,
          ),
          sybaseOptions: sybaseOptionsJson,
        );

        return rd.Success(
          BackupExecutionResult(
            backupPath: actualBackupPath,
            fileSize: totalSize,
            duration: totalDuration,
            databaseName: config.databaseNameValue,
            metrics: metrics,
          ),
        );
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao executar backup Sybase', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar backup Sybase: $e',
          originalError: e,
        ),
      );
    }
  }

  static const List<String> _dbisqlStrategyNames = [
    'ENG+DBN (serverName + databaseName)',
    'Apenas ENG por serverName',
    'ENG+DBN (databaseName como ambos)',
  ];

  static String _dbisqlStrategyName(int strategyIndex1Based) {
    final i = strategyIndex1Based - 1;
    if (i >= 0 && i < _dbisqlStrategyNames.length) {
      return _dbisqlStrategyNames[i];
    }
    return 'dbisql #$strategyIndex1Based';
  }

  static const String _pathInstructionsHint =
      'não encontrado no PATH do sistema';

  String _buildNoStrategyWorkedMessage(String lastError, SybaseConfig config) {
    final lower = lastError.toLowerCase();
    if (lower.contains(_pathInstructionsHint) ||
        lower.contains('instruções') ||
        lower.contains('path_setup')) {
      return 'Nenhuma estratégia de backup funcionou.\n\n$lastError';
    }
    return 'Nenhuma estratégia de backup funcionou. Último erro: $lastError\n\n'
        'AÇÕES RECOMENDADAS:\n'
        '1. Verifique na página de configuração se dbisql e dbbackup estão '
        'disponíveis (ícone verde)\n'
        '2. Confirme Engine Name e DBN (geralmente o nome do arquivo .db)\n'
        '3. Verifique se o servidor Sybase está rodando\n'
        '4. Confirme usuário e senha';
  }

  String _buildProcessResultErrorMessage(
    ps.ProcessResult processResult,
    SybaseConfig config,
    String databaseName,
  ) {
    final stderr = processResult.stderr.toLowerCase();
    final combined = '${processResult.stdout}\n${processResult.stderr}'
        .toLowerCase();

    if (stderr.contains('already in use')) {
      return 'O banco de dados está em uso e não foi possível conectar. '
          'Verifique se o nome do servidor (Engine Name) está correto. '
          'Geralmente é o nome do arquivo .db sem extensão (ex: "Data7").';
    }
    if (stderr.contains('server not found') ||
        stderr.contains('unable to connect') ||
        combined.contains('connection refused') ||
        combined.contains('connection timed out')) {
      return 'Não foi possível encontrar/conectar ao servidor Sybase.\n\n'
          'Verifique:\n'
          '1. Se o servidor Sybase está rodando\n'
          '2. Se a porta ${config.port} está correta\n'
          '3. Se o Engine Name (${config.serverName}) está correto\n'
          '4. Se o DBN ($databaseName) está correto';
    }
    if (stderr.contains('permission denied') ||
        stderr.contains('access denied')) {
      return 'Permissão negada.\n\n'
          'Verifique se o usuário tem permissão para fazer backup do banco.';
    }
    if (stderr.contains('invalid user') || stderr.contains('login failed')) {
      return 'Usuário ou senha inválidos. Verifique as credenciais na configuração.';
    }
    if (combined.contains('disk full') ||
        combined.contains('no space') ||
        combined.contains('insufficient') ||
        combined.contains('not enough space')) {
      return 'Espaço em disco insuficiente no destino do backup.\n\n'
          'Libere espaço ou escolha outro diretório.';
    }
    if (stderr.contains('path not found') ||
        stderr.contains('file not found') ||
        stderr.contains('cannot find') ||
        stderr.contains('directory')) {
      return 'Caminho de destino inválido ou inacessível.\n\n'
          'Verifique se o diretório existe e tem permissão de escrita.';
    }

    return 'Erro ao executar backup (Exit Code: ${processResult.exitCode})\n'
        '${processResult.stderr}';
  }

  String _buildBackupNotCreatedMessage(String backupPath) {
    return 'Backup não foi criado em: $backupPath\n\n'
        'AÇÕES RECOMENDADAS:\n'
        '1. Verifique se o diretório existe e tem permissão de escrita\n'
        '2. Confirme se há espaço em disco suficiente\n'
        '3. Verifique os logs para detalhes do erro';
  }

  String _buildBackupEmptyMessage(String backupPath) {
    return 'Backup foi criado mas está vazio em: $backupPath\n\n'
        'Isso pode indicar falha no comando ou caminho incorreto. '
        'Verifique os logs para detalhes.';
  }

  static SybaseLogBackupMode _resolveLogBackupMode(
    SybaseBackupOptions options,
    bool truncateLog,
  ) {
    if (options.logBackupMode != null) return options.logBackupMode!;
    return truncateLog ? SybaseLogBackupMode.truncate : SybaseLogBackupMode.only;
  }

  static List<String> _buildDbbackupLogArgs(SybaseLogBackupMode mode) {
    switch (mode) {
      case SybaseLogBackupMode.truncate:
        return ['-t', '-x'];
      case SybaseLogBackupMode.rename:
        return ['-t', '-r'];
      case SybaseLogBackupMode.only:
        return ['-t'];
    }
  }

  String? _buildBackupSql(
    BackupType effectiveType,
    String escapedBackupPath,
    SybaseLogBackupMode logMode,
    SybaseBackupOptions options,
  ) {
    switch (effectiveType) {
      case BackupType.full:
      case BackupType.fullSingle:
        final base =
            "BACKUP DATABASE DIRECTORY '$escapedBackupPath'";
        final checkpointClause = options.buildCheckpointLogClause();
        final autoTuneClause = options.buildAutoTuneWritersClause();
        return base + checkpointClause + autoTuneClause;
      case BackupType.log:
        final logClause = switch (logMode) {
          SybaseLogBackupMode.truncate => 'TRANSACTION LOG TRUNCATE',
          SybaseLogBackupMode.only => 'TRANSACTION LOG ONLY',
          SybaseLogBackupMode.rename => 'TRANSACTION LOG RENAME',
        };
        final autoTuneClause = options.buildAutoTuneWritersClause();
        return "BACKUP DATABASE DIRECTORY '$escapedBackupPath' $logClause$autoTuneClause";
      case BackupType.differential:
      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
      case BackupType.convertedLog:
        return null;
    }
  }

  Future<File?> _tryFindLogFile(Directory backupDir) async {
    try {
      final entities = await backupDir.list().toList();
      final files = entities.whereType<File>().toList()
        ..sort(
          (a, b) => b.statSync().modified.compareTo(a.statSync().modified),
        );

      if (files.isEmpty) return null;

      final logCandidates = files.where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ext == '.trn' || ext == '.log';
      }).toList();

      if (logCandidates.isNotEmpty) return logCandidates.first;
      return files.first;
    } on Object catch (_) {
      return null;
    }
  }

  Future<File?> _tryFindBackupDbFile(Directory backupDir) async {
    try {
      final entities = await backupDir.list().toList();
      final dbFiles = entities.whereType<File>().where((f) {
        return p.extension(f.path).toLowerCase() == '.db';
      }).toList()..sort((a, b) => b.lengthSync().compareTo(a.lengthSync()));

      if (dbFiles.isEmpty) return null;
      return dbFiles.first;
    } on Object catch (_) {
      return null;
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(SybaseConfig config) async {
    try {
      LoggerService.info(
        'Testando conexão Sybase: Engine=${config.serverName}, DBN=${config.databaseNameValue}',
      );

      if (config.serverName.trim().isEmpty) {
        return const rd.Failure(
          BackupFailure(
            message: 'Nome do servidor (Engine Name) não pode estar vazio',
          ),
        );
      }

      if (config.databaseNameValue.trim().isEmpty) {
        return const rd.Failure(
          BackupFailure(
            message: 'Nome do banco de dados (DBN) não pode estar vazio',
          ),
        );
      }

      if (config.username.trim().isEmpty) {
        return const rd.Failure(
          BackupFailure(message: 'Usuário não pode estar vazio'),
        );
      }

      final databaseName = config.databaseNameValue;
      final connectionStrategies = <String>[
        'ENG=${config.serverName};DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=$databaseName;DBN=$databaseName;UID=${config.username};PWD=${config.password}',

        'ENG=${config.serverName};UID=${config.username};PWD=${config.password}',
      ];

      var lastError = '';

      var testStrategyIndex = 0;
      for (final connStr in connectionStrategies) {
        testStrategyIndex++;
        try {
          LoggerService.debug(
            'Tentando teste de conexão com estratégia '
            '$testStrategyIndex/${connectionStrategies.length}',
          );

          final arguments = ['-c', connStr, '-q', 'SELECT 1', '-nogui'];

          final result = await _processService.run(
            executable: 'dbisql',
            arguments: arguments,
            timeout: const Duration(seconds: 10),
          );

          final success = result.fold(
            (processResult) => processResult.isSuccess,
            (failure) => false,
          );

          if (success) {
            LoggerService.info('Teste de conexão Sybase bem-sucedido');
            return const rd.Success(true);
          }

          result.fold(
            (processResult) {
              final combinedOutput =
                  '${processResult.stdout}\n${processResult.stderr}'.trim();
              lastError = combinedOutput.isNotEmpty
                  ? combinedOutput
                  : 'Falha na conexão (Exit Code: ${processResult.exitCode})';
              LoggerService.debug('Estratégia falhou: $lastError');
            },
            (failure) {
              lastError = failure is Failure
                  ? failure.message
                  : failure.toString();
              LoggerService.debug('Estratégia falhou: $lastError');
            },
          );
        } on Object catch (e) {
          lastError = e.toString();
          LoggerService.debug('Erro ao testar estratégia: $lastError');
        }
      }

      var errorMessage = 'Não foi possível conectar ao banco de dados Sybase';

      if (lastError.isNotEmpty) {
        final errorLower = lastError.toLowerCase();
        if (errorLower.contains(_pathInstructionsHint) ||
            errorLower.contains('instruções') ||
            errorLower.contains('path_setup')) {
          errorMessage = lastError;
        } else if (errorLower.contains('unable to connect') ||
            errorLower.contains('server not found') ||
            errorLower.contains('connection refused') ||
            errorLower.contains('connection timed out')) {
          errorMessage =
              'Não foi possível conectar ao servidor Sybase. Verifique:\n'
              '1. Se o servidor está rodando\n'
              '2. Se o Engine Name (${config.serverName}) está correto\n'
              '3. Se o DBN (${config.databaseNameValue}) está correto\n'
              '4. Se a porta (${config.portValue}) está correta';
        } else if (errorLower.contains('invalid user') ||
            errorLower.contains('login failed')) {
          errorMessage = 'Usuário ou senha inválidos.';
        } else if (errorLower.contains('already in use')) {
          errorMessage =
              'O banco de dados está em uso. Verifique se o Engine Name está correto.';
        } else {
          errorMessage =
              'Erro ao conectar: $lastError\n\n'
              'Verifique na página de configuração se dbisql está disponível.';
        }
      }

      LoggerService.warning(
        'Todas as estratégias de teste de conexão falharam',
      );
      return rd.Failure(NetworkFailure(message: errorMessage));
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao testar conexão Sybase', e, stackTrace);
      return rd.Failure(
        NetworkFailure(
          message: 'Erro ao testar conexão Sybase: $e',
          originalError: e,
        ),
      );
    }
  }

  String _formatBytes(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) {
      return '${(bytes / 1024).toStringAsFixed(2)} KB';
    }
    if (bytes < 1024 * 1024 * 1024) {
      return '${(bytes / (1024 * 1024)).toStringAsFixed(2)} MB';
    }
    return '${(bytes / (1024 * 1024 * 1024)).toStringAsFixed(2)} GB';
  }

  double _calculateSpeedMbPerSec(int sizeInBytes, int durationSeconds) {
    if (durationSeconds <= 0) return 0;
    final sizeInMb = sizeInBytes / 1024 / 1024;
    return sizeInMb / durationSeconds;
  }
}
