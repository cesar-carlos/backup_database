import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/firebird_embedded_support.dart';
import 'package:backup_database/core/utils/firebird_nbackup_output_chain_check.dart';
import 'package:backup_database/core/utils/firebird_runtime_version.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/core/utils/unit.dart';
import 'package:backup_database/domain/entities/backup_metrics.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/infrastructure/external/process/firebird/firebird_isql_parse.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdCliRunner {
  FirebirdCliRunner(
    this._processService, {
    this._enableGbakZRuntimeProbe = true,
  });

  final ps.ProcessService _processService;
  final bool _enableGbakZRuntimeProbe;

  static const Duration gbakZProbeTimeout = Duration(seconds: 15);
  static const Duration defaultBackupTimeout = Duration(hours: 2);

  static final Map<String, String> _gbakZTaglineCache = <String, String>{};
  static final RegExp _gbakZWiToken = RegExp(
    r'\bWI-V[\d.]+[^\s\r\n]*',
    caseSensitive: false,
  );

  static String _gbakZCacheKey(FirebirdConfig config) {
    final lib = p
        .normalize((config.clientLibraryPath ?? '').trim())
        .toLowerCase();
    final embedded = config.useEmbedded ? '1' : '0';
    if (config.useEmbedded) {
      final db = p.normalize(config.databaseFile.trim()).toLowerCase();
      return '$embedded|$lib|$db';
    }
    final host = config.host.trim().toLowerCase();
    final port = '${config.portValue}';
    final alias = (config.aliasName ?? '').trim().toLowerCase();
    final db = config.databaseFile.trim().toLowerCase();
    final target = alias.isNotEmpty ? 'alias:$alias' : 'db:$db';
    return '$embedded|$lib|$host|$port|$target';
  }

  static void resetGbakZProbeCacheForTest() {
    _gbakZTaglineCache.clear();
  }

  static void invalidateGbakZProbeCacheForConfig(FirebirdConfig config) {
    _gbakZTaglineCache.remove(_gbakZCacheKey(config));
  }

  Future<rd.Result<ps.ProcessResult>> runFirebirdCli({
    required String executable,
    required List<String> arguments,
    required FirebirdConfig config,
    required Duration timeout,
    String? cancelTag,
  }) {
    return _processService.run(
      executable: executable,
      arguments: arguments,
      environment: _clientLibEnvironment(config),
      timeout: timeout,
      tag: cancelTag,
    );
  }

  Future<String?> resolveGbakZTagline(
    FirebirdConfig config,
    String? cancelTag,
  ) async {
    if (!_enableGbakZRuntimeProbe) {
      return null;
    }
    if (config.serverVersionHint != FirebirdServerVersionHint.auto) {
      return null;
    }
    final key = _gbakZCacheKey(config);
    if (_gbakZTaglineCache.containsKey(key)) {
      final cached = _gbakZTaglineCache[key]!;
      return cached.isEmpty ? null : cached;
    }

    final runResult = await _processService.run(
      executable: 'gbak',
      arguments: const <String>['-z'],
      environment: _clientLibEnvironment(config),
      timeout: gbakZProbeTimeout,
      tag: cancelTag,
    );

    return runResult.fold<String?>(
      (processResult) {
        if (!processResult.isSuccess) {
          LoggerService.warning(
            'gbak -z (hint Auto) falhou (exit ${processResult.exitCode}); '
            'metricas permanecem firebirdVersion=auto. '
            '${processResult.stderr}',
          );
          _gbakZTaglineCache[key] = '';
          return null;
        }
        final combined = '${processResult.stdout}\n${processResult.stderr}';
        final match = _gbakZWiToken.firstMatch(combined);
        final tag = match?.group(0)?.trim();
        if (tag == null || tag.isEmpty) {
          LoggerService.warning(
            'gbak -z (hint Auto) nao retornou token WI-V*; '
            'metricas permanecem firebirdVersion=auto.',
          );
          _gbakZTaglineCache[key] = '';
          return null;
        }
        final clipped = tag.length > 100 ? '${tag.substring(0, 97)}...' : tag;
        _gbakZTaglineCache[key] = clipped;
        return clipped;
      },
      (Object failure) {
        LoggerService.warning('gbak -z (hint Auto) nao executou: $failure');
        _gbakZTaglineCache[key] = '';
        return null;
      },
    );
  }

  static List<String> gbakServiceManagerPair(FirebirdConfig config) {
    return <String>[
      '-SE',
      '${config.host}/${config.portValue}:service_mgr',
    ];
  }

  static List<String> gbakServiceManagerSwitch(FirebirdConfig config) {
    if (config.useEmbedded) {
      return const <String>[];
    }
    switch (config.serviceManagerMode) {
      case FirebirdServiceManagerMode.never:
        return const <String>[];
      case FirebirdServiceManagerMode.always:
        if (config.serverVersionHint == FirebirdServerVersionHint.v25) {
          LoggerService.warning(
            'Firebird: serviceManagerMode=always + hint v2.5 — gbak -SE '
            'omitido (o utilizador escolheu Sempre usar, mas a política '
            'evita Services Manager neste hint). Defina hint 3.0/4.0 se '
            'pretende forcar -SE.',
          );
          return const <String>[];
        }
        return gbakServiceManagerPair(config);
      case FirebirdServiceManagerMode.auto:
        switch (config.serverVersionHint) {
          case FirebirdServerVersionHint.v30:
          case FirebirdServerVersionHint.v40:
            return gbakServiceManagerPair(config);
          case FirebirdServerVersionHint.auto:
          case FirebirdServerVersionHint.v25:
            return const <String>[];
        }
    }
  }

  Future<rd.Result<String>> resolveNbackupBArgument({
    required FirebirdConfig config,
    required String dbSpec,
    required int nbackupLevel,
    required String outputDirectory,
    required String databaseStem,
    required String? resolvedGbakTagline,
    required Duration? backupTimeout,
    String? cancelTag,
  }) async {
    if (nbackupLevel <= 0) {
      return const rd.Success('0');
    }

    final useGuidParent = firebirdRuntimeSupportsNbackupGuidMode(
      serverVersionHint: config.serverVersionHint,
      gbakWiTagline: resolvedGbakTagline,
    );

    if (!useGuidParent) {
      final missingPattern = await missingFirebirdNbackupChainPattern(
        outputDirectory: outputDirectory,
        databaseStem: databaseStem,
        nbackupLevel: nbackupLevel,
      );
      if (missingPattern != null) {
        return rd.Failure(
          ValidationFailure(
            message:
                'Backup incremental Firebird (nbackup -B $nbackupLevel): '
                'na pasta de saida falta ficheiro da cadeia ($missingPattern). '
                'Execute os backups fisicos anteriores nessa pasta ou copie os '
                '.nbk necessarios antes de nivel $nbackupLevel.',
          ),
        );
      }
      return rd.Success('$nbackupLevel');
    }

    final parentLevel = nbackupLevel - 1;
    final parentGuid = await _queryLatestNbackupParentGuid(
      config: config,
      dbSpec: dbSpec,
      parentLevel: parentLevel,
      timeout: backupTimeout ?? defaultBackupTimeout,
      cancelTag: cancelTag,
    );
    if (parentGuid == null || parentGuid.isEmpty) {
      return rd.Failure(
        ValidationFailure(
          message:
              'Firebird 4.0 nbackup -B $nbackupLevel: nao foi encontrado GUID do '
              'backup nivel $parentLevel em RDB\$BACKUP_HISTORY. Execute um '
              'backup fisico nivel 0 (Full) nesta base antes do incremental, ou '
              'use hint de versao 2.5/3.0 se o servidor nao for Firebird 4.',
        ),
      );
    }

    LoggerService.info(
      r'Firebird 4.0 nbackup: parente via GUID do motor (RDB$BACKUP_HISTORY, '
      'nivel $parentLevel).',
    );
    return rd.Success(parentGuid);
  }

  Future<String?> _queryLatestNbackupParentGuid({
    required FirebirdConfig config,
    required String dbSpec,
    required int parentLevel,
    required Duration timeout,
    String? cancelTag,
  }) async {
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('fb_nbackup_guid_');
      final scriptFile = File(p.join(tempDir.path, 'nbackup_parent_guid.sql'));
      // Em algumas builds, RDB$GUID e CHAR(16) CHARACTER SET OCTETS, e o
      // CAST direto para VARCHAR retorna bytes ilegiveis. Preferimos a
      // funcao UUID_TO_CHAR (FB 2.5+) que produz o formato canonico
      // hexadecimal. Em ambientes onde a funcao nao existir, isql vai
      // falhar com erro de funcao desconhecida e o caller cai no fluxo
      // de fallback (mensagem "GUID nao encontrado").
      final sql =
          '''
SET HEADING OFF;
SET LIST OFF;
SELECT FIRST 1 UUID_TO_CHAR(RDB\$GUID)
FROM RDB\$BACKUP_HISTORY
WHERE RDB\$BACKUP_LEVEL = $parentLevel
ORDER BY RDB\$TIMESTAMP DESC;
QUIT;
''';
      await scriptFile.writeAsString(sql, flush: true);

      final arguments = <String>[
        '-q',
        '-user',
        config.username,
        '-password',
        config.password,
        '-i',
        scriptFile.path,
        dbSpec,
      ];

      final run = await runFirebirdCli(
        executable: 'isql',
        arguments: arguments,
        config: config,
        timeout: timeout,
        cancelTag: cancelTag,
      );

      return run.fold((processResult) {
        if (!processResult.isSuccess) {
          LoggerService.warning(
            r'Consulta RDB$BACKUP_HISTORY falhou (exit '
            '${processResult.exitCode}): ${processResult.stderr}',
          );
          return null;
        }
        final text = '${processResult.stdout}\n${processResult.stderr}';
        return FirebirdIsqlParse.parseGuid(text);
      }, (_) => null);
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Consulta RDB\$BACKUP_HISTORY ignorada: $e',
        e,
        stackTrace,
      );
      return null;
    } finally {
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } on Object catch (e, s) {
          LoggerService.warning(
            r'Falha ao remover diretorio temporario isql (RDB$BACKUP_HISTORY)',
            e,
            s,
          );
        }
      }
    }
  }

  Future<rd.Result<BackupExecutionResult>> runCliBackup({
    required String executable,
    required List<String> arguments,
    required String backupPath,
    required FirebirdConfig config,
    required BackupExecutionContext context,
    required String failureToolName,
    required String failureDefaultMessage,
    required String metricsTool,
    String? resolvedGbakTagline,
  }) async {
    final stopwatch = Stopwatch()..start();
    final runResult = await runFirebirdCli(
      executable: executable,
      arguments: arguments,
      config: config,
      timeout: context.backupTimeout ?? defaultBackupTimeout,
      cancelTag: context.cancelTag,
    );
    stopwatch.stop();

    return runResult.fold(
      (processResult) async {
        if (!processResult.isSuccess) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(
            failureFromProcess(
              processResult: processResult,
              toolName: failureToolName,
              defaultMessage: failureDefaultMessage,
              asBackupFailure: true,
            ),
          );
        }

        await BackupArtifactUtils.waitForStableFile(File(backupPath));
        final sizeResult = await BackupSizeCalculator.bytesOfFile(backupPath);
        if (sizeResult.isError()) {
          return rd.Failure(sizeResult.exceptionOrNull()!);
        }
        final totalSize = sizeResult.getOrNull()!;
        if (totalSize == 0) {
          return rd.Failure(
            BackupFailure(
              message: 'Backup Firebird foi criado mas esta vazio',
              originalError: Exception('Backup vazio'),
            ),
          );
        }

        final backupDuration = stopwatch.elapsed;
        var verifyDuration = Duration.zero;
        if (context.verifyAfterBackup) {
          if (metricsTool == 'nbackup') {
            LoggerService.warning(
              'Verify after backup ignorado para backup fisico Firebird '
              '(nbackup); apenas Full Single (gbak) suporta verificacao.',
            );
          } else if (metricsTool == 'gbak') {
            final verifySw = Stopwatch()..start();
            final verifyResult = await _verifyGbakLogicalBackup(
              backupPath: backupPath,
              config: config,
              context: context,
            );
            verifySw.stop();
            verifyDuration = verifySw.elapsed;
            if (verifyResult.isError()) {
              return rd.Failure(verifyResult.exceptionOrNull()!);
            }
          }
        }

        final totalDuration = backupDuration + verifyDuration;
        final metrics = BackupMetrics(
          totalDuration: totalDuration,
          backupDuration: backupDuration,
          verifyDuration: verifyDuration,
          backupSizeBytes: totalSize,
          backupSpeedMbPerSec: ByteFormat.speedMbPerSecFromDuration(
            totalSize,
            backupDuration,
          ),
          backupType: context.backupType.name,
          flags: _flagsForFirebirdBackup(
            config,
            tool: metricsTool,
            verifyPolicyLabel: context.verifyAfterBackup
                ? context.verifyPolicy.name
                : 'none',
            resolvedGbakTagline: resolvedGbakTagline,
          ),
        );
        LoggerService.info(
          'Backup Firebird concluido: $backupPath '
          '(${ByteFormat.format(totalSize)})',
        );
        return rd.Success(
          BackupExecutionResult(
            backupPath: backupPath,
            fileSize: totalSize,
            duration: totalDuration,
            databaseName: config.primaryDatabase.value,
            metrics: metrics,
            executedBackupType: _firebirdExecutedBackupTypeForHistory(
              context.backupType,
            ),
          ),
        );
      },
      rd.Failure.new,
    );
  }

  Future<rd.Result<String>> runGstatHeaderProbe({
    required FirebirdConfig config,
    required Duration timeout,
  }) async {
    final specResult = connectionSpec(config);
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

    final result = await runFirebirdCli(
      executable: 'gstat',
      arguments: arguments,
      config: config,
      timeout: timeout,
    );

    return result.fold(
      (ps.ProcessResult processResult) {
        if (processResult.isSuccess) {
          final text = '${processResult.stdout}\n${processResult.stderr}'
              .trim();
          return rd.Success(text);
        }
        return rd.Failure(
          failureFromProcess(
            processResult: processResult,
            toolName: 'gstat',
            defaultMessage: 'Falha ao validar conexao Firebird',
            asBackupFailure: false,
          ),
        );
      },
      (Object failure) {
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

  rd.Result<String> connectionSpec(FirebirdConfig config) {
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
    return FirebirdEmbeddedSupport.clientLibEnvironment(config);
  }

  Future<rd.Result<void>> _verifyGbakLogicalBackup({
    required String backupPath,
    required FirebirdConfig config,
    required BackupExecutionContext context,
  }) async {
    final stamp =
        '${DateTime.now().microsecondsSinceEpoch}_'
        '${Random().nextInt(1 << 20)}';
    final tempDbPath = p.join(
      Directory.systemTemp.path,
      'fb_verify_$stamp.fdb',
    );
    final logPath = p.join(
      Directory.systemTemp.path,
      'fb_verify_${stamp}_gbak.log',
    );

    Future<void> cleanup() async {
      await BackupArtifactUtils.safeDeletePartial(tempDbPath);
      await BackupArtifactUtils.safeDeletePartial(logPath);
    }

    final arguments = <String>[
      '-c',
      ...gbakServiceManagerSwitch(config),
      backupPath,
      tempDbPath,
      '-user',
      config.username,
      '-pas',
      config.password,
      '-y',
      logPath,
    ];

    try {
      final runResult = await runFirebirdCli(
        executable: 'gbak',
        arguments: arguments,
        config: config,
        timeout: context.verifyTimeout ?? const Duration(minutes: 45),
        cancelTag: context.cancelTag,
      );

      if (runResult.isError()) {
        await cleanup();
        final Object failure = runResult.exceptionOrNull()!;
        final msg = failure is Failure ? failure.message : failure.toString();
        if (context.verifyPolicy == VerifyPolicy.strict) {
          return rd.Failure(
            BackupFailure(message: 'Verificacao gbak -c: $msg'),
          );
        }
        LoggerService.warning('Verificacao gbak -c: $msg');
        return const rd.Success(unit);
      }

      final processResult = runResult.getOrNull()!;
      if (!processResult.isSuccess) {
        final detail = '${processResult.stderr}\n${processResult.stdout}'
            .trim();
        final msg = detail.isEmpty
            ? 'Verificacao gbak -c falhou (exit ${processResult.exitCode}).'
            : 'Verificacao gbak -c falhou: ${detail.split('\n').first.trim()}';
        await cleanup();
        if (context.verifyPolicy == VerifyPolicy.strict) {
          return rd.Failure(
            BackupFailure(
              message: msg,
              originalError: Exception(detail),
            ),
          );
        }
        LoggerService.warning(msg);
        return const rd.Success(unit);
      }

      await cleanup();
      return const rd.Success(unit);
    } on Object catch (e, st) {
      await cleanup();
      LoggerService.warning('Verificacao gbak -c excecao', e, st);
      if (context.verifyPolicy == VerifyPolicy.strict) {
        return rd.Failure(
          BackupFailure(
            message: 'Verificacao gbak -c falhou: $e',
            originalError: e,
          ),
        );
      }
      return const rd.Success(unit);
    }
  }

  static BackupType? _firebirdExecutedBackupTypeForHistory(
    BackupType requested,
  ) {
    switch (requested) {
      case BackupType.log:
      case BackupType.convertedLog:
        return BackupType.differential;
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.differential:
      case BackupType.convertedDifferential:
      case BackupType.convertedFullSingle:
        return null;
    }
  }

  static String _firebirdVersionFlagValue(FirebirdServerVersionHint hint) {
    return switch (hint) {
      FirebirdServerVersionHint.auto => 'auto',
      FirebirdServerVersionHint.v25 => 'v25',
      FirebirdServerVersionHint.v30 => 'v30',
      FirebirdServerVersionHint.v40 => 'v40',
    };
  }

  static String _firebirdVersionForMetrics(
    FirebirdConfig config, {
    String? resolvedGbakTagline,
  }) {
    final base = _firebirdVersionFlagValue(config.serverVersionHint);
    if (config.serverVersionHint != FirebirdServerVersionHint.auto) {
      return base;
    }
    final tag = resolvedGbakTagline?.trim();
    if (tag == null || tag.isEmpty) {
      return base;
    }
    final clipped = tag.length > 100 ? '${tag.substring(0, 97)}...' : tag;
    return 'auto|$clipped';
  }

  static BackupFlags _flagsForFirebirdBackup(
    FirebirdConfig config, {
    required String tool,
    required String verifyPolicyLabel,
    String? resolvedGbakTagline,
  }) {
    return BackupFlags(
      // Firebird (gbak/nbackup) não tem conceito equivalente ao
      // `STOP_ON_ERROR` do SQL Server. Reportar `true` antes era
      // copy/paste enganoso — agora `false` sinaliza "N/A" no
      // histórico/relatório (paridade com AUDIT-12 Postgres e
      // AUDIT-13 Sybase). `compression`, `stripingCount=1`,
      // `withChecksum=false` também são N/A em Firebird neste fluxo;
      // o campo realmente significativo é `firebirdVersion` abaixo.
      compression: false,
      verifyPolicy: verifyPolicyLabel,
      stripingCount: 1,
      withChecksum: false,
      stopOnError: false,
      tool: tool,
      firebirdVersion: _firebirdVersionForMetrics(
        config,
        resolvedGbakTagline: resolvedGbakTagline,
      ),
    );
  }

  Failure failureFromProcess({
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
    } else if (errorLower.contains('incompatible wire encryption') ||
        errorLower.contains('encryption requirements between client')) {
      errorMessage =
          'Requisitos de WireCrypt incompativeis entre cliente e servidor. '
          'No servidor Firebird 4+ ajuste WireCrypt (ex.: Enabled em vez de '
          'Required) ou atualize fbclient/gbak nesta maquina para a mesma '
          'geracao do servidor.';
    } else if (errorLower.contains(
      'your user name and password are not defined',
    )) {
      errorMessage =
          'Autenticacao rejeitada pelo servidor (plugin/protocolo). Em '
          'Firebird 3+ verifique AuthServer em firebird.conf (ex.: '
          'Legacy_Auth, Srp) se precisar de clientes ou contas legadas.';
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
        // Tenta cortar num boundary de palavra para nao quebrar o
        // ultimo token ao meio; cai no corte hard so quando nao ha
        // espaco proximo (raro em saidas de CLI Firebird).
        final softBoundary = errorMessage.lastIndexOf(' ', 200);
        final cut = softBoundary > 150 ? softBoundary : 200;
        errorMessage = '${errorMessage.substring(0, cut)}...';
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
      message: failureUserMessage(failure),
      originalError: failure,
    );
  }
}
