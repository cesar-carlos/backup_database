import 'dart:async';
import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sybase_backup_options.dart';
import 'package:backup_database/domain/entities/sybase_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sybase_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:backup_database/infrastructure/external/process/sybase_connection_strategy_cache.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

/// Extrai mensagem amigável de qualquer Object usado em `result.fold`.
///
/// Substitui o padrão `failure is Failure ? failure.message : failure.toString()`
/// repetido em vários `fold` deste serviço, evitando expor `Failure(...)` no
/// stdout/UI (§5.6 de `architectural_patterns.mdc`) e o cast inseguro §5.2.
String _failureMessage(Object failure) {
  if (failure is Failure) {
    return failure.message;
  }
  return failure.toString();
}

class SybaseBackupService implements ISybaseBackupService {
  SybaseBackupService(
    this._processService, {
    required SybaseConnectionStrategyCache strategyCache,
    bool useCredentialsFile = true,
  }) : _strategyCache = strategyCache,
       _useCredentialsFile = useCredentialsFile {
    // A6: limpa eventuais diretórios `sybase_backup_*` deixados em
    // `Directory.systemTemp` por execuções anteriores que foram mortas
    // antes do `finally` do `_runSybaseToolWithCredentials`. Cada um
    // contém um `args.txt` com `PWD=...` em texto plano. O cleanup é
    // best-effort e roda em background — falhas são logadas em debug.
    unawaited(_cleanupOrphanCredentialDirs());
  }

  final ps.ProcessService _processService;
  final SybaseConnectionStrategyCache _strategyCache;

