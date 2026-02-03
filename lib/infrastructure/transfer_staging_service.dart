import 'dart:io';

import 'package:backup_database/core/utils/logger_service.dart';
import 'package:backup_database/domain/services/i_transfer_staging_service.dart';
import 'package:path/path.dart' as p;

class TransferStagingService implements ITransferStagingService {
  TransferStagingService({required String transferBasePath})
      : _transferBasePath = p.normalize(p.absolute(transferBasePath));

  final String _transferBasePath;

  @override
  Future<String?> copyToStaging(String backupPath, String scheduleId) async {
    final source = File(backupPath);
    if (!await source.exists()) {
      LoggerService.warning(
        'TransferStagingService: backup file not found: $backupPath',
      );
      return null;
    }

    final baseName = p.basename(backupPath);
    final relativePath = p.join('remote', scheduleId, baseName);
    final destPath = p.join(_transferBasePath, relativePath);
    final destFile = File(destPath);
    final destDir = destFile.parent;

    try {
      if (!await destDir.exists()) {
        await destDir.create(recursive: true);
      }
      await source.copy(destPath);
      return p.join(relativePath).replaceAll(r'\', '/');
    } on Object catch (e, st) {
      LoggerService.warning(
        'TransferStagingService: copy failed',
        e,
        st,
      );
      return null;
    }
  }
}
