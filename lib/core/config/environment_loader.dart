import 'dart:io';

import 'package:backup_database/core/utils/app_data_directory_resolver.dart';
import 'package:backup_database/core/utils/logger_service.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:path/path.dart' as p;

enum EnvironmentSource { externalMachineFile, bundledAsset }

class EnvironmentLoadPlan {
  const EnvironmentLoadPlan({
    required this.source,
    required this.description,
    this.filePath,
  });

  final EnvironmentSource source;
  final String description;
  final String? filePath;
}

/// Centraliza o carregamento do `.env`.
///
/// Em Windows instalado, a prioridade agora e o arquivo externo em
/// `C:\ProgramData\BackupDatabase\config\.env`. Em desenvolvimento local,
/// ou quando o arquivo externo ainda nao existe, o fallback continua sendo
/// o asset `.env` empacotado para `flutter run`.
class EnvironmentLoader {
  EnvironmentLoader._();

  static const String bundledAssetFileName = '.env';
  static const String migratedBackupFileName = '.env.migrated-from-appdir.bak';

  static EnvironmentLoadPlan resolveLoadPlan({
    required bool isWindows,
    required bool externalFileExists,
    String? externalFilePath,
  }) {
    if (isWindows && externalFileExists && externalFilePath != null) {
      return EnvironmentLoadPlan(
        source: EnvironmentSource.externalMachineFile,
        filePath: externalFilePath,
        description: externalFilePath,
      );
    }

    return const EnvironmentLoadPlan(
      source: EnvironmentSource.bundledAsset,
      description: bundledAssetFileName,
    );
  }

  static File resolveLegacyInstalledEnvironmentFile({
    String? executablePath,
  }) {
    final resolvedExecutable = executablePath ?? Platform.resolvedExecutable;
    final appDir = File(resolvedExecutable).parent.path;
    return File(p.join(appDir, bundledAssetFileName));
  }

  static Future<bool> migrateLegacyWindowsEnvironmentIfNeeded({
    required bool isWindows,
    required File externalEnvFile,
    required File legacyEnvFile,
    String? logPrefix,
  }) async {
    if (!isWindows ||
        await externalEnvFile.exists() ||
        !await legacyEnvFile.exists()) {
      return false;
    }

    await externalEnvFile.parent.create(recursive: true);
    await legacyEnvFile.copy(externalEnvFile.path);

    final backupFile = File(
      p.join(externalEnvFile.parent.path, migratedBackupFileName),
    );
    if (!await backupFile.exists()) {
      await legacyEnvFile.copy(backupFile.path);
    }

    LoggerService.info(
      '${logPrefix ?? '[env]'} arquivo legado migrado de '
      '${legacyEnvFile.path} para ${externalEnvFile.path}',
    );
    return true;
  }

  /// Carrega o arquivo `.env` se ainda nao foi carregado. Captura erros
  /// para nao interromper o boot, e variaveis ausentes serao tratadas como
  /// `null` pelos consumidores.
  static Future<void> loadIfNeeded({String? logPrefix}) async {
    if (dotenv.isInitialized) {
      LoggerService.debug(
        '${logPrefix ?? '[env]'} variaveis ja carregadas (skip)',
      );
      return;
    }

    try {
      final externalEnvFile = await resolveMachineEnvironmentFile();
      await migrateLegacyWindowsEnvironmentIfNeeded(
        isWindows: Platform.isWindows,
        externalEnvFile: externalEnvFile,
        legacyEnvFile: resolveLegacyInstalledEnvironmentFile(),
        logPrefix: logPrefix,
      );
      final loadPlan = resolveLoadPlan(
        isWindows: Platform.isWindows,
        externalFileExists: await externalEnvFile.exists(),
        externalFilePath: externalEnvFile.path,
      );

      switch (loadPlan.source) {
        case EnvironmentSource.externalMachineFile:
          final envText = await File(loadPlan.filePath!).readAsString();
          dotenv.loadFromString(envString: envText);
        case EnvironmentSource.bundledAsset:
          await dotenv.load();
      }

      LoggerService.info(
        '${logPrefix ?? '[env]'} variaveis de ambiente carregadas de '
        '${loadPlan.description}',
      );
    } on Object catch (e, s) {
      LoggerService.warning(
        '${logPrefix ?? '[env]'} nao foi possivel carregar .env: $e',
        e,
        s,
      );
    }
  }
}
