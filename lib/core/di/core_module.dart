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
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:result_dart/result_dart.dart' as rd;

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
