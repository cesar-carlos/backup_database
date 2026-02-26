import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/services/temp_directory_service.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/database_migration_224.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/http/api_client.dart';
import 'package:backup_database/infrastructure/security/secure_credential_service.dart';
import 'package:crypto/crypto.dart';
import 'package:dio/dio.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

const _resetFlagKey = 'reset_v2_2_3_done';

/// P3.2: Fases da operação de reset de tabelas para logging estruturado.
enum _ResetPhase {
  validation,
  backupCreation,
  dropExecution,
  cleanup,
}

/// P3.1 e P3.2: Tipos de erro para operação de drop de tabelas.
enum _DropErrorType {
  /// Erro crítico que impede a operação de reset
  critical,

  /// Erro esperado (tabela já dropada, versão diferente, etc)
  expected,

  /// Erro recuperável (falha temporária que pode ser tratada)
  recoverable,
}

/// P3.2: Classe para medição de tempo das operações de reset.
class _ResetPerformanceMetrics {
  final Map<_ResetPhase, Stopwatch> _stopwatches = {};

  void start(_ResetPhase phase) {
    _stopwatches[phase] = Stopwatch()..start();
  }

  void stop(_ResetPhase phase) {
    _stopwatches[phase]?.stop();
  }

  int getElapsedMs(_ResetPhase phase) {
    return _stopwatches[phase]?.elapsedMilliseconds ?? 0;
  }

  Duration getElapsed(_ResetPhase phase) {
    return Duration(milliseconds: getElapsedMs(phase));
  }

  void dispose() {
    for (final stopwatch in _stopwatches.values) {
      stopwatch.stop();
    }
  }
}

Future<bool> _hasAlreadyResetForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    final flag = await storage.read(key: _resetFlagKey);
    return flag == 'true';
  } on Exception catch (e) {
    LoggerService.warning('Erro ao ler flag de reset: $e');
    return false;
  }
}

Future<void> _markResetCompletedForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _resetFlagKey, value: 'true');
    LoggerService.info('Flag de reset v2.2.3 marcada como concluída');
  } on Exception catch (e) {
    LoggerService.warning('Erro ao gravar flag de reset: $e');
  }
}

