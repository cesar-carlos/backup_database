import 'dart:io';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/byte_format.dart';
import 'package:backup_database/core/utils/firebird_embedded_support.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/tool_path_help.dart';
import 'package:backup_database/domain/entities/backup_type.dart';
import 'package:backup_database/domain/entities/firebird_config.dart';
import 'package:backup_database/domain/entities/verify_policy.dart';
import 'package:backup_database/domain/services/backup_execution_context.dart';
import 'package:backup_database/domain/services/backup_execution_result.dart';
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/infrastructure/external/process/firebird/firebird_cli_runner.dart';
import 'package:backup_database/infrastructure/external/process/firebird/firebird_isql_parse.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdBackupService implements IFirebirdBackupService {
  FirebirdBackupService(
    ps.ProcessService processService, {
    bool enableGbakZRuntimeProbe = true,
  }) : _cliRunner = FirebirdCliRunner(
         processService,
         enableGbakZRuntimeProbe: enableGbakZRuntimeProbe,
       );

  final FirebirdCliRunner _cliRunner;

  static const Duration _defaultProbeTimeout = Duration(seconds: 30);

  static final RegExp _pageSizePattern = RegExp(
    r'page\s+size:?\s*(\d+)',
    caseSensitive: false,
  );
  static final RegExp _dataPagesPattern = RegExp(
    r'data\s+pages:\s*(\d+)',
    caseSensitive: false,
  );

  /// Backup logico com chave de criptografia ainda nao e suportado nesta
  /// versao do app. As CLI flags reais do `gbak` (`-CRYPT`, `-KEYHOLDER`,
  /// `-KEYNAME`) exigem o trio combinado para encriptar, e `-key` nao e
  /// switch valido de `gbak` em nenhuma versao do Firebird. Enquanto o
  /// suporte completo (UI + tres campos) nao chega, qualquer config com
  /// `cryptKey` nao vazio e rejeitada antes de o backup comecar (em vez
  /// de gerar comando invalido que confunde o utilizador).
  static ValidationFailure? _rejectCryptKeyIfPresent(FirebirdConfig config) {
    if (config.cryptKey.trim().isEmpty) {
      return null;
    }
    return const ValidationFailure(
      message:
          'Backup logico Firebird com chave de criptografia ainda nao e '
          'suportado nesta versao. A flag real do gbak requer a combinacao '
          '-CRYPT + -KEYHOLDER + -KEYNAME (apenas Firebird 3+). Remova a '
          'chave da configuracao ou aguarde o suporte dedicado no diálogo '
          'de agendamento.',
    );
  }

  @visibleForTesting
  static void resetGbakZProbeCacheForTest() {
    FirebirdCliRunner.resetGbakZProbeCacheForTest();
  }

  static void invalidateGbakZProbeCacheForConfig(FirebirdConfig config) {
    FirebirdCliRunner.invalidateGbakZProbeCacheForConfig(config);
  }

  Future<ValidationFailure?> _validateEmbeddedEnginePlugins(
    FirebirdConfig config,
  ) {
    return FirebirdEmbeddedSupport.validateEmbeddedEnginePlugins(config);
  }

  static int _firebirdNbackupLevel(BackupType backupType) {
    switch (backupType) {
      case BackupType.full:
      case BackupType.fullSingle:
        return 0;
      case BackupType.differential:
      case BackupType.convertedDifferential:
      case BackupType.log:
      case BackupType.convertedLog:
        return 1;
      case BackupType.convertedFullSingle:
        return 0;
    }
  }

  static ValidationFailure? _firebirdNbackupPhysicalLevelOverrideFailure({
    required BackupType backupType,
    required bool useGbak,
    required int? overrideLevel,
  }) {
    if (overrideLevel == null) {
      return null;
    }
    if (useGbak) {
      return const ValidationFailure(
        message:
            'Nivel nbackup (-B) personalizado nao se aplica a Full Single '
            '(gbak). Remova o nivel no agendamento ou use backup fisico Full.',
      );
    }
    if (overrideLevel < 0 || overrideLevel > 9) {
      return const ValidationFailure(
        message: 'Nivel nbackup (-B) invalido: use um inteiro de 0 a 9.',
      );
    }
    switch (backupType) {
      case BackupType.full:
        if (overrideLevel != 0) {
          return const ValidationFailure(
            message:
                'Backup Full fisico Firebird so usa nbackup -B 0. Ajuste o '
                'nivel personalizado no agendamento ou defina 0.',
          );
        }
      case BackupType.differential:
      case BackupType.log:
      case BackupType.convertedDifferential:
      case BackupType.convertedLog:
        if (overrideLevel < 1) {
          return const ValidationFailure(
            message:
                'Tipos incrementais Firebird requerem nbackup -B de 1 a 9. '
                'Remova o nivel personalizado ou use valor entre 1 e 9.',
          );
        }
      case BackupType.fullSingle:
      case BackupType.convertedFullSingle:
        break;
    }
    return null;
  }

  void _warnFirebirdNbackupOperationalSemantics(
    BackupType backupType,
    int nbackupLevel,
  ) {
    if (nbackupLevel < 1) {
      return;
    }
    switch (backupType) {
      case BackupType.log:
      case BackupType.convertedLog:
        LoggerService.warning(
          'Firebird: o agendamento pede tipo "log", mas Firebird nao expoe WAL '
          'como SQL Server. Este backup executa nbackup -B 1 (incremental '
          'fisico) e o historico sera gravado como Diferencial. Requer cadeia '
          'nbackup valida (nivel 0) na mesma base.',
        );
      case BackupType.differential:
      case BackupType.convertedDifferential:
        LoggerService.warning(
          'Firebird nbackup incremental (-B 1): requer backup fisico nivel 0 '
          'previo na mesma base; sem cadeia valida o nbackup falha.',
        );
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.convertedFullSingle:
        break;
    }
  }

  @override
  Future<rd.Result<BackupExecutionResult>> executeBackup({
    required FirebirdConfig config,
    required BackupExecutionContext context,
  }) async {
    if (!_isSupportedBackupType(context.backupType)) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Tipo de backup Firebird nao suportado (Full Single convertido).',
        ),
      );
    }

    final useGbakFlow = context.backupType == BackupType.fullSingle;
    if (context.verifyAfterBackup &&
        !useGbakFlow &&
        context.verifyPolicy == VerifyPolicy.strict) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Politica de verificacao estrita nao e compativel com backup '
              'fisico Firebird (nbackup). Use Full Single (gbak) ou desative '
              'a verificacao / relaxe a politica.',
        ),
      );
    }
    if (context.verifyAfterBackup && !useGbakFlow) {
      LoggerService.warning(
        'Verify after backup ignorado para backup fisico Firebird (nbackup); '
        'apenas Full Single (gbak) suporta verificacao por restauracao local.',
      );
    }

    final cryptKeyFailure = _rejectCryptKeyIfPresent(config);
    if (cryptKeyFailure != null) {
      return rd.Failure(cryptKeyFailure);
    }

    final specResult = _cliRunner.connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    final embeddedFailure = await _validateEmbeddedEnginePlugins(config);
    if (embeddedFailure != null) {
      return rd.Failure(embeddedFailure);
    }

    final resolvedGbakTagline = await _cliRunner.resolveGbakZTagline(
      config,
      context.cancelTag,
    );

    final outputDir = Directory(context.outputDirectory);
    if (!await outputDir.exists()) {
      await outputDir.create(recursive: true);
    }

    final timestamp = DateTime.now().toIso8601String().replaceAll(':', '-');
    final useGbak = useGbakFlow;
    final overrideFailure = _firebirdNbackupPhysicalLevelOverrideFailure(
      backupType: context.backupType,
      useGbak: useGbak,
      overrideLevel: context.firebirdNbackupPhysicalLevel,
    );
    if (overrideFailure != null) {
      return rd.Failure(overrideFailure);
    }
    final nbackupLevel = useGbak
        ? 0
        : (context.firebirdNbackupPhysicalLevel ??
              _firebirdNbackupLevel(context.backupType));
    if (!useGbak) {
      _warnFirebirdNbackupOperationalSemantics(
        context.backupType,
        nbackupLevel,
      );
    }
    final rd.Result<String> nbackupBResult;
    if (useGbak) {
      nbackupBResult = const rd.Success('0');
    } else {
      nbackupBResult = await _cliRunner.resolveNbackupBArgument(
        config: config,
        dbSpec: dbSpec,
        nbackupLevel: nbackupLevel,
        outputDirectory: context.outputDirectory,
        databaseStem: config.primaryDatabase.value,
        resolvedGbakTagline: resolvedGbakTagline,
        backupTimeout: context.backupTimeout,
        cancelTag: context.cancelTag,
      );
    }
    if (nbackupBResult.isError()) {
      return rd.Failure(_asFailure(nbackupBResult.exceptionOrNull()!));
    }
    final nbackupBArg = nbackupBResult.getOrNull()!;
    final backupFileName =
        context.customFileName ??
        (useGbak
            ? '${config.primaryDatabase.value}_fullSingle_$timestamp.fbk'
            : nbackupLevel == 0
            ? '${config.primaryDatabase.value}_full_$timestamp.nbk'
            : '${config.primaryDatabase.value}_nbackup_B$nbackupLevel'
                  '_$timestamp.nbk');
    final backupPath = p.join(context.outputDirectory, backupFileName);

    if (useGbak) {
      LoggerService.info(
        'Iniciando backup Firebird logico (gbak): '
        '${config.primaryDatabase.value}',
      );
      return _cliRunner.runCliBackup(
        executable: 'gbak',
        arguments: <String>[
          '-b',
          ...FirebirdCliRunner.gbakServiceManagerSwitch(config),
          '-user',
          config.username,
          '-pas',
          config.password,
          '-y',
          dbSpec,
          backupPath,
        ],
        backupPath: backupPath,
        config: config,
        context: context,
        failureToolName: 'gbak',
        failureDefaultMessage: 'Falha ao executar gbak',
        metricsTool: 'gbak',
        resolvedGbakTagline: resolvedGbakTagline,
      );
    }

    LoggerService.info(
      'Iniciando backup Firebird fisico (nbackup -B $nbackupBArg): '
      '${config.primaryDatabase.value}',
    );
    // nbackup nao aceita `-SE host/port:service_mgr` (nao existe esse
    // switch na CLI). O remoto via Services Manager exigiria a tool
    // `fbsvcmgr` com switches diferentes (`-action_nbak`, ...) — fora
    // do MVP. Para o cliente/servidor habitual, `nbackup` usa o
    // proprio protocolo Firebird via `dbSpec`.
    return _cliRunner.runCliBackup(
      executable: 'nbackup',
      arguments: <String>[
        '-USER',
        config.username,
        '-PASSWORD',
        config.password,
        '-B',
        nbackupBArg,
        dbSpec,
        backupPath,
      ],
      backupPath: backupPath,
      config: config,
      context: context,
      failureToolName: 'nbackup',
      failureDefaultMessage: 'Falha ao executar nbackup',
      metricsTool: 'nbackup',
      resolvedGbakTagline: resolvedGbakTagline,
    );
  }

  Future<rd.Result<String>> _rawGstatHeaderAfterEmbedded(
    FirebirdConfig config,
  ) async {
    final embeddedFailure = await _validateEmbeddedEnginePlugins(config);
    if (embeddedFailure != null) {
      return rd.Failure(embeddedFailure);
    }
    return _cliRunner.runGstatHeaderProbe(
      config: config,
      timeout: _defaultProbeTimeout,
    );
  }

  Future<rd.Result<String>> _gstatHeaderProbeWithConnectionLogs(
    FirebirdConfig config,
  ) async {
    invalidateGbakZProbeCacheForConfig(config);
    LoggerService.info(
      'Testando conexao Firebird (gstat): ${config.primaryDatabase.value}',
    );
    final probe = await _rawGstatHeaderAfterEmbedded(config);
    return probe.fold(
      (String text) {
        LoggerService.info('Conexao Firebird (gstat) bem-sucedida');
        return rd.Success(text);
      },
      (Object failure) => rd.Failure(_asFailure(failure)),
    );
  }

  @override
  Future<rd.Result<bool>> testConnection(FirebirdConfig config) async {
    final probe = await _gstatHeaderProbeWithConnectionLogs(config);
    return probe.fold(
      (_) => const rd.Success(true),
      (Object failure) => rd.Failure(_asFailure(failure)),
    );
  }

  @override
  Future<rd.Result<FirebirdGstatHeaderProbe>> probeGstatHeaderConnection(
    FirebirdConfig config,
  ) async {
    final probe = await _gstatHeaderProbeWithConnectionLogs(config);
    return probe.fold(
      (String text) {
        final hint = _parseGstatHeaderVersionHint(text) ?? '';
        return rd.Success((versionHint: hint));
      },
      (Object failure) => rd.Failure(_asFailure(failure)),
    );
  }

  @override
  Future<rd.Result<String>> getGstatHeaderVersionHint(
    FirebirdConfig config,
  ) async {
    final probe = await _rawGstatHeaderAfterEmbedded(config);
    return probe.fold(
      (String text) => rd.Success(_parseGstatHeaderVersionHint(text) ?? ''),
      (Object failure) => rd.Failure(_asFailure(failure)),
    );
  }

  @override
  Future<rd.Result<int>> getDatabaseSizeBytes({
    required FirebirdConfig config,
    Duration? timeout,
  }) async {
    final specResult = _cliRunner.connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    final timeoutUsed = timeout ?? _defaultProbeTimeout;
    final fromMon = await _tryGetDatabaseSizeBytesViaMonIsql(
      config: config,
      dbSpec: dbSpec,
      timeout: timeoutUsed,
    );
    if (fromMon != null && fromMon > 0) {
      LoggerService.debug(
        r'Tamanho Firebird via MON$DATABASE (page_size * pages): '
        '${ByteFormat.format(fromMon)}',
      );
      return rd.Success(fromMon);
    }

    final gstatResult = await _getDatabaseSizeBytesFromGstat(
      config: config,
      dbSpec: dbSpec,
      timeout: timeoutUsed,
    );
    if (gstatResult.isSuccess()) {
      return gstatResult;
    }

    final fromFile = await _tryGetDatabaseSizeBytesFromLocalFile(config);
    if (fromFile != null && fromFile > 0) {
      LoggerService.debug(
        'Tamanho Firebird via arquivo local (fallback): '
        '${ByteFormat.format(fromFile)}',
      );
      return rd.Success(fromFile);
    }

    return gstatResult;
  }

  Future<int?> _tryGetDatabaseSizeBytesFromLocalFile(
    FirebirdConfig config,
  ) async {
    if (!config.useEmbedded) {
      return null;
    }
    final path = config.databaseFile.trim();
    if (path.isEmpty) {
      return null;
    }
    try {
      final file = File(path);
      if (!await file.exists()) {
        return null;
      }
      return await file.length();
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'Tamanho Firebird via arquivo local ignorado: $e',
        e,
        stackTrace,
      );
      return null;
    }
  }

  static List<String> _configuredDatabaseDisplayIdentifiers(
    FirebirdConfig config,
  ) {
    final alias = config.aliasName?.trim();
    if (alias != null && alias.isNotEmpty) {
      return <String>[alias];
    }
    final path = config.databaseFile.trim();
    if (path.isNotEmpty) {
      return <String>[path];
    }
    return const <String>[];
  }

  @override
  Future<rd.Result<List<String>>> listDatabases({
    required FirebirdConfig config,
    Duration? timeout,
  }) async {
    LoggerService.info(
      'Resolvendo identificador da base Firebird (MON '
      r'$DATABASE_NAME ou configuracao).',
    );
    final specResult = _cliRunner.connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;
    final timeoutUsed = timeout ?? _defaultProbeTimeout;
    final monResult = await _listMonDatabaseNameViaIsql(
      config: config,
      dbSpec: dbSpec,
      timeout: timeoutUsed,
    );
    return monResult.fold(
      (String nameFromMon) {
        if (nameFromMon.isNotEmpty) {
          return rd.Success(<String>[nameFromMon]);
        }
        return rd.Success(
          List<String>.from(_configuredDatabaseDisplayIdentifiers(config)),
        );
      },
      rd.Failure.new,
    );
  }

  Future<int?> _tryGetDatabaseSizeBytesViaMonIsql({
    required FirebirdConfig config,
    required String dbSpec,
    required Duration timeout,
  }) async {
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('fb_mon_size_');
      final scriptFile = File(p.join(tempDir.path, 'mon_size.sql'));
      const sql = r'''
SET HEADING OFF;
SET LIST OFF;
SELECT CAST(MON$PAGE_SIZE AS BIGINT) * CAST(MON$PAGES AS BIGINT)
FROM MON$DATABASE;
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

      final run = await _cliRunner.runFirebirdCli(
        executable: 'isql',
        arguments: arguments,
        config: config,
        timeout: timeout,
      );

      return run.fold((processResult) {
        if (!processResult.isSuccess) {
          return null;
        }
        final text = '${processResult.stdout}\n${processResult.stderr}';
        return FirebirdIsqlParse.parseSingleIntLine(text);
      }, (_) => null);
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        '${r'Consulta MON$ para tamanho Firebird ignorada: '}$e',
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
            r'Falha ao remover diretorio temporario isql (MON$)',
            e,
            s,
          );
        }
      }
    }
  }

  Future<rd.Result<String>> _listMonDatabaseNameViaIsql({
    required FirebirdConfig config,
    required String dbSpec,
    required Duration timeout,
  }) async {
    Directory? tempDir;
    try {
      tempDir = await Directory.systemTemp.createTemp('fb_mon_dbname_');
      final scriptFile = File(p.join(tempDir.path, 'mon_dbname.sql'));
      const sql = r'''
SET HEADING OFF;
SET LIST OFF;
SELECT MON$DATABASE_NAME FROM MON$DATABASE;
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

      final run = await _cliRunner.runFirebirdCli(
        executable: 'isql',
        arguments: arguments,
        config: config,
        timeout: timeout,
      );

      return run.fold(
        (ps.ProcessResult processResult) {
          if (!processResult.isSuccess) {
            return rd.Failure(
              _cliRunner.failureFromProcess(
                processResult: processResult,
                toolName: 'isql',
                defaultMessage:
                    r'Falha ao listar nome Firebird (MON$DATABASE_NAME)',
                asBackupFailure: true,
              ),
            );
          }
          final text = '${processResult.stdout}\n${processResult.stderr}';
          return rd.Success(FirebirdIsqlParse.parseMonDatabaseName(text) ?? '');
        },
        (Object failure) => rd.Failure(_asFailure(failure)),
      );
    } on Object catch (e, stackTrace) {
      LoggerService.debug(
        'isql MON\$DATABASE_NAME ignorado: $e',
        e,
        stackTrace,
      );
      return rd.Failure(
        BackupFailure(
          message: 'Erro inesperado ao consultar MON\$DATABASE_NAME: $e',
          originalError: e,
        ),
      );
    } finally {
      if (tempDir != null) {
        try {
          if (await tempDir.exists()) {
            await tempDir.delete(recursive: true);
          }
        } on Object catch (e, s) {
          LoggerService.warning(
            r'Falha ao remover diretorio temporario isql (MON$ nome)',
            e,
            s,
          );
        }
      }
    }
  }

  Future<rd.Result<int>> _getDatabaseSizeBytesFromGstat({
    required FirebirdConfig config,
    required String dbSpec,
    required Duration timeout,
  }) async {
    final arguments = <String>[
      '-h',
      '-user',
      config.username,
      '-pas',
      config.password,
      dbSpec,
    ];

    final result = await _cliRunner.runFirebirdCli(
      executable: 'gstat',
      arguments: arguments,
      config: config,
      timeout: timeout,
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

  static bool _isSupportedBackupType(BackupType type) {
    switch (type) {
      case BackupType.full:
      case BackupType.fullSingle:
      case BackupType.differential:
      case BackupType.log:
      case BackupType.convertedDifferential:
      case BackupType.convertedLog:
        return true;
      case BackupType.convertedFullSingle:
        return false;
    }
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

  static String? _parseGstatHeaderVersionHint(String text) {
    if (text.isEmpty) {
      return null;
    }
    final odsMatch = RegExp(
      r'ODS\s+version\s+([\d]+(?:\.[\d]+)?)',
      caseSensitive: false,
    ).firstMatch(text);
    if (odsMatch != null) {
      final ods = odsMatch.group(1)!;
      final family = _firebirdFamilyLabelForOdsMajor(ods);
      return family != null ? 'ODS $ods ($family)' : 'ODS $ods';
    }
    final wiMatch = RegExp(
      r'\b(WI-V[\d.]+[^\s\r\n]*)',
      caseSensitive: false,
    ).firstMatch(text);
    return wiMatch?.group(1);
  }

  static String? _firebirdFamilyLabelForOdsMajor(String ods) {
    final majorStr = ods.split('.').first.trim();
    final major = int.tryParse(majorStr);
    return switch (major) {
      13 => 'Firebird 4.x',
      12 => 'Firebird 3.x',
      11 => 'Firebird 2.5',
      _ => null,
    };
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
