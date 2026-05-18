import 'dart:io';
import 'dart:math';

import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/utils/backup_artifact_utils.dart';
import 'package:backup_database/core/utils/backup_size_calculator.dart';
import 'package:backup_database/core/utils/byte_format.dart';
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
import 'package:backup_database/domain/services/i_firebird_backup_service.dart';
import 'package:backup_database/domain/value_objects/firebird_config_enums.dart';
import 'package:backup_database/infrastructure/external/process/process_service.dart'
    as ps;
import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:result_dart/result_dart.dart' as rd;

class FirebirdBackupService implements IFirebirdBackupService {
  FirebirdBackupService(
    this._processService, {
    bool enableGbakZRuntimeProbe = true,
  }) : _enableGbakZRuntimeProbe = enableGbakZRuntimeProbe;

  final ps.ProcessService _processService;
  final bool _enableGbakZRuntimeProbe;

  static const Duration _gbakZProbeTimeout = Duration(seconds: 15);
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

  static List<String> _gbakCryptCliArgs(
    FirebirdConfig config, {
    String? resolvedGbakTagline,
  }) {
    final key = config.cryptKey.trim();
    if (key.isEmpty) {
      return const <String>[];
    }
    if (firebirdGbakUsesKeyNameEncryption(
      serverVersionHint: config.serverVersionHint,
      gbakWiTagline: resolvedGbakTagline,
    )) {
      return <String>['-KEYNAME', key];
    }
    return <String>['-key', key];
  }

  static void _warnCryptKeyServerHintMismatch(FirebirdConfig config) {
    if (config.cryptKey.trim().isEmpty) {
      return;
    }
    if (config.serverVersionHint == FirebirdServerVersionHint.v25) {
      LoggerService.warning(
        'Firebird: chave de criptografia configurada com hint 2.5; gbak usa '
        '-key (plugin legado). Para criptografia nativa Firebird 4 (-KEYNAME), '
        'defina hint 4.0 ou Automatico com gbak -z.',
      );
    }
  }

  @visibleForTesting
  static void resetGbakZProbeCacheForTest() {
    _gbakZTaglineCache.clear();
  }

  static void invalidateGbakZProbeCacheForConfig(FirebirdConfig config) {
    _gbakZTaglineCache.remove(_gbakZCacheKey(config));
  }

  static const Duration _defaultProbeTimeout = Duration(seconds: 30);
  static const Duration _defaultBackupTimeout = Duration(hours: 2);

  static final RegExp _pageSizePattern = RegExp(
    r'page\s+size:?\s*(\d+)',
    caseSensitive: false,
  );
  static final RegExp _dataPagesPattern = RegExp(
    r'data\s+pages:\s*(\d+)',
    caseSensitive: false,
  );
  static final RegExp _isqlSingleIntLine = RegExp(r'^\s*(\d+)\s*$');
  static final RegExp _isqlGuidLine = RegExp(
    r'^\s*(\{?[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}\}?)\s*$',
  );

  static const String _engine12Dll = 'engine12.dll';
  static const String _engine13Dll = 'engine13.dll';

  static const String _legacyAuthProviderDllName = 'Engine12';
  static const String _legacyAuthRejectedSnake =
      'your user name and password are not defined';

  static String _combinedProcessOutput(ps.ProcessResult result) =>
      '${result.stderr}\n${result.stdout}'.trim();

  static bool _processOutputImpliesLegacyAuthPluginRejection(
    String combined,
  ) {
    return combined.toLowerCase().contains(_legacyAuthRejectedSnake);
  }

  static bool _firebirdConfigAllowsLegacyProviderRetry(FirebirdConfig config) {
    return config.serverVersionHint != FirebirdServerVersionHint.v25;
  }

  static bool _argsContainLegacyProvider(List<String> args) {
    for (var i = 0; i < args.length - 1; i++) {
      if (args[i].toLowerCase() == '-provider' &&
          args[i + 1].toLowerCase() ==
              _legacyAuthProviderDllName.toLowerCase()) {
        return true;
      }
    }
    return false;
  }

  static int? _indexOfArgIgnoreCase(List<String> args, String flag) {
    final lower = flag.toLowerCase();
    for (var i = 0; i < args.length; i++) {
      if (args[i].toLowerCase() == lower) {
        return i;
      }
    }
    return null;
  }