  /// Quando `true` (default em produção) os utilitários SA são executados
  /// via arquivo temporário de argumentos (`@<file>`) para evitar expor a
  /// senha em `tasklist /v`. Pode ser desabilitado em testes que precisam
  /// inspecionar diretamente os argumentos passados ao `ProcessService`.
  final bool _useCredentialsFile;

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SybaseConfig config,
    required BackupExecutionContext context,
  }) {
    return _executeBackupCore(
      config: config,
      outputDirectory: context.outputDirectory,
      backupType: context.backupType,
      customFileName: context.customFileName,
      dbbackupPath: context.dbbackupPath,
      truncateLog: context.truncateLog,
      verifyAfterBackup: context.verifyAfterBackup,
      verifyPolicy: context.verifyPolicy,
      backupTimeout: context.backupTimeout,
      verifyTimeout: context.verifyTimeout,
      sybaseBackupOptions: context.sybaseBackupOptions,
      cancelTag: context.cancelTag,
    );
  }

  Future<rd.Result<BackupExecutionResult>> _executeBackupCore({
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
    String? cancelTag,
  }) async {
    final options = sybaseBackupOptions ?? SybaseBackupOptions.safeDefaults;

    // C7: validação early-return das opções (CHECKPOINT LOG AUTO exige
    // server-side, blockSize dentro dos limites). Antes dessa checagem,
    // um schedule inválido só falhava no momento do disparo com erro
    // críptico do dbisql/dbbackup.
    final validation = options.validate();
    if (!validation.isValid) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Opções de backup Sybase inválidas: ${validation.errorMessage}',
        ),
      );
    }

    final effectiveLogMode = options.effectiveLogMode(truncateLog: truncateLog);
    // Tag canônica vinda do orchestrator (geralmente `backup-<historyId>`).
    // Quando ausente, mantemos o comportamento legado baseado em `config.id`.
    final effectiveCancelTag = cancelTag ?? 'backup-${config.id}';
    final verifyCancelTag = cancelTag ?? 'verify-${config.id}';
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

      // M3: substitui também `.` (microssegundos) para evitar nomes de
      // diretório como `mydb_log_2026-05-27T09-26-11.123456` que alguns
      // utilitários no Windows interpretam como tendo extensão.
      final timestamp = DateTime.now()
          .toIso8601String()
          .replaceAll(RegExp('[:.]'), '-');
      final typeSlug = effectiveType.name;

      // Agora todos os tipos (inclusive FULL) recebem timestamp único no
      // diretório de destino. Anteriormente backups full reusavam o mesmo
      // diretório (`<dbName>`), o que sobrescrevia o backup anterior antes
      // do upload para destinations e quebrava a cadeia de retenção.
      final folderName =
          customFileName ??
          '${config.databaseNameValue}_${typeSlug}_$timestamp';
      final backupPath = p.join(outputDirectory, folderName);

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

      // Lista única de estratégias dbisql (nome + conn). Substitui o par
      // `dbisqlConnections` + `_dbisqlStrategyNames` que vivia em locais
      // distintos e exigia manter a ordem em sincronia manualmente.
      final dbisqlStrategies = _buildDbisqlStrategies(config, databaseName);

      final cacheKey = effectiveType.name;
      final cached = _strategyCache.get(config.id, cacheKey);

      var sqlBackupSuccess = false;
      // Índices sempre 0-based internamente. O `+1` aparece só nas
      // mensagens de log/strings.
      var dbisqlStrategyIndex = -1;
      var dbbackupStrategyIndex = -1;

      final connectionStrategies = _buildDbbackupStrategies(
        config,
        databaseName,
      );

      // Se a estratégia que funcionou da última vez foi dbbackup, tentamos
      // ela primeiro. As ferramentas SA recebem argumentos via arquivo
      // (`@<file>`) com permissão restrita, mantendo a senha fora do
      // tasklist/cmdline do processo filho.
      if (cached != null &&
          cached.method == SybaseConnectionMethod.dbbackup &&
          cached.strategyIndex < connectionStrategies.length) {
        final strategy = connectionStrategies[cached.strategyIndex];
        LoggerService.debug(
          'Tentando estratégia cacheada dbbackup ${cached.strategyIndex + 1}',
        );
        final args = _buildDbbackupArgs(
          options: options,
          effectiveType: effectiveType,
          effectiveLogMode: effectiveLogMode,
          connectionString: strategy.conn,
          backupPath: backupPath,
        );

        result = await _runSybaseToolWithCredentials(
          executable: executable,
          arguments: args,
          timeout: backupTimeout ?? const Duration(hours: 2),
          tag: effectiveCancelTag,
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
          cached.strategyIndex < dbisqlStrategies.length) {
        final connStr = dbisqlStrategies[cached.strategyIndex].conn;
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
          result = await _runSybaseToolWithCredentials(
            executable: 'dbisql',
            arguments: ['-c', connStr, '-nogui', backupSql],
            timeout: backupTimeout ?? const Duration(hours: 2),
            tag: effectiveCancelTag,
          );

          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                sqlBackupSuccess = true;
                dbisqlStrategyIndex = cached.strategyIndex;
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
        for (var i = 0; i < dbisqlStrategies.length; i++) {
          final connStr = dbisqlStrategies[i].conn;
          dbisqlStrategyIndex = i;
          LoggerService.debug(
            'Tentando dbisql com estratégia '
            '${i + 1}/${dbisqlStrategies.length}',
          );

          final backupSql = _buildBackupSql(
            effectiveType,
            escapedBackupPath,
            effectiveLogMode,
            options,
          );
          if (backupSql == null) {
            await BackupArtifactUtils.safeDeletePartial(backupPath);
            return const rd.Failure(
              BackupFailure(
                message:
                    'Sybase SQL Anywhere não suporta tipos convertidos. '
                    'Use o tipo de backup nativo correspondente.',
              ),
            );
          }

          final dbisqlArgs = ['-c', connStr, '-nogui', backupSql];

          result = await _runSybaseToolWithCredentials(
            executable: 'dbisql',
            arguments: dbisqlArgs,
            timeout: backupTimeout ?? const Duration(hours: 2),
            tag: effectiveCancelTag,
          );

          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                sqlBackupSuccess = true;
                LoggerService.info(
                  'Backup SQL bem-sucedido com estratégia ${i + 1}',
                );
              } else {
                lastError = processResult.stderr;
                LoggerService.debug('dbisql falhou: ${processResult.stderr}');
              }
            },
            (failure) {
              lastError = _failureMessage(failure);
            },
          );

          if (sqlBackupSuccess) break;
        }
      }

      if (!sqlBackupSuccess) {
        LoggerService.info('Backup SQL falhou, tentando dbbackup...');

        for (var i = 0; i < connectionStrategies.length; i++) {
          final strategy = connectionStrategies[i];
          LoggerService.debug('Tentando dbbackup: ${strategy.name}');

          final args = _buildDbbackupArgs(
            options: options,
            effectiveType: effectiveType,
            effectiveLogMode: effectiveLogMode,
            connectionString: strategy.conn,
            backupPath: backupPath,
          );

          result = await _runSybaseToolWithCredentials(
            executable: executable,
            arguments: args,
            timeout: backupTimeout ?? const Duration(hours: 2),
            tag: effectiveCancelTag,
          );

          var success = false;
          result.fold(
            (processResult) {
              if (processResult.isSuccess) {
                success = true;
                dbbackupStrategyIndex = i;
                LoggerService.info(
                  'Backup bem-sucedido com: ${strategy.name}',
                );
              } else {
                lastError = processResult.stderr;
                LoggerService.debug(
                  'Estratégia "${strategy.name}" falhou: ${processResult.stderr}',
                );
              }
            },
            (failure) {
              lastError = _failureMessage(failure);
            },
          );

          if (success) break;
        }
      }

      backupStopwatch.stop();

      if (result == null) {
        await BackupArtifactUtils.safeDeletePartial(backupPath);
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
              dbisqlStrategyIndex,
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

          await BackupArtifactUtils.safeDeletePartial(backupPath);

          return rd.Failure(BackupFailure(message: errorMessage));
        }

        var totalSize = 0;
        var actualBackupPath = backupPath;

        final backupDir = Directory(backupPath);
        final backupFile = File(backupPath);

        var backupFound = false;
        for (var i = 0; i < 10; i++) {
          if (await backupDir.exists()) {
            final dirBytes = await _sumFileLengthsInDirectory(backupDir);
            if (dirBytes > 0) {
              await Future<void>.delayed(const Duration(milliseconds: 200));
              final dirBytes2 = await _sumFileLengthsInDirectory(backupDir);
              if (dirBytes2 == dirBytes) {
                totalSize = dirBytes;
                backupFound = true;
                break;
              }
            }
          }

          if (!backupFound && await backupFile.exists()) {
            final ready = await BackupArtifactUtils.waitForStableFile(
              backupFile,
            );
            if (ready) {
              totalSize = await backupFile.length();
              backupFound = true;
              break;
            }
          }

          if (!backupFound && i < 9) {
            await Future<void>.delayed(const Duration(milliseconds: 500));
          }
        }

        if (!backupFound) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(
            BackupFailure(
              message: _buildBackupNotCreatedMessage(backupPath),
            ),
          );
        }

        if (totalSize == 0) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(
            BackupFailure(
              message: _buildBackupEmptyMessage(backupPath),
            ),
          );
        }

        if (effectiveType == BackupType.log && await backupDir.exists()) {
          final resolvedLogFiles = await _findLogFiles(backupDir);
          if (resolvedLogFiles.isNotEmpty) {
            // Quando há vários arquivos de log no diretório, expomos o mais
            // recente como `actualBackupPath` (compatibilidade) mas somamos
            // todos os tamanhos para refletir o total real do backup.
            actualBackupPath = resolvedLogFiles.first.path;
            var sum = 0;
            for (final file in resolvedLogFiles) {
              sum += await file.length();
            }
            if (sum > 0) {
              totalSize = sum;
            }
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
          'Backup Sybase concluído: $actualBackupPath (${ByteFormat.format(totalSize)})',
        );

        final verification = await _runVerification(
          config: config,
          actualBackupPath: actualBackupPath,
          effectiveType: effectiveType,
          verifyAfterBackup: verifyAfterBackup,
          verifyPolicy: verifyPolicy,
          verifyTimeout: verifyTimeout,
          verifyCancelTag: verifyCancelTag,
        );

        final strictFailure = verification.strictFailureMessage;
        if (strictFailure != null) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(BackupFailure(message: strictFailure));
        }

        final backupDuration = backupStopwatch.elapsed;
        final verifyDuration = verification.duration;
        final totalDuration = backupDuration + verifyDuration;

        final verifyPolicyLabel = _resolveVerifyPolicyLabel(
          verifyAfterBackup: verifyAfterBackup,
          effectiveType: effectiveType,
          verifySuccess: verification.success,
          verificationMethodUsed: verification.methodUsed,
        );

        final sybaseOptionsJson = _buildSybaseOptionsJson(
          options: options,
          verifyPolicyLabel: verifyPolicyLabel,
          dbbackupStrategyIndex: dbbackupStrategyIndex,
          dbisqlStrategyIndex: dbisqlStrategyIndex,
          dbbackupStrategies: connectionStrategies,
          dbisqlStrategies: dbisqlStrategies,
        );

        final metrics = BackupMetrics(
          totalDuration: totalDuration,
          backupDuration: backupDuration,
          verifyDuration: verifyDuration,
          backupSizeBytes: totalSize,
          backupSpeedMbPerSec: ByteFormat.speedMbPerSec(
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

  /// Roda a verificação pós-backup (dbvalid + fallback dbverify) ou
  /// determina que verificação não é aplicável (log).
  ///
  /// Para `effectiveType == log`, retorna `_VerifyOutcome.logUnavailable` e
  /// (em strict) sinaliza falha via `strictFailureMessage` para o caller
  /// abortar antes de montar métricas.
  Future<_VerifyOutcome> _runVerification({
    required SybaseConfig config,
    required String actualBackupPath,
    required BackupType effectiveType,
    required bool verifyAfterBackup,
    required VerifyPolicy verifyPolicy,
    required Duration? verifyTimeout,
    required String verifyCancelTag,
  }) async {
    if (!verifyAfterBackup) {
      return const _VerifyOutcome(
        success: false,
        methodUsed: 'dbvalid',
        duration: Duration.zero,
      );
    }

    if (effectiveType == BackupType.log) {
      // C6: strict + log = decisão explícita de "não há verificação real
      // disponível para log". Em strict, sinalizamos falha via mensagem.
      if (verifyPolicy == VerifyPolicy.strict) {
        return const _VerifyOutcome(
          success: false,
          methodUsed: 'dbvalid',
          duration: Duration.zero,
          strictFailureMessage:
              'Verificação de integridade não disponível para backup '
              'de log Sybase, e modo estrito (strict) foi solicitado. '
              'Use VerifyPolicy.bestEffort para backups de log ou '
              'desabilite "Verificar após backup".',
        );
      }
      LoggerService.info(
        'Verificação não disponível para backup de log; '
        'resultado registrado como indisponível',
      );
      return const _VerifyOutcome(
        success: false,
        methodUsed: 'dbvalid',
        duration: Duration.zero,
      );
    }

    // M2: stopwatch só roda quando há verificação real (full).
    final stopwatch = Stopwatch()..start();
    LoggerService.info('Verificando integridade do backup Sybase...');

    var verifySuccess = false;
    var methodUsed = 'dbvalid';
    var lastVerifyError = '';

    final dir = Directory(actualBackupPath);
    if (await dir.exists()) {
      final backupDbFile = await _tryFindBackupDbFile(dir);
      if (backupDbFile != null) {
        final connStr =
            'UID=${config.username};PWD=${config.password};'
            'DBF=${backupDbFile.path}';

        final dbvalidOutcome = await _runVerifyTool(
          executable: 'dbvalid',
          connectionString: connStr,
          timeout: verifyTimeout,
          tag: verifyCancelTag,
        );
        verifySuccess = dbvalidOutcome.success;
        lastVerifyError = dbvalidOutcome.errorMessage;

        if (!verifySuccess) {
          LoggerService.debug(
            'Tentando fallback dbverify no arquivo: ${backupDbFile.path}',
          );
          final dbverifyOutcome = await _runVerifyTool(
            executable: 'dbverify',
            connectionString: connStr,
            timeout: verifyTimeout,
            tag: verifyCancelTag,
          );
          if (dbverifyOutcome.success) {
            verifySuccess = true;
            methodUsed = 'dbverify';
          } else {
            lastVerifyError = dbverifyOutcome.errorMessage;
          }
        }
      } else {
        lastVerifyError =
            'Não foi possível localizar um arquivo .db no diretório do backup';
      }
    }

    if (!verifySuccess) {
      LoggerService.warning(
        'Verificação de integridade falhou (dbvalid e dbverify): '
        '$lastVerifyError',
      );
      if (verifyPolicy == VerifyPolicy.strict) {
        stopwatch.stop();
        return _VerifyOutcome(
          success: false,
          methodUsed: methodUsed,
          duration: stopwatch.elapsed,
          strictFailureMessage:
              'Verificação de integridade falhou (modo estrito). '
              '$lastVerifyError',
        );
      }
    }
    stopwatch.stop();
    return _VerifyOutcome(
      success: verifySuccess,
      methodUsed: methodUsed,
      duration: stopwatch.elapsed,
    );
  }

  /// Executa um único utilitário de verificação (`dbvalid` ou `dbverify`)
  /// e devolve sucesso + mensagem de erro consolidada.
  Future<_VerifyToolOutcome> _runVerifyTool({
    required String executable,
    required String connectionString,
    required Duration? timeout,
    required String tag,
  }) async {
    final result = await _runSybaseToolWithCredentials(
      executable: executable,
      arguments: ['-c', connectionString],
      timeout: timeout ?? const Duration(minutes: 30),
      tag: tag,
    );
    return result.fold(
      (processResult) {
        if (processResult.isSuccess) {
          LoggerService.info(
            'Verificação de integridade concluída com sucesso ($executable)',
          );
          return const _VerifyToolOutcome(success: true, errorMessage: '');
        }
        final msg = processResult.stderr.isNotEmpty
            ? processResult.stderr
            : processResult.stdout;
        LoggerService.debug('$executable falhou: $msg');
        return _VerifyToolOutcome(success: false, errorMessage: msg);
      },
      (failure) => _VerifyToolOutcome(
        success: false,
        errorMessage: _failureMessage(failure),
      ),
    );
  }

  /// Resolve a etiqueta exibida em `flags.verifyPolicy` /
  /// `sybaseOptions.verificationMethod` na ordem: `none`,
  /// `log_unavailable`, método usado (dbvalid/dbverify) ou `dbvalid_falhou`.
  static String _resolveVerifyPolicyLabel({
    required bool verifyAfterBackup,
    required BackupType effectiveType,
    required bool verifySuccess,
    required String verificationMethodUsed,
  }) {
    if (!verifyAfterBackup) return 'none';
    if (effectiveType == BackupType.log) return 'log_unavailable';
    return verifySuccess ? verificationMethodUsed : 'dbvalid_falhou';
  }

  /// Monta o mapa `sybaseOptions` que vai para `BackupMetrics`, embutindo
  /// `verificationMethod`, `backupMethod` e `connectionStrategy`.
  Map<String, dynamic> _buildSybaseOptionsJson({
    required SybaseBackupOptions options,
    required String verifyPolicyLabel,
    required int dbbackupStrategyIndex,
    required int dbisqlStrategyIndex,
    required List<_SybaseConnectionStrategy> dbbackupStrategies,
    required List<_SybaseConnectionStrategy> dbisqlStrategies,
  }) {
    final json = Map<String, dynamic>.from(options.toJson());
    json['verificationMethod'] = verifyPolicyLabel;
    if (dbbackupStrategyIndex >= 0) {
      json['backupMethod'] = 'dbbackup';
      json['connectionStrategy'] =
          dbbackupStrategies[dbbackupStrategyIndex].name;
    } else {
      json['backupMethod'] = 'dbisql';
      json['connectionStrategy'] =
          dbisqlStrategyIndex >= 0 &&
                  dbisqlStrategyIndex < dbisqlStrategies.length
              ? dbisqlStrategies[dbisqlStrategyIndex].name
              : 'dbisql #${dbisqlStrategyIndex + 1}';
    }
    return json;
  }

  /// Monta a lista de argumentos do `dbbackup` para uma dada estratégia.
  /// Centralizado para eliminar duplicação entre cache hit e fallback loop.
  List<String> _buildDbbackupArgs({
    required SybaseBackupOptions options,
    required BackupType effectiveType,
    required SybaseLogBackupMode effectiveLogMode,
    required String connectionString,
    required String backupPath,
  }) {
    final args = <String>[];
    if (options.serverSide) args.add('-s');
    if (options.blockSize != null) {
      args.addAll(['-b', options.blockSize.toString()]);
    }
    if (effectiveType == BackupType.log) {
      args.addAll(_buildDbbackupLogArgs(effectiveLogMode));
    }
    args.addAll(['-c', connectionString, '-y', backupPath]);
    return args;
  }

  /// Prefixo dos diretórios temporários criados em
  /// [_runSybaseToolWithCredentials]. Específico o suficiente para não
  /// colidir com dirs criados por testes (que tipicamente usam prefixos
  /// como `sybase_backup_test_`) ou outros consumidores de
  /// `Directory.systemTemp`.
  static const String _credentialsTempDirPrefix = 'sybase_backup_creds_';

  /// Remove diretórios `sybase_backup_creds_*` órfãos em `systemTemp`.
  ///
  /// Quando o processo Dart é morto (Task Manager, BSOD, watchdog) antes
  /// do `finally` do [_runSybaseToolWithCredentials] rodar, o diretório
  /// temporário (com o `args.txt` contendo `PWD=...` em texto puro) fica
  /// no disco indefinidamente. Este método varre `systemTemp` no boot do
  /// service e remove diretórios com o prefixo conhecido.
  Future<void> _cleanupOrphanCredentialDirs() async {
    try {
      final tempDir = Directory.systemTemp;
      if (!await tempDir.exists()) return;
      await for (final entity in tempDir.list(followLinks: false)) {
        if (entity is! Directory) continue;
        final name = p.basename(entity.path);
        if (!name.startsWith(_credentialsTempDirPrefix)) continue;
        try {
          await entity.delete(recursive: true);
          LoggerService.debug(
            'Removido diretório órfão de credenciais Sybase: ${entity.path}',
          );
        } on Object catch (e) {
          // Outro processo (talvez outro backup em execução) pode estar
          // segurando o diretório. Skip silencioso — pegaremos no próximo
          // boot.
          LoggerService.debug(
            'Não foi possível remover ${entity.path} (em uso?): $e',
          );
        }
      }
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Cleanup de diretórios órfãos Sybase falhou: $e',
        e,
        stackTrace,
      );
    }
  }

  /// Executa um utilitário Sybase (dbisql/dbbackup) escrevendo a lista de
  /// argumentos em um arquivo temporário e invocando `<exe> @<arquivo>`.
  ///
  /// Vantagens em relação a passar a senha como argumento direto:
  ///  - A connection string (com `PWD=...`) não aparece em ferramentas
  ///    como `tasklist /v`/`wmic process` (Windows) ou `ps -ef` (Linux).
  ///  - O arquivo é criado no diretório temporário do usuário e removido
  ///    no `finally`, mesmo em caso de falha/timeout.
  ///
  /// Se a escrita do arquivo falhar (caso muito raro), faz fallback para a
  /// execução direta com aviso em log para preservar a operação do backup.
  Future<rd.Result<ps.ProcessResult>> _runSybaseToolWithCredentials({
    required String executable,
    required List<String> arguments,
    required Duration timeout,
    String? tag,
  }) async {
    if (!_useCredentialsFile) {
      // Modo de testes/legacy: executa diretamente preservando o array
      // de argumentos para que mocks possam inspecionar a chamada.
      return _processService.run(
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        tag: tag,
      );
    }
    File? credentialsFile;
    try {
      final tempDir = await Directory.systemTemp.createTemp(
        _credentialsTempDirPrefix,
      );
      credentialsFile = File(p.join(tempDir.path, 'args.txt'));
      // Cada argumento em uma linha; valores com espaços já vêm sem aspas
      // (a Sybase Tools faz parsing de uma linha por argumento neste modo).
      final buffer = StringBuffer();
      arguments.forEach(buffer.writeln);
      await credentialsFile.writeAsString(buffer.toString(), flush: true);

      final result = await _processService.run(
        executable: executable,
        arguments: ['@${credentialsFile.path}'],
        timeout: timeout,
        tag: tag,
      );
      return result;
    } on Object catch (e, stackTrace) {
      // M1: degradação de segurança — quando o arquivo de credenciais
      // falha, a senha acaba indo no `arguments` do processo filho
      // (visível em `tasklist /v` no Windows). Logamos como ERRO para
      // garantir visibilidade no painel de logs do app, não warning.
      LoggerService.error(
        'Falha ao usar arquivo de credenciais para $executable; '
        'fazendo fallback para execução direta — a senha pode ficar '
        'visível em `tasklist /v`/`ps -ef` durante a execução. Erro: $e',
        e,
        stackTrace,
      );
      return _processService.run(
        executable: executable,
        arguments: arguments,
        timeout: timeout,
        tag: tag,
      );
    } finally {
      if (credentialsFile != null) {
        try {
          if (await credentialsFile.exists()) {
            await credentialsFile.delete();
          }
          final parent = credentialsFile.parent;
          if (await parent.exists()) {
            await parent.delete(recursive: true);
          }
        } on Object catch (e) {
          LoggerService.debug(
            'Não foi possível remover arquivo temporário de credenciais: $e',
          );
        }
      }
    }
  }

  /// Constrói lista de estratégias dbisql na ordem cronológica de tentativa.
  ///
  /// A ordem aqui define o índice usado pelo cache (`SybaseConnectionStrategyCache`)
  /// e o `connectionStrategy` reportado em `BackupMetrics.sybaseOptions`.
  static List<_SybaseConnectionStrategy> _buildDbisqlStrategies(
    SybaseConfig config,
    String databaseName,
  ) {
    return [
      _SybaseConnectionStrategy(
        name: 'ENG+DBN (serverName + databaseName)',
        conn:
            'ENG=${config.serverName};DBN=$databaseName;'
            'UID=${config.username};PWD=${config.password}',
      ),
      _SybaseConnectionStrategy(
        name: 'Apenas ENG por serverName',
        conn:
            'ENG=${config.serverName};'
            'UID=${config.username};PWD=${config.password}',
      ),
      _SybaseConnectionStrategy(
        name: 'ENG+DBN (databaseName como ambos)',
        conn:
            'ENG=$databaseName;DBN=$databaseName;'
            'UID=${config.username};PWD=${config.password}',
      ),
    ];
  }

  static List<_SybaseConnectionStrategy> _buildDbbackupStrategies(
    SybaseConfig config,
    String databaseName,
  ) {
    return [
      _SybaseConnectionStrategy(
        name: 'ENG+DBN (serverName + databaseName)',
        conn:
            'ENG=${config.serverName};DBN=$databaseName;'
            'UID=${config.username};PWD=${config.password}',
      ),
      _SybaseConnectionStrategy(
        name: 'ENG+DBN (databaseName como ambos)',
        conn:
            'ENG=$databaseName;DBN=$databaseName;'
            'UID=${config.username};PWD=${config.password}',
      ),
      _SybaseConnectionStrategy(
        name: 'Apenas ENG por serverName',
        conn:
            'ENG=${config.serverName};'
            'UID=${config.username};PWD=${config.password}',
      ),
      _SybaseConnectionStrategy(
        name: 'Conexão via TCPIP',
        conn:
            'HOST=localhost:${config.port};DBN=$databaseName;'
            'UID=${config.username};PWD=${config.password};LINKS=TCPIP',
      ),
    ];
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
        final base = "BACKUP DATABASE DIRECTORY '$escapedBackupPath'";
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

  Future<int> _sumFileLengthsInDirectory(Directory dir) =>
      BackupSizeCalculator.sumBytesInDirectoryShallow(dir);

  /// Retorna a lista de arquivos de log encontrados no diretório de backup,
  /// ordenados pelo mais recente primeiro. Quando não há candidatos `.trn`
  /// ou `.log`, retorna todos os arquivos do diretório (também ordenados),
  /// preservando o comportamento anterior de fallback.
  ///
  /// A7: a ordenação consulta `stat()` async em vez de `statSync()` no
  /// comparador (que executava bloqueante ~N·log(N) vezes em diretórios
  /// com muitos arquivos, em filesystems lentos / network shares).
  Future<List<File>> _findLogFiles(Directory backupDir) async {
    try {
      final entities = await backupDir.list().toList();
      final files = entities.whereType<File>().toList();
      if (files.isEmpty) return const [];

      final pairs = await Future.wait(
        files.map((f) async => (f, await f.stat())),
      );
      pairs.sort((a, b) => b.$2.modified.compareTo(a.$2.modified));
      final sorted = pairs.map((pair) => pair.$1).toList();

      final logCandidates = sorted.where((f) {
        final ext = p.extension(f.path).toLowerCase();
        return ext == '.trn' || ext == '.log';
      }).toList();

      if (logCandidates.isNotEmpty) return logCandidates;
      return sorted;
    } on Object catch (_) {
      return const [];
    }
  }

  Future<File?> _tryFindBackupDbFile(Directory backupDir) async {
    try {
      final entities = await backupDir.list().toList();
      final dbFiles = entities
          .whereType<File>()
          .where((f) => p.extension(f.path).toLowerCase() == '.db')
          .toList();
      if (dbFiles.isEmpty) return null;

      // A7: `length()` async em vez de `lengthSync()` no comparador.
      final pairs = await Future.wait(
        dbFiles.map((f) async => (f, await f.length())),
      );
      pairs.sort((a, b) => b.$2.compareTo(a.$2));
      return pairs.first.$1;
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
      // C4: reusa a mesma fonte de estratégias do backup (sem duplicação
      // da composição de connection string).
      final strategies = _buildDbisqlStrategies(config, databaseName);
      // Tag de processo para permitir que o orchestrator/painel de
      // diagnóstico identifique probes de teste de conexão e os agrupe
      // separadamente dos backups de produção.
      final probeTag = 'sybase-test-conn-${config.id}';

      var lastError = '';

      for (var i = 0; i < strategies.length; i++) {
        final connStr = strategies[i].conn;
        try {
          LoggerService.debug(
            'Tentando teste de conexão com estratégia '
            '${i + 1}/${strategies.length}',
          );

          final arguments = ['-c', connStr, '-q', 'SELECT 1', '-nogui'];

          final result = await _runSybaseToolWithCredentials(
            executable: 'dbisql',
            arguments: arguments,
            timeout: const Duration(seconds: 10),
            tag: probeTag,
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
              lastError = _failureMessage(failure);
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

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required SybaseConfig config,
    Duration? timeout,
  }) async {
    final databaseName = config.databaseNameValue;
    final connStr =
        'ENG=${config.serverName};DBN=$databaseName;'
        'UID=${config.username};PWD=${config.password}';
    // db_property('FileSize') retorna o tamanho do arquivo principal em
    // páginas; multiplicamos por PageSize para chegar em bytes.
    const sql =
        "SELECT CAST(db_property('FileSize') AS BIGINT) * "
        "CAST(db_property('PageSize') AS BIGINT)";

    final result = await _runSybaseToolWithCredentials(
      executable: 'dbisql',
      arguments: ['-c', connStr, '-nogui', '-q', sql],
      timeout: timeout ?? const Duration(seconds: 15),
      tag: 'sybase-size-${config.id}',
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Não foi possível obter tamanho do banco Sybase: '
                  '${processResult.stderr}',
            ),
          );
        }
        final raw = processResult.stdout
            .split(RegExp(r'[\r\n]+'))
            .map((l) => l.trim())
            .firstWhere(
              (l) => l.isNotEmpty && int.tryParse(l) != null,
              orElse: () => '',
            );
        final size = int.tryParse(raw);
        if (size == null) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Resposta inválida ao consultar tamanho do banco Sybase: '
                  '${processResult.stdout}',
            ),
          );
        }
        return rd.Success(size);
      },
      rd.Failure.new,
    );
  }
}

