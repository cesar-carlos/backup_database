import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';

class BackupArtifactUtils {
  BackupArtifactUtils._();

  static const Duration defaultFileInitialDelay = Duration(milliseconds: 200);
  static const Duration defaultFilePollInterval = Duration(milliseconds: 250);
  static const Duration defaultFileStabilizeDelay = Duration(
    milliseconds: 200,
  );
  static const Duration defaultFileMaxWait = Duration(seconds: 12);

  static Future<void> safeDeletePartial(String artifactPath) async {
    try {
      final file = File(artifactPath);
      if (await file.exists()) {
        await file.delete();
        LoggerService.info(
          'Arquivo parcial de backup removido após falha: $artifactPath',
        );
        return;
      }
      final dir = Directory(artifactPath);
      if (await dir.exists()) {
        await dir.delete(recursive: true);
        LoggerService.info(
          'Diretório parcial de backup removido após falha: $artifactPath',
        );
      }
    } on Object catch (e) {
      LoggerService.debug(
        'Falha ao remover artefato parcial $artifactPath: $e',
      );
    }
  }

  static Future<bool> waitForStableFile(
    File backupFile, {
    Duration initialDelay = defaultFileInitialDelay,
    Duration pollInterval = defaultFilePollInterval,
    Duration stabilizeDelay = defaultFileStabilizeDelay,
    Duration maxWait = defaultFileMaxWait,
  }) async {
    await Future<void>.delayed(initialDelay);
    final deadline = DateTime.now().add(maxWait);

    while (DateTime.now().isBefore(deadline)) {
      if (await backupFile.exists()) {
        final length = await backupFile.length();
        if (length > 0) {
          await Future<void>.delayed(stabilizeDelay);
          final length2 = await backupFile.length();
          if (length2 == length) {
            return true;
          }
        }
      }
      await Future<void>.delayed(pollInterval);
    }

    return backupFile.existsSync() && backupFile.lengthSync() > 0;
  }
}
