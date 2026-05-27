import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/sql_server_backup_options.dart';
import 'package:backup_database/domain/entities/sql_server_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_sql_server_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;
import 'package:result_dart/result_dart.dart' show unit;

class SqlServerBackupService implements ISqlServerBackupService {
  SqlServerBackupService(this._processService);
  final ps.ProcessService _processService;

  List<String> _baseSqlcmdArgs(SqlServerConfig config) {
    final args = <String>[
      '-S',
      '${config.server},${config.portValue}',
      '-d',
      config.databaseValue,
      '-b',
      '-r',
      '1',
    ];

    if (config.useWindowsAuth || config.username.isEmpty) {
      args.add('-E');
    } else {
      args.addAll(['-U', config.username]);
    }

    return args;
  }

  Map<String, String>? _sqlcmdEnvironment(SqlServerConfig config) {
    if (config.useWindowsAuth || config.username.isEmpty) {
      return null;
    }
    return {'SQLCMDPASSWORD': config.password};
  }

  /// Escapa o conteúdo de um identificador delimitado por colchetes
  /// (`[<identifier>]`) duplicando colchetes de fechamento.
  String _escapeSqlIdentifier(String value) => value.replaceAll(']', ']]');

  /// Escapa o conteúdo de um literal string T-SQL (`N'...'`) duplicando
  /// aspas simples. Sem este escape, um nome de banco contendo `'` quebra
  /// o SQL gerado e potencialmente vira vetor de injection.
  String _escapeSqlString(String value) => value.replaceAll("'", "''");

