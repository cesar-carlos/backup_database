import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:backup_database/application/services/services.dart';
import 'package:backup_database/core/bootstrap/machine_scope_r1_legacy_paths_hint.dart';
import 'package:backup_database/core/config/app_mode.dart';
import 'package:backup_database/core/constants/license_constants.dart';
import 'package:backup_database/core/encryption/encryption_service.dart';
import 'package:backup_database/core/errors/failure.dart';
import 'package:backup_database/core/logging/logging.dart';
import 'package:backup_database/core/service/service_shutdown_handler.dart';
import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/clipboard_service.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/core/utils/machine_storage_bootstrap_diagnostics.dart';
import 'package:backup_database/core/utils/machine_storage_layout.dart';
import 'package:backup_database/core/utils/machine_storage_migration.dart';
import 'package:backup_database/domain/repositories/repositories.dart';
import 'package:backup_database/domain/services/services.dart';
import 'package:backup_database/infrastructure/datasources/local/database.dart';
import 'package:backup_database/infrastructure/datasources/local/database_config_tables_drop_v223.dart';
import 'package:backup_database/infrastructure/datasources/local/database_migration_224.dart';
import 'package:backup_database/infrastructure/external/external.dart';
import 'package:backup_database/infrastructure/http/api_client.dart';
import 'package:backup_database/infrastructure/license/revocation_list_issued_at_store.dart';
import 'package:backup_database/infrastructure/license/signed_revocation_list_service.dart';
import 'package:backup_database/infrastructure/security/machine_scope_secure_credential_service.dart';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:get_it/get_it.dart';
import 'package:path/path.dart' as p;

Future<Directory> getAppDataDirectory() => resolveMachineRootDirectory();

/// Sets up core services and utilities.
///
/// This module registers fundamental services like logging,
/// encryption, database, HTTP client, and system utilities.
Future<void> setupCoreModule(GetIt getIt) async {
  await ensureMachineStorageDirectoriesExist();
  final migrationSummary = await ensureLegacyAppDataMigratedToMachineScope();

  await DatabaseConfigTablesDropV223.run();

  final exportData224 = await runFullDatabaseMigration224();

  final appDataDir = await getAppDataDirectory();
  final logsDirectory = p.join(
    appDataDir.path,
    MachineStorageLayout.logs,
  );

  await LoggerService.init(logsDirectory: logsDirectory);
  final loggerHealth = LoggerService.health;
  if (!loggerHealth.isHealthy) {
    // Não use LoggerService.error aqui — se o logger está degradado, a
    // própria mensagem pode não chegar ao disco. Joga no stderr direto
    // para garantir trace mínimo (mesmo em service mode, NSSM captura
    // stderr em service_stderr.log).
    stderr.writeln(
      '[bootstrap] LoggerService DEGRADADO: '
      'fileLoggingEnabled=${loggerHealth.fileLoggingEnabled} '
      'logsDirectory=${loggerHealth.logsDirectory} '
      'initError=${loggerHealth.initError} '
      'sentinelError=${loggerHealth.lastBootSentinelError}',
    );
  } else {
    LoggerService.info(
      '[bootstrap] LoggerService healthy '
      'logsDirectory=$logsDirectory '
      'sentinelWrittenAt=${loggerHealth.lastBootSentinelWrittenAt}',
    );
  }

  final legacyLogsMigration =
      await migrateLegacyUserLogFilesToMachineScopeIfNeeded();
  final otherLegacyProfilePaths =
      await findLegacyBackupDatabasePathsOutsideCurrentUser();
  getIt.registerSingleton<MachineScopeR1LegacyPathsHint>(
    MachineScopeR1LegacyPathsHint(
      otherProfilesLegacySqlitePaths: otherLegacyProfilePaths,
    ),
  );
  final legacyLogsInfo = await countLegacyLogFilesVisibleForCurrentUser();
  final secureCredentialBackendLabel = Platform.isWindows
      ? 'windows_machine_dpapi_files'
      : 'flutter_secure_storage';
  await recordMachineStorageBootstrapDiagnostics(
    migrationSummary: migrationSummary,
    otherLegacyProfilePaths: otherLegacyProfilePaths,
    legacyLogFileCount: legacyLogsInfo.count,
    legacyLogsDirectoryPath: legacyLogsInfo.directoryPath,
    legacyLogsMigration: legacyLogsMigration,
    secureCredentialBackendLabel: secureCredentialBackendLabel,
  );

  final socketLogger = SocketLoggerService(logsDirectory: logsDirectory);
  await socketLogger.initialize();
  getIt.registerSingleton<SocketLoggerService>(socketLogger);

  getIt.registerLazySingleton<ClipboardService>(ClipboardService.new);
  // S9 da auditoria: ServiceShutdownHandler agora vem do DI em vez de
  // singleton estático. Cada chamada a `getIt<ServiceShutdownHandler>()`
  // retorna o mesmo objeto (lazySingleton). O construtor antigo
  // `ServiceShutdownHandler()` redirecionou para `factory.legacy()` que
  // mantém compat com testes que ainda não migraram.
  getIt.registerLazySingleton<ServiceShutdownHandler>(
    ServiceShutdownHandler.new,
  );
  getIt.registerLazySingleton<ISingleInstanceService>(
    SingleInstanceService.new,
  );
  getIt.registerLazySingleton<ISingleInstanceIpcClient>(
    SingleInstanceIpcClient.new,
  );
  getIt.registerLazySingleton<IIpcService>(IpcService.new);
  getIt.registerLazySingleton<IWindowsMessageBox>(WindowsMessageBox.new);

  getIt.registerLazySingleton<Dio>(Dio.new);
  getIt.registerLazySingleton<ApiClient>(() => ApiClient(getIt<Dio>()));

  final databaseName = getDatabaseNameForMode(currentAppMode);
  getIt.registerLazySingleton<AppDatabase>(
    () => AppDatabase(databaseName: databaseName),
  );
  getIt.registerLazySingleton<IAppDatabaseLifecycle>(getIt.get<AppDatabase>);

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
    MachineScopeSecureCredentialService.new,
  );

  // License
  final licenseDecoderResult = LicenseDecoder.fromEnv();
  final licenseDecoder = licenseDecoderResult.fold(
    (decoder) => decoder,
    (error) {
      LoggerService.error('Failed to initialize license decoder: $error');
      LoggerService.warning(
        'License validation/generation bootstrap will run in degraded mode. '
        'Configure BACKUP_DATABASE_LICENSE_PUBLIC_KEY to re-enable signed '
        'license decoding without reinstalling the app.',
      );
      final message = error is Failure
          ? error.message
          : 'Chave publica de licenca indisponivel.';
      return LicenseDecoder.unavailable(message: message);
    },
  );
  final issuedAtStore = FileRevocationListIssuedAtStore();
  final revocationChecker = SignedRevocationListService.fromEnv(
    issuedAtStore: issuedAtStore,
  );
  // Hidrata o marcador anti-rollback no boot — best-effort, falha aqui
  // não impede inicialização do app.
  unawaited(revocationChecker.ensureLastAcceptedIssuedAtLoaded());
  getIt.registerLazySingleton<LicenseDecoder>(() => licenseDecoder);
  getIt.registerLazySingleton<IRevocationChecker>(() => revocationChecker);
  getIt.registerLazySingleton<RevocationListIssuedAtStore>(
    () => issuedAtStore,
  );
  getIt.registerLazySingleton<IMetricsCollector>(MetricsCollector.new);

  final generationService = _createLicenseGenerationService(
    licenseDecoder,
    revocationChecker,
  );
  getIt.registerLazySingleton<LicenseGenerationService>(
    () => generationService,
  );

  if (generationService.canGenerateLocally) {
    LoggerService.info('License generation service initialized (debug only)');
  } else {
    LoggerService.info(
      'License generation disabled (requires debug mode and valid private key)',
    );
  }

  getIt.registerLazySingleton<LicenseValidationService>(
    () => LicenseValidationService(
      licenseRepository: getIt<ILicenseRepository>(),
      deviceKeyService: getIt<IDeviceKeyService>(),
      revocationChecker: revocationChecker,
    ),
  );
  getIt.registerLazySingleton<ILicenseValidationService>(
    () => CachedLicenseValidationService(
      delegate: getIt<LicenseValidationService>(),
    ),
  );
  getIt.registerLazySingleton<ILicenseCacheInvalidator>(
    () => getIt<ILicenseValidationService>() as ILicenseCacheInvalidator,
  );
}