  static List<String>? _argumentsWithInjectedLegacyProvider({
    required String executable,
    required List<String> arguments,
  }) {
    if (_argsContainLegacyProvider(arguments)) {
      return null;
    }
    switch (executable) {
      case 'gbak':
        final anchor =
            _indexOfArgIgnoreCase(arguments, '-b') ??
            _indexOfArgIgnoreCase(arguments, '-c');
        if (anchor == null) {
          return null;
        }
        return <String>[
          ...arguments.sublist(0, anchor + 1),
          '-PROVIDER',
          _legacyAuthProviderDllName,
          ...arguments.sublist(anchor + 1),
        ];
      case 'nbackup':
        return <String>[
          '-PROVIDER',
          _legacyAuthProviderDllName,
          ...arguments,
        ];
      case 'gstat':
        final iH = _indexOfArgIgnoreCase(arguments, '-h');
        if (iH == null) {
          return null;
        }
        return <String>[
          ...arguments.sublist(0, iH + 1),
          '-PROVIDER',
          _legacyAuthProviderDllName,
          ...arguments.sublist(iH + 1),
        ];
      case 'isql':
        final iQ = _indexOfArgIgnoreCase(arguments, '-q');
        if (iQ == null) {
          return <String>[
            '-PROVIDER',
            _legacyAuthProviderDllName,
            ...arguments,
          ];
        }
        return <String>[
          ...arguments.sublist(0, iQ + 1),
          '-PROVIDER',
          _legacyAuthProviderDllName,
          ...arguments.sublist(iQ + 1),
        ];
      default:
        return null;
    }
  }

  Future<rd.Result<ps.ProcessResult>> _runFirebirdCliWithOptionalLegacyRetry({
    required String executable,
    required List<String> arguments,
    required FirebirdConfig config,
    required Duration timeout,
    String? cancelTag,
  }) async {
    var args = List<String>.from(arguments);

    Future<rd.Result<ps.ProcessResult>> runOnce() {
      return _processService.run(
        executable: executable,
        arguments: args,
        environment: _clientLibEnvironment(config),
        timeout: timeout,
        tag: cancelTag,
      );
    }

    final first = await runOnce();
    if (first.isError()) {
      return first;
    }
    final firstProcess = first.getOrNull()!;
    if (firstProcess.isSuccess) {
      return first;
    }
    if (!_firebirdConfigAllowsLegacyProviderRetry(config) ||
        !_processOutputImpliesLegacyAuthPluginRejection(
          _combinedProcessOutput(firstProcess),
        )) {
      return first;
    }
    final next = _argumentsWithInjectedLegacyProvider(
      executable: executable,
      arguments: args,
    );
    if (next == null) {
      return first;
    }
    args = next;
    LoggerService.warning(
      'Firebird ($executable): autenticacao rejeitada na primeira '
      'tentativa (plugin/protocolo). Nova execucao com -PROVIDER '
      '$_legacyAuthProviderDllName (modo compativel). Em Firebird 3+ '
      'considere AuthServer em firebird.conf (ex.: Legacy_Auth, Srp).',
    );

    return runOnce();
  }

  Future<ValidationFailure?> _validateEmbeddedEnginePlugins(
    FirebirdConfig config,
  ) async {
    if (!config.useEmbedded || !Platform.isWindows) {
      return null;
    }
    if (config.serverVersionHint == FirebirdServerVersionHint.v25) {
      return null;
    }

    final clientRaw = config.clientLibraryPath?.trim();
    if (clientRaw == null || clientRaw.isEmpty) {
      return const ValidationFailure(
        message:
            'Modo embedded Firebird 3.0+ no Windows requer Client library path '
            '(fbclient.dll) para validar a pasta plugins (engine12.dll / '
            'engine13.dll).',
      );
    }

    final clientAbs = p.normalize(File(clientRaw).absolute.path);
    if (!await File(clientAbs).exists()) {
      return ValidationFailure(
        message: 'Client library Firebird nao encontrado: $clientAbs',
      );
    }

    final binDir = p.dirname(clientAbs);
    final installRoot = p.normalize(p.join(binDir, '..'));
    final pluginsDir = p.join(installRoot, 'plugins');

    final hint = config.serverVersionHint;
    if (hint == FirebirdServerVersionHint.v40) {
      if (!await File(p.join(pluginsDir, _engine13Dll)).exists()) {
        return ValidationFailure(
          message:
              'Firebird embedded 4.0: nao encontrado $_engine13Dll em '
              "'$pluginsDir'. Use uma instalacao completa do servidor ou "
              'copie os plugins para essa pasta.',
        );
      }
      return null;
    }
    if (hint == FirebirdServerVersionHint.v30) {
      if (!await File(p.join(pluginsDir, _engine12Dll)).exists()) {
        return ValidationFailure(
          message:
              'Firebird embedded 3.0: nao encontrado $_engine12Dll em '
              "'$pluginsDir'. Use uma instalacao completa do servidor ou "
              'copie os plugins para essa pasta.',
        );
      }
      return null;
    }
    if (hint == FirebirdServerVersionHint.auto) {
      final has12 = await File(p.join(pluginsDir, _engine12Dll)).exists();
      final has13 = await File(p.join(pluginsDir, _engine13Dll)).exists();
      if (!has12 && !has13) {
        return ValidationFailure(
          message:
              'Firebird embedded (hint Auto): nao encontrado $_engine12Dll '
              'nem $_engine13Dll em '
              "'$pluginsDir'. Confira a instalacao ou defina o hint de "
              'versao (3.0 / 4.0).',
        );
      }
    }

    return null;
  }