Future<bool> _dropConfigTablesForVersion223() async {
  await Future.delayed(const Duration(milliseconds: 500));

  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  final metrics = _ResetPerformanceMetrics();

  // P3.2: FASE 1 - Validação
  metrics.start(_ResetPhase.validation);
  LoggerService.info('===== CONFIG TABLES DROP CHECK =====');
  LoggerService.info('Versão do app: $version');
  LoggerService.info('Target version: 2.2.3');

  final targetVersion = Version.parse('2.2.3');
  Version? currentVersion;

  try {
    currentVersion = Version.parse(version.split('+').first);
  } on Exception catch (e) {
    LoggerService.warning('Versão inválida: $version');
    return false;
  }

  final shouldReset = currentVersion == targetVersion;

  LoggerService.info(
    'Versão parseada: $currentVersion, '
    'Target: $targetVersion, '
    'Reset: $shouldReset',
  );

  if (!shouldReset) {
    LoggerService.info(
      'Versão não é exatamente 2.2.3, pulando drop de tabelas',
    );
    return false;
  }

  final validationElapsedMs = metrics.getElapsedMs(_ResetPhase.validation);
  LoggerService.info('Tempo validação: ${validationElapsedMs}ms');

  final hasAlreadyReset = await _hasAlreadyResetForVersion223();
  if (hasAlreadyReset) {
    LoggerService.info('Reset v2.2.3 já foi executado anteriormente');
    return false;
  }

  final flagCheckElapsedMs = metrics.getElapsedMs(_ResetPhase.validation);
  LoggerService.info('Tempo verificação de flag: ${flagCheckElapsedMs}ms');

  sqlite3.Database? database;

  try {
    final appDataDir = await getApplicationDocumentsDirectory();
    final dbPath = p.join(appDataDir.path, 'backup_database.db');
    final dbFile = File(dbPath);

    if (!await dbFile.exists()) {
      return false;
    }

    final timestamp = DateTime.now().millisecondsSinceEpoch;
    final backupSuffix = '_backup_v2_2_3_$timestamp';

    // P3.2: FASE 2 - Abertura do banco
    metrics.start(_ResetPhase.cleanup);
    LoggerService.info('FASE 2: Abertura do banco');
    database = sqlite3.sqlite3.open(dbPath);

    metrics.stop(_ResetPhase.cleanup);
    final dbOpenElapsedMs = metrics.getElapsedMs(_ResetPhase.cleanup);
    LoggerService.info('Tempo abertura do banco: ${dbOpenElapsedMs}ms');

    try {
      // P3.2: FASE 3 - Criação de backups
      metrics.start(_ResetPhase.backupCreation);
      LoggerService.info('FASE 3: Criação de backups');

      final tablesToDrop = [
        'sql_server_configs_table',
        'sybase_configs_table',
        'postgres_configs_table',
      ];

      for (final tableName in tablesToDrop) {
        final backupTableName = '$tableName$backupSuffix';
        database.execute('ALTER TABLE $tableName RENAME TO $backupTableName');
        LoggerService.info('Backup criado: $backupTableName');
      }

      metrics.stop(_ResetPhase.backupCreation);
      final backupElapsedMs = metrics.getElapsedMs(_ResetPhase.backupCreation);
      LoggerService.info('Tempo criação de backups: ${backupElapsedMs}ms');

      LoggerService.warning('===== INICIANDO DROP DE TABELAS DE CONFIG =====');

      // P3.1: Transação SQLite - Iniciar transação
      metrics.start(_ResetPhase.dropExecution);
      database.execute('BEGIN IMMEDIATE TRANSACTION');
      LoggerService.info('FASE 4: DROP de tabelas - Transação iniciada');

      for (final tableName in tablesToDrop) {
        try {
          database.execute('DROP TABLE IF EXISTS $tableName');
          LoggerService.warning('Tabela dropada: $tableName');
        } on Exception catch (e) {
          LoggerService.warning('Erro ao dropar tabela $tableName: $e');
        }
      }

      // P3.1: Transação SQLite - Commit da transação
      database.execute('COMMIT');

      metrics.stop(_ResetPhase.dropExecution);
      final dropElapsedMs = metrics.getElapsedMs(_ResetPhase.dropExecution);
      LoggerService.info('Tempo DROP de tabelas: ${dropElapsedMs}ms');

      database.dispose();
      database = null;

      LoggerService.warning(
        '===== DROP DE TABELAS CONCLUÍDO, BACKUPS DISPONÍVEIS =====',
      );

      await _markResetCompletedForVersion223();

      LoggerService.info(
        'Tabelas serão recriadas automaticamente pelo Drift '
        'no próximo acesso. Backups disponíveis para rollback.',
      );

      metrics.stop(_ResetPhase.cleanup);
      final cleanupElapsedMs = metrics.getElapsedMs(_ResetPhase.cleanup);
      LoggerService.info('Tempo conclusão: ${cleanupElapsedMs}ms');

      // P3.2: Logging estruturado - Resumo de performance
      final validationTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.validation),
      );
      final flagCheckTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.validation),
      );
      final dbOpenTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.cleanup),
      );
      final backupTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.backupCreation),
      );
      final dropTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.dropExecution),
      );
      final cleanupTime = Duration(
        milliseconds: metrics.getElapsedMs(_ResetPhase.cleanup),
      );
      final totalTime =
          validationTime +
          flagCheckTime +
          dbOpenTime +
          backupTime +
          dropTime +
          cleanupTime;

      LoggerService.info('===== RESUMO DE PERFORMANCE =====');
      LoggerService.info('Validação: ${validationTime.inMilliseconds}');
      LoggerService.info(
        'Verificação de flag: ${flagCheckTime.inMilliseconds}',
      );
      LoggerService.info('Abertura do banco: ${dbOpenTime.inMilliseconds}');
      LoggerService.info('Criação de backups: ${backupTime.inMilliseconds}');
      LoggerService.info('DROP de tabelas: ${dropTime.inMilliseconds}');
      LoggerService.info('Conclusão: ${cleanupTime.inMilliseconds}');
      LoggerService.info('TOTAL: ${totalTime.inMilliseconds}');

      metrics.dispose();

      return true;
    } on Object catch (e) {
      // P3.1: Transação SQLite - Rollback em caso de erro
      database?.execute('ROLLBACK');

      final rollbackElapsedMs = metrics.getElapsedMs(_ResetPhase.dropExecution);
      LoggerService.warning(
        'Tempo rollback de transação: $rollbackElapsedMs',
      );

      _handleDropError(e, metrics);
      return false;
    }
  } on Object catch (e) {
    _handleDropError(e, metrics);
    return false;
  } finally {
    database?.dispose();
    metrics.dispose();
  }
}

