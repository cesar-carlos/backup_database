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
import 'package:get_it/get_it.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:result_dart/result_dart.dart' as rd;
import 'package:sqlite3/sqlite3.dart' as sqlite3;

/// Drop das tabelas de configuração de banco de dados para a versão 2.2.3.
///
/// Executa DROP TABLE nas tabelas de configuração (SQL Server, Sybase, PostgreSQL)
/// para forçar recriação limpa na próxima inicialização.
Future<void> _dropConfigTablesForVersion222() async {
  await Future.delayed(const Duration(milliseconds: 500));

  final packageInfo = await PackageInfo.fromPlatform();
  final version = packageInfo.version;

  LoggerService.info('===== CONFIG TABLES DROP CHECK =====');
  LoggerService.info('Versão do app: $version');
  LoggerService.info('Target version: 2.2.3');

  final shouldReset = version.startsWith('2.2.3');
  LoggerService.info('Deve dropar tabelas: $shouldReset');

  if (!shouldReset) {
    LoggerService.info('Versão não é 2.2.3, pulando drop de tabelas');
    return;
  }

  try {
    final appDataDir = await _getAppDataDirectory();
    final dbPath = p.join(appDataDir.path, 'backup_database.db');
    final dbFile = File(dbPath);

    LoggerService.info('Caminho do banco de dados: $dbPath');
    LoggerService.info('Arquivo existe: ${await dbFile.exists()}');

    if (!await dbFile.exists()) {
      LoggerService.info('Banco de dados não encontrado, nada para dropar');
      return;
    }

    LoggerService.warning('===== INICIANDO DROP DE TABELAS DE CONFIG =====');

    final database = await openSqliteApi(dbPath);

    final tablesToDrop = [
      'sql_server_configs_table',
      'sybase_configs_table',
      'postgres_configs_table',
    ];

    for (final tableName in tablesToDrop) {
      try {
        database.execute('DROP TABLE IF EXISTS $tableName');
        LoggerService.warning('Tabela dropada: $tableName');
      } catch (e) {
        LoggerService.warning('Erro ao dropar tabela $tableName: $e');
      }
    }

    database.dispose();

    LoggerService.warning('===== DROP DE TABELAS CONCLUÍDO =====');
    LoggerService.info(
      'Tabelas serão recriadas automaticamente pelo Drift '
      'no próximo acesso',
    );
  } catch (e, stackTrace) {
    LoggerService.error('===== ERRO AO DROPAR TABELAS =====');
    LoggerService.error('Erro ao dropar tabelas: $e', e, stackTrace);
  }
}

/// Abre o banco de dados SQLite diretamente usando sqlite3.
dynamic openSqliteApi(String dbPath) {
  return sqlite3.sqlite3.open(dbPath);
}

/// Obtém o diretório de dados do aplicativo sem duplicação de pastas
Future<Directory> _getAppDataDirectory() async {
  // No Windows, o getApplicationDocumentsDirectory pode criar pastas duplicadas
  // Usamos um caminho customizado para evitar isso
  if (Platform.isWindows) {
    // Obtém o AppData Roaming diretamente
    final appData = Platform.environment['APPDATA'];
    if (appData != null) {
      // Cria diretório: C:\Users\<usuario>\AppData\Roaming\Backup Database
      final customPath = p.join(appData, 'Backup Database');
      return Directory(customPath);
    }
  }

  // Para outras plataformas, usa o padrão
  return getApplicationDocumentsDirectory();
}

/// Sets up core services and utilities.
///
/// This module registers fundamental services like logging,
/// encryption, database, HTTP client, and system utilities.
Future<void> setupCoreModule(GetIt getIt) async {
  // Drop tabelas de configuração na versão 2.2.3
  await _dropConfigTablesForVersion222();

  final appDataDir = await _getAppDataDirectory();
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