  Future<String?> _resolveGbakZTagline(
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
      timeout: _gbakZProbeTimeout,
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
        final clipped = tag.length > 120 ? '${tag.substring(0, 117)}...' : tag;
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

  static List<String> _firebirdServiceManagerPair(FirebirdConfig config) {
    return <String>[
      '-SE',
      '${config.host}/${config.portValue}:service_mgr',
    ];
  }

  static List<String> _firebirdServiceManagerSwitch(FirebirdConfig config) {
    if (config.useEmbedded) {
      return const <String>[];
    }
    switch (config.serviceManagerMode) {
      case FirebirdServiceManagerMode.never:
        return const <String>[];
      case FirebirdServiceManagerMode.always:
        if (config.serverVersionHint == FirebirdServerVersionHint.v25) {
          return const <String>[];
        }
        return _firebirdServiceManagerPair(config);
      case FirebirdServiceManagerMode.auto:
        switch (config.serverVersionHint) {
          case FirebirdServerVersionHint.v30:
          case FirebirdServerVersionHint.v40:
            return _firebirdServiceManagerPair(config);
          case FirebirdServerVersionHint.auto:
          case FirebirdServerVersionHint.v25:
            return const <String>[];
        }
    }
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

  Future<rd.Result<String>> _resolveNbackupBArgument({
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
      timeout: backupTimeout ?? _defaultBackupTimeout,
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
      final sql =
          '''
SET HEADING OFF;
SET LIST OFF;
SELECT FIRST 1 TRIM(CAST(RDB\$GUID AS VARCHAR(38)))
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

      final run = await _runFirebirdCliWithOptionalLegacyRetry(
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
        return _parseGuidFromIsql(text);
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

  static String? _parseGuidFromIsql(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (_isIsqlNoiseLine(line)) {
        continue;
      }
      final m = _isqlGuidLine.firstMatch(line);
      if (m != null) {
        return m.group(1);
      }
      if (line.isNotEmpty) {
        return line;
      }
    }
    return null;
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

    final specResult = _connectionSpec(config);
    if (specResult.isError()) {
      return rd.Failure(_asFailure(specResult.exceptionOrNull()!));
    }
    final dbSpec = specResult.getOrNull()!;

    if (!useGbakFlow && config.cryptKey.trim().isNotEmpty) {
      return const rd.Failure(
        ValidationFailure(
          message:
              'Chave de criptografia (AES) so se aplica ao backup logico '
              'com gbak. Use tipo Full Single ou remova a chave para backup '
              'fisico (nbackup).',
        ),
      );
    }

    final embeddedFailure = await _validateEmbeddedEnginePlugins(config);
    if (embeddedFailure != null) {
      return rd.Failure(embeddedFailure);
    }

    final resolvedGbakTagline = await _resolveGbakZTagline(
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
      nbackupBResult = await _resolveNbackupBArgument(
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
      _warnCryptKeyServerHintMismatch(config);
      LoggerService.info(
        'Iniciando backup Firebird logico (gbak): '
        '${config.primaryDatabase.value}',
      );
      return _runCliBackup(
        executable: 'gbak',
        arguments: <String>[
          '-b',
          ..._firebirdServiceManagerSwitch(config),
          '-user',
          config.username,
          '-pas',
          config.password,
          '-y',
          ..._gbakCryptCliArgs(
            config,
            resolvedGbakTagline: resolvedGbakTagline,
          ),
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
    return _runCliBackup(
      executable: 'nbackup',
      arguments: <String>[
        '-USER',
        config.username,
        '-PASSWORD',
        config.password,
        ..._firebirdServiceManagerSwitch(config),
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

  Future<rd.Result<BackupExecutionResult>> _runCliBackup({
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
    final runResult = await _runFirebirdCliWithOptionalLegacyRetry(
      executable: executable,
      arguments: arguments,
      config: config,
      timeout: context.backupTimeout ?? _defaultBackupTimeout,
      cancelTag: context.cancelTag,
    );
    stopwatch.stop();

    return runResult.fold(
      (processResult) async {
        if (!processResult.isSuccess) {
          await BackupArtifactUtils.safeDeletePartial(backupPath);
          return rd.Failure(
            _failureFromProcess(
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
              resolvedGbakTagline: resolvedGbakTagline,
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

  Future<rd.Result<String>> _runGstatHeaderProbe({
    required FirebirdConfig config,
    required Duration timeout,
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

    final result = await _runFirebirdCliWithOptionalLegacyRetry(
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
          _failureFromProcess(
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

  Future<rd.Result<String>> _rawGstatHeaderAfterEmbedded(
    FirebirdConfig config,
  ) async {
    final embeddedFailure = await _validateEmbeddedEnginePlugins(config);
    if (embeddedFailure != null) {
      return rd.Failure(embeddedFailure);
    }
    return _runGstatHeaderProbe(
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
    final specResult = _connectionSpec(config);
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
    final specResult = _connectionSpec(config);
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

      final run = await _runFirebirdCliWithOptionalLegacyRetry(
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
        return _parseSingleIntLineFromIsql(text);
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

      final run = await _runFirebirdCliWithOptionalLegacyRetry(
        executable: 'isql',
        arguments: arguments,
        config: config,
        timeout: timeout,
      );

      return run.fold(
        (ps.ProcessResult processResult) {
          if (!processResult.isSuccess) {
            return rd.Failure(
              _failureFromProcess(
                processResult: processResult,
                toolName: 'isql',
                defaultMessage:
                    r'Falha ao listar nome Firebird (MON$DATABASE_NAME)',
                asBackupFailure: true,
              ),
            );
          }
          final text = '${processResult.stdout}\n${processResult.stderr}';
          return rd.Success(_parseMonDatabaseNameFromIsql(text) ?? '');
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

  static bool _isIsqlNoiseLine(String line) {
    final t = line.trim();
    if (t.isEmpty) {
      return true;
    }
    final lower = t.toLowerCase();
    if (lower.startsWith('set ')) {
      return true;
    }
    if (lower == 'quit' ||
        lower == 'exit' ||
        lower == 'commit' ||
        lower == 'rollback') {
      return true;
    }
    if (lower.startsWith('select ')) {
      return true;
    }
    if (t.startsWith('SQL>')) {
      return true;
    }
    if (RegExp(r'^=+$').hasMatch(t)) {
      return true;
    }
    if (lower.startsWith('database:')) {
      return true;
    }
    return false;
  }

  static String? _parseMonDatabaseNameFromIsql(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (_isIsqlNoiseLine(line)) {
        continue;
      }
      if (_isqlSingleIntLine.hasMatch(line)) {
        continue;
      }
      return line;
    }
    return null;
  }

  static int? _parseSingleIntLineFromIsql(String text) {
    final lines = text.split(RegExp(r'[\r\n]+'));
    for (var i = lines.length - 1; i >= 0; i--) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        continue;
      }
      final m = _isqlSingleIntLine.firstMatch(line);
      if (m != null) {
        return int.tryParse(m.group(1)!);
      }
    }
    return null;
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

    final result = await _runFirebirdCliWithOptionalLegacyRetry(
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
      compression: false,
      verifyPolicy: verifyPolicyLabel,
      stripingCount: 1,
      withChecksum: false,
      stopOnError: true,
      tool: tool,
      firebirdVersion: _firebirdVersionForMetrics(
        config,
        resolvedGbakTagline: resolvedGbakTagline,
      ),
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

  Future<rd.Result<void>> _verifyGbakLogicalBackup({
    required String backupPath,
    required FirebirdConfig config,
    required BackupExecutionContext context,
    String? resolvedGbakTagline,
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
      await _deletePathBestEffort(File(tempDbPath));
      await _deletePathBestEffort(File(logPath));
    }

    final arguments = <String>[
      '-c',
      ..._firebirdServiceManagerSwitch(config),
      backupPath,
      tempDbPath,
      '-user',
      config.username,
      '-pas',
      config.password,
      '-y',
      logPath,
      ..._gbakCryptCliArgs(
        config,
        resolvedGbakTagline: resolvedGbakTagline,
      ),
    ];

    try {
      final runResult = await _runFirebirdCliWithOptionalLegacyRetry(
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

  static Future<void> _deletePathBestEffort(File file) async {
    try {
      if (await file.exists()) {
        await file.delete();
      }
    } on Object {
      // ignore
    }
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