void _handleDropError(Object error, [_ResetPerformanceMetrics? metrics]) {
  final errorType = _categorizeError(error);

  switch (errorType) {
    case _DropErrorType.critical:
      LoggerService.error(
        'CRÍTICO: Operação de drop não pode continuar: $error',
      );

    case _DropErrorType.expected:
      LoggerService.info(
        'Esperado: ${_getErrorMessage(errorType)}: $error',
      );

    case _DropErrorType.recoverable:
      LoggerService.warning(
        'Recuperável: ${_getErrorMessage(errorType)}: $error',
      );
  }
}

_DropErrorType _categorizeError(Object error) {
  if (error case final sqlite3.SqliteException sqliteError) {
    final code = sqliteError.extendedResultCode;

    if (code == sqlite3.SqlError.SQLITE_CONSTRAINT ||
        code == sqlite3.SqlError.SQLITE_CORRUPT ||
        code == sqlite3.SqlError.SQLITE_NOTADB ||
        code == sqlite3.SqlError.SQLITE_FORMAT ||
        code == sqlite3.SqlError.SQLITE_FULL) {
      return _DropErrorType.critical;
    }

    if (code == sqlite3.SqlError.SQLITE_BUSY ||
        code == sqlite3.SqlError.SQLITE_LOCKED) {
      return _DropErrorType.recoverable;
    }

    return _DropErrorType.expected;
  }

  if (error case final FileSystemException fsError) {
    if (fsError.osError?.errorCode == 5 || // ERROR_ACCESS_DENIED
        fsError.osError?.errorCode == 32) {
      // ERROR_SHARING_VIOLATION
      return _DropErrorType.critical;
    }
    return _DropErrorType.recoverable;
  }

  return _DropErrorType.recoverable;
}

String _getErrorMessage(_DropErrorType type) {
  switch (type) {
    case _DropErrorType.critical:
      return 'Erro fatal';
    case _DropErrorType.expected:
      return 'Condição normal';
    case _DropErrorType.recoverable:
      return 'Erro recuperável';
  }
}

/// Obtém o diretório de dados do aplicativo sem duplicação de pastas
Future<Directory> getAppDataDirectory() async {
  if (Platform.isWindows) {
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      return Directory(p.join(appData, 'Backup Database'));
    }
  }
  return getApplicationDocumentsDirectory();
}