  /// Verifica o recovery model do banco antes de um backup de log.
  ///
  /// Retorna:
  /// - [rd.Success] quando o modo é `FULL`/`BULK_LOGGED` **ou** quando o
  ///   `sqlcmd` rodou com sucesso mas o `SELECT` voltou vazio (parsing
  ///   inconclusivo — tratado como best-effort para não bloquear
  ///   schedules cujo banco não retorna `recovery_model_desc` em
  ///   versões/configurações específicas).
  /// - [rd.Failure] quando o modo é `SIMPLE` **ou** quando a execução do
  ///   `sqlcmd` falhou (rede, credencial, timeout, exit code ≠ 0). Antes
  ///   o caminho de falha era "fail-open" (assumia FULL e prosseguia
  ///   com o `BACKUP LOG`), que então falhava mais tarde com mensagem
  ///   menos clara para o usuário.
  Future<rd.Result<void>> _checkRecoveryModel(SqlServerConfig config) async {
    const query =
        'SELECT recovery_model_desc FROM sys.databases WHERE name = DB_NAME()';
    final args = [..._baseSqlcmdArgs(config), '-Q', query, '-h', '-1', '-W'];
    final result = await _processService.run(
      executable: 'sqlcmd',
      arguments: args,
      environment: _sqlcmdEnvironment(config),
      timeout: const Duration(seconds: 10),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          final stderr = processResult.stderr.trim();
          return rd.Failure(
            ValidationFailure(
              message:
                  'Não foi possível verificar o recovery model do banco antes '
                  'do backup de log (sqlcmd exit code '
                  '${processResult.exitCode}). Verifique credenciais, rede e '
                  'permissões do usuário SQL Server.\n'
                  '${stderr.isEmpty ? "" : "Detalhes: $stderr"}',
            ),
          );
        }
        final model = processResult.stdout.trim().toUpperCase();
        if (model.isEmpty) {
          // Inconclusive — best-effort: deixa o BACKUP LOG decidir.
          LoggerService.warning(
            'Recovery model check inconclusivo (sqlcmd OK mas stdout vazio). '
            'Prosseguindo com BACKUP LOG (best-effort).',
          );
          return const rd.Success(unit);
        }
        if (model.contains('SIMPLE')) {
          return const rd.Failure(
            ValidationFailure(
              message:
                  'Backup de log de transações não permitido: banco em modo '
                  'SIMPLE. Altere para FULL ou BULK_LOGGED.',
            ),
          );
        }
        return const rd.Success(unit);
      },
      (failure) => rd.Failure(
        ValidationFailure(
          message:
              'Não foi possível verificar o recovery model do banco antes '
              'do backup de log: ${failure is Failure ? failure.message : failure}',
          originalError: failure,
        ),
      ),
    );
  }

  /// Detecta a presença de mensagens de erro reais de SQL Server / sqlcmd
  /// na saída combinada. O matching é mais restrito do que um simples
  /// `contains('error')` para evitar falsos positivos com `RAISERROR(...)`
  /// informativos que mencionam apenas a palavra "msg".
  ///
  /// Nota: `sqlcmd -b` já retorna exit code != 0 em erros reais, portanto
  /// esta função serve como sinal redundante para detectar regressões raras
  /// (ex.: erros de severidade alta com exit code 0 em algumas builds).
  bool _hasSqlcmdErrorOutput(String combinedOutputLower) {
    // Erros do servidor SQL costumam vir como
    // "Msg 3013, Level 16, State 1, Server <name>, Line N".
    // Exigimos os três marcadores juntos para reduzir falso positivo.
    final msgPattern = RegExp(r'\bmsg\s+\d+\b');
    // Antes: r'\blevel\s+1[6-9]|\blevel\s+2[0-5]\b' — sem `\b` na
    // primeira alternativa, casava "level 169" e "level 1900". Agora
    // exige fronteira de palavra após a faixa numérica.
    final levelPattern = RegExp(r'\blevel\s+(1[6-9]|2[0-5])\b');
    if (msgPattern.hasMatch(combinedOutputLower) &&
        levelPattern.hasMatch(combinedOutputLower)) {
      return true;
    }

    // Erros cliente-side do sqlcmd começam com "Sqlcmd: Error:".
    if (combinedOutputLower.contains('sqlcmd: error')) return true;

    return false;
  }

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required SqlServerConfig config,
    required BackupExecutionContext context,
  }) {
    return _executeBackupCore(
      config: config,
      outputDirectory: context.outputDirectory,
      scheduleId: context.scheduleId,
      backupType: context.backupType,
      customFileName: context.customFileName,
      truncateLog: context.truncateLog,
      enableChecksum: context.enableChecksum,
      verifyAfterBackup: context.verifyAfterBackup,
      verifyPolicy: context.verifyPolicy,
      sqlServerBackupOptions: context.sqlServerBackupOptions,
      backupTimeout: context.backupTimeout,
      verifyTimeout: context.verifyTimeout,
      cancelTag: context.cancelTag,
    );
  }

  Future<rd.Result<BackupExecutionResult>> _executeBackupCore({
    required SqlServerConfig config,
    required String outputDirectory,
    required String scheduleId,
    BackupType backupType = BackupType.full,
    String? customFileName,
    bool truncateLog = true,
    bool enableChecksum = false,
    bool verifyAfterBackup = false,
    VerifyPolicy verifyPolicy = VerifyPolicy.none,
    SqlServerBackupOptions? sqlServerBackupOptions,
    Duration? backupTimeout,
    Duration? verifyTimeout,
    String? cancelTag,
  }) async {
    // Tag canônica vinda do orchestrator (geralmente `backup-<historyId>`).
    // Quando não fornecida, mantém o comportamento legado baseado em
    // `scheduleId` para preservar compatibilidade com chamadas antigas.
    final effectiveCancelTag = cancelTag ?? 'backup-$scheduleId';
    final verifyCancelTag = cancelTag ?? 'verify-$scheduleId';
    try {
      // Validação prévia das opções avançadas: sem isso, valores fora
      // de faixa (ex.: maxTransferSize não múltiplo de 64KB) só seriam
      // detectados pelo servidor como `Msg 5009, Level 16, ...`,
      // mensagem opaca para o usuário. Aqui devolvemos `ValidationFailure`
      // com motivo legível antes de gerar T-SQL.
      final optionsToValidate = sqlServerBackupOptions;
      if (optionsToValidate != null) {
        final validation = optionsToValidate.validate();
        if (!validation.isValid) {
          return rd.Failure(
            ValidationFailure(
              message:
                  'Opções SQL Server inválidas: ${validation.errorMessage}',
            ),
          );
        }
      }

      LoggerService.info(
        'Iniciando backup SQL Server: ${config.databaseValue} (Tipo: ${getBackupTypeDisplayName(backupType)})',
      );

      final outputDir = Directory(outputDirectory);
      if (!await outputDir.exists()) {
        await outputDir.create(recursive: true);
      }

      if (backupType == BackupType.log) {
        final preCheckResult = await _checkRecoveryModel(config);
        if (preCheckResult.isError()) {
          final failure = preCheckResult.exceptionOrNull()!;
          return rd.Failure(
            failure is Failure
                ? failure
                : BackupFailure(message: failureUserMessage(failure)),
          );
        }
      }

      final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
      final extension = backupType == BackupType.log ? '.trn' : '.bak';
      final typeSlug = getBackupTypeName(backupType);
      final baseName =
          customFileName ??
          '${config.databaseValue}_${typeSlug}_$timestamp$extension';

      // Striping real: quando `stripingCount > 1`, geramos N arquivos
      // `<base>.partXofN.bak` que o SQL Server escreve em paralelo (cada
      // `TO DISK` adicional vira uma stripe). Anteriormente o valor era
      // só cosmético (gravado em `BackupFlags`), mas o T-SQL gerado tinha
      // apenas um `TO DISK` — agora o striping de fato acontece.
      final requestedStripes = (sqlServerBackupOptions?.stripingCount ?? 1)
          .clamp(1, 4);
      final stripeCount = backupType == BackupType.log ? 1 : requestedStripes;
      final List<String> backupPaths;
      if (stripeCount == 1) {
        backupPaths = [p.join(outputDirectory, baseName)];
      } else {
        final dot = baseName.lastIndexOf('.');
        final stem = dot > 0 ? baseName.substring(0, dot) : baseName;
        final ext = dot > 0 ? baseName.substring(dot) : '';
        backupPaths = List.generate(
          stripeCount,
          (i) =>
              p.join(outputDirectory, '$stem.part${i + 1}of$stripeCount$ext'),
        );
      }
      // Caminho "principal" usado para nomes de arquivo de erro / log;
      // historicamente o serviço retornava um único path. Mantemos o
      // primeiro stripe como representativo e expomos o tamanho total
      // somando todos os arquivos.
      final backupPath = backupPaths.first;

      final escapedDbName = _escapeSqlIdentifier(config.databaseValue);
      // O nome do banco também aparece dentro de literais N'...' (cláusula
      // NAME). Aplicamos o escape de string T-SQL para evitar SQL malformado
      // ou injection caso o nome contenha aspas simples.
      final escapedDbForLiteral = _escapeSqlString(config.databaseValue);

      // Constrói a lista de cláusulas `TO DISK = N'...'` separadas por
      // vírgula (T-SQL aceita até 64 stripes; o options já limita a 4).
      final toDiskClause = backupPaths
          .map(
            (path) =>
                "TO DISK = N'${_escapeSqlString(path.replaceAll(r'\', '/'))}'",
          )
          .join(', ');

      final opts = sqlServerBackupOptions;
      final checksumClause = enableChecksum ? 'CHECKSUM, ' : '';
      final stopOnErrorClause = enableChecksum ? 'STOP_ON_ERROR, ' : '';
      final optionsClause = opts != null ? opts.buildWithClause() : '';
      final statsValue = opts?.statsPercent ?? 10;

      String query;

      switch (backupType) {
        case BackupType.full:
        case BackupType.fullSingle:
          query =
              'BACKUP DATABASE [$escapedDbName] '
              '$toDiskClause '
              'WITH $checksumClause$stopOnErrorClause$optionsClause'
              'NOFORMAT, INIT, '
              "NAME = N'$escapedDbForLiteral-Full Database Backup', "
              'SKIP, NOREWIND, NOUNLOAD, STATS = $statsValue';
        case BackupType.differential:
          query =
              'BACKUP DATABASE [$escapedDbName] '
              '$toDiskClause '
              'WITH DIFFERENTIAL, $checksumClause$stopOnErrorClause$optionsClause'
              'NOFORMAT, INIT, '
              "NAME = N'$escapedDbForLiteral-Differential Database Backup', "
              'SKIP, NOREWIND, NOUNLOAD, STATS = $statsValue';
        case BackupType.log:
          final copyOnlyClause = truncateLog ? '' : 'COPY_ONLY, ';
          query =
              'BACKUP LOG [$escapedDbName] '
              '$toDiskClause '
              'WITH $copyOnlyClause$checksumClause$stopOnErrorClause$optionsClause'
              'NOFORMAT, INIT, '
              "NAME = N'$escapedDbForLiteral-Transaction Log Backup', "
              'SKIP, NOREWIND, NOUNLOAD, STATS = $statsValue';
        case BackupType.convertedDifferential:
        case BackupType.convertedFullSingle:
        case BackupType.convertedLog:
          return const rd.Failure(
            BackupFailure(
              message:
                  'SQL Server não suporta tipos convertidos de backup do Sybase. '
                  'Use um tipo de backup nativo do SQL Server.',
            ),
          );
      }

      final arguments = [..._baseSqlcmdArgs(config), '-Q', query];

      final stopwatch = Stopwatch()..start();
      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        environment: _sqlcmdEnvironment(config),
        timeout: backupTimeout ?? const Duration(hours: 2),
        tag: effectiveCancelTag,
      );

      stopwatch.stop();

      return result.fold((processResult) async {
        final stdout = processResult.stdout;
        final stderr = processResult.stderr;

        final outputLower = (stdout + stderr).toLowerCase();
        if (_hasSqlcmdErrorOutput(outputLower)) {
          LoggerService.error(
            'Backup SQL Server falhou (mensagem de erro detectada)',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: $stdout\n'
              'STDERR: $stderr',
            ),
          );
          // Remove arquivo parcial que possa ter sido criado antes do erro
          // para evitar que cleanups por retenção promovam um `.bak`
          // corrompido como "último backup válido".
          for (final path in backupPaths) {
            await BackupArtifactUtils.safeDeletePartial(path);
          }
          return rd.Failure(
            BackupFailure(
              message:
                  'Erro ao executar backup SQL Server\n'
                  'STDOUT: $stdout\n'
                  'STDERR: $stderr',
            ),
          );
        }

        if (!processResult.isSuccess) {
          LoggerService.error(
            'Backup SQL Server falhou',
            Exception(
              'Exit Code: ${processResult.exitCode}\n'
              'STDOUT: $stdout\n'
              'STDERR: $stderr',
            ),
          );
          for (final path in backupPaths) {
            await BackupArtifactUtils.safeDeletePartial(path);
          }
          return rd.Failure(
            BackupFailure(
              message:
                  'Erro ao executar backup SQL Server (Exit Code: ${processResult.exitCode})\n'
                  'STDERR: $stderr',
            ),
          );
        }

        // Aguarda estabilização de TODOS os stripes e soma seus tamanhos.
        final stablePaths = <String>[];
        for (final path in backupPaths) {
          final file = File(path);
          final ready = await BackupArtifactUtils.waitForStableFile(file);
          if (!ready) {
            // Antes não havia cleanup aqui: stripes parcialmente
            // escritos ficavam no disco indefinidamente após falha.
            for (final partial in backupPaths) {
              await BackupArtifactUtils.safeDeletePartial(partial);
            }
            return rd.Failure(
              BackupFailure(
                message: 'Arquivo de backup não foi criado em: $path',
              ),
            );
          }
          stablePaths.add(path);
        }

        final sizeRes = await BackupSizeCalculator.bytesOfExistingFiles(
          stablePaths,
        );
        if (!sizeRes.isSuccess()) {
          for (final partial in backupPaths) {
            await BackupArtifactUtils.safeDeletePartial(partial);
          }
          return rd.Failure(sizeRes.exceptionOrNull()!);
        }
        final fileSize = sizeRes.getOrNull()!;

        if (fileSize == 0) {
          // Stripes vazios também ficavam no disco. Limpa todos.
          for (final partial in backupPaths) {
            await BackupArtifactUtils.safeDeletePartial(partial);
          }
          return const rd.Failure(
            BackupFailure(
              message: 'Arquivo de backup foi criado mas está vazio',
            ),
          );
        }

        LoggerService.info(
          'Backup SQL Server concluído (${backupPaths.length} stripe(s)): '
          '$backupPath (${ByteFormat.format(fileSize)})',
        );

        // Verificar integridade do backup se solicitado
        final verifyStopwatch = Stopwatch();
        if (verifyAfterBackup) {
          if (!enableChecksum) {
            // RESTORE VERIFYONLY sem CHECKSUM apenas valida o cabeçalho do
            // arquivo; não detecta corrupção real das páginas. Logamos um
            // warning para evitar a falsa sensação de integridade.
            LoggerService.warning(
              'verifyAfterBackup=true sem enableChecksum=true: a verificação '
              'irá apenas validar o header do .bak, sem checagem de '
              'corrupção real. Habilite enableChecksum para verificação '
              'completa.',
            );
          }
          LoggerService.info('Verificando integridade do backup...');
          verifyStopwatch.start();
          // Para backups com striping, RESTORE VERIFYONLY exige TODOS os
          // stripes na mesma ordem em que foram gerados.
          final fromDiskClause = backupPaths
              .map(
                (path) =>
                    "FROM DISK = N'${_escapeSqlString(path.replaceAll(r'\', '/'))}'",
              )
              .join(', ');
          final verifyQuery = enableChecksum
              ? 'RESTORE VERIFYONLY $fromDiskClause WITH CHECKSUM'
              : 'RESTORE VERIFYONLY $fromDiskClause';

          final verifyArguments = [
            ..._baseSqlcmdArgs(config),
            '-Q',
            verifyQuery,
          ];

          final verifyResult = await _processService.run(
            executable: 'sqlcmd',
            arguments: verifyArguments,
            environment: _sqlcmdEnvironment(config),
            timeout: verifyTimeout ?? const Duration(minutes: 30),
            tag: verifyCancelTag,
          );
          verifyStopwatch.stop();

          var verifyFailed = false;
          String? verifyErrorMsg;
          verifyResult.fold(
            (processResult) {
              if (processResult.isSuccess) {
                LoggerService.info(
                  'Verificação de integridade concluída com sucesso',
                );
              } else {
                verifyFailed = true;
                verifyErrorMsg = processResult.stderr;
                LoggerService.warning(
                  'Verificação de integridade falhou: ${processResult.stderr}',
                );
              }
            },
            (failure) {
              verifyFailed = true;
              verifyErrorMsg = failure is Failure
                  ? failure.message
                  : failure.toString();
              LoggerService.warning(
                'Erro ao verificar integridade do backup: $verifyErrorMsg',
              );
            },
          );

          if (verifyFailed && verifyPolicy == VerifyPolicy.strict) {
            return rd.Failure(
              BackupFailure(
                message:
                    'Verificação de integridade falhou: ${verifyErrorMsg ?? "erro desconhecido"}',
              ),
            );
          }
        }

        final backupDuration = stopwatch.elapsed;
        final verifyDuration = verifyAfterBackup
            ? verifyStopwatch.elapsed
            : Duration.zero;
        final totalDuration = backupDuration + verifyDuration;

        final metrics = BackupMetrics(
          totalDuration: totalDuration,
          backupDuration: backupDuration,
          verifyDuration: verifyDuration,
          backupSizeBytes: fileSize,
          backupSpeedMbPerSec: ByteFormat.speedMbPerSec(
            fileSize,
            backupDuration.inSeconds,
          ),
          backupType: getBackupTypeName(backupType),
          flags: BackupFlags(
            compression: sqlServerBackupOptions?.compression ?? false,
            verifyPolicy: verifyAfterBackup ? verifyPolicy.name : 'none',
            stripingCount: sqlServerBackupOptions?.stripingCount ?? 1,
            withChecksum: enableChecksum,
            // STOP_ON_ERROR só vai no T-SQL quando enableChecksum é true
            // (ver bloco de query acima). Antes este flag era reportado
            // como sempre `true` no histórico, divergindo do BACKUP real.
            stopOnError: enableChecksum,
          ),
        );

        return rd.Success(
          BackupExecutionResult(
            backupPath: backupPath,
            fileSize: fileSize,
            duration: totalDuration,
            databaseName: config.databaseValue,
            metrics: metrics,
          ),
        );
      }, rd.Failure.new);
    } on Object catch (e, stackTrace) {
      LoggerService.error('Erro ao executar backup SQL Server', e, stackTrace);
      return rd.Failure(
        BackupFailure(
          message: 'Erro ao executar backup SQL Server: $e',
          originalError: e,
        ),
      );
    }
  }

  @override
  Future<rd.Result<bool>> testConnection(SqlServerConfig config) async {
    try {
      const query = 'SELECT @@VERSION';

      final arguments = [..._baseSqlcmdArgs(config), '-Q', query, '-t', '5'];

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        environment: _sqlcmdEnvironment(config),
        timeout: const Duration(seconds: 10),
      );

      return result.fold(
        (processResult) => rd.Success(processResult.isSuccess),
        rd.Failure.new,
      );
    } on Object catch (e) {
      return rd.Failure(
        NetworkFailure(message: 'Erro ao testar conexão SQL Server: $e'),
      );
    }
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required SqlServerConfig config,
    Duration? timeout,
  }) async {
    try {
      const query =
          "SELECT name FROM sys.databases WHERE name NOT IN ('master', 'tempdb', 'model', 'msdb') ORDER BY name";

      final arguments = [
        ..._baseSqlcmdArgs(config),
        '-Q',
        query,
        '-h',
        '-1',
        '-W',
        '-t',
        '10',
      ];

      final result = await _processService.run(
        executable: 'sqlcmd',
        arguments: arguments,
        environment: _sqlcmdEnvironment(config),
        timeout: timeout ?? const Duration(seconds: 15),
      );

      return result.fold((processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            NetworkFailure(
              message:
                  'Erro ao listar bancos de dados: ${processResult.stderr}',
            ),
          );
        }

        final output = processResult.stdout.trim();
        if (output.isEmpty) {
          return const rd.Success([]);
        }

        final databases = output
            .split('\n')
            .map((line) => line.trim())
            .where((line) => line.isNotEmpty && !line.startsWith('---'))
            .toList();

        LoggerService.debug('Bancos de dados encontrados: ${databases.length}');
        return rd.Success(databases);
      }, rd.Failure.new);
    } on Object catch (e) {
      LoggerService.error('Erro ao listar bancos de dados', e);
      return rd.Failure(
        NetworkFailure(message: 'Erro ao listar bancos de dados: $e'),
      );
    }
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required SqlServerConfig config,
    Duration? timeout,
  }) async {
    // size em sys.master_files está em páginas de 8KB.
    const query =
        'SELECT CAST(SUM(CAST(size AS BIGINT)) * 8192 AS BIGINT) AS bytes '
        'FROM sys.master_files WHERE database_id = DB_ID()';
    final args = [..._baseSqlcmdArgs(config), '-Q', query, '-h', '-1', '-W'];

    final result = await _processService.run(
      executable: 'sqlcmd',
      arguments: args,
      environment: _sqlcmdEnvironment(config),
      timeout: timeout ?? const Duration(seconds: 15),
    );

    return result.fold(
      (processResult) {
        if (!processResult.isSuccess) {
          return rd.Failure(
            BackupFailure(
              message:
                  'Não foi possível obter tamanho do banco SQL Server: '
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
                  'Resposta inválida ao consultar tamanho do banco SQL Server: '
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