LicenseGenerationService _createLicenseGenerationService(
  LicenseDecoder licenseDecoder,
  IRevocationChecker revocationChecker,
) {
  // `activeKeyId` é lido sempre (mesmo em release) para permitir que
  // ferramentas administrativas externas que rodem com este build
  // identifiquem corretamente a chave ativa. O override só é
  // significativo em conjunto com a private key (configurada apenas
  // em dev/admin).
  final rawActiveKeyId = dotenv
      .env[LicenseConstants.envLicenseActiveKeyId]
      ?.trim();
  final activeKeyId = (rawActiveKeyId != null && rawActiveKeyId.isNotEmpty)
      ? rawActiveKeyId
      : LicenseConstants.keyIdDefault;

  if (!kDebugMode) {
    return LicenseGenerationService(
      licenseDecoder: licenseDecoder,
      revocationChecker: revocationChecker,
      activeKeyId: activeKeyId,
    );
  }

  final base64PrivateKey = dotenv.env[LicenseConstants.envLicensePrivateKey];
  if (base64PrivateKey == null || base64PrivateKey.trim().isEmpty) {
    return LicenseGenerationService(
      licenseDecoder: licenseDecoder,
      revocationChecker: revocationChecker,
      activeKeyId: activeKeyId,
    );
  }

  try {
    final privateKeyBytes = base64.decode(base64PrivateKey.trim());
    if (privateKeyBytes.length != 64) {
      LoggerService.warning(
        'Invalid private key length for local generation: '
        '${privateKeyBytes.length}',
      );
      return LicenseGenerationService(
        licenseDecoder: licenseDecoder,
        revocationChecker: revocationChecker,
        activeKeyId: activeKeyId,
      );
    }

    LoggerService.info(
      'LicenseGenerationService initialized with activeKeyId="$activeKeyId" '
      '(decoder accepts: ${licenseDecoder.acceptedKeyIds.join(", ")})',
    );

    return LicenseGenerationService(
      privateKeyBytes: privateKeyBytes,
      licenseDecoder: licenseDecoder,
      revocationChecker: revocationChecker,
      activeKeyId: activeKeyId,
    );
  } on Object catch (e) {
    LoggerService.warning(
      'Failed to decode private key for local generation: $e',
    );
    return LicenseGenerationService(
      licenseDecoder: licenseDecoder,
      revocationChecker: revocationChecker,
      activeKeyId: activeKeyId,
    );
  }
}