/// Sets up core services and utilities.
///
/// This module registers fundamental services like logging,
/// encryption, database, HTTP client, and system utilities.
Future<void> setupCoreModule(GetIt getIt) async {
  await _dropConfigTablesForVersion223();

  final exportData224 = await runFullDatabaseMigration224();

  final appDataDir = await getApplicationDocumentsDirectory();
  final logsDirectory = p.join(appDataDir.path, 'logs');

  await LoggerService.init(logsDirectory: logsDirectory);

  final socketLogger = SocketLoggerService(logsDirectory: logsDirectory);
  await socketLogger.initialize();
  getIt.registerSingleton<SocketLoggerService>(socketLogger);

  getIt.registerLazySingleton<ClipboardService>(ClipboardService.new);
  getIt.registerLazySingleton<TempDirectoryService>(TempDirectoryService.new);
  getIt.registerLazySingleton<ISingleInstanceService>(
    SingleInstanceService.new,
  );
  getIt.registerLazySingleton<IIpcService>(IpcService.new);
  getIt.registerLazySingleton<IWindowsMessageBox>(WindowsMessageBox.new);

  getIt.registerLazySingleton<Dio>(Dio.new);
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));

  final databaseName = getDatabaseNameForMode(currentAppMode);
  getIt.registerLazySingleton<AppDatabase>(
    () => AppDatabase(databaseName: databaseName),
  );

  if (exportData224 != null) {
    final db = getIt<AppDatabase>();
    await importMigration224Data(db, exportData224);
  }

  // Security & Encryption
  getIt.registerLazySingleton<IDeviceKeyService>(DeviceKeyService.new);
  final deviceKeyResult = await getIt<IDeviceKeyService>().getDeviceKey();

  if (deviceKeyResult.isSuccess()) {
    final deviceKey = deviceKeyResult.getOrNull()!;
    EncryptionService.initializeWithDeviceKey(deviceKey);
    LoggerService.info(
      'EncryptionService initialized with device-specific key',
    );
  } else {
    LoggerService.warning(
      'Failed to get device key, EncryptionService using legacy key',
    );
  }

  getIt.registerLazySingleton<ISecureCredentialService>(
    SecureCredentialService.new,
  );

  // License
  final licenseSecretKeyResult = await _getOrCreateLicenseSecretKey(getIt);
  if (licenseSecretKeyResult.isError()) {
    final error = licenseSecretKeyResult.exceptionOrNull();
    LoggerService.error(
      'Failed to get license secret key: $error',
    );
  }

  getIt.registerLazySingleton<LicenseGenerationService>(() {
    final secretKey = licenseSecretKeyResult.getOrElse(
      (_) => 'BACKUP_DATABASE_LICENSE_SECRET_2024',
    );
    return LicenseGenerationService(secretKey: secretKey);
  });

  getIt.registerLazySingleton<ILicenseValidationService>(
    () => LicenseValidationService(
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
    ),
  );
}

Future<rd.Result<String>> _getOrCreateLicenseSecretKey(GetIt getIt) async {
  const licenseSecretKey = 'license_secret_key';

  final secureCredentialService = getIt<ISecureCredentialService>();
  final deviceKeyService = getIt<IDeviceKeyService>();

  final existingKeyResult = await secureCredentialService.getPassword(
    key: licenseSecretKey,
  );

  if (existingKeyResult.isSuccess()) {
    final existingKey = existingKeyResult.getOrNull()!;
    if (existingKey.isNotEmpty) {
      LoggerService.info(
        'Using existing license secret key from secure storage',
      );
      return rd.Success(existingKey);
    }
  }

  final deviceKeyResult = await deviceKeyService.getDeviceKey();
  if (deviceKeyResult.isError()) {
    return rd.Failure(deviceKeyResult.exceptionOrNull()!);
  }

  final deviceKey = deviceKeyResult.getOrNull()!;
  final timestamp = DateTime.now().millisecondsSinceEpoch;
  final randomBytes = List<int>.generate(32, (i) => (i + timestamp) % 256);
  final combined = '$deviceKey:$timestamp:${randomBytes.join()}';

  final keyBytes = utf8.encode(combined);
  final digest = sha256.convert(keyBytes);
  final generatedKey = digest.toString();

  final storeResult = await secureCredentialService.storePassword(
    key: licenseSecretKey,
    password: generatedKey,
  );

  if (storeResult.isError()) {
    return rd.Failure(storeResult.exceptionOrNull()!);
  }

  LoggerService.info('Generated and stored new license secret key');
  return rd.Success(generatedKey);
}
