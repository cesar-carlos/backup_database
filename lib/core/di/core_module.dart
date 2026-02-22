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

/// Tipos de erro para operação de drop de tabelas.
enum _DropErrorType {
  /// Erro crítico que impede a operação de reset
  critical,

  /// Erro esperado (tabela já dropada, versão diferente, etc)
  expected,

  /// Erro recuperável (falha temporária que pode ser tratada)
  recoverable,
}

Future<bool> _hasAlreadyResetForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    final flag = await storage.read(key: _resetFlagKey);
    return flag == 'true';
  } catch (e) {
    LoggerService.warning('Erro ao ler flag de reset: $e');
    return false;
  }
}

Future<void> _markResetCompletedForVersion223() async {
  const storage = FlutterSecureStorage();
  try {
    await storage.write(key: _resetFlagKey, value: 'true');
    LoggerService.info('Flag de reset v2.2.3 marcada como concluída');
  } catch (e) {   
    LoggerService.warning('Erro ao gravar flag de reset: $e');
  }
}

Future<bool> _dropConfigTablesForVersion223() async {
  await Future.delayed(const Duration(milliseconds: 500));

  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  LoggerService.info('===== CONFIG TABLES DROP CHECK =====');
  LoggerService.info('Versão do app: $version');
  LoggerService.info('Target version: 2.2.3');

  final targetVersion = Version.parse('2.2.3');
  Version? currentVersion;

  try {
    currentVersion = Version.parse(version.split('+').first);
  } catch (e) {
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
    LoggerService.info('Versão não é exatamente 2.2.3, pulando drop de tabelas');
    return false;
  }

  final hasAlreadyReset = await _hasAlreadyResetForVersion223();
  if (hasAlreadyReset) {
    LoggerService.info('Reset v2.2.3 já foi executado anteriormente');
    return false;
  }

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

    database = sqlite3.sqlite3.open(dbPath);

    try {
      LoggerService.warning('===== CRIANDO BACKUP DAS TABELAS =====');

      final tablesToDrop = [
        'sql_server_configs_table',
        'sybase_configs_table',
        'postgres_configs_table',
      ];

      for (final tableName in tablesToDrop) {
        final backupTableName = '${tableName}$backupSuffix';
        database.execute('ALTER TABLE $tableName RENAME TO $backupTableName');
        LoggerService.info('Backup criado: $backupTableName');
      }

      LoggerService.warning('===== INICIANDO DROP DE TABELAS DE CONFIG =====');

      for (final tableName in tablesToDrop) {
        try {
          database.execute('DROP TABLE IF EXISTS $tableName');
          LoggerService.warning('Tabela dropada: $tableName');
        } catch (e) {
          LoggerService.warning('Erro ao dropar tabela $tableName: $e');
        }
      }

      database.dispose();
      database = null;

      LoggerService.warning('===== DROP DE TABELAS CONCLUÍDO, BACKUPS DISPONÍVEIS =====');

      await _markResetCompletedForVersion223();

      LoggerService.info(
        'Tabelas serão recriadas automaticamente pelo Drift '
        'no próximo acesso. Backups disponíveis para rollback.',
      );

      return true;
    } catch (e) {
      _handleDropError(e);
      return false;
    }
  } catch (e) {
    _handleDropError(e);
    return false;
  } finally {
    database?.dispose();
  }
}

void _handleDropError(Object error) {
  final errorType = _categorizeError(error);

  switch (errorType) {
    case _DropErrorType.critical:
      LoggerService.error(
        'CRÍTICO: Operação de drop não pode continuar: $error',
      );
      break;

    case _DropErrorType.expected:
      LoggerService.info(
        'Esperado: ${_getErrorMessage(errorType)}: $error',
      );
      break;

    case _DropErrorType.recoverable:
      LoggerService.warning(
        'Recuperável: ${_getErrorMessage(errorType)}: $error',
      );
      break;
  }
}

_DropErrorType _categorizeError(Object error) {
  if (error is sqlite3.SqliteException) {
    final sqliteError = error as sqlite3.SqliteException;
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

  if (error is FileSystemException) {
    final fsError = error as FileSystemException;
    if (fsError.osError?.errorCode == 5 || // ERROR_ACCESS_DENIED
        fsError.osError?.errorCode == 32) { // ERROR_SHARING_VIOLATION
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