/// Par (nome, conn-string) de uma estratégia de conexão Sybase.
///
/// Substitui o par desalinhado `dbisqlConnections` (`List<String>`) +
/// `_dbisqlStrategyNames` (`List<String>`), garantindo que adicionar uma
/// nova estratégia exige editar **um único lugar**.
class _SybaseConnectionStrategy {
  const _SybaseConnectionStrategy({required this.name, required this.conn});

  final String name;
  final String conn;
}

/// Resultado consolidado da fase de verificação pós-backup.
///
/// Substitui um conjunto de variáveis locais (`verifySuccess`,
/// `verificationMethodUsed`, `verifyDuration`, `lastVerifyError`) que
/// poluíam o frame do `_executeBackupCore`. O caller só lê o tipo aqui.
class _VerifyOutcome {
  const _VerifyOutcome({
    required this.success,
    required this.methodUsed,
    required this.duration,
    this.strictFailureMessage,
  });

  final bool success;
  final String methodUsed;
  final Duration duration;

  /// Quando preenchido, indica que o pipeline deve abortar com este
  /// texto em `BackupFailure` (modo strict).
  final String? strictFailureMessage;
}

class _VerifyToolOutcome {
  const _VerifyToolOutcome({required this.success, required this.errorMessage});
  final bool success;
  final String errorMessage;
}
